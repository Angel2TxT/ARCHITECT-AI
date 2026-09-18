"""Notificaciones in-app persistentes (campana + panel)."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Iterable

from sqlalchemy.orm import Session

from db.models import NotificationKind, User, UserNotification, UserRole

_KIND_ICONS: dict[str, str] = {
    NotificationKind.home_invite.value: "group_add",
    NotificationKind.home_assigned.value: "assignment_ind",
    NotificationKind.home_mention.value: "alternate_email",
    NotificationKind.home_comment.value: "chat",
    NotificationKind.home_section_status.value: "fact_check",
    NotificationKind.home_stage.value: "flag",
    NotificationKind.home_project_completed.value: "emoji_events",
    NotificationKind.home_ai_review.value: "auto_awesome",
    NotificationKind.home_reopen.value: "replay",
    NotificationKind.billing_plan.value: "workspace_premium",
    NotificationKind.billing_payment_failed.value: "credit_card_off",
    NotificationKind.billing_canceled.value: "cancel",
    NotificationKind.billing_refund.value: "currency_exchange",
    NotificationKind.usage_limit.value: "speed",
    NotificationKind.security_password.value: "lock",
    NotificationKind.support_reply.value: "support_agent",
    NotificationKind.support_ticket_closed.value: "task_alt",
    NotificationKind.staff_ticket.value: "confirmation_number",
    NotificationKind.staff_refund.value: "receipt_long",
    NotificationKind.admin_account.value: "manage_accounts",
}


def kind_icon(kind: str) -> str:
    return _KIND_ICONS.get(kind, "notifications")


def notify(
    db: Session,
    user_id: int,
    *,
    kind: str | NotificationKind,
    title: str,
    body: str = "",
    link: str | None = None,
    entity_type: str | None = None,
    entity_id: str | int | None = None,
    actor_user_id: int | None = None,
    metadata: dict | None = None,
    dedupe_hours: float | None = None,
) -> UserNotification | None:
    """Crea una notificación (sin commit). Omite si user_id == actor o dedupe reciente."""
    if not user_id:
        return None
    if actor_user_id is not None and int(actor_user_id) == int(user_id):
        return None

    kind_val = kind.value if isinstance(kind, NotificationKind) else str(kind)
    eid = None if entity_id is None else str(entity_id)

    if dedupe_hours and eid is not None:
        since = datetime.utcnow() - timedelta(hours=dedupe_hours)
        exists = (
            db.query(UserNotification.id)
            .filter(
                UserNotification.user_id == user_id,
                UserNotification.kind == kind_val,
                UserNotification.entity_type == entity_type,
                UserNotification.entity_id == eid,
                UserNotification.created_at >= since,
            )
            .first()
        )
        if exists:
            return None

    row = UserNotification(
        user_id=user_id,
        kind=kind_val[:48],
        title=(title or "Aviso")[:160],
        body=(body or "")[:500],
        link=(link or None),
        entity_type=entity_type,
        entity_id=eid,
        actor_user_id=actor_user_id,
        metadata_json=metadata or None,
        is_read=False,
    )
    try:
        db.add(row)
    except Exception:
        return None
    return row


def notify_many(
    db: Session,
    user_ids: Iterable[int],
    *,
    kind: str | NotificationKind,
    title: str,
    body: str = "",
    link: str | None = None,
    entity_type: str | None = None,
    entity_id: str | int | None = None,
    actor_user_id: int | None = None,
    metadata: dict | None = None,
    dedupe_hours: float | None = None,
) -> int:
    created = 0
    seen: set[int] = set()
    for uid in user_ids:
        if not uid or uid in seen:
            continue
        seen.add(int(uid))
        if notify(
            db,
            int(uid),
            kind=kind,
            title=title,
            body=body,
            link=link,
            entity_type=entity_type,
            entity_id=entity_id,
            actor_user_id=actor_user_id,
            metadata=metadata,
            dedupe_hours=dedupe_hours,
        ):
            created += 1
    return created


def staff_user_ids(db: Session) -> list[int]:
    rows = (
        db.query(User.id)
        .filter(
            User.is_active.is_(True),
            User.role.in_([UserRole.admin, UserRole.support]),
        )
        .all()
    )
    return [int(r[0]) for r in rows]


def notification_payload(row: UserNotification) -> dict[str, Any]:
    return {
        "id": row.id,
        "kind": row.kind,
        "icon": kind_icon(row.kind),
        "title": row.title,
        "body": row.body or "",
        "link": row.link,
        "entity_type": row.entity_type,
        "entity_id": row.entity_id,
        "actor_user_id": row.actor_user_id,
        "metadata": row.metadata_json or {},
        "is_read": bool(row.is_read),
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "read_at": row.read_at.isoformat() if row.read_at else None,
    }


def unread_count(db: Session, user_id: int) -> int:
    return (
        db.query(UserNotification)
        .filter(UserNotification.user_id == user_id, UserNotification.is_read.is_(False))
        .count()
    )


def list_notifications(
    db: Session,
    user_id: int,
    *,
    limit: int = 30,
    offset: int = 0,
    unread_only: bool = False,
) -> dict[str, Any]:
    limit = max(1, min(int(limit or 30), 100))
    offset = max(0, int(offset or 0))
    q = db.query(UserNotification).filter(UserNotification.user_id == user_id)
    if unread_only:
        q = q.filter(UserNotification.is_read.is_(False))
    total = q.count()
    rows = (
        q.order_by(UserNotification.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {
        "total": total,
        "unread": unread_count(db, user_id),
        "items": [notification_payload(r) for r in rows],
    }


def mark_read(
    db: Session,
    user_id: int,
    *,
    notification_ids: list[int] | None = None,
    all_unread: bool = False,
) -> dict[str, Any]:
    q = db.query(UserNotification).filter(
        UserNotification.user_id == user_id,
        UserNotification.is_read.is_(False),
    )
    if not all_unread:
        ids = [int(i) for i in (notification_ids or []) if i]
        if not ids:
            return {"ok": True, "updated": 0, "unread": unread_count(db, user_id)}
        q = q.filter(UserNotification.id.in_(ids))

    now = datetime.utcnow()
    updated = 0
    for row in q.all():
        row.is_read = True
        row.read_at = now
        updated += 1
    if updated:
        db.commit()
    return {"ok": True, "updated": updated, "unread": unread_count(db, user_id)}


def delete_notification(db: Session, user_id: int, notification_id: int) -> bool:
    row = (
        db.query(UserNotification)
        .filter(
            UserNotification.id == notification_id,
            UserNotification.user_id == user_id,
        )
        .first()
    )
    if not row:
        return False
    db.delete(row)
    db.commit()
    return True


# ── Helpers de dominio ──────────────────────────────────────────────


def home_project_link(project_id: str) -> str:
    return f"/legacy-app?home_project={project_id}"


def notify_home_members(
    db: Session,
    *,
    member_user_ids: Iterable[int],
    actor_user_id: int | None,
    kind: NotificationKind,
    title: str,
    body: str,
    project_id: str,
    entity_type: str = "home_project",
    entity_id: str | int | None = None,
    metadata: dict | None = None,
) -> int:
    return notify_many(
        db,
        member_user_ids,
        kind=kind,
        title=title,
        body=body,
        link=home_project_link(project_id),
        entity_type=entity_type,
        entity_id=entity_id if entity_id is not None else project_id,
        actor_user_id=actor_user_id,
        metadata=metadata,
    )


def maybe_notify_usage_threshold(
    db: Session,
    user: User,
    *,
    used: int,
    limit: int,
    unlimited: bool,
) -> None:
    if unlimited or limit <= 0 or used <= 0:
        return
    ratio = used / float(limit)
    if ratio < 0.8:
        return
    if used >= limit:
        title = "Límite mensual de análisis alcanzado"
        body = f"Usaste {used} de {limit} análisis este mes. Mejora tu plan para continuar."
        kind_key = "hit"
    else:
        pct = int(ratio * 100)
        title = "Te estás acercando al límite de análisis"
        body = f"Llevas {used} de {limit} análisis ({pct}%)."
        kind_key = "warn"
    notify(
        db,
        user.id,
        kind=NotificationKind.usage_limit,
        title=title,
        body=body,
        link="/legacy-app?plans=1",
        entity_type="usage",
        entity_id=f"{datetime.utcnow().strftime('%Y-%m')}:{kind_key}",
        metadata={"used": used, "limit": limit},
        dedupe_hours=24 * 20,
    )
