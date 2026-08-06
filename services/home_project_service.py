"""Catálogo y lógica de proyectos casa hogar (9 etapas)."""

from __future__ import annotations

import re
import secrets
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import yaml
from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from db.models import (
    Analysis,
    HomeProject,
    HomeProjectDocument,
    HomeProjectEvent,
    HomeProjectEventType,
    HomeProjectInvite,
    HomeProjectMember,
    HomeProjectMemberRole,
    HomeProjectSection,
    HomeProjectSectionComment,
    HomeProjectSectionStatus,
    HomeProjectStage,
    HomeProjectStatus,
    HomeStageStatus,
    User,
    UserRole,
)
from services.email_service import (
    send_project_invite_email,
    send_section_assigned_email,
    send_section_review_email,
    send_mention_email,
    send_reopen_alert_email,
)
from services.qa_service import answer_construction_question
from services.storage_service import (
    MAX_PROJECT_DOC_MB,
    save_project_document,
)
from services.subscription_service import (
    assert_can_create_home_project,
    assert_can_invite_members,
    assert_can_store_documentation,
)

ROOT = Path(__file__).resolve().parents[1]
_STAGES_CACHE: list[dict[str, Any]] | None = None


def _log_event(
    db: Session,
    *,
    project: HomeProject,
    actor_user_id: int | None,
    event_type: HomeProjectEventType,
    section_id: int | None = None,
    document_id: int | None = None,
    comment_id: int | None = None,
    metadata: dict | None = None,
) -> None:
    try:
        db.add(
            HomeProjectEvent(
                project_id=project.id,
                actor_user_id=actor_user_id,
                event_type=event_type,
                section_id=section_id,
                document_id=document_id,
                comment_id=comment_id,
                metadata_json=metadata or None,
            )
        )
    except Exception:
        # Auditoría no debe romper la acción principal.
        pass


def load_stage_catalog() -> list[dict[str, Any]]:
    global _STAGES_CACHE
    if _STAGES_CACHE is not None:
        return _STAGES_CACHE
    path = ROOT / "config" / "home_stages.yaml"
    if not path.exists():
        raise RuntimeError(f"No se encontró catálogo de etapas: {path}")
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    _STAGES_CACHE = list(data.get("stages") or [])
    if len(_STAGES_CACHE) != 9:
        raise RuntimeError("El catálogo debe definir exactamente 9 etapas")
    return _STAGES_CACHE


def _checklist_from_catalog(stage_def: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "id": f"task-{i + 1}",
            "title": title,
            "done": False,
            "notes": "",
        }
        for i, title in enumerate(stage_def.get("tasks") or [])
    ]


def _stage_catalog_by_number() -> dict[int, dict[str, Any]]:
    return {int(s["number"]): s for s in load_stage_catalog()}


def _project_query_options():
    return (
        joinedload(HomeProject.stages),
        joinedload(HomeProject.documents),
        joinedload(HomeProject.sections),
        joinedload(HomeProject.members).joinedload(HomeProjectMember.user),
    )


def _member_role(db: Session, project: HomeProject, user_id: int) -> str | None:
    actor = db.query(User).filter(User.id == user_id).first()
    if actor and actor.role == UserRole.admin:
        return "admin"
    if project.user_id == user_id:
        return "owner"
    member = next((m for m in (project.members or []) if m.user_id == user_id), None)
    if member:
        return member.role.value
    row = (
        db.query(HomeProjectMember)
        .filter(
            HomeProjectMember.project_id == project.id,
            HomeProjectMember.user_id == user_id,
        )
        .first()
    )
    return row.role.value if row else None


def _require_project_access(
    db: Session, project: HomeProject, user_id: int, *, min_role: str = "viewer"
) -> str:
    role = _member_role(db, project, user_id)
    if not role:
        raise HTTPException(404, "Proyecto no encontrado")
    rank = {"viewer": 1, "editor": 2, "owner": 3, "admin": 4}
    if rank.get(role, 0) < rank.get(min_role, 0):
        raise HTTPException(403, "No tienes permiso para esta acción")
    return role


def _require_owner(db: Session, project: HomeProject, user_id: int) -> None:
    _require_project_owner_or_admin(db, project, user_id)


def _require_project_owner_or_admin(
    db: Session, project: HomeProject, user_id: int
) -> str:
    role = _member_role(db, project, user_id)
    if not role:
        raise HTTPException(404, "Proyecto no encontrado")
    if role not in ("owner", "admin"):
        raise HTTPException(
            403,
            "Solo el propietario del proyecto o un administrador pueden realizar esta acción",
        )
    return role


def _is_global_admin(db: Session, user_id: int) -> bool:
    u = db.query(User).filter(User.id == user_id).first()
    return bool(u and u.role == UserRole.admin)


def _validate_reopen_reason(reason: str | None, *, fallback: str = "") -> str:
    text = (reason or fallback or "").strip()
    if len(text) < 10:
        raise HTTPException(
            400,
            "Indica el motivo de reapertura (mínimo 10 caracteres)",
        )
    if len(text) > 4000:
        raise HTTPException(400, "Motivo demasiado largo (máx. 4000)")
    return text


def _seed_sections_from_catalog(db: Session, project: HomeProject, user_id: int) -> None:
    catalog = _stage_catalog_by_number()
    for stage_def in catalog.values():
        num = int(stage_def["number"])
        tasks = stage_def.get("tasks") or []
        for i, title in enumerate(tasks):
            db.add(
                HomeProjectSection(
                    project_id=project.id,
                    stage_number=num,
                    title=str(title),
                    description="",
                    sort_order=i,
                    status=HomeProjectSectionStatus.pending,
                    created_by=user_id,
                    is_catalog=True,
                )
            )


def _ensure_sections_migrated(db: Session, project: HomeProject) -> None:
    existing = (
        db.query(HomeProjectSection.id)
        .filter(HomeProjectSection.project_id == project.id)
        .limit(1)
        .first()
    )
    if existing:
        return
    catalog = _stage_catalog_by_number()
    for stage in project.stages:
        items = stage.checklist_json or _checklist_from_catalog(
            catalog.get(stage.stage_number, {})
        )
        for i, item in enumerate(items):
            status = (
                HomeProjectSectionStatus.completed
                if item.get("done")
                else HomeProjectSectionStatus.pending
            )
            db.add(
                HomeProjectSection(
                    project_id=project.id,
                    stage_number=stage.stage_number,
                    title=str(item.get("title") or f"Apartado {i + 1}"),
                    description=str(item.get("notes") or ""),
                    sort_order=i,
                    status=status,
                    created_by=project.user_id,
                    is_catalog=True,
                )
            )
    db.commit()
    db.refresh(project)


def _sections_for_stage(project: HomeProject, stage_number: int) -> list[HomeProjectSection]:
    return sorted(
        [s for s in (project.sections or []) if s.stage_number == stage_number],
        key=lambda s: (s.sort_order, s.id),
    )


