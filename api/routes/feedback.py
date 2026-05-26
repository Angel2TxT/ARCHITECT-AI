"""Correcciones del usuario sobre detecciones (aprendizaje supervisado)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from api.deps import get_current_user
from api.routes.analyze import _build_assistant_content
from core.correction_intent import parse_correction_message
from core.pipeline import revalidate_analysis
from db.database import get_db
from db.models import Analysis, Chat, Message, User
from services.feedback_service import (
    append_correction,
    apply_corrections,
    build_correction_record,
    correction_ack_text,
    export_correction_for_training,
    normalize_stored_detections,
    resolve_correction_from_intent,
)
from services.storage_service import resolve_analysis_raster_path, save_annotated_jpeg

router = APIRouter(prefix="/api/analyses", tags=["feedback"])


class CorrectionBody(BaseModel):
    detection_index: int = Field(ge=0)
    action: str = Field(pattern="^(reject|relabel)$")
    new_class: str | None = None
    note: str = Field(default="", max_length=500)


class CorrectionMessageBody(BaseModel):
    message: str = Field(min_length=3, max_length=2000)
    chat_id: str = ""


def _get_analysis(db: Session, user: User, analysis_id: int) -> Analysis:
    row = (
        db.query(Analysis)
        .filter(Analysis.id == analysis_id, Analysis.user_id == user.id)
        .first()
    )
    if not row:
        raise HTTPException(404, "Análisis no encontrado.")
    return row


def _run_correction_pipeline(
    db: Session,
    analysis: Analysis,
    record: dict,
    *,
    chat: Chat | None = None,
    user_message: str | None = None,
) -> dict:
    base_detections = normalize_stored_detections(analysis.detections_json)
    if not base_detections:
        raise HTTPException(400, "Este análisis no tiene detecciones guardadas.")

    analysis.corrections_json = append_correction(analysis.corrections_json, record)
    active = apply_corrections(base_detections, analysis.corrections_json)

    try:
        image_path = resolve_analysis_raster_path(analysis.source_path)
    except FileNotFoundError as exc:
        raise HTTPException(400, str(exc)) from exc

    result = revalidate_analysis(
        str(image_path),
        active,
        pixels_per_meter=analysis.pixels_per_meter or 100.0,
        user_prompt=user_message or record.get("note") or "",
        weights=analysis.weights_path,
    )

    annotated_path = save_annotated_jpeg(
        analysis.user_id, analysis.id, result["image_base64"]
    )
    analysis.annotated_path = str(annotated_path)
    analysis.status_text = result.get("status", "")
    # Mantener detecciones originales del modelo; las correcciones viven en corrections_json.
    analysis.issues_json = result.get("issues")
    analysis.counts_json = result.get("counts")
    result["detections"] = active
    result["detections_list"] = active

    export_correction_for_training(
        analysis.user_id,
        analysis.id,
        record,
        image_path=str(image_path),
    )

    ack = correction_ack_text(record, active)
    result["correction_ack"] = ack
    result["corrections_count"] = len(analysis.corrections_json or [])

    if chat:
        if user_message:
            db.add(
                Message(
                    chat_id=chat.id,
                    role="user",
                    content={
                        "text": user_message,
                        "filename": analysis.original_filename,
                        "analysis_id": analysis.id,
                    },
                    analysis_id=analysis.id,
                )
            )
        assistant_content = _build_assistant_content(result, analysis_id=analysis.id)
        assistant_content["text"] = ack + "\n\n" + (assistant_content.get("text") or "")
        assistant_content["corrections_count"] = result["corrections_count"]
        db.add(
            Message(
                chat_id=chat.id,
                role="assistant",
                content=assistant_content,
                analysis_id=analysis.id,
            )
        )
        chat.updated_at = datetime.utcnow()

    db.commit()
    result["analysis_id"] = analysis.id
    if chat:
        result["chat_id"] = chat.id
    return result


@router.post("/{analysis_id}/corrections")
def post_correction(
    analysis_id: int,
    body: CorrectionBody,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    chat_id: str = "",
):
    analysis = _get_analysis(db, user, analysis_id)
    base = normalize_stored_detections(analysis.detections_json)
    if body.detection_index >= len(base):
        raise HTTPException(400, "Índice de detección inválido.")

    det = base[body.detection_index]
    if body.action == "relabel" and not body.new_class:
        raise HTTPException(400, "Indica la clase correcta (wall, door, window, room).")

    record = build_correction_record(
        detection_index=body.detection_index,
        action=body.action,
        from_class=det.get("class", ""),
        new_class=body.new_class if body.action == "relabel" else None,
        note=body.note,
        source="ui",
    )

    chat = None
    if chat_id.strip():
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id.strip(), Chat.user_id == user.id)
            .first()
        )

    return _run_correction_pipeline(db, analysis, record, chat=chat)


def apply_correction_from_text(
    db: Session,
    user: User,
    analysis: Analysis,
    message: str,
    *,
    chat_id: str = "",
) -> dict:
    """Aplica corrección desde texto libre (usado por followup y API)."""
    base = normalize_stored_detections(analysis.detections_json)
    if not base:
        raise HTTPException(400, "Este análisis no tiene detecciones guardadas.")

    intent = parse_correction_message(message)
    if not intent.is_correction:
        raise HTTPException(
            400,
            "No entendí la corrección. Ejemplo: «esa ventana no es ventana, ahí hay muro».",
        )

    record, err = resolve_correction_from_intent(intent, base)
    if err or not record:
        raise HTTPException(400, err or "No pude aplicar la corrección.")

    chat: Chat | None = None
    if chat_id.strip():
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id.strip(), Chat.user_id == user.id)
            .first()
        )
    if not chat and analysis.chat_id:
        chat = db.query(Chat).filter(Chat.id == analysis.chat_id).first()
    if not chat:
        chat = Chat(
            id=str(uuid.uuid4()),
            user_id=user.id,
            title="Corrección de plano",
        )
        db.add(chat)
        db.flush()
        analysis.chat_id = chat.id

    return _run_correction_pipeline(
        db,
        analysis,
        record,
        chat=chat,
        user_message=message.strip(),
    )


@router.post("/{analysis_id}/correct-from-message")
def correct_from_message(
    analysis_id: int,
    body: CorrectionMessageBody,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    analysis = _get_analysis(db, user, analysis_id)
    return apply_correction_from_text(
        db,
        user,
        analysis,
        body.message.strip(),
        chat_id=body.chat_id.strip(),
    )
