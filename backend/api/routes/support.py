"""API de soporte: usuarios abren tickets; support/admin responden."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from api.deps import get_current_user, require_support_staff
from db.database import get_db
from db.models import SupportTicketStatus, User
from services import support_service as svc

router = APIRouter(prefix="/api/support", tags=["support"])


class TicketCreate(BaseModel):
    subject: str = Field(min_length=3, max_length=160)
    body: str = Field(min_length=5, max_length=8000)
    priority: str = "normal"
    related_chat_id: str | None = None
    related_analysis_id: int | None = None


class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=8000)


class TicketPatch(BaseModel):
    status: str | None = None
    priority: str | None = None
    assigned_to: int | None = None
    assign_to_me: bool = False


@router.post("/tickets")
def create_ticket(
    body: TicketCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    if svc.is_staff_user(user):
        raise HTTPException(
            403,
            "Las cuentas de admin/soporte no abren tickets. Usa la bandeja de soporte.",
        )
    try:
        ticket = svc.create_ticket(
            db,
            user,
            subject=body.subject,
            body=body.body,
            priority=body.priority,
            related_chat_id=body.related_chat_id,
            related_analysis_id=body.related_analysis_id,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return svc._ticket_item(ticket, include_messages=True)


@router.get("/tickets")
def my_tickets(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    return svc.list_user_tickets(db, user, limit=limit, offset=offset)


@router.get("/tickets/{ticket_id}")
def get_my_ticket(
    ticket_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    ticket = svc.get_ticket(db, ticket_id)
    if not ticket:
        raise HTTPException(404, "Ticket no encontrado")
    if ticket.user_id != user.id and not svc.is_staff_user(user):
        raise HTTPException(403, "No puedes ver este ticket")
    return svc._ticket_item(ticket, include_messages=True)


@router.post("/tickets/{ticket_id}/messages")
def reply_ticket(
    ticket_id: int,
    body: MessageCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    ticket = svc.get_ticket(db, ticket_id)
    if not ticket:
        raise HTTPException(404, "Ticket no encontrado")
    if ticket.user_id != user.id and not svc.is_staff_user(user):
        raise HTTPException(403, "No puedes responder este ticket")
    if ticket.status == SupportTicketStatus.closed and not svc.is_staff_user(user):
        raise HTTPException(400, "Este ticket está cerrado")
    try:
        ticket = svc.add_message(db, ticket, user, body.body)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return svc._ticket_item(ticket, include_messages=True)


@router.get("/inbox")
def staff_inbox(
    _: Annotated[User, Depends(require_support_staff)],
    db: Annotated[Session, Depends(get_db)],
    status: str | None = None,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    return svc.list_inbox(db, status=status, limit=limit, offset=offset)


@router.get("/inbox/stats")
def inbox_stats(
    _: Annotated[User, Depends(require_support_staff)],
    db: Annotated[Session, Depends(get_db)],
):
    return {"open_or_pending": svc.open_ticket_count(db)}


@router.patch("/tickets/{ticket_id}")
def patch_ticket(
    ticket_id: int,
    body: TicketPatch,
    staff: Annotated[User, Depends(require_support_staff)],
    db: Annotated[Session, Depends(get_db)],
):
    ticket = svc.get_ticket(db, ticket_id)
    if not ticket:
        raise HTTPException(404, "Ticket no encontrado")
    try:
        ticket = svc.update_ticket(
            db,
            ticket,
            status=body.status,
            priority=body.priority,
            assigned_to=body.assigned_to,
            assign_self=staff if body.assign_to_me else None,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return svc._ticket_item(ticket, include_messages=True)


@router.post("/impersonate/{user_id}")
def impersonate_user(
    user_id: int,
    staff: Annotated[User, Depends(require_support_staff)],
    db: Annotated[Session, Depends(get_db)],
):
    """Soporte/admin entra al workspace como un usuario final (diagnóstico)."""
    from api.routes.auth import _user_out
    from db.models import UserRole
    from services.auth_service import create_access_token
    from services.subscription_service import subscription_payload

    target = db.query(User).filter(User.id == user_id).first()
    if not target:
        raise HTTPException(404, "Usuario no encontrado")
    if not target.is_active:
        raise HTTPException(403, "La cuenta del usuario está desactivada")
    role_val = target.role.value if hasattr(target.role, "value") else str(target.role)
    if role_val in (UserRole.admin.value, UserRole.support.value):
        raise HTTPException(403, "No se puede suplantar cuentas de admin o soporte")
    if target.id == staff.id:
        raise HTTPException(400, "No puedes suplantar tu propia cuenta")

    token = create_access_token(
        target.id,
        target.email,
        role_val,
        impersonator_id=staff.id,
        expire_hours=4,
    )
    user_out = _user_out(target)
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": user_out.model_dump() if hasattr(user_out, "model_dump") else user_out.dict(),
        "subscription": subscription_payload(db, target),
        "impersonation": True,
        "impersonator": {
            "id": staff.id,
            "email": staff.email,
            "full_name": staff.full_name or "",
            "role": staff.role.value if hasattr(staff.role, "value") else str(staff.role),
        },
    }