def _document_payload(project: HomeProject, doc: HomeProjectDocument) -> dict:
    section_title = None
    if doc.section_id and project.sections:
        sec = next((s for s in project.sections if s.id == doc.section_id), None)
        section_title = sec.title if sec else None
    return {
        "id": doc.id,
        "stage_number": doc.stage_number,
        "section_id": doc.section_id,
        "section_title": section_title,
        "filename": doc.original_filename,
        "mime_type": doc.mime_type,
        "file_size": doc.file_size,
        "uploaded_by": doc.user_id,
        "created_at": doc.created_at.isoformat() if doc.created_at else None,
        "download_url": f"/api/home-projects/{project.id}/documents/{doc.id}/file",
        "is_image": (doc.mime_type or "").startswith("image/"),
    }


def _members_payload(db: Session, project: HomeProject) -> list[dict]:
    owner = db.query(User).filter(User.id == project.user_id).first()
    out: list[dict] = []
    if owner:
        out.append(
            {
                "user_id": owner.id,
                "email": owner.email,
                "full_name": owner.full_name or owner.email,
                "avatar_url": owner.avatar_url,
                "role": "owner",
            }
        )
    for member in project.members or []:
        u = member.user or db.query(User).filter(User.id == member.user_id).first()
        if not u:
            continue
        out.append(
            {
                "user_id": u.id,
                "email": u.email,
                "full_name": u.full_name or u.email,
                "avatar_url": u.avatar_url,
                "role": member.role.value,
            }
        )
    return out


def create_home_project(
    db: Session,
    user: User,
    *,
    name: str,
    client_name: str = "",
    location: str = "",
    description: str = "",
    metadata: dict | None = None,
) -> HomeProject:
    name = (name or "").strip()
    if len(name) < 2:
        raise HTTPException(400, "El nombre del proyecto es obligatorio")

    assert_can_create_home_project(db, user)

    catalog = load_stage_catalog()
    project = HomeProject(
        id=str(uuid.uuid4()),
        user_id=user.id,
        name=name,
        client_name=(client_name or "").strip(),
        location=(location or "").strip(),
        description=(description or "").strip(),
        status=HomeProjectStatus.active,
        current_stage=1,
        metadata_json=metadata or {},
    )
    db.add(project)
    db.flush()

    for stage_def in catalog:
        num = int(stage_def["number"])
        status = HomeStageStatus.in_progress if num == 1 else HomeStageStatus.pending
        started = datetime.utcnow() if num == 1 else None
        db.add(
            HomeProjectStage(
                project_id=project.id,
                stage_number=num,
                slug=str(stage_def["slug"]),
                title=str(stage_def["title"]),
                status=status,
                checklist_json=_checklist_from_catalog(stage_def),
                started_at=started,
            )
        )

    _seed_sections_from_catalog(db, project, user.id)
    db.commit()
    db.refresh(project)
    return project


def list_home_projects(db: Session, user: User) -> list[HomeProject]:
    if user.role == UserRole.admin:
        return (
            db.query(HomeProject)
            .options(*_project_query_options())
            .order_by(HomeProject.updated_at.desc())
            .all()
        )

    member_ids = (
        db.query(HomeProjectMember.project_id)
        .filter(HomeProjectMember.user_id == user.id)
        .subquery()
    )
    return (
        db.query(HomeProject)
        .options(*_project_query_options())
        .filter(
            or_(
                HomeProject.user_id == user.id,
                HomeProject.id.in_(member_ids),
            )
        )
        .order_by(HomeProject.updated_at.desc())
        .all()
    )


def get_home_project(db: Session, user_id: int, project_id: str) -> HomeProject:
    project = (
        db.query(HomeProject)
        .options(*_project_query_options())
        .filter(HomeProject.id == project_id)
        .first()
    )
    if not project:
        raise HTTPException(404, "Proyecto no encontrado")
    _require_project_access(db, project, user_id, min_role="viewer")
    _ensure_sections_migrated(db, project)
    project = (
        db.query(HomeProject)
        .options(*_project_query_options())
        .filter(HomeProject.id == project_id)
        .first()
    )
    return project


def update_home_project(
    db: Session,
    user: User,
    project_id: str,
    *,
    name: str | None = None,
    client_name: str | None = None,
    location: str | None = None,
    description: str | None = None,
    status: str | None = None,
    metadata: dict | None = None,
) -> HomeProject:
    project = get_home_project(db, user.id, project_id)
    _require_project_access(db, project, user.id, min_role="editor")
    if name is not None:
        name = name.strip()
        if len(name) < 2:
            raise HTTPException(400, "Nombre inválido")
        project.name = name
    if client_name is not None:
        project.client_name = client_name.strip()
    if location is not None:
        project.location = location.strip()
    if description is not None:
        project.description = description.strip()
    if status is not None:
        try:
            project.status = HomeProjectStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Estado de proyecto inválido") from exc
    if metadata is not None:
        project.metadata_json = metadata
    project.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(project)
    return project


def delete_home_project(db: Session, user_id: int, project_id: str) -> None:
    project = get_home_project(db, user_id, project_id)
    _require_owner(db, project, user_id)
    for doc in project.documents or []:
        path = Path(doc.stored_path)
        if path.is_file():
            try:
                path.unlink()
            except OSError:
                pass
    db.delete(project)
    db.commit()


def _sync_project_current_stage(project: HomeProject) -> None:
    active = next(
        (
            s
            for s in sorted(project.stages, key=lambda x: x.stage_number)
            if s.status in (HomeStageStatus.in_progress, HomeStageStatus.blocked)
        ),
        None,
    )
    if active:
        project.current_stage = active.stage_number
        return
    pending = next(
        (
            s
            for s in sorted(project.stages, key=lambda x: x.stage_number)
            if s.status == HomeStageStatus.pending
        ),
        None,
    )
    if pending:
        project.current_stage = pending.stage_number
        return
    project.current_stage = 9
    if project.status == HomeProjectStatus.active:
        project.status = HomeProjectStatus.completed


def _notify_reopen(
    db: Session,
    project: HomeProject,
    actor: User,
    *,
    target_label: str,
    reason: str,
    admin_override: bool = False,
) -> None:
    actor_name = actor.full_name or actor.email
    for email, uid in _project_member_emails(db, project).items():
        if uid == actor.id:
            continue
        user = db.query(User).filter(User.id == uid).first()
        if not user:
            continue
        send_reopen_alert_email(
            to_email=user.email,
            project_name=project.name,
            project_id=project.id,
            actor_name=actor_name,
            target_label=target_label,
            reason=reason,
            admin_override=admin_override,
        )


