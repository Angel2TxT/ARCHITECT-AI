"""Revisiones IA embebidas en el expediente Casa hogar."""

from __future__ import annotations

import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from core.pipeline import analyze_plano_json, find_default_weights
from db.models import (
    Analysis,
    Chat,
    HomeProject,
    HomeProjectAiReview,
    HomeProjectAiReviewStatus,
    HomeProjectDocument,
    HomeProjectEventType,
    HomeProjectSection,
    HomeProjectSectionStatus,
    Message,
    User,
)
from services.cad_service import (
    CadConversionError,
    is_supported_filename,
    prepare_upload_async,
)
from services.storage_service import analysis_dir, save_annotated_jpeg
from services.subscription_service import (
    assert_can_analyze,
    is_admin_user,
    record_analysis_usage,
)

ROOT = Path(__file__).resolve().parents[1]

SCOPE_PRESETS: dict[str, dict[str, Any]] = {
    "habitability_2d": {
        "key": "habitability_2d",
        "title": "Habitabilidad en planta 2D",
        "covers": [
            "Puertas, ventanas, muros y recintos detectados en la planta",
            "Reglas de habitabilidad y vanos (referencia Chiapas / Tuxtla)",
            "Medidas estimadas según la escala del plano (ppm)",
        ],
        "exclusions": [
            "CAD nativo (DXF/DWG)",
            "Cortes, fachadas y volumetría 3D",
            "Estructura e instalaciones",
            "Accesibilidad real en obra",
            "Contenido de Word, Excel u otros documentos de texto",
        ],
    },
    "planta_integral_2d": {
        "key": "planta_integral_2d",
        "title": "Revisión integral de planta 2D",
        "covers": [
            "Detección de puertas, ventanas, muros y recintos",
            "Habitabilidad: áreas, dimensiones, iluminación y ventilación",
            "Vanos: anchos/áreas mínimas, solapes y apoyo en muros",
            "Circulación: pasillos estrechos y accesos a locales",
            "Heurísticas de baño/cocina/recámara/estancia por tamaño",
            "Coherencia de muros y superficie construida estimada",
            "Guía de corrección paso a paso por cada hallazgo",
            "Checklists de dominios fuera de planta (estructura, MEP, accesibilidad, etc.)",
        ],
        "exclusions": [
            "Detección automática de escaleras, columnas o tipologías tipadas (requiere reentrenar YOLO)",
            "Medición real de alturas sin corte",
            "Validación automática de instalaciones/estructura (solo checklist)",
            "Contenido interno de Word/Excel/PDF de texto",
        ],
    },
}

ASK_DISCLAIMER = (
    "Alcance del asistente: respondo con manuales y normas indexadas. "
    "No leo el contenido interno de tus PDF/Office; solo uso el contexto "
    "de la etapa (títulos de apartados, notas y nombres de archivos)."
)


def scope_payload(scope_key: str | None = None) -> dict[str, Any]:
    key = (scope_key or "planta_integral_2d").strip() or "planta_integral_2d"
    if key == "habitability_2d":
        key = "planta_integral_2d"
    preset = SCOPE_PRESETS.get(key) or SCOPE_PRESETS["planta_integral_2d"]
    return {
        "key": preset["key"],
        "title": preset["title"],
        "covers": list(preset["covers"]),
        "exclusions": list(preset["exclusions"]),
    }


def _open_findings_count(findings: list | None) -> int:
    return sum(1 for f in (findings or []) if (f or {}).get("status") == "open")


def ai_review_payload(review: HomeProjectAiReview) -> dict[str, Any]:
    findings = list(review.findings_json or [])
    verdict = review.verdict_json or {}
    scope = review.scope_json or scope_payload()
    return {
        "id": review.id,
        "project_id": review.project_id,
        "stage_number": review.stage_number,
        "section_id": review.section_id,
        "document_id": review.document_id,
        "analysis_id": review.analysis_id,
        "status": review.status.value if review.status else "open",
        "scope": scope,
        "exclusions": review.exclusions_json or scope.get("exclusions") or [],
        "verdict": verdict,
        "findings": findings,
        "open_findings": _open_findings_count(findings),
        "workspace_url": (
            f"/legacy-app?chat=&analysis={review.analysis_id}"
            if review.analysis_id
            else "/legacy-app"
        ),
        "created_at": review.created_at.isoformat() if review.created_at else None,
        "updated_at": review.updated_at.isoformat() if review.updated_at else None,
    }


def list_ai_reviews_for_stage(
    db: Session, project_id: str, stage_number: int
) -> list[HomeProjectAiReview]:
    return (
        db.query(HomeProjectAiReview)
        .filter(
            HomeProjectAiReview.project_id == project_id,
            HomeProjectAiReview.stage_number == stage_number,
        )
        .order_by(HomeProjectAiReview.created_at.desc())
        .all()
    )


def count_open_findings_for_stage(
    db: Session, project_id: str, stage_number: int
) -> int:
    total = 0
    for review in list_ai_reviews_for_stage(db, project_id, stage_number):
        if review.status == HomeProjectAiReviewStatus.dismissed:
            continue
        total += _open_findings_count(review.findings_json)
    return total


def _normalize_findings(issues: list | None) -> list[dict[str, Any]]:
    from rules.remediation import enrich_issue_dict

    out: list[dict[str, Any]] = []
    for i, issue in enumerate(issues or []):
        if not isinstance(issue, dict):
            continue
        sev = str(issue.get("severity") or "info")
        base = {
            "id": f"f-{i + 1}",
            "code": issue.get("code") or "",
            "label": issue.get("label") or issue.get("code") or "Hallazgo",
            "message": issue.get("message") or "",
            "severity": sev,
            "norm_ref": issue.get("norm_ref") or "",
            "class": issue.get("class") or "",
            "status": "open",
            "fix": issue.get("fix") or "",
            "fix_steps": list(issue.get("fix_steps") or []),
        }
        enriched = enrich_issue_dict(base)
        out.append(enriched)
    return out


def _resolve_weights(weights: str = "") -> Path:
    wpath = Path(weights.strip()) if weights.strip() else find_default_weights()
    if wpath is not None and not wpath.is_absolute():
        wpath = ROOT / wpath
    if wpath is None or not wpath.is_file():
        raise HTTPException(
            400,
            "Modelo no encontrado. Entrena con train.py o indica best.pt en Ajustes.",
        )
    return wpath


async def create_ai_review_from_document(
    db: Session,
    user: User,
    project: HomeProject,
    *,
    document_id: int,
    stage_number: int,
    section_id: int | None = None,
    message: str = "",
    weights: str = "",
    log_event=None,
    require_access=None,
) -> dict[str, Any]:
    """Ejecuta el pipeline de análisis sobre un documento del expediente."""
    if require_access:
        require_access()

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
    if doc.stage_number != stage_number:
        raise HTTPException(400, "El documento no pertenece a esta etapa")
    if section_id is not None and doc.section_id and doc.section_id != section_id:
        raise HTTPException(400, "El documento no pertenece a este apartado")

    filename = doc.original_filename or "plano.png"
    if not is_supported_filename(filename):
        raise HTTPException(
            400,
            "Solo se pueden revisar con IA archivos de planta en PNG, JPG, WEBP, TIFF o PDF. "
            "CAD y Office quedan fuera de alcance.",
        )

    stored = Path(doc.stored_path)
    if not stored.is_file():
        raise HTTPException(404, "Archivo no encontrado en almacenamiento")

    content = stored.read_bytes()
    wpath = _resolve_weights(weights)
    assert_can_analyze(
        db,
        user,
        weights_path=str(wpath),
        file_size_bytes=len(content),
    )

    stage = next((s for s in project.stages if s.stage_number == stage_number), None)
    if not stage:
        raise HTTPException(404, "Etapa no encontrada")

    chat = Chat(
        id=str(uuid.uuid4()),
        user_id=user.id,
        title=f"Casa hogar · {project.name[:80]} · etapa {stage_number}"[:120],
    )
    db.add(chat)
    db.flush()

    analysis = Analysis(
        user_id=user.id,
        chat_id=chat.id,
        original_filename=filename,
        source_path="",
        weights_path=str(wpath),
        pixels_per_meter=0.0,
        confidence=0.0,
        user_prompt=(message or "Revisión de planta desde Casa hogar").strip(),
        training_eligible=True,
    )
    db.add(analysis)
    db.flush()

    try:
        prepared = await prepare_upload_async(
            content, filename, analysis_dir(user.id, analysis.id)
        )
    except CadConversionError as exc:
        db.rollback()
        raise HTTPException(400, str(exc)) from exc

    analysis.source_path = str(prepared.original_path)

    prompt = (message or "").strip() or (
        "Revisa esta planta 2D de forma integral: habitabilidad, vanos, circulación, "
        "coherencia de muros y checklists de dominios fuera de planta. "
        "Indica cómo corregir cada incidencia."
    )
    db.add(
        Message(
            chat_id=chat.id,
            role="user",
            content={
                "text": prompt,
                "filename": filename,
                "analysis_id": analysis.id,
                "type": "analysis",
                "home_project_id": project.id,
                "home_stage_number": stage_number,
            },
            analysis_id=analysis.id,
        )
    )

    try:
        result = analyze_plano_json(
            str(prepared.image_path),
            weights=wpath,
            pixels_per_meter=0.0,
            conf=0.0,
            auto_calibrate=True,
            user_prompt=prompt,
        )
        analysis.pixels_per_meter = result.get("pixels_per_meter_used", 100.0)
        analysis.confidence = result.get("confidence_used", 0.18)
    except Exception as exc:
        db.rollback()
        raise HTTPException(500, str(exc)) from exc

    annotated_path = save_annotated_jpeg(user.id, analysis.id, result["image_base64"])
    analysis.annotated_path = str(annotated_path)
    analysis.status_text = result.get("status", "")
    analysis.is_demo_model = result.get("is_demo_model", False)
    analysis.detections_json = result.get("detections")
    analysis.issues_json = result.get("issues")
    analysis.counts_json = result.get("counts")

    from services.analysis_reply_service import compose_analysis_reply

    payload = dict(result)
    if prepared.conversion_note:
        payload["conversion_note"] = prepared.conversion_note
    text, steps, llm_used = compose_analysis_reply(payload)
    counts = result.get("counts") or {}
    assistant_content = {
        "text": text,
        "steps": steps,
        "image_base64": result.get("image_base64"),
        "stats": {
            "detections": counts.get("detections", 0),
            "errors": counts.get("errors", 0),
            "warnings": counts.get("warnings", 0),
        },
        "issues_summary": result.get("issues_summary"),
        "detections_summary": result.get("detections_summary"),
        "verdict": result.get("verdict"),
        "analysis_intent": result.get("analysis_intent"),
        "analysis_id": analysis.id,
        "assistant_mode": "architect",
        "llm_used": llm_used,
        "home_project_id": project.id,
    }

    db.add(
        Message(
            chat_id=chat.id,
            role="assistant",
            content=assistant_content,
            analysis_id=analysis.id,
        )
    )
    chat.updated_at = datetime.utcnow()

    scope = scope_payload("planta_integral_2d")
    findings = _normalize_findings(result.get("issues"))
    review_status = (
        HomeProjectAiReviewStatus.open
        if _open_findings_count(findings)
        else HomeProjectAiReviewStatus.resolved
    )

    review = HomeProjectAiReview(
        project_id=project.id,
        stage_number=stage_number,
        section_id=section_id or doc.section_id,
        document_id=doc.id,
        analysis_id=analysis.id,
        created_by=user.id,
        status=review_status,
        scope_json=scope,
        exclusions_json=list(scope.get("exclusions") or []),
        verdict_json=result.get("verdict") or {},
        findings_json=findings,
    )
    db.add(review)
    db.flush()

    stage.analysis_id = analysis.id
    stage.updated_at = datetime.utcnow()

    target_section_id = section_id or doc.section_id
    if target_section_id and _open_findings_count(findings):
        sec = (
            db.query(HomeProjectSection)
            .filter(
                HomeProjectSection.id == target_section_id,
                HomeProjectSection.project_id == project.id,
            )
            .first()
        )
        if sec and sec.status not in (
            HomeProjectSectionStatus.needs_correction,
            HomeProjectSectionStatus.completed,
        ):
            has_errors = any(
                f.get("severity") == "error" and f.get("status") == "open"
                for f in findings
            )
            if has_errors:
                sec.status = HomeProjectSectionStatus.needs_correction
                sec.updated_at = datetime.utcnow()

    project.updated_at = datetime.utcnow()

    if log_event:
        log_event(
            db,
            project=project,
            actor_user_id=user.id,
            event_type=HomeProjectEventType.ai_review_created,
            section_id=review.section_id,
            document_id=doc.id,
            metadata={
                "ai_review_id": review.id,
                "analysis_id": analysis.id,
                "open_findings": _open_findings_count(findings),
                "stage_number": stage_number,
            },
        )

    if not is_admin_user(user):
        record_analysis_usage(db, user.id)

    db.commit()
    db.refresh(review)

    return {
        "review": ai_review_payload(review),
        "analysis_id": analysis.id,
        "chat_id": chat.id,
        "counts": result.get("counts") or {},
        "verdict": result.get("verdict") or {},
    }


