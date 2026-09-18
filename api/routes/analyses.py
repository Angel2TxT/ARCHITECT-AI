"""Historial de análisis guardados (entrenamiento)."""

from __future__ import annotations

import base64
from pathlib import Path
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from api.db_errors import http_db_error
from api.deps import get_current_user
from db.database import get_db
from db.models import Analysis, User
from services.storage_service import UPLOADS_ROOT

router = APIRouter(prefix="/api/analyses", tags=["analyses"])


def _owned_analysis(db: Session, user: User, analysis_id: int) -> Analysis:
    row = (
        db.query(Analysis)
        .filter(Analysis.id == analysis_id, Analysis.user_id == user.id)
        .first()
    )
    if not row:
        raise HTTPException(404, "Análisis no encontrado")
    return row


def _annotated_path(analysis: Analysis) -> Path:
    candidates: list[Path] = []
    if analysis.annotated_path:
        candidates.append(Path(analysis.annotated_path))
    candidates.append(
        UPLOADS_ROOT / str(analysis.user_id) / str(analysis.id) / "annotated.jpg"
    )
    for path in candidates:
        if path.is_file():
            return path
    raise HTTPException(404, "No hay imagen anotada para este análisis")


@router.get("")
def list_analyses(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(20, le=100),
):
    try:
        rows = (
            db.query(Analysis)
            .filter(Analysis.user_id == user.id)
            .order_by(Analysis.created_at.desc())
            .limit(limit)
            .all()
        )
        return [
            {
                "id": a.id,
                "chat_id": a.chat_id,
                "filename": a.original_filename,
                "created_at": a.created_at.isoformat() if a.created_at else None,
                "counts": a.counts_json or {},
                "is_demo_model": a.is_demo_model,
                "user_prompt": (a.user_prompt or "")[:80],
            }
            for a in rows
        ]
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.get("/{analysis_id}/annotated")
def get_annotated_image(
    analysis_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    response_format: Literal["file", "base64"] = Query("file", alias="format"),
):
    """Devuelve el plano con incidencias marcadas (para web y app móvil)."""
    try:
        analysis = _owned_analysis(db, user, analysis_id)
        path = _annotated_path(analysis)
        if response_format == "base64":
            return {
                "ok": True,
                "analysis_id": analysis.id,
                "chat_id": analysis.chat_id,
                "content_type": "image/jpeg",
                "image_base64": base64.b64encode(path.read_bytes()).decode("ascii"),
            }
        return FileResponse(
            path,
            media_type="image/jpeg",
            filename=f"analysis_{analysis.id}_annotated.jpg",
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc
