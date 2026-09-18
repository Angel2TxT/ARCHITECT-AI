"""API de notificaciones in-app."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from api.deps import get_current_user
from db.database import get_db
from db.models import User
from services import notification_service as svc

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


class MarkReadBody(BaseModel):
    ids: list[int] = Field(default_factory=list)
    all: bool = False


@router.get("")
def list_notifications(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(30, ge=1, le=100),
    offset: int = Query(0, ge=0),
    unread_only: bool = False,
):
    return svc.list_notifications(
        db, user.id, limit=limit, offset=offset, unread_only=unread_only
    )


@router.get("/unread-count")
def get_unread_count(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return {"unread": svc.unread_count(db, user.id)}


@router.post("/mark-read")
def mark_read(
    body: MarkReadBody,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return svc.mark_read(
        db,
        user.id,
        notification_ids=body.ids,
        all_unread=bool(body.all),
    )


@router.delete("/{notification_id}")
def delete_notification(
    notification_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    ok = svc.delete_notification(db, user.id, notification_id)
    if not ok:
        raise HTTPException(404, "Notificación no encontrada")
    return {"ok": True, "unread": svc.unread_count(db, user.id)}