def update_ai_finding(
    db: Session,
    user: User,
    project: HomeProject,
    review_id: int,
    *,
    finding_id: str,
    action: str,
    note: str = "",
    log_event=None,
) -> dict[str, Any]:
    review = (
        db.query(HomeProjectAiReview)
        .filter(
            HomeProjectAiReview.id == review_id,
            HomeProjectAiReview.project_id == project.id,
        )
        .first()
    )
    if not review:
        raise HTTPException(404, "Revisión IA no encontrada")

    action_norm = (action or "").strip().lower()
    if action_norm not in ("accept", "dismiss", "reopen"):
        raise HTTPException(400, "Acción inválida (accept | dismiss | reopen)")

    findings = list(review.findings_json or [])
    found = False
    for item in findings:
        if str(item.get("id")) != str(finding_id):
            continue
        found = True
        if action_norm == "accept":
            item["status"] = "accepted"
            item["resolved_note"] = (note or "").strip()[:500]
            if review.section_id:
                sec = (
                    db.query(HomeProjectSection)
                    .filter(
                        HomeProjectSection.id == review.section_id,
                        HomeProjectSection.project_id == project.id,
                    )
                    .first()
                )
                if sec and sec.status != HomeProjectSectionStatus.completed:
                    sec.status = HomeProjectSectionStatus.needs_correction
                    sec.updated_at = datetime.utcnow()
        elif action_norm == "dismiss":
            if len((note or "").strip()) < 5:
                raise HTTPException(
                    400, "Indica un motivo breve para descartar el hallazgo (mín. 5)"
                )
            item["status"] = "dismissed"
            item["resolved_note"] = note.strip()[:500]
        else:
            item["status"] = "open"
            item.pop("resolved_note", None)
        break

    if not found:
        raise HTTPException(404, "Hallazgo no encontrado")

    review.findings_json = findings
    open_n = _open_findings_count(findings)
    if open_n == 0:
        review.status = HomeProjectAiReviewStatus.resolved
    else:
        review.status = HomeProjectAiReviewStatus.open
    review.updated_at = datetime.utcnow()
    project.updated_at = datetime.utcnow()

    if log_event:
        log_event(
            db,
            project=project,
            actor_user_id=user.id,
            event_type=HomeProjectEventType.ai_finding_updated,
            section_id=review.section_id,
            document_id=review.document_id,
            metadata={
                "ai_review_id": review.id,
                "finding_id": finding_id,
                "action": action_norm,
            },
        )

    db.commit()
    db.refresh(review)
    return ai_review_payload(review)
