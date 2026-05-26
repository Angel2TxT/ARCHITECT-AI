"""Historial de análisis guardados (entrenamiento)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from api.db_errors import http_db_error
from api.deps import get_current_user
from db.database import get_db
from db.models import Analysis, User

router = APIRouter(prefix="/api/analyses", tags=["analyses"])


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