def update_stage(
    db: Session,
    user: User,
    project_id: str,
    stage_number: int,
    *,
    status: str | None = None,
    notes: str | None = None,
    checklist: list[dict] | None = None,
    analysis_id: int | None = None,
    reopen_reason: str | None = None,
) -> HomeProjectStage:
    if stage_number < 1 or stage_number > 9:
        raise HTTPException(400, "Etapa inválida (1-9)")
    project = get_home_project(db, user.id, project_id)
    actor_role = _require_project_access(db, project, user.id, min_role="editor")
    is_owner_or_admin = actor_role in ("owner", "admin")
    stage = next((s for s in project.stages if s.stage_number == stage_number), None)
    if not stage:
        raise HTTPException(404, "Etapa no encontrada")

    prev_status = stage.status
    reopen_reason_text = ""
    now = datetime.utcnow()
    if status is not None:
        try:
            new_status = HomeStageStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Estado de etapa inválido") from exc
        if new_status == HomeStageStatus.completed and not is_owner_or_admin:
            raise HTTPException(
                403,
                "Solo el propietario del proyecto o un administrador pueden completar etapas",
            )
        if (
            prev_status == HomeStageStatus.completed
            and new_status != HomeStageStatus.completed
        ):
            _require_project_owner_or_admin(db, project, user.id)
            reopen_reason_text = _validate_reopen_reason(reopen_reason)
        if new_status == HomeStageStatus.in_progress and not stage.started_at:
            stage.started_at = now
        if new_status == HomeStageStatus.completed:
            stage.completed_at = now
            for sec in _sections_for_stage(project, stage_number):
                sec.status = HomeProjectSectionStatus.completed
                sec.updated_at = now
        if (
            prev_status == HomeStageStatus.completed
            and new_status != HomeStageStatus.completed
        ):
            stage.completed_at = None
        stage.status = new_status

    if notes is not None:
        stage.notes = notes.strip()
    if checklist is not None:
        stage.checklist_json = checklist
    if analysis_id is not None:
        if analysis_id == 0:
            stage.analysis_id = None
        else:
            owned = (
                db.query(Analysis)
                .filter(Analysis.id == analysis_id, Analysis.user_id == user.id)
                .first()
            )
            if not owned:
                raise HTTPException(404, "Análisis no encontrado")
            stage.analysis_id = analysis_id

    stage.updated_at = now
    project.updated_at = now
    _sync_project_current_stage(project)
    db.commit()
    db.refresh(stage)

    if prev_status != stage.status:
        if stage.status == HomeStageStatus.completed:
            _log_event(
                db,
                project=project,
                actor_user_id=user.id,
                event_type=HomeProjectEventType.stage_completed,
                metadata={"stage_number": stage_number},
            )
            db.commit()
        elif (
            prev_status == HomeStageStatus.completed
            and stage.status != HomeStageStatus.completed
        ):
            _log_event(
                db,
                project=project,
                actor_user_id=user.id,
                event_type=HomeProjectEventType.stage_reopened,
                metadata={
                    "stage_number": stage_number,
                    "from": prev_status.value,
                    "to": stage.status.value,
                    "reason": reopen_reason_text,
                },
            )
            db.commit()
            _notify_reopen(
                db,
                project,
                user,
                target_label=f"la etapa {stage_number} («{stage.title}»)",
                reason=reopen_reason_text,
                admin_override=actor_role == "admin" and _is_global_admin(db, user.id),
            )
    return stage


def advance_to_next_stage(db: Session, user: User, project_id: str) -> HomeProject:
    project = get_home_project(db, user.id, project_id)
    actor_role = _require_project_owner_or_admin(db, project, user.id)
    current = project.current_stage
    stage = next((s for s in project.stages if s.stage_number == current), None)
    if not stage:
        raise HTTPException(400, "Etapa actual no encontrada")

    if stage.status != HomeStageStatus.completed:
        stage.status = HomeStageStatus.completed
        stage.completed_at = datetime.utcnow()
        for sec in _sections_for_stage(project, current):
            sec.status = HomeProjectSectionStatus.completed
            sec.updated_at = datetime.utcnow()
        _log_event(
            db,
            project=project,
            actor_user_id=user.id,
            event_type=HomeProjectEventType.stage_completed,
            metadata={"stage_number": current},
        )

    next_stage_num = current + 1 if current < 9 else 9
    if current >= 9:
        project.status = HomeProjectStatus.completed
        project.current_stage = 9
    else:
        nxt = next((s for s in project.stages if s.stage_number == current + 1), None)
        if nxt:
            nxt.status = HomeStageStatus.in_progress
            if not nxt.started_at:
                nxt.started_at = datetime.utcnow()
            project.current_stage = current + 1
        _log_event(
            db,
            project=project,
            actor_user_id=user.id,
            event_type=HomeProjectEventType.stage_advanced,
            metadata={"from_stage": current, "to_stage": next_stage_num},
        )

    project.updated_at = datetime.utcnow()
    _sync_project_current_stage(project)
    db.commit()
    db.refresh(project)
    return project


def _build_ai_prompt(
    project: HomeProject,
    stage: HomeProjectStage,
    user_question: str,
) -> str:
    catalog = _stage_catalog_by_number().get(stage.stage_number, {})
    summary = catalog.get("summary", stage.title)
    loc = project.location or "sin ubicación definida"
    pending_tasks = [
        item.title
        for item in _sections_for_stage(project, stage.stage_number)
        if item.status != HomeProjectSectionStatus.completed
    ]
    done_count = sum(
        1
        for item in _sections_for_stage(project, stage.stage_number)
        if item.status == HomeProjectSectionStatus.completed
    )
    total = len(_sections_for_stage(project, stage.stage_number))

    parts = [
        f"Contexto: proyecto de casa hogar «{project.name}».",
        f"Cliente: {project.client_name or 'no indicado'}. Ubicación: {loc}.",
        f"Etapa actual ({stage.stage_number}/9): {stage.title} — {summary}.",
        f"Avance apartados: {done_count}/{total} entregables.",
    ]
    if pending_tasks:
        parts.append("Pendientes: " + "; ".join(pending_tasks[:6]))
    if stage.notes:
        parts.append(f"Notas del usuario: {stage.notes[:800]}")
    if project.description:
        parts.append(f"Descripción del proyecto: {project.description[:500]}")
    if catalog.get("plan_review"):
        parts.append(
            "Indica si conviene subir planos a ARCHITECT para revisión técnica en esta etapa."
        )
    q = (user_question or "").strip()
    if q:
        parts.append(f"Pregunta del usuario: {q}")
    else:
        hints = catalog.get("ai_hints") or []
        hint = hints[0] if hints else "orientación práctica para esta etapa"
        parts.append(
            f"Genera orientación práctica, checklist de acciones y riesgos comunes. "
            f"Tema: {hint}."
        )
    return "\n".join(parts)


def assist_stage(
    db: Session,
    user: User,
    project_id: str,
    stage_number: int,
    *,
    question: str = "",
) -> dict:
    project = get_home_project(db, user.id, project_id)
    _require_project_access(db, project, user.id, min_role="editor")
    stage = next((s for s in project.stages if s.stage_number == stage_number), None)
    if not stage:
        raise HTTPException(404, "Etapa no encontrada")

    prompt = _build_ai_prompt(project, stage, question)
    result = answer_construction_question(prompt)
    guidance = result.get("text", "")

    catalog = _stage_catalog_by_number().get(stage_number, {})
    if catalog.get("plan_review"):
        guidance += (
            "\n\n—\n**Revisión con ARCHITECT:** en esta etapa puedes subir el plano "
            "en el Workspace y vincular el análisis a esta etapa desde el panel del proyecto."
        )

    stage.ai_guidance = guidance
    stage.updated_at = datetime.utcnow()
    project.updated_at = datetime.utcnow()
    db.commit()

    return {
        "stage_number": stage_number,
        "guidance": guidance,
        "municipality": result.get("municipality"),
        "local_sources": result.get("local_sources", []),
        "web_sources": result.get("web_sources", []),
        "thresholds": result.get("thresholds", []),
        "web_search_used": result.get("web_search_used", False),
        "plan_review_recommended": bool(catalog.get("plan_review")),
    }


