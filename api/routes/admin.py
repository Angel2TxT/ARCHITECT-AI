"""Panel admin: usuarios y métricas."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from api.deps import require_admin
from db.database import get_db
from db.models import Analysis, User

router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.get("/stats")
def stats(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    users = db.query(func.count(User.id)).scalar() or 0
    analyses = db.query(func.count(Analysis.id)).scalar() or 0
    training = (
        db.query(func.count(Analysis.id))
        .filter(Analysis.training_eligible.is_(True))
        .scalar()
        or 0
    )
    return {
        "users": users,
        "analyses_total": analyses,
        "analyses_training_eligible": training,
    }


@router.get("/users")
def list_users(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 50,
):
    rows = db.query(User).order_by(User.created_at.desc()).limit(limit).all()
    return [
        {
            "id": u.id,
            "email": u.email,
            "full_name": u.full_name,
            "role": u.role.value,
            "is_active": u.is_active,
            "created_at": u.created_at.isoformat() if u.created_at else None,
        }
        for u in rows
    ]
