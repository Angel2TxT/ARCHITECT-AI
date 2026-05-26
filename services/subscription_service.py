"""Límites de plan, uso mensual y permisos."""

from __future__ import annotations

from calendar import monthrange
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session, joinedload

from db.models import Plan, Subscription, SubscriptionStatus, UsageRecord, User


def period_key(dt: datetime | None = None) -> str:
    dt = dt or datetime.utcnow()
    return dt.strftime("%Y-%m")


def _period_bounds(now: datetime | None = None) -> tuple[datetime, datetime]:
    now = now or datetime.utcnow()
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_day = monthrange(start.year, start.month)[1]
    end = start.replace(day=last_day, hour=23, minute=59, second=59)
    return start, end


def get_user_subscription(db: Session, user: User) -> Subscription | None:
    return (
        db.query(Subscription)
        .options(joinedload(Subscription.plan))
        .filter(Subscription.user_id == user.id)
        .first()
    )


def ensure_subscription(db: Session, user: User) -> Subscription:
    sub = get_user_subscription(db, user)
    if sub:
        return sub
    free = db.query(Plan).filter(Plan.slug == "free").first()
    if not free:
        raise HTTPException(503, "Planes no configurados. Ejecuta scripts/init_db.py")
    start, end = _period_bounds()
    sub = Subscription(
        user_id=user.id,
        plan_id=free.id,
        status=SubscriptionStatus.active,
        current_period_start=start,
        current_period_end=end,
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    sub.plan = free
    return sub


def get_usage(db: Session, user_id: int, key: str | None = None) -> UsageRecord:
    key = key or period_key()
    row = (
        db.query(UsageRecord)
        .filter(UsageRecord.user_id == user_id, UsageRecord.period_key == key)
        .first()
    )
    if not row:
        row = UsageRecord(user_id=user_id, period_key=key, analyses_count=0)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


def subscription_payload(db: Session, user: User) -> dict:
    sub = ensure_subscription(db, user)
    plan = sub.plan
    usage = get_usage(db, user.id)
    limit = plan.analyses_limit_monthly
    used = usage.analyses_count
    remaining = max(0, limit - used) if limit < 9999 else None

    return {
        "plan": {
            "slug": plan.slug,
            "name": plan.name,
            "analyses_limit_monthly": limit,
            "allow_real_model": plan.allow_real_model,
            "max_file_mb": plan.max_file_mb,
            "price_monthly_cents": plan.price_monthly_cents,
            "features": plan.features or {},
        },
        "status": sub.status.value,
        "period_start": sub.current_period_start.isoformat(),
        "period_end": sub.current_period_end.isoformat(),
        "usage": {
            "period_key": usage.period_key,
            "analyses_used": used,
            "analyses_remaining": remaining,
            "limit_reached": used >= limit if limit < 9999 else False,
        },
    }


def assert_can_analyze(
    db: Session,
    user: User,
    *,
    weights_path: str,
    file_size_bytes: int,
) -> Subscription:
    sub = ensure_subscription(db, user)
    plan = sub.plan

    if sub.status not in (
        SubscriptionStatus.active,
        SubscriptionStatus.trialing,
    ):
        raise HTTPException(
            402,
            "Tu suscripción no está activa. Renueva o cambia de plan.",
        )

    usage = get_usage(db, user.id)
    if usage.analyses_count >= plan.analyses_limit_monthly:
        raise HTTPException(
            402,
            f"Límite mensual alcanzado ({plan.analyses_limit_monthly} análisis). "
            f"Mejora tu plan para continuar.",
        )

    max_bytes = plan.max_file_mb * 1024 * 1024
    if file_size_bytes > max_bytes:
        raise HTTPException(
            413,
            f"Archivo demasiado grande. Máximo {plan.max_file_mb} MB en plan {plan.name}.",
        )

    is_demo = "demo_planos" in weights_path.replace("\\", "/").lower()
    if is_demo and plan.slug != "free":
        return sub
    if not plan.allow_real_model and not is_demo:
        raise HTTPException(
            403,
            "Tu plan solo permite el modelo demo. Entrena con train_demo.py o sube de plan.",
        )

    return sub


def record_analysis_usage(db: Session, user_id: int) -> None:
    usage = get_usage(db, user_id)
    usage.analyses_count += 1
    db.commit()


def change_plan(db: Session, user: User, plan_slug: str) -> dict:
    plan = db.query(Plan).filter(Plan.slug == plan_slug, Plan.is_public.is_(True)).first()
    if not plan:
        raise HTTPException(404, "Plan no encontrado")
    sub = ensure_subscription(db, user)
    start, end = _period_bounds()
    sub.plan_id = plan.id
    sub.status = SubscriptionStatus.active
    sub.current_period_start = start
    sub.current_period_end = end
    sub.canceled_at = None
    db.commit()
    return subscription_payload(db, user)