def _analysis_summary(db: Session, user_id: int, analysis_id: int | None) -> dict | None:
    if not analysis_id:
        return None
    row = (
        db.query(Analysis)
        .filter(Analysis.id == analysis_id, Analysis.user_id == user_id)
        .first()
    )
    if not row:
        return None
    counts = row.counts_json or {}
    return {
        "id": row.id,
        "filename": row.original_filename,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "counts": counts,
        "errors": counts.get("errors", 0),
        "warnings": counts.get("warnings", 0),
        "chat_id": row.chat_id,
    }


def _documents_for_stage(
    project: HomeProject, stage_number: int, *, section_id: int | None = None
) -> list[dict]:
    docs = [
        d
        for d in (project.documents or [])
        if d.stage_number == stage_number
        and (section_id is None or d.section_id == section_id)
    ]
    docs.sort(key=lambda d: d.created_at or datetime.min, reverse=True)
    return [_document_payload(project, d) for d in docs]


def _section_doc_count(project: HomeProject, section_id: int) -> int:
    return sum(1 for d in (project.documents or []) if d.section_id == section_id)


def _require_section_has_documents(
    project: HomeProject, section: HomeProjectSection
) -> None:
    if _section_doc_count(project, section.id) < 1:
        raise HTTPException(
            400,
            "Sube documentación en este apartado antes de comentar o revisar",
        )


def _require_unassigned_section_owner(
    section: HomeProjectSection, actor_role: str
) -> None:
    if section.assigned_to_user_id:
        return
    if actor_role in ("owner", "admin"):
        return
    raise HTTPException(
        403,
        "Este apartado no tiene responsable asignado. Solo la persona propietaria puede trabajarlo hasta asignar responsable.",
    )


_REVIEW_STATUSES_REQUIRING_COMMENT = frozenset(
    {
        HomeProjectSectionStatus.needs_details,
        HomeProjectSectionStatus.needs_correction,
    }
)

_MENTION_RE = re.compile(r"@([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})")


def _permissions_for_role(role: str | None) -> dict[str, bool]:
    is_member = bool(role)
    is_editor = role in ("owner", "editor", "admin")
    is_owner_or_admin = role in ("owner", "admin")
    return {
        "can_view": is_member,
        "can_edit": is_editor,
        "can_review": is_editor,
        "can_comment": is_editor,
        "can_upload": is_editor,
        "can_assign": is_owner_or_admin,
        "can_create_section": is_editor,
        "can_delete_documents": is_editor,
        "can_delete_section": is_owner_or_admin,
        "can_manage_team": is_owner_or_admin,
        "can_delete_project": is_owner_or_admin,
        "can_advance_stage": is_owner_or_admin,
        "can_complete_stage": is_owner_or_admin,
        "can_reopen_section": is_owner_or_admin,
        "can_reopen_stage": is_owner_or_admin,
        "is_global_admin": role == "admin",
        "is_project_owner": role == "owner",
    }


def _project_member_emails(db: Session, project: HomeProject) -> dict[str, int]:
    out: dict[str, int] = {}
    owner = db.query(User).filter(User.id == project.user_id).first()
    if owner:
        out[owner.email.lower()] = owner.id
    for member in project.members or []:
        u = member.user or db.query(User).filter(User.id == member.user_id).first()
        if u:
            out[u.email.lower()] = u.id
    return out


def _extract_mentions(body: str) -> list[str]:
    return list({m.group(1).lower() for m in _MENTION_RE.finditer(body or "")})


def _notify_mentions(
    db: Session,
    project: HomeProject,
    section: HomeProjectSection,
    actor: User,
    body: str,
) -> None:
    emails = _extract_mentions(body)
    if not emails:
        return
    member_map = _project_member_emails(db, project)
    actor_name = actor.full_name or actor.email
    for email in emails:
        uid = member_map.get(email)
        if not uid or uid == actor.id:
            continue
        user = db.query(User).filter(User.id == uid).first()
        if not user:
            continue
        send_mention_email(
            to_email=user.email,
            project_name=project.name,
            project_id=project.id,
            section_title=section.title,
            author_name=actor_name,
            comment=body,
        )


def _notify_assignee(
    db: Session,
    project: HomeProject,
    section: HomeProjectSection,
    actor: User,
    assignee_id: int | None,
) -> None:
    if not assignee_id or assignee_id == actor.id:
        return
    user = db.query(User).filter(User.id == assignee_id).first()
    if not user:
        return
    send_section_assigned_email(
        to_email=user.email,
        project_name=project.name,
        project_id=project.id,
        section_title=section.title,
        assigner_name=actor.full_name or actor.email,
    )


def _notify_status_change(
    db: Session,
    project: HomeProject,
    section: HomeProjectSection,
    actor: User,
    new_status: HomeProjectSectionStatus,
    comment: str = "",
) -> None:
    if not section.assigned_to_user_id or section.assigned_to_user_id == actor.id:
        return
    user = db.query(User).filter(User.id == section.assigned_to_user_id).first()
    if not user:
        return
    send_section_review_email(
        to_email=user.email,
        project_name=project.name,
        project_id=project.id,
        section_title=section.title,
        reviewer_name=actor.full_name or actor.email,
        new_status=new_status.value,
        comment=comment,
    )


def _last_review_payload(db: Session, section_id: int) -> dict | None:
    if not db:
        return None
    ev = (
        db.query(HomeProjectEvent)
        .filter(
            HomeProjectEvent.section_id == section_id,
            HomeProjectEvent.event_type == HomeProjectEventType.section_status_changed,
        )
        .order_by(HomeProjectEvent.created_at.desc())
        .first()
    )
    if not ev:
        return None
    meta = ev.metadata_json or {}
    actor = (
        db.query(User).filter(User.id == ev.actor_user_id).first()
        if ev.actor_user_id
        else None
    )
    return {
        "status": meta.get("to"),
        "previous_status": meta.get("from"),
        "author_name": (actor.full_name or actor.email) if actor else "Sistema",
        "comment_preview": meta.get("comment_preview"),
        "created_at": ev.created_at.isoformat() if ev.created_at else None,
    }


def _event_payload(db: Session, event: HomeProjectEvent) -> dict:
    actor = (
        db.query(User).filter(User.id == event.actor_user_id).first()
        if event.actor_user_id
        else None
    )
    section_title = None
    if event.section_id:
        sec = db.query(HomeProjectSection).filter(HomeProjectSection.id == event.section_id).first()
        section_title = sec.title if sec else None
    return {
        "id": event.id,
        "event_type": event.event_type.value,
        "actor_user_id": event.actor_user_id,
        "actor_name": (actor.full_name or actor.email) if actor else "Sistema",
        "section_id": event.section_id,
        "section_title": section_title,
        "document_id": event.document_id,
        "comment_id": event.comment_id,
        "metadata": event.metadata_json or {},
        "created_at": event.created_at.isoformat() if event.created_at else None,
    }


