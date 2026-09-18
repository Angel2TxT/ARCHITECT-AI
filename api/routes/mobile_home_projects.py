"""API móvil — proyectos casa hogar (9 etapas).

Envuelve la misma lógica de /api/home-projects con respuestas
orientadas a la app Flutter: { ok, ... } y URLs bajo /api/mobile/.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from api.deps import get_current_user
from db.database import get_db
from db.models import Analysis, User
from services.home_project_service import (
    _log_event,
    _require_project_access,
    accept_project_invite,
    add_section_comment,
    add_section_slot,
    add_stage_document,
    advance_to_next_stage,
    assist_stage,
    catalog_payload,
    create_home_project,
    create_section,
    delete_home_project,
    delete_section,
    delete_section_comment,
    delete_section_slot,
    delete_stage_document,
    get_home_project,
    get_stage_document,
    invite_project_member,
    list_home_projects,
    list_project_events,
    list_section_comments,
    project_payload,
    remove_project_member,
    update_home_project,
    update_section,
    update_stage,
)

router = APIRouter(prefix="/api/mobile/home-projects", tags=["mobile-home-projects"])

_MOBILE_PREFIX = "/api/mobile/home-projects"


class HomeProjectCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    client_name: str = Field(default="", max_length=120)
    location: str = Field(default="", max_length=200)
    description: str = Field(default="", max_length=4000)
    metadata: dict[str, Any] | None = None


class HomeProjectUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=160)
    client_name: str | None = Field(default=None, max_length=120)
    location: str | None = Field(default=None, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    status: str | None = None
    metadata: dict[str, Any] | None = None


class StageUpdate(BaseModel):
    status: str | None = None
    notes: str | None = None
    checklist: list[dict[str, Any]] | None = None
    analysis_id: int | None = None
    reopen_reason: str | None = Field(default=None, max_length=4000)


class SectionCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    description: str = Field(default="", max_length=4000)


class SectionUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    status: str | None = None
    sort_order: int | None = None
    assigned_to_user_id: int | None = None
    review_comment: str | None = Field(default=None, max_length=4000)
    reopen_reason: str | None = Field(default=None, max_length=4000)


class SectionCommentCreate(BaseModel):
    body: str = Field(min_length=1, max_length=4000)


class SectionSlotCreate(BaseModel):
    title: str = Field(min_length=2, max_length=120)
    accept: list[str] | None = None
    required: bool = False
    ai_plan_review: bool = False


class InviteMember(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    role: str = Field(default="editor", pattern="^(editor|viewer)$")


class AcceptInvite(BaseModel):
    token: str = Field(min_length=8, max_length=64)


class StageAssistRequest(BaseModel):
    question: str = Field(default="", max_length=2000)


class AdvanceRequest(BaseModel):
    acknowledge_open_findings: bool = False


class AiReviewCreate(BaseModel):
    document_id: int
    section_id: int | None = None
    message: str = Field(default="", max_length=2000)
    weights: str = Field(default="", max_length=512)


class AiFindingUpdate(BaseModel):
    action: str = Field(pattern="^(accept|dismiss|reopen)$")
    note: str = Field(default="", max_length=500)


def _rewrite_download_urls(payload: dict, project_id: str) -> dict:
    """Apunta download_url de documentos al prefijo móvil."""

    def _fix_doc(doc: dict) -> None:
        doc_id = doc.get("id")
        if doc_id is not None:
            doc["download_url"] = f"{_MOBILE_PREFIX}/{project_id}/documents/{doc_id}/file"

    for doc in payload.get("files") or []:
        _fix_doc(doc)

    for stage in payload.get("stages") or []:
        for doc in stage.get("documents") or []:
            _fix_doc(doc)
        for sec in stage.get("sections") or []:
            for doc in sec.get("documents") or []:
                _fix_doc(doc)
            for slot in sec.get("slots") or []:
                for doc in slot.get("documents") or []:
                    _fix_doc(doc)
    return payload


def _payload(db: Session, project, user_id: int) -> dict:
    raw = project_payload(project, db, user_id=user_id)
    return _rewrite_download_urls(raw, project.id)


def _ok_project(db: Session, project, user_id: int) -> dict:
    return {"ok": True, "project": _payload(db, project, user_id)}


@router.get("/catalog")
def mobile_catalog():
    """Catálogo público de las 9 etapas (sin auth)."""
    return {"ok": True, "stages": catalog_payload()}


@router.get("/analyses-picker")
def mobile_analyses_picker(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 30,
):
    """Lista análisis de planos del usuario para vincular a etapas 5–6."""
    rows = (
        db.query(Analysis)
        .filter(Analysis.user_id == user.id)
        .order_by(Analysis.created_at.desc())
        .limit(min(limit, 50))
        .all()
    )
    return {
        "ok": True,
        "analyses": [
            {
                "id": a.id,
                "filename": a.original_filename,
                "created_at": a.created_at.isoformat() if a.created_at else None,
                "counts": a.counts_json or {},
                "chat_id": a.chat_id,
            }
            for a in rows
        ],
    }


@router.get("")
def mobile_list_projects(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    rows = list_home_projects(db, user)
    return {
        "ok": True,
        "projects": [_payload(db, p, user.id) for p in rows],
    }


@router.post("")
def mobile_create_project(
    body: HomeProjectCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    project = create_home_project(
        db,
        user,
        name=body.name,
        client_name=body.client_name,
        location=body.location,
        description=body.description,
        metadata=body.metadata,
    )
    project = get_home_project(db, user.id, project.id)
    return _ok_project(db, project, user.id)


@router.post("/invites/accept")
def mobile_accept_invite(
    body: AcceptInvite,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    project = accept_project_invite(db, user, body.token)
    return _ok_project(db, project, user.id)


@router.get("/{project_id}")
def mobile_get_project(
    project_id: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.patch("/{project_id}")
def mobile_patch_project(
    project_id: str,
    body: HomeProjectUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    project = update_home_project(
        db,
        user,
        project_id,
        name=body.name,
        client_name=body.client_name,
        location=body.location,
        description=body.description,
        status=body.status,
        metadata=body.metadata,
    )
    project = get_home_project(db, user.id, project.id)
    return _ok_project(db, project, user.id)


@router.delete("/{project_id}")
def mobile_delete_project(
    project_id: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    delete_home_project(db, user.id, project_id)
    return {"ok": True}


@router.get("/{project_id}/events")
def mobile_project_events(
    project_id: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 50,
    offset: int = 0,
):
    data = list_project_events(db, user, project_id, limit=limit, offset=offset)
    return {"ok": True, **data}


@router.post("/{project_id}/members/invite")
def mobile_invite_member(
    project_id: str,
    body: InviteMember,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    result = invite_project_member(
        db, user, project_id, email=body.email, role=body.role
    )
    return {"ok": True, **result}


@router.delete("/{project_id}/members/{member_user_id}")
def mobile_remove_member(
    project_id: str,
    member_user_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    remove_project_member(db, user, project_id, member_user_id)
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.post("/{project_id}/stages/{stage_number}/sections")
def mobile_add_section(
    project_id: str,
    stage_number: int,
    body: SectionCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    create_section(
        db,
        user,
        project_id,
        stage_number,
        title=body.title,
        description=body.description,
    )
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.patch("/{project_id}/sections/{section_id}")
def mobile_patch_section(
    project_id: str,
    section_id: int,
    body: SectionUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    update_section(
        db,
        user,
        project_id,
        section_id,
        title=body.title,
        description=body.description,
        status=body.status,
        sort_order=body.sort_order,
        assigned_to_user_id=body.assigned_to_user_id
        if "assigned_to_user_id" in body.model_fields_set
        and body.assigned_to_user_id is not None
        else None,
        clear_assignment="assigned_to_user_id" in body.model_fields_set
        and body.assigned_to_user_id is None,
        review_comment=body.review_comment,
        reopen_reason=body.reopen_reason,
    )
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.delete("/{project_id}/sections/{section_id}")
def mobile_delete_section(
    project_id: str,
    section_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    delete_section(db, user, project_id, section_id)
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.get("/{project_id}/sections/{section_id}/comments")
def mobile_list_comments(
    project_id: str,
    section_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 50,
    offset: int = 0,
):
    data = list_section_comments(
        db, user, project_id, section_id, limit=limit, offset=offset
    )
    return {"ok": True, **data}


@router.post("/{project_id}/sections/{section_id}/comments")
def mobile_add_comment(
    project_id: str,
    section_id: int,
    body: SectionCommentCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    add_section_comment(db, user, project_id, section_id, body=body.body)
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.delete("/{project_id}/sections/{section_id}/comments/{comment_id}")
def mobile_delete_comment(
    project_id: str,
    section_id: int,
    comment_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    delete_section_comment(db, user, project_id, section_id, comment_id)
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.post("/{project_id}/sections/{section_id}/slots")
def mobile_create_section_slot(
    project_id: str,
    section_id: int,
    body: SectionSlotCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    add_section_slot(
        db,
        user,
        project_id,
        section_id,
        title=body.title,
        accept=body.accept,
        required=body.required,
        ai_plan_review=body.ai_plan_review,
    )
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.delete("/{project_id}/sections/{section_id}/slots/{slot_key}")
def mobile_remove_section_slot(
    project_id: str,
    section_id: int,
    slot_key: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    delete_section_slot(db, user, project_id, section_id, slot_key)
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.patch("/{project_id}/stages/{stage_number}")
def mobile_patch_stage(
    project_id: str,
    stage_number: int,
    body: StageUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    update_stage(
        db,
        user,
        project_id,
        stage_number,
        status=body.status,
        notes=body.notes,
        checklist=body.checklist,
        analysis_id=body.analysis_id,
        reopen_reason=body.reopen_reason,
    )
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.post("/{project_id}/stages/{stage_number}/assist")
def mobile_stage_assist(
    project_id: str,
    stage_number: int,
    body: StageAssistRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    result = assist_stage(
        db,
        user,
        project_id,
        stage_number,
        question=body.question,
    )
    return {"ok": True, **result}


@router.post("/{project_id}/stages/{stage_number}/ai-reviews")
async def mobile_create_stage_ai_review(
    project_id: str,
    stage_number: int,
    body: AiReviewCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    from services.home_ai_review_service import create_ai_review_from_document
    from services.home_project_service import _stage_catalog_by_number

    project = get_home_project(db, user.id, project_id)
    _require_project_access(db, project, user.id, min_role="editor")
    cat = _stage_catalog_by_number().get(stage_number, {})
    if not (cat.get("ai_plan_review") or cat.get("plan_review")):
        raise HTTPException(
            400,
            "Esta etapa no admite revisión de plano con IA. Usa el asistente de dudas o la revisión del equipo.",
        )
    result = await create_ai_review_from_document(
        db,
        user,
        project,
        document_id=body.document_id,
        stage_number=stage_number,
        section_id=body.section_id,
        message=body.message,
        weights=body.weights,
        log_event=_log_event,
    )
    project = get_home_project(db, user.id, project_id)
    return {
        "ok": True,
        **result,
        "project": _payload(db, project, user.id),
    }


@router.patch("/{project_id}/ai-reviews/{review_id}/findings/{finding_id}")
def mobile_patch_ai_finding(
    project_id: str,
    review_id: int,
    finding_id: str,
    body: AiFindingUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    from services.home_ai_review_service import update_ai_finding

    project = get_home_project(db, user.id, project_id)
    _require_project_access(db, project, user.id, min_role="editor")
    review = update_ai_finding(
        db,
        user,
        project,
        review_id,
        finding_id=finding_id,
        action=body.action,
        note=body.note,
        log_event=_log_event,
    )
    project = get_home_project(db, user.id, project_id)
    return {
        "ok": True,
        "review": review,
        "project": _payload(db, project, user.id),
    }


@router.post("/{project_id}/stages/{stage_number}/documents")
async def mobile_upload_document(
    project_id: str,
    stage_number: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    file: UploadFile = File(...),
    section_id: int | None = Form(default=None),
    slot_key: str | None = Form(default=None),
):
    content = await file.read()
    if not content:
        raise HTTPException(400, "Archivo vacío")
    doc = add_stage_document(
        db,
        user,
        project_id,
        stage_number,
        filename=file.filename or "documento",
        content=content,
        mime_type=file.content_type or "",
        section_id=section_id,
        slot_key=slot_key,
    )
    project = get_home_project(db, user.id, project_id)
    return {
        "ok": True,
        "document": {
            "id": doc.id,
            "filename": doc.original_filename,
            "file_size": doc.file_size,
            "mime_type": doc.mime_type,
            "section_id": doc.section_id,
            "slot_key": doc.slot_key,
            "download_url": f"{_MOBILE_PREFIX}/{project_id}/documents/{doc.id}/file",
        },
        "project": _payload(db, project, user.id),
    }


@router.get("/{project_id}/documents/{document_id}/file")
def mobile_download_document(
    project_id: str,
    document_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    doc = get_stage_document(db, user, project_id, document_id)
    path = Path(doc.stored_path)
    if not path.is_file():
        raise HTTPException(404, "Archivo no encontrado en disco")
    return FileResponse(
        path,
        filename=doc.original_filename,
        media_type=doc.mime_type or "application/octet-stream",
    )


@router.delete("/{project_id}/documents/{document_id}")
def mobile_delete_document(
    project_id: str,
    document_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    delete_stage_document(db, user, project_id, document_id)
    project = get_home_project(db, user.id, project_id)
    return _ok_project(db, project, user.id)


@router.post("/{project_id}/advance")
def mobile_advance_project(
    project_id: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    body: AdvanceRequest = AdvanceRequest(),
):
    project, advisory = advance_to_next_stage(
        db,
        user,
        project_id,
        acknowledge_open_findings=bool(body.acknowledge_open_findings),
    )
    project = get_home_project(db, user.id, project.id)
    payload = _ok_project(db, project, user.id)
    payload["project"]["advance_advisory"] = advisory
    payload["advance_advisory"] = advisory
    return payload
