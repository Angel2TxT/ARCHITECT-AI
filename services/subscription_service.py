"""Límites de plan, uso mensual y permisos."""

from __future__ import annotations

from calendar import monthrange
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session, joinedload

from db.models import Plan, Subscription, SubscriptionStatus, UsageRecord, User, UserRole


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


def is_admin_user(user: User) -> bool:
    return user.role == UserRole.admin or str(user.role) == UserRole.admin.value


def is_paid_plan(plan: Plan) -> bool:
    return (plan.price_monthly_cents or 0) > 0


def subscription_payload(db: Session, user: User) -> dict:
    sub = ensure_subscription(db, user)
    plan = sub.plan
    usage = get_usage(db, user.id)
    limit = plan.analyses_limit_monthly
    used = usage.analyses_count
    is_unlimited = is_admin_user(user)
    remaining = None if is_unlimited else max(0, limit - used)

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
        "is_unlimited": is_unlimited,
        "status": sub.status.value,
        "period_start": sub.current_period_start.isoformat(),
        "period_end": sub.current_period_end.isoformat(),
        "stripe_customer_id": sub.stripe_customer_id,
        "has_active_payment": bool(
            sub.stripe_subscription_id
            and not str(sub.stripe_subscription_id).startswith("demo_sub_")
        ),
        "usage": {
            "period_key": usage.period_key,
            "analyses_used": used,
            "analyses_remaining": remaining,
            "limit_reached": False if is_unlimited else used >= limit,
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
    is_unlimited = is_admin_user(user)

    if sub.status not in (
        SubscriptionStatus.active,
        SubscriptionStatus.trialing,
    ):
        raise HTTPException(
            402,
            "Tu suscripción no está activa. Renueva o cambia de plan.",
        )

    usage = get_usage(db, user.id)
    if not is_unlimited and usage.analyses_count >= plan.analyses_limit_monthly:
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


def change_plan(
    db: Session,
    user: User,
    plan_slug: str,
    *,
    bypass_checkout: bool = False,
    payment_ref: str | None = None,
    stripe_customer_id: str | None = None,
) -> dict:
    plan = db.query(Plan).filter(Plan.slug == plan_slug, Plan.is_public.is_(True)).first()
    if not plan:
        raise HTTPException(404, "Plan no encontrado")
    sub = ensure_subscription(db, user)

    if (
        not bypass_checkout
        and not is_admin_user(user)
        and is_paid_plan(plan)
    ):
        raise HTTPException(
            status_code=402,
            detail={
                "message": "Este plan requiere completar el pago en la pasarela.",
                "code": "checkout_required",
                "plan_slug": plan_slug,
            },
        )

    start, end = _period_bounds()
    sub.plan_id = plan.id
    sub.status = SubscriptionStatus.active
    sub.current_period_start = start
    sub.current_period_end = end
    sub.canceled_at = None

    if stripe_customer_id:
        sub.stripe_customer_id = stripe_customer_id
    elif not sub.stripe_customer_id:
        sub.stripe_customer_id = f"demo_cus_{user.id}"

    if payment_ref is not None:
        sub.stripe_subscription_id = payment_ref
    elif not is_paid_plan(plan):
        sub.stripe_subscription_id = None

    db.commit()
    return subscription_payload(db, user)


def user_usage_history(db: Session, user: User, *, months: int = 6) -> list[dict]:
    """Uso mensual de análisis (últimos N meses) para gráfica en perfil."""
    months = max(1, min(months, 12))
    sub = ensure_subscription(db, user)
    plan = sub.plan
    limit = plan.analyses_limit_monthly if plan else 0
    unlimited = is_admin_user(user)

    now = datetime.utcnow()
    keys: list[str] = []
    y, m = now.year, now.month
    for _ in range(months):
        keys.append(f"{y:04d}-{m:02d}")
        m -= 1
        if m < 1:
            m = 12
            y -= 1
    keys.reverse()

    rows = (
        db.query(UsageRecord.period_key, UsageRecord.analyses_count)
        .filter(UsageRecord.user_id == user.id, UsageRecord.period_key.in_(keys))
        .all()
    )
    used_map = {k: int(v or 0) for k, v in rows}

    labels = ("Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic")

    return [
        {
            "period_key": key,
            "label": labels[int(key.split("-")[1]) - 1],
            "analyses_used": used_map.get(key, 0),
            "analyses_limit": None if unlimited else limit,
            "is_current": key == period_key(now),
        }
        for key in keys
    ]