def list_project_events(
    db: Session,
    user: User,
    project_id: str,
    *,
    limit: int = 50,
    offset: int = 0,
) -> dict:
    project = get_home_project(db, user.id, project_id)
    lim = min(max(limit, 1), 200)
    off = max(offset, 0)
    rows = (
        db.query(HomeProjectEvent)
        .filter(HomeProjectEvent.project_id == project.id)
        .order_by(HomeProjectEvent.created_at.desc())
        .offset(off)
        .limit(lim + 1)
        .all()
    )
    has_more = len(rows) > lim
    rows = rows[:lim]
    return {
        "events": [_event_payload(db, e) for e in rows],
        "next_offset": off + len(rows),
        "has_more": has_more,
    }


def list_section_comments(
    db: Session,
    user: User,
    project_id: str,
    section_id: int,
    *,
    limit: int = 50,
    offset: int = 0,
) -> dict:
    project = get_home_project(db, user.id, project_id)
    _require_project_access(db, project, user.id, min_role="viewer")
    section = (
        db.query(HomeProjectSection)
        .filter(
            HomeProjectSection.id == section_id,
            HomeProjectSection.project_id == project.id,
        )
        .first()
    )
    if not section:
        raise HTTPException(404, "Apartado no encontrado")
    lim = min(max(limit, 1), 200)
    off = max(offset, 0)
    q = (
        db.query(HomeProjectSectionComment)
        .filter(HomeProjectSectionComment.section_id == section.id)
        .order_by(HomeProjectSectionComment.created_at.asc())
    )
    total = q.count()
    rows = q.offset(off).limit(lim).all()
    return {
        "comments": [_comment_payload(c, db) for c in rows],
        "total": total,
        "offset": off,
        "limit": lim,
        "has_more": off + len(rows) < total,
    }


def _user_brief(db: Session, user_id: int | None) -> dict | None:
    if not user_id:
        return None
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        return None
    return {
        "user_id": u.id,
        "email": u.email,
        "full_name": u.full_name or u.email,
        "avatar_url": u.avatar_url,
    }


def _validate_assignee(db: Session, project: HomeProject, user_id: int | None) -> None:
    if user_id is None:
        return
    if user_id == project.user_id:
        return
    member = (
        db.query(HomeProjectMember)
        .filter(
            HomeProjectMember.project_id == project.id,
            HomeProjectMember.user_id == user_id,
        )
        .first()
    )
    if not member:
        raise HTTPException(400, "Solo puedes asignar a miembros del proyecto")


def _comments_for_sections(
    db: Session, section_ids: list[int]
) -> dict[int, list[HomeProjectSectionComment]]:
    if not section_ids:
        return {}
    rows = (
        db.query(HomeProjectSectionComment)
        .filter(HomeProjectSectionComment.section_id.in_(section_ids))
        .order_by(HomeProjectSectionComment.created_at.asc())
        .all()
    )
    out: dict[int, list[HomeProjectSectionComment]] = {}
    for row in rows:
        out.setdefault(row.section_id, []).append(row)
    return out


def _comment_payload(comment: HomeProjectSectionComment, db: Session) -> dict:
    author = comment.author or db.query(User).filter(User.id == comment.user_id).first()
    return {
        "id": comment.id,
        "section_id": comment.section_id,
        "user_id": comment.user_id,
        "author_name": (author.full_name or author.email) if author else "Usuario",
        "author_email": author.email if author else "",
        "body": comment.body,
        "created_at": comment.created_at.isoformat() if comment.created_at else None,
        "updated_at": comment.updated_at.isoformat() if comment.updated_at else None,
    }


def _section_payload(
    db: Session,
    project: HomeProject,
    sec: HomeProjectSection,
    all_docs: list[HomeProjectDocument],
    comments: list[HomeProjectSectionComment] | None = None,
    *,
    comments_preview_limit: int = 3,
) -> dict:
    sec_docs = [d for d in all_docs if d.section_id == sec.id]
    if comments is None:
        comments = (
            db.query(HomeProjectSectionComment)
            .filter(HomeProjectSectionComment.section_id == sec.id)
            .order_by(HomeProjectSectionComment.created_at.asc())
            .all()
        )
    preview = comments[-comments_preview_limit:] if comments_preview_limit > 0 else []
    return {
        "id": sec.id,
        "stage_number": sec.stage_number,
        "title": sec.title,
        "description": sec.description,
        "status": sec.status.value,
        "sort_order": sec.sort_order,
        "is_catalog": sec.is_catalog,
        "assigned_to": _user_brief(db, sec.assigned_to_user_id),
        "assigned_to_user_id": sec.assigned_to_user_id,
        "has_documents": len(sec_docs) > 0,
        "documents": [_document_payload(project, d) for d in sec_docs],
        "comments": [_comment_payload(c, db) for c in preview],
        "comments_count": len(comments),
        "last_review": _last_review_payload(db, sec.id),
        "created_at": sec.created_at.isoformat() if sec.created_at else None,
        "updated_at": sec.updated_at.isoformat() if sec.updated_at else None,
    }


def create_section(
    db: Session,
    user: User,
    project_id: str,
    stage_number: int,
    *,
    title: str,
    description: str = "",
) -> HomeProjectSection:
    if stage_number < 1 or stage_number > 9:
        raise HTTPException(400, "Etapa inválida (1-9)")
    title = (title or "").strip()
    if len(title) < 2:
        raise HTTPException(400, "El título del apartado es obligatorio")
    project = get_home_project(db, user.id, project_id)
    _require_project_access(db, project, user.id, min_role="editor")
    stage = next((s for s in project.stages if s.stage_number == stage_number), None)
    if not stage:
        raise HTTPException(404, "Etapa no encontrada")
    existing = _sections_for_stage(project, stage_number)
    section = HomeProjectSection(
        project_id=project.id,
        stage_number=stage_number,
        title=title,
        description=(description or "").strip(),
        sort_order=len(existing),
        status=HomeProjectSectionStatus.pending,
        created_by=user.id,
        is_catalog=False,
    )
    db.add(section)
    project.updated_at = datetime.utcnow()
    stage.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(section)
    return section


