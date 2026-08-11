"""Tickets de soporte humano (dudas de usuarios → rol support/admin)."""

from __future__ import annotations

from sqlalchemy.orm import Session, joinedload

from db.models import (
    SupportMessage,
    SupportTicket,
    SupportTicketPriority,
    SupportTicketStatus,
    User,
    UserRole,
)


def is_support_user(user: User) -> bool:
    return user.role == UserRole.support or str(user.role) == UserRole.support.value


def is_staff_user(user: User) -> bool:
    from services.subscription_service import is_admin_user

    return is_admin_user(user) or is_support_user(user)


def _ticket_item(ticket: SupportTicket, *, include_messages: bool = False) -> dict:
    last = ticket.messages[-1] if ticket.messages else None
    data = {
        "id": ticket.id,
        "subject": ticket.subject,
        "status": ticket.status.value if hasattr(ticket.status, "value") else ticket.status,
        "priority": ticket.priority.value if hasattr(ticket.priority, "value") else ticket.priority,
        "user_id": ticket.user_id,
        "user_email": ticket.user.email if ticket.user else None,
        "user_name": ticket.user.full_name if ticket.user else "",
        "assigned_to": ticket.assigned_to,
        "assignee_email": ticket.assignee.email if ticket.assignee else None,
        "related_chat_id": ticket.related_chat_id,
        "related_analysis_id": ticket.related_analysis_id,
        "messages_count": len(ticket.messages or []),
        "last_message_at": last.created_at.isoformat() if last else None,
        "created_at": ticket.created_at.isoformat() if ticket.created_at else None,
        "updated_at": ticket.updated_at.isoformat() if ticket.updated_at else None,
    }
    if include_messages:
        data["messages"] = [
            {
                "id": m.id,
                "author_id": m.author_id,
                "author_email": m.author.email if m.author else None,
                "author_name": m.author.full_name if m.author else "",
                "body": m.body,
                "is_staff": bool(m.is_staff),
                "created_at": m.created_at.isoformat() if m.created_at else None,
            }
            for m in (ticket.messages or [])
        ]
    return data


def create_ticket(
    db: Session,
    user: User,
    *,
    subject: str,
    body: str,
    priority: str = "normal",
    related_chat_id: str | None = None,
    related_analysis_id: int | None = None,
) -> SupportTicket:
    subject = (subject or "").strip()[:160]
    body = (body or "").strip()
    if len(subject) < 3:
        raise ValueError("El asunto debe tener al menos 3 caracteres")
    if len(body) < 5:
        raise ValueError("Describe tu duda con un poco más de detalle")
    try:
        prio = SupportTicketPriority(priority)
    except ValueError:
        prio = SupportTicketPriority.normal

    ticket = SupportTicket(
        user_id=user.id,
        subject=subject,
        priority=prio,
        status=SupportTicketStatus.open,
        related_chat_id=related_chat_id or None,
        related_analysis_id=related_analysis_id,
    )
    db.add(ticket)
    db.flush()
    db.add(
        SupportMessage(
            ticket_id=ticket.id,
            author_id=user.id,
            body=body,
            is_staff=False,
        )
    )
    db.commit()
    return get_ticket(db, ticket.id)


def list_user_tickets(db: Session, user: User, *, limit: int = 20, offset: int = 0) -> dict:
    q = (
        db.query(SupportTicket)
        .options(joinedload(SupportTicket.messages), joinedload(SupportTicket.user), joinedload(SupportTicket.assignee))
        .filter(SupportTicket.user_id == user.id)
    )
    total = q.count()
    rows = (
        q.order_by(SupportTicket.updated_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {"total": total, "items": [_ticket_item(t) for t in rows]}


def list_inbox(
    db: Session,
    *,
    status: str | None = None,
    limit: int = 20,
    offset: int = 0,
) -> dict:
    q = db.query(SupportTicket).options(
        joinedload(SupportTicket.messages),
        joinedload(SupportTicket.user),
        joinedload(SupportTicket.assignee),
    )
    if status:
        try:
            q = q.filter(SupportTicket.status == SupportTicketStatus(status))
        except ValueError:
            pass
    total = q.count()
    rows = (
        q.order_by(SupportTicket.updated_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {"total": total, "items": [_ticket_item(t) for t in rows]}


def get_ticket(db: Session, ticket_id: int) -> SupportTicket | None:
    return (
        db.query(SupportTicket)
        .options(
            joinedload(SupportTicket.messages).joinedload(SupportMessage.author),
            joinedload(SupportTicket.user),
            joinedload(SupportTicket.assignee),
        )
        .filter(SupportTicket.id == ticket_id)
        .first()
    )


def add_message(
    db: Session,
    ticket: SupportTicket,
    author: User,
    body: str,
) -> SupportTicket:
    body = (body or "").strip()
    if len(body) < 1:
        raise ValueError("El mensaje no puede estar vacío")
    staff = is_staff_user(author)
    db.add(
        SupportMessage(
            ticket_id=ticket.id,
            author_id=author.id,
            body=body,
            is_staff=staff,
        )
    )
    if staff:
        if ticket.status == SupportTicketStatus.open:
            ticket.status = SupportTicketStatus.pending
        if ticket.assigned_to is None:
            ticket.assigned_to = author.id
    else:
        if ticket.status in (SupportTicketStatus.pending, SupportTicketStatus.resolved):
            ticket.status = SupportTicketStatus.open
    db.commit()
    return get_ticket(db, ticket.id)


def update_ticket(
    db: Session,
    ticket: SupportTicket,
    *,
    status: str | None = None,
    assigned_to: int | None = None,
    priority: str | None = None,
    assign_self: User | None = None,
) -> SupportTicket:
    if status is not None:
        ticket.status = SupportTicketStatus(status)
    if priority is not None:
        ticket.priority = SupportTicketPriority(priority)
    if assign_self is not None:
        ticket.assigned_to = assign_self.id
    elif assigned_to is not None:
        ticket.assigned_to = assigned_to if assigned_to > 0 else None
    db.commit()
    return get_ticket(db, ticket.id)


def open_ticket_count(db: Session) -> int:
    return (
        db.query(SupportTicket)
        .filter(SupportTicket.status.in_([SupportTicketStatus.open, SupportTicketStatus.pending]))
        .count()
    )
