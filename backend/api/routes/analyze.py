"""Análisis de planos con persistencia y control de uso."""

from __future__ import annotations

import uuid
from datetime import datetime
from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from api.deps import get_current_user
from core.pipeline import analyze_plano_json, find_default_weights
from db.database import get_db
from db.models import Analysis, Chat, Message, User
from services.cad_service import (
    PREVIEW_DPI,
    CadConversionError,
    cad_bytes_to_png_async,
    is_cad_filename,
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


def _safe_str(val: Any, default: str = "") -> str:
    if val is None or not isinstance(val, str):
        if hasattr(val, "default") and val.default is not None:
            return str(val.default)
        return default if val is None else str(val)
    return val


def _safe_float(val: Any, default: float = 0.0) -> float:
    if val is None or not isinstance(val, (int, float)):
        if hasattr(val, "default") and val.default is not None:
            try:
                return float(val.default)
            except (ValueError, TypeError):
                return default
        try:
            return float(val)
        except (ValueError, TypeError):
            return default
    return float(val)


def _safe_int(val: Any, default: int = 0) -> int:
    if val is None or not isinstance(val, int):
        if hasattr(val, "default") and val.default is not None:
            try:
                return int(val.default)
            except (ValueError, TypeError):
                return default
        try:
            return int(val)
        except (ValueError, TypeError):
            return default
    return int(val)


def _resolve_weights(weights: Any) -> Path:
    weights_str = _safe_str(weights).strip()
    wpath = Path(weights_str) if weights_str else find_default_weights()
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
    jurisdiction: str = Form(""),
):
    message_str = _safe_str(message).strip()
    chat_id_str = _safe_str(chat_id).strip()
    jurisdiction_str = _safe_str(jurisdiction).strip()
    auto_calibrate_str = _safe_str(auto_calibrate, "1").strip()
    ppm_val = _safe_float(ppm, 0.0)
    conf_val = _safe_float(conf, 0.0)

    content = await file.read()
    filename = file.filename or "plano.png"
    if not is_supported_filename(filename):
        raise HTTPException(
            400,
            "Formato no soportado. Usa PNG, JPG, WEBP, TIFF, PDF, DXF o DWG.",
        )

    wpath = _resolve_weights(weights)

    assert_can_analyze(
        db,
        user,
        weights_path=str(wpath),
        file_size_bytes=len(content),
    )

    chat: Chat | None = None
    if chat_id_str:
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id_str, Chat.user_id == user.id)
            .first()
        )
    if not chat:
        chat = Chat(
            id=str(uuid.uuid4()),
            user_id=user.id,
            title=(message_str or "Análisis de plano")[:120],
        )
        db.add(chat)
        db.flush()
    elif message_str and chat.title == "Nuevo chat":
        chat.title = message_str[:120]

    analysis = Analysis(
        user_id=user.id,
        chat_id=chat.id,
        original_filename=filename,
        source_path="",
        weights_path=str(wpath),
        pixels_per_meter=ppm_val if ppm_val > 0 else 0.0,
        confidence=conf_val if conf_val > 0 else 0.0,
        user_prompt=message_str,
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
        "text": message_str or "Analiza este plano",
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
        use_auto = auto_calibrate_str.lower() not in ("0", "false", "no", "off")
        result = analyze_plano_json(
            str(prepared.image_path),
            weights=wpath,
            pixels_per_meter=ppm_val,
            conf=conf_val,
            auto_calibrate=use_auto,
            user_prompt=message_str,
            dxf_path=prepared.dxf_path,
            jurisdiction=jurisdiction_str or None,
        )
        analysis.pixels_per_meter = result.get("pixels_per_meter_used", ppm_val or 100.0)
        analysis.confidence = result.get("confidence_used", conf_val or 0.18)
    except Exception as exc:
        db.rollback()
        raise HTTPException(500, str(exc)) from exc

    if prepared.conversion_note:
        result["conversion_note"] = prepared.conversion_note
    result["source_filename"] = prepared.original_filename
    result["was_converted"] = prepared.was_converted
    result["user_message"] = message_str
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
    record_analysis_usage(db, user)

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
    analysis_id_val = _safe_int(analysis_id, 0)
    message_str = _safe_str(message).strip()
    chat_id_str = _safe_str(chat_id).strip()
    auto_calibrate_str = _safe_str(auto_calibrate, "1").strip()
    ppm_val = _safe_float(ppm, 0.0)
    conf_val = _safe_float(conf, 0.0)

    if analysis_id_val <= 0:
        raise HTTPException(400, "Indica un análisis previo (analysis_id).")

    analysis = (
        db.query(Analysis)
        .filter(Analysis.id == analysis_id_val, Analysis.user_id == user.id)
        .first()
    )
    if not analysis:
        raise HTTPException(404, "No encontré ese análisis. Vuelve a adjuntar el plano.")

    prompt = message_str
    from core.correction_intent import parse_correction_message
    from api.routes.feedback import apply_correction_from_text

    if prompt and parse_correction_message(prompt).is_correction:
        return apply_correction_from_text(
            db, user, analysis, prompt, chat_id=chat_id_str
        )

    chat: Chat | None = None
    if chat_id_str:
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id_str, Chat.user_id == user.id)
            .first()
        )
    if not chat and analysis.chat_id:
        chat = db.query(Chat).filter(Chat.id == analysis.chat_id).first()
    if not chat:
        chat = Chat(
            id=str(uuid.uuid4()),
            user_id=user.id,
            title=(message_str or "Seguimiento de plano")[:120],
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

    prompt = message_str or "Medidas del plano"
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
        use_auto = auto_calibrate_str.lower() not in ("0", "false", "no", "off")
        dxf_candidate = Path(image_path).parent / "source.dxf"
        result = analyze_plano_json(
            str(image_path),
            weights=wpath,
            pixels_per_meter=ppm_val or analysis.pixels_per_meter,
            conf=conf_val or analysis.confidence,
            auto_calibrate=use_auto,
            user_prompt=prompt,
            dxf_path=dxf_candidate if dxf_candidate.is_file() else None,
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
    record_analysis_usage(db, user)
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
        raise HTTPException(400, "Formato no soportado. Usa PNG, JPG, WEBP, TIFF, PDF, DXF o DWG.")

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
            note = pdf_note or "Vista previa desde PDF"
        elif is_cad_filename(filename):
            png = await cad_bytes_to_png_async(content, filename, dpi=PREVIEW_DPI)
            mime = "image/png"
            note = f"Vista previa desde {ext.upper().lstrip('.')}"
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


@router.get("/api/analyses/{analysis_id}/dossier.pdf")
def download_dossier_pdf(
    analysis_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Descarga el dictamen técnico pericial oficial en PDF con evidencia y sellos normativos."""
    from fastapi.responses import Response
    from services.peritaje_pdf_service import build_dossier_pdf

    analysis = db.query(Analysis).filter(Analysis.id == analysis_id).first()
    if not analysis:
        raise HTTPException(404, "Análisis no encontrado")

    if analysis.user_id != user.id and getattr(user, "role", "") not in ("admin", "support"):
        raise HTTPException(403, "No tienes permiso para descargar este dictamen")

    pdf_bytes = build_dossier_pdf(analysis, user)
    filename = f"Dictamen_ARCHITECT_{analysis.id:06d}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "no-store",
        },
    )


@router.get("/api/analyses/{analysis_id}/export.dxf")
def download_analysis_dxf(
    analysis_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Descarga el plano en formato CAD DXF con capas separadas (MUROS, PUERTAS, VENTANAS, RECINTOS, ESCALERAS)."""
    from fastapi.responses import Response
    from services.cad_export_service import export_detections_to_dxf

    analysis = db.query(Analysis).filter(Analysis.id == analysis_id).first()
    if not analysis:
        raise HTTPException(404, "Análisis no encontrado")

    if analysis.user_id != user.id and getattr(user, "role", "") not in ("admin", "support"):
        raise HTTPException(403, "No tienes permiso para descargar este archivo CAD")

    detections = analysis.detections_json or []
    ppm = analysis.pixels_per_meter or 100.0
    project_title = f"ARCHITECT {analysis.original_filename or 'Plano'}"

    dxf_bytes = export_detections_to_dxf(detections, pixels_per_meter=ppm, project_title=project_title)
    filename = f"Plano_CAD_{analysis.id:06d}.dxf"

    return Response(
        content=dxf_bytes,
        media_type="application/dxf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "no-store",
        },
    )