def update_section(
    db: Session,
    user: User,
    project_id: str,
    section_id: int,
    *,
    title: str | None = None,
    description: str | None = None,
    status: str | None = None,
    sort_order: int | None = None,
    assigned_to_user_id: int | None = None,
    clear_assignment: bool = False,
    review_comment: str | None = None,
    reopen_reason: str | None = None,
) -> HomeProjectSection:
    project = get_home_project(db, user.id, project_id)
    actor_role = _require_project_access(db, project, user.id, min_role="editor")
    is_owner_or_admin = actor_role in ("owner", "admin")
    section = (
        db.query(HomeProjectSection)
        .filter(
            HomeProjectSection.id == section_id,
            HomeProjectSection.project_id == project.id,
        )
        .first()
    )
    if not section:
        raise HTTPException(404, "Apartado no encontrado")
    wants_work_change = (
        title is not None
        or description is not None
        or status is not None
        or sort_order is not None
        or bool((review_comment or "").strip())
    )
    if wants_work_change:
        _require_unassigned_section_owner(section, actor_role)
    prev_assignee = section.assigned_to_user_id
    prev_status = section.status
    review_comment_text = ""
    reopen_reason_text = ""

    if prev_status == HomeProjectSectionStatus.completed and not is_owner_or_admin:
        changing = (
            title is not None
            or description is not None
            or status is not None
            or sort_order is not None
            or clear_assignment
            or assigned_to_user_id is not None
        )
        if changing:
            raise HTTPException(
                403,
                "Este apartado está completado. Solo el propietario o un administrador pueden reabrirlo",
            )

    if title is not None:
        title = title.strip()
        if len(title) < 2:
            raise HTTPException(400, "Título inválido")
        section.title = title
    if description is not None:
        section.description = description.strip()
    if status is not None:
        try:
            new_status = HomeProjectSectionStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Estado de apartado inválido") from exc
        if (
            prev_status == HomeProjectSectionStatus.completed
            and new_status != HomeProjectSectionStatus.completed
        ):
            _require_project_owner_or_admin(db, project, user.id)
            reopen_reason_text = _validate_reopen_reason(reopen_reason)
        if new_status != HomeProjectSectionStatus.pending and actor_role != "admin":
            _require_section_has_documents(project, section)
        if new_status in _REVIEW_STATUSES_REQUIRING_COMMENT:
            comment_text = (review_comment or reopen_reason or "").strip()
            if len(comment_text) < 1:
                raise HTTPException(
                    400,
                    "Debes incluir un comentario al marcar «le faltan detalles» "
                    "o «requiere corrección»",
                )
            if len(comment_text) > 4000:
                raise HTTPException(400, "Comentario demasiado largo (máx. 4000)")
        section.status = new_status
        comment_text = (review_comment or "").strip()
        review_comment_text = comment_text
        if comment_text:
            if len(comment_text) > 4000:
                raise HTTPException(400, "Comentario demasiado largo (máx. 4000)")
            db.add(
                HomeProjectSectionComment(
                    section_id=section.id,
                    user_id=user.id,
                    body=comment_text,
                )
            )
    if sort_order is not None:
        section.sort_order = sort_order
    if clear_assignment or assigned_to_user_id is not None:
        _require_project_owner_or_admin(db, project, user.id)
    if clear_assignment:
        section.assigned_to_user_id = None
    elif assigned_to_user_id is not None:
        if assigned_to_user_id == 0:
            section.assigned_to_user_id = None
        else:
            _validate_assignee(db, project, assigned_to_user_id)
            section.assigned_to_user_id = assigned_to_user_id
    # Si se reabre un apartado, también reabrimos la etapa si estaba cerrada.
    if (
        prev_status == HomeProjectSectionStatus.completed
        and section.status != HomeProjectSectionStatus.completed
    ):
        stage = next(
            (s for s in (project.stages or []) if s.stage_number == section.stage_number),
            None,
        )
        if stage and stage.status == HomeStageStatus.completed:
            stage.status = HomeStageStatus.in_progress
            stage.completed_at = None
            stage.updated_at = datetime.utcnow()

    section.updated_at = datetime.utcnow()
    project.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(section)

    if prev_assignee != section.assigned_to_user_id:
        _log_event(
            db,
            project=project,
            actor_user_id=user.id,
            event_type=HomeProjectEventType.section_assigned,
            section_id=section.id,
            metadata={"from": prev_assignee, "to": section.assigned_to_user_id},
        )
        db.commit()
        _notify_assignee(db, project, section, user, section.assigned_to_user_id)

    if prev_status != section.status:
        if (
            prev_status == HomeProjectSectionStatus.completed
            and section.status != HomeProjectSectionStatus.completed
        ):
            _log_event(
                db,
                project=project,
                actor_user_id=user.id,
                event_type=HomeProjectEventType.section_reopened,
                section_id=section.id,
                metadata={
                    "from": prev_status.value,
                    "to": section.status.value,
                    "reason": reopen_reason_text,
                },
            )
            db.commit()
            _notify_reopen(
                db,
                project,
                user,
                target_label=f"el apartado «{section.title}»",
                reason=reopen_reason_text,
                admin_override=actor_role == "admin" and _is_global_admin(db, user.id),
            )
        else:
            _log_event(
                db,
                project=project,
                actor_user_id=user.id,
                event_type=HomeProjectEventType.section_status_changed,
                section_id=section.id,
                metadata={
                    "from": prev_status.value,
                    "to": section.status.value,
                    "comment_preview": review_comment_text[:180] if review_comment_text else None,
                },
            )
            db.commit()
            _notify_status_change(
                db, project, section, user, section.status, review_comment_text
            )
        if review_comment_text:
            _notify_mentions(db, project, section, user, review_comment_text)
    return section


def delete_section(
    db: Session, user: User, project_id: str, section_id: int
) -> None:
    project = get_home_project(db, user.id, project_id)
    _require_project_owner_or_admin(db, project, user.id)
    section = (
        db.query(HomeProjectSection)
        .filter(
            HomeProjectSection.id == section_id,
            HomeProjectSection.project_id == project.id,
        )
        .first()
    )
    if not section:
        raise HTTPException(404, "Apartado no encontrado")
    for doc in list(project.documents or []):
        if doc.section_id == section_id:
            path = Path(doc.stored_path)
            if path.is_file():
                try:
                    path.unlink()
                except OSError:
                    pass
            db.delete(doc)
    db.delete(section)
    project.updated_at = datetime.utcnow()
    db.commit()


def add_section_comment(
    db: Session,
    user: User,
    project_id: str,
    section_id: int,
    *,
    body: str,
) -> HomeProjectSectionComment:
    body = (body or "").strip()
    if len(body) < 1:
        raise HTTPException(400, "El comentario no puede estar vacío")
    if len(body) > 4000:
        raise HTTPException(400, "Comentario demasiado largo (máx. 4000)")
    project = get_home_project(db, user.id, project_id)
    actor_role = _require_project_access(db, project, user.id, min_role="editor")
    section = (
        db.query(HomeProjectSection)
        .filter(
            HomeProjectSection.id == section_id,
            HomeProjectSection.project_id == project.id,
        )
        .first()
    )
    if not section:
        raise HTTPException(404, "Apartado no encontrado")
    _require_unassigned_section_owner(section, actor_role)
    _require_section_has_documents(project, section)
    comment = HomeProjectSectionComment(
        section_id=section.id,
        user_id=user.id,
        body=body,
    )
    db.add(comment)
    section.updated_at = datetime.utcnow()
    project.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(comment)
    _log_event(
        db,
        project=project,
        actor_user_id=user.id,
        event_type=HomeProjectEventType.section_comment_added,
        section_id=section.id,
        comment_id=comment.id,
        metadata={"preview": body[:180]},
    )
    db.commit()
    _notify_mentions(db, project, section, user, body)
    return comment


