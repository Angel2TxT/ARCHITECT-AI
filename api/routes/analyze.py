"""Análisis de planos con persistencia y control de uso."""

from __future__ import annotations

import uuid
from datetime import datetime
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from api.deps import get_current_user
from core.pipeline import analyze_plano_json, find_default_weights
from db.database import get_db
from db.models import Analysis, Chat, Message, User
from services.cad_service import (
    PREVIEW_DPI,
    CadConversionError,
    is_pdf_filename,
    is_supported_filename,
    pdf_bytes_to_png_async,
    prepare_upload_async,
)
from services.storage_service import (
    analysis_dir,
    resolve_analysis_raster_path,
    save_annotated_jpeg,
)
from services.subscription_service import (
    assert_can_analyze,
    is_admin_user,
    record_analysis_usage,
    subscription_payload,
)

router = APIRouter(tags=["analyze"])

ROOT = Path(__file__).resolve().parents[2]


def _resolve_weights(weights: str) -> Path:
    wpath = Path(weights.strip()) if weights.strip() else find_default_weights()
    if wpath is not None and not wpath.is_absolute():
        wpath = ROOT / wpath
    if wpath is None or not wpath.is_file():
        raise HTTPException(
            400,
            "Modelo no encontrado. Entrena con train.py o indica best.pt en Ajustes.",
        )
    return wpath


