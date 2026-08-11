"""Prueba gratuita sin autenticación."""

from __future__ import annotations

import base64
import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, Response, UploadFile
from sqlalchemy.orm import Session

from api.routes.analyze import _build_assistant_content, _resolve_weights
from core.pipeline import analyze_plano_json, find_default_weights
from db.database import get_db
from services.cad_service import (
    PREVIEW_DPI,
    CadConversionError,
    is_pdf_filename,
    is_supported_filename,
    pdf_bytes_to_png_async,
    prepare_upload_async,
)
from services.architect_ai_service import architect_ai_status
from services.knowledge_service import get_document_catalog, knowledge_stats
from services.guest_trial_service import (
    assert_guest_can_analyze,
    assert_guest_can_ask,
    get_guest_id,
    get_or_create_guest,
    guest_trial_payload,
    record_guest_analysis,
    record_guest_ask,
)
from services.qa_service import answer_construction_question

router = APIRouter(prefix="/api/guest", tags=["guest"])

ROOT = Path(__file__).resolve().parents[2]
GUEST_UPLOAD_ROOT = ROOT / "data" / "guest_uploads"


def _guest_weights() -> Path:
    """En prueba se usa el modelo demo si existe."""
    demo = ROOT / "runs" / "detect" / "demo_planos" / "weights" / "best.pt"
    if demo.is_file():
        return demo
    return _resolve_weights("")


def _guest_work_dir(guest_id: str) -> Path:
    d = GUEST_UPLOAD_ROOT / guest_id / str(uuid.uuid4())
    d.mkdir(parents=True, exist_ok=True)
    return d


@router.get("/status")
def guest_status(
    request: Request,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
):
    guest_id = get_guest_id(request, response)
    row = get_or_create_guest(db, guest_id)
    db.commit()
    pages = knowledge_stats().get("pages", 0)
    catalog = get_document_catalog()
    return {
        **guest_trial_payload(row),
        **architect_ai_status(knowledge_pages=pages, catalog=catalog),
    }


@router.post("/analyze")
async def guest_analyze(
    request: Request,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
    file: UploadFile = File(...),
    auto_calibrate: str = Form("1"),
    ppm: float = Form(0.0),
    conf: float = Form(0.0),
    message: str = Form(""),
):
    guest_id = get_guest_id(request, response)
    content = await file.read()
    filename = file.filename or "plano.png"
    if not is_supported_filename(filename):
        raise HTTPException(400, "Formato no soportado. Usa PNG, JPG, WEBP, TIFF o PDF.")

    assert_guest_can_analyze(db, guest_id, len(content))
    wpath = _guest_weights()

    try:
        prepared = await prepare_upload_async(content, filename, _guest_work_dir(guest_id))
    except CadConversionError as exc:
        raise HTTPException(400, str(exc)) from exc

    use_auto = auto_calibrate.strip().lower() not in ("0", "false", "no", "off")
    try:
        result = analyze_plano_json(
            str(prepared.image_path),
            weights=wpath,
            pixels_per_meter=ppm,
            conf=conf,
            auto_calibrate=use_auto,
            user_prompt=message.strip(),
        )
    except Exception as exc:
        raise HTTPException(500, str(exc)) from exc

    if prepared.conversion_note:
        result["conversion_note"] = prepared.conversion_note
    result["source_filename"] = prepared.original_filename
    result["was_converted"] = prepared.was_converted
    result["user_message"] = message

    assistant_content = _build_assistant_content(result, prepared)
    trial = record_guest_analysis(db, guest_id)

    out = {**result, **assistant_content}
    out["guest_trial"] = trial
    out["guest"] = True
    return out


@router.post("/ask")
async def guest_ask(
    request: Request,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
    message: str = Form(...),
):
    guest_id = get_guest_id(request, response)
    q = (message or "").strip()
    if len(q) < 3:
        raise HTTPException(400, "Escribe tu pregunta (mínimo 3 caracteres).")

    assert_guest_can_ask(db, guest_id)
    result = answer_construction_question(q)
    trial = record_guest_ask(db, guest_id)
    result["guest_trial"] = trial
    result["guest"] = True
    return result


@router.post("/preview")
async def guest_preview(
    request: Request,
    response: Response,
    file: UploadFile = File(...),
):
    get_guest_id(request, response)
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

    return {
        "image_base64": base64.b64encode(png).decode("ascii"),
        "mime": mime,
        "preview_note": note,
        "filename": filename,
    }