def delete_section_comment(
    db: Session,
    user: User,
    project_id: str,
    section_id: int,
    comment_id: int,
) -> None:
    project = get_home_project(db, user.id, project_id)
    role = _require_project_access(db, project, user.id, min_role="editor")
    comment = (
        db.query(HomeProjectSectionComment)
        .join(HomeProjectSection, HomeProjectSection.id == HomeProjectSectionComment.section_id)
        .filter(
            HomeProjectSectionComment.id == comment_id,
            HomeProjectSectionComment.section_id == section_id,
            HomeProjectSection.project_id == project.id,
        )
        .first()
    )
    if not comment:
        raise HTTPException(404, "Comentario no encontrado")
    if comment.user_id != user.id and role not in ("owner", "admin"):
        raise HTTPException(403, "No puedes eliminar este comentario")
    db.delete(comment)
    project.updated_at = datetime.utcnow()
    db.commit()
    _log_event(
        db,
        project=project,
        actor_user_id=user.id,
        event_type=HomeProjectEventType.section_comment_deleted,
        section_id=section_id,
        comment_id=comment_id,
    )
    db.commit()


def invite_project_member(
    db: Session,
    user: User,
    project_id: str,
    *,
    email: str,
    role: str = "editor",
) -> dict:
    project = get_home_project(db, user.id, project_id)
    _require_project_owner_or_admin(db, project, user.id)
    assert_can_invite_members(db, user)
    email = (email or "").strip().lower()
    if not email or "@" not in email:
        raise HTTPException(400, "Correo inválido")
    try:
        member_role = HomeProjectMemberRole(role)
    except ValueError as exc:
        raise HTTPException(400, "Rol inválido (editor o viewer)") from exc

    target = db.query(User).filter(User.email == email).first()
    if target:
        if target.id == project.user_id:
            raise HTTPException(400, "Esa persona ya es la propietaria del proyecto")
        existing = (
            db.query(HomeProjectMember)
            .filter(
                HomeProjectMember.project_id == project.id,
                HomeProjectMember.user_id == target.id,
            )
            .first()
        )
        if existing:
            existing.role = member_role
            db.commit()
            return {"status": "member_updated", "email": email, "role": member_role.value}
        db.add(
            HomeProjectMember(
                project_id=project.id,
                user_id=target.id,
                role=member_role,
            )
        )
        db.commit()
        return {"status": "member_added", "email": email, "role": member_role.value}

    token = secrets.token_urlsafe(32)
    invite = HomeProjectInvite(
        project_id=project.id,
        email=email,
        role=member_role,
        token=token,
        invited_by=user.id,
        expires_at=datetime.utcnow() + timedelta(days=14),
    )
    db.add(invite)
    db.commit()
    inviter_name = user.full_name or user.email
    email_sent = send_project_invite_email(
        to_email=email,
        project_name=project.name,
        inviter_name=inviter_name,
        role=member_role.value,
        token=token,
    )
    _log_event(
        db,
        project=project,
        actor_user_id=user.id,
        event_type=HomeProjectEventType.member_invited,
        metadata={"email": email, "role": member_role.value, "email_sent": email_sent},
    )
    db.commit()
    return {
        "status": "invite_created",
        "email": email,
        "role": member_role.value,
        "token": token,
        "accept_path": f"/api/home-projects/invites/accept",
        "email_sent": email_sent,
    }


def accept_project_invite(db: Session, user: User, token: str) -> HomeProject:
    token = (token or "").strip()
    if not token:
        raise HTTPException(400, "Token de invitación requerido")
    invite = (
        db.query(HomeProjectInvite)
        .filter(
            HomeProjectInvite.token == token,
            HomeProjectInvite.accepted_at.is_(None),
        )
        .first()
    )
    if not invite:
        raise HTTPException(404, "Invitación no encontrada o ya usada")
    if invite.expires_at < datetime.utcnow():
        raise HTTPException(410, "La invitación ha expirado")
    if user.email.lower() != invite.email.lower():
        raise HTTPException(403, "Esta invitación es para otro correo")

    existing = (
        db.query(HomeProjectMember)
        .filter(
            HomeProjectMember.project_id == invite.project_id,
            HomeProjectMember.user_id == user.id,
        )
        .first()
    )
    if not existing:
        db.add(
            HomeProjectMember(
                project_id=invite.project_id,
                user_id=user.id,
                role=invite.role,
            )
        )
    invite.accepted_at = datetime.utcnow()
    db.commit()
    project = get_home_project(db, user.id, invite.project_id)
    _log_event(
        db,
        project=project,
        actor_user_id=user.id,
        event_type=HomeProjectEventType.member_joined,
        metadata={"email": user.email, "role": invite.role.value},
    )
    db.commit()
    return project


def remove_project_member(
    db: Session, user: User, project_id: str, member_user_id: int
) -> None:
    project = get_home_project(db, user.id, project_id)
    _require_project_owner_or_admin(db, project, user.id)
    if member_user_id == project.user_id:
        raise HTTPException(400, "No puedes quitar al propietario")
    row = (
        db.query(HomeProjectMember)
        .filter(
            HomeProjectMember.project_id == project.id,
            HomeProjectMember.user_id == member_user_id,
        )
        .first()
    )
    if not row:
        raise HTTPException(404, "Miembro no encontrado")
    removed_user = db.query(User).filter(User.id == member_user_id).first()
    removed_role = row.role.value
    removed_email = removed_user.email if removed_user else None
    db.delete(row)
    project.updated_at = datetime.utcnow()
    db.commit()
    _log_event(
        db,
        project=project,
        actor_user_id=user.id,
        event_type=HomeProjectEventType.member_removed,
        metadata={
            "email": removed_email,
            "role": removed_role,
        },
    )
    db.commit()