@router.post("/api/analyze")
async def analyze(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    file: UploadFile = File(...),
    auto_calibrate: str = Form("1"),
    ppm: float = Form(0.0),
    conf: float = Form(0.0),
    weights: str = Form(""),
    message: str = Form(""),
    chat_id: str = Form(""),
):
    content = await file.read()
    filename = file.filename or "plano.png"
    if not is_supported_filename(filename):
        raise HTTPException(
            400,
            "Formato no soportado. Usa PNG, JPG, WEBP, TIFF o PDF.",
        )

    wpath = _resolve_weights(weights)

    assert_can_analyze(
        db,
        user,
        weights_path=str(wpath),
        file_size_bytes=len(content),
    )

    chat: Chat | None = None
    if chat_id.strip():
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id.strip(), Chat.user_id == user.id)
            .first()
        )
    if not chat:
        chat = Chat(
            id=str(uuid.uuid4()),
            user_id=user.id,
            title=(message.strip() or "Análisis de plano")[:120],
        )
        db.add(chat)
        db.flush()
    elif message.strip() and chat.title == "Nuevo chat":
        chat.title = message.strip()[:120]

    analysis = Analysis(
        user_id=user.id,
        chat_id=chat.id,
        original_filename=filename,
        source_path="",
        weights_path=str(wpath),
        pixels_per_meter=ppm if ppm > 0 else 0.0,
        confidence=conf if conf > 0 else 0.0,
        user_prompt=message.strip(),
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

    user_msg_content = {
        "text": message.strip() or "Analiza este plano",
        "filename": filename,
        "analysis_id": analysis.id,
        "type": "analysis",
    }
    db.add(
        Message(
            chat_id=chat.id,
            role="user",
            content=user_msg_content,
            analysis_id=analysis.id,
        )
    )

    try:
        use_auto = auto_calibrate.strip().lower() not in ("0", "false", "no", "off")
        result = analyze_plano_json(
            str(prepared.image_path),
            weights=wpath,
            pixels_per_meter=ppm,
            conf=conf,
            auto_calibrate=use_auto,
            user_prompt=message.strip(),
        )
        analysis.pixels_per_meter = result.get("pixels_per_meter_used", ppm or 100.0)
        analysis.confidence = result.get("confidence_used", conf or 0.18)
    except Exception as exc:
        db.rollback()
        raise HTTPException(500, str(exc)) from exc

    if prepared.conversion_note:
        result["conversion_note"] = prepared.conversion_note
    result["source_filename"] = prepared.original_filename
    result["was_converted"] = prepared.was_converted
    result["user_message"] = message
    annotated_path = save_annotated_jpeg(user.id, analysis.id, result["image_base64"])

    analysis.annotated_path = str(annotated_path)
    analysis.status_text = result.get("status", "")
    analysis.is_demo_model = result.get("is_demo_model", False)
    analysis.detections_json = result.get("detections")
    analysis.issues_json = result.get("issues")
    analysis.counts_json = result.get("counts")

    assistant_content = _build_assistant_content(result, prepared, analysis_id=analysis.id)
    assistant_msg = Message(
        chat_id=chat.id,
        role="assistant",
        content=assistant_content,
        analysis_id=analysis.id,
    )
    db.add(assistant_msg)

    chat.updated_at = datetime.utcnow()
    if not is_admin_user(user):
        record_analysis_usage(db, user.id)

    db.commit()

    sub = subscription_payload(db, user)
    result["chat_id"] = chat.id
    result["analysis_id"] = analysis.id
    result["subscription"] = sub
    result.update(assistant_content)
    return result


def _build_assistant_content(
    data: dict, prepared=None, *, analysis_id: int | None = None
) -> dict:
    from services.analysis_reply_service import compose_analysis_reply

    errors = data.get("counts", {}).get("errors", 0)
    warnings = data.get("counts", {}).get("warnings", 0)
    det_count = data.get("counts", {}).get("detections", 0)

    payload = dict(data)
    if prepared and prepared.conversion_note:
        payload["conversion_note"] = prepared.conversion_note

    text, steps, llm_used = compose_analysis_reply(payload)

    return {
        "text": text,
        "steps": steps,
        "image_base64": data.get("image_base64"),
        "stats": {
            "detections": det_count,
            "errors": errors,
            "warnings": warnings,
        }
        if det_count > 0
        else None,
        "issues_summary": data.get("issues_summary"),
        "detections_summary": data.get("detections_summary"),
        "scale_hint": data.get("scale_hint"),
        "auto_calibration": data.get("auto_calibration"),
        "construction_coverage": data.get("construction_coverage"),
        "knowledge_references": data.get("knowledge_references"),
        "verdict": data.get("verdict"),
        "analysis_intent": data.get("analysis_intent"),
        "custom_findings": data.get("custom_findings"),
        "measures_report": data.get("measures_report"),
        "conversion_note": payload.get("conversion_note"),
        "analysis_id": analysis_id,
        "detections_list": data.get("detections") or [],
        "corrections_count": data.get("corrections_count"),
        "assistant_mode": "architect",
        "llm_used": llm_used,
    }


@router.post("/api/analyze/followup")
async def analyze_followup(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    message: str = Form(""),
    analysis_id: int = Form(0),
    chat_id: str = Form(""),
    auto_calibrate: str = Form("1"),
    ppm: float = Form(0.0),
    conf: float = Form(0.0),
    weights: str = Form(""),
):
    """Reanaliza el último plano del chat con una nueva pregunta (sin volver a subir archivo)."""
    if analysis_id <= 0:
        raise HTTPException(400, "Indica un análisis previo (analysis_id).")

    analysis = (
        db.query(Analysis)
        .filter(Analysis.id == analysis_id, Analysis.user_id == user.id)
        .first()
    )
    if not analysis:
        raise HTTPException(404, "No encontré ese análisis. Vuelve a adjuntar el plano.")

    prompt = message.strip()
    from core.correction_intent import parse_correction_message
    from api.routes.feedback import apply_correction_from_text

    if prompt and parse_correction_message(prompt).is_correction:
        return apply_correction_from_text(
            db, user, analysis, prompt, chat_id=chat_id.strip()
        )

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
            title=(message.strip() or "Seguimiento de plano")[:120],
        )
        db.add(chat)
        db.flush()

    try:
        image_path = resolve_analysis_raster_path(analysis.source_path)
    except FileNotFoundError as exc:
        raise HTTPException(400, str(exc)) from exc

    wpath = _resolve_weights(weights or analysis.weights_path or "")

    assert_can_analyze(
        db,
        user,
        weights_path=str(wpath),
        file_size_bytes=image_path.stat().st_size,
    )

    prompt = message.strip() or "Medidas del plano"
    db.add(
        Message(
            chat_id=chat.id,
            role="user",
            content={
                "text": prompt,
                "filename": analysis.original_filename,
                "type": "analysis",
            },
            analysis_id=analysis.id,
        )
    )

    try:
        use_auto = auto_calibrate.strip().lower() not in ("0", "false", "no", "off")
        result = analyze_plano_json(
            str(image_path),
            weights=wpath,
            pixels_per_meter=ppm or analysis.pixels_per_meter,
            conf=conf or analysis.confidence,
            auto_calibrate=use_auto,
            user_prompt=prompt,
        )
        analysis.pixels_per_meter = result.get("pixels_per_meter_used", analysis.pixels_per_meter)
        analysis.confidence = result.get("confidence_used", analysis.confidence)
        analysis.user_prompt = prompt
    except Exception as exc:
        db.rollback()
        raise HTTPException(500, str(exc)) from exc

    result["source_filename"] = analysis.original_filename
    annotated_path = save_annotated_jpeg(user.id, analysis.id, result["image_base64"])
    analysis.annotated_path = str(annotated_path)
    analysis.status_text = result.get("status", "")
    analysis.detections_json = result.get("detections")
    analysis.issues_json = result.get("issues")
    analysis.counts_json = result.get("counts")

    assistant_content = _build_assistant_content(result, analysis_id=analysis.id)
    db.add(
        Message(
            chat_id=chat.id,
            role="assistant",
            content=assistant_content,
            analysis_id=analysis.id,
        )
    )
    chat.updated_at = datetime.utcnow()
    if not is_admin_user(user):
        record_analysis_usage(db, user.id)
    db.commit()

    result["chat_id"] = chat.id
    result["analysis_id"] = analysis.id
    result["subscription"] = subscription_payload(db, user)
    result.update(assistant_content)
    return result


@router.post("/api/plano/preview")
async def plano_preview(
    user: Annotated[User, Depends(get_current_user)],
    file: UploadFile = File(...),
):
    """Vista previa rápida (imagen o PDF) para el compositor."""
    import base64

    content = await file.read()
    filename = file.filename or "plano.png"
    if not is_supported_filename(filename):
        raise HTTPException(400, "Formato no soportado. Usa PNG, JPG, WEBP, TIFF o PDF.")

    mime_map = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".bmp": "image/bmp",
        ".tif": "image/tiff",
        ".tiff": "image/tiff",
    }
    ext = Path(filename).suffix.lower()

    try:
        if is_pdf_filename(filename):
            png, pdf_note = await pdf_bytes_to_png_async(content, dpi=PREVIEW_DPI)
            mime = "image/png"
            note = pdf_note or "Vista previa desde PDF (página 1)"
        else:
            png = content
            mime = mime_map.get(ext, "image/png")
            note = None
    except CadConversionError as exc:
        raise HTTPException(400, str(exc)) from exc
    except Exception as exc:
        raise HTTPException(500, f"Error al generar vista previa: {exc}") from exc

    b64 = base64.b64encode(png).decode("ascii")
    return {
        "image_base64": b64,
        "mime": mime,
        "preview_note": note,
        "filename": filename,
    }