def add_stage_document(
    db: Session,
    user: User,
    project_id: str,
    stage_number: int,
    *,
    filename: str,
    content: bytes,
    mime_type: str = "",
    section_id: int | None = None,
) -> HomeProjectDocument:
    if stage_number < 1 or stage_number > 9:
        raise HTTPException(400, "Etapa inválida (1-9)")
    project = get_home_project(db, user.id, project_id)
    actor_role = _require_project_access(db, project, user.id, min_role="editor")
    stage = next((s for s in project.stages if s.stage_number == stage_number), None)
    if not stage:
        raise HTTPException(404, "Etapa no encontrada")

    section = None
    if section_id is not None:
        section = (
            db.query(HomeProjectSection)
            .filter(
                HomeProjectSection.id == section_id,
                HomeProjectSection.project_id == project.id,
                HomeProjectSection.stage_number == stage_number,
            )
            .first()
        )
        if not section:
            raise HTTPException(404, "Apartado no encontrado")
        _require_unassigned_section_owner(section, actor_role)

    max_bytes = MAX_PROJECT_DOC_MB * 1024 * 1024
    if len(content) > max_bytes:
        raise HTTPException(413, f"Archivo demasiado grande (máx. {MAX_PROJECT_DOC_MB} MB)")

    # La cuota de GB aplica al dueño del proyecto (quien paga el almacenamiento).
    owner = db.query(User).filter(User.id == project.user_id).first() or user
    assert_can_store_documentation(db, owner, additional_bytes=len(content))

    doc = HomeProjectDocument(
        project_id=project.id,
        user_id=user.id,
        stage_number=stage_number,
        section_id=section_id,
        original_filename=Path(filename or "documento").name,
        stored_path="",
        mime_type=(mime_type or "application/octet-stream")[:120],
        file_size=len(content),
    )
    db.add(doc)
    db.flush()
    try:
        path = save_project_document(user.id, project.id, doc.id, content, filename)
    except ValueError as exc:
        db.rollback()
        raise HTTPException(400, str(exc)) from exc
    doc.stored_path = str(path)
    if section:
        section.status = HomeProjectSectionStatus.in_progress
        section.updated_at = datetime.utcnow()
    project.updated_at = datetime.utcnow()
    stage.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(doc)
    _log_event(
        db,
        project=project,
        actor_user_id=user.id,
        event_type=HomeProjectEventType.document_uploaded,
        section_id=section_id,
        document_id=doc.id,
        metadata={
            "filename": doc.original_filename,
            "bytes": doc.file_size,
            "mime_type": doc.mime_type,
        },
    )
    db.commit()
    return doc


def delete_stage_document(
    db: Session, user: User, project_id: str, document_id: int
) -> None:
    project = get_home_project(db, user.id, project_id)
    actor_role = _require_project_access(db, project, user.id, min_role="editor")
    doc = (
        db.query(HomeProjectDocument)
        .filter(
            HomeProjectDocument.id == document_id,
            HomeProjectDocument.project_id == project.id,
        )
        .first()
    )
    if not doc:
        raise HTTPException(404, "Documento no encontrado")
    section_id = doc.section_id
    path = Path(doc.stored_path)
    if path.is_file():
        try:
            path.unlink()
        except OSError:
            pass
    db.delete(doc)
    db.flush()
    if section_id:
        section = (
            db.query(HomeProjectSection)
            .filter(
                HomeProjectSection.id == section_id,
                HomeProjectSection.project_id == project.id,
            )
            .first()
        )
        if section:
            _require_unassigned_section_owner(section, actor_role)
            remaining = (
                db.query(HomeProjectDocument)
                .filter(
                    HomeProjectDocument.project_id == project.id,
                    HomeProjectDocument.section_id == section_id,
                )
                .count()
            )
            if remaining == 0:
                section.status = HomeProjectSectionStatus.pending
                section.updated_at = datetime.utcnow()
    project.updated_at = datetime.utcnow()
    db.commit()
    _log_event(
        db,
        project=project,
        actor_user_id=user.id,
        event_type=HomeProjectEventType.document_deleted,
        section_id=section_id,
        document_id=document_id,
    )
    db.commit()


def get_stage_document(
    db: Session, user: User, project_id: str, document_id: int
) -> HomeProjectDocument:
    project = get_home_project(db, user.id, project_id)
    doc = (
        db.query(HomeProjectDocument)
        .filter(
            HomeProjectDocument.id == document_id,
            HomeProjectDocument.project_id == project.id,
        )
        .first()
    )
    if not doc:
        raise HTTPException(404, "Documento no encontrado")
    return doc


def project_payload(
    project: HomeProject, db: Session | None = None, *, user_id: int | None = None
) -> dict:
    if db:
        _ensure_sections_migrated(db, project)
    catalog = _stage_catalog_by_number()
    all_docs = list(project.documents or [])
    section_ids = [s.id for s in (project.sections or [])]
    comments_map = _comments_for_sections(db, section_ids) if db else {}
    stages_out = []
    for stage in sorted(project.stages, key=lambda s: s.stage_number):
        cat = catalog.get(stage.stage_number, {})
        sections = _sections_for_stage(project, stage.stage_number)
        sec_progress = {
            "done": sum(1 for s in sections if s.status == HomeProjectSectionStatus.completed),
            "total": len(sections),
            "with_files": sum(
                1 for s in sections if any(d.section_id == s.id for d in all_docs)
            ),
            "assigned": sum(1 for s in sections if s.assigned_to_user_id),
            "needs_action": sum(
                1
                for s in sections
                if s.status
                in (
                    HomeProjectSectionStatus.needs_details,
                    HomeProjectSectionStatus.needs_correction,
                )
            ),
            "without_docs": sum(
                1
                for s in sections
                if not any(d.section_id == s.id for d in all_docs)
            ),
        }
        sections_out = [
            _section_payload(
                db,
                project,
                sec,
                all_docs,
                comments_map.get(sec.id, []),
            )
            for sec in sections
        ]
        stages_out.append(
            {
                "stage_number": stage.stage_number,
                "slug": stage.slug,
                "title": stage.title,
                "summary": cat.get("summary", ""),
                "status": stage.status.value,
                "sections": sections_out,
                "sections_progress": sec_progress,
                "notes": stage.notes,
                "ai_guidance": stage.ai_guidance,
                "analysis_id": stage.analysis_id,
                "analysis": (
                    _analysis_summary(db, project.user_id, stage.analysis_id)
                    if db
                    else None
                ),
                "documents": _documents_for_stage(
                    project, stage.stage_number, section_id=None
                ),
                "plan_review": bool(cat.get("plan_review")),
                "started_at": stage.started_at.isoformat() if stage.started_at else None,
                "completed_at": stage.completed_at.isoformat() if stage.completed_at else None,
                "updated_at": stage.updated_at.isoformat() if stage.updated_at else None,
            }
        )

    completed = sum(1 for s in project.stages if s.status == HomeStageStatus.completed)
    my_role = _member_role(db, project, user_id) if db and user_id is not None else None
    members = _members_payload(db, project) if db else []
    files = sorted(
        [_document_payload(project, d) for d in all_docs],
        key=lambda x: x.get("created_at") or "",
        reverse=True,
    )
    return {
        "id": project.id,
        "name": project.name,
        "client_name": project.client_name,
        "location": project.location,
        "description": project.description,
        "status": project.status.value,
        "current_stage": project.current_stage,
        "progress_percent": round(completed / 9 * 100),
        "stages_completed": completed,
        "metadata": project.metadata_json or {},
        "stages": stages_out,
        "members": members,
        "files": files,
        "my_role": my_role,
        "permissions": _permissions_for_role(my_role),
        "created_at": project.created_at.isoformat() if project.created_at else None,
        "updated_at": project.updated_at.isoformat() if project.updated_at else None,
    }


def catalog_payload() -> list[dict]:
    return [
        {
            "number": int(s["number"]),
            "slug": s["slug"],
            "title": s["title"],
            "summary": s.get("summary", ""),
            "tasks": s.get("tasks", []),
            "plan_review": bool(s.get("plan_review")),
        }
        for s in load_stage_catalog()
    ]
