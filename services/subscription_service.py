"""Límites de plan, uso mensual y permisos."""

from __future__ import annotations

from calendar import monthrange
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from db.models import (
    Chat,
    HomeProject,
    HomeProjectDocument,
    Message,
    Plan,
    Subscription,
    SubscriptionStatus,
    UsageRecord,
    User,
    UserRole,
)


def period_key(dt: datetime | None = None) -> str:
    dt = dt or datetime.utcnow()
    return dt.strftime("%Y-%m")


def plan_storage_gb(plan: Plan | None) -> float:
    """GB de documentación incluidos en el plan (casa hogar / archivos del proyecto)."""
    if not plan:
        return 1.0
    features = plan.features or {}
    raw = features.get("storage_gb", 1)
    try:
        return max(0.0, float(raw))
    except (TypeError, ValueError):
        return 1.0


def plan_capabilities(plan: Plan | None) -> dict:
    """Capacidades efectivas del plan (flags + límites)."""
    f = (plan.features if plan else None) or {}
    asks = f.get("asks_limit_monthly", 20)
    try:
        asks_limit = int(asks)
    except (TypeError, ValueError):
        asks_limit = 20
    max_projects = f.get("max_projects", 1)
    try:
        max_projects_i = int(max_projects)
    except (TypeError, ValueError):
        max_projects_i = 1
    return {
        "home_projects": bool(f.get("home_projects", True)),
        "team_invites": bool(f.get("team_invites", False)),
        "export": bool(f.get("export", False)),
        "mobile_app": bool(f.get("mobile_app", False)),
        "max_projects": max(0, max_projects_i),
        "asks_limit_monthly": max(0, asks_limit),
        "asks_unlimited": asks_limit >= 9999,
        "storage_gb": plan_storage_gb(plan),
        "allow_real_model": bool(plan.allow_real_model) if plan else False,
        "max_file_mb": int(plan.max_file_mb) if plan else 5,
        "analyses_limit_monthly": int(plan.analyses_limit_monthly) if plan else 5,
    }


def count_owned_home_projects(db: Session, user_id: int) -> int:
    return (
        db.query(func.count(HomeProject.id))
        .filter(HomeProject.user_id == user_id)
        .scalar()
        or 0
    )


def get_asks_used(db: Session, user_id: int) -> int:
    """Preguntas al chat (mensajes user) en el periodo mensual actual."""
    start, _end = _period_bounds()
    total = (
        db.query(func.count(Message.id))
        .join(Chat, Chat.id == Message.chat_id)
        .filter(
            Chat.user_id == user_id,
            Message.role == "user",
            Message.created_at >= start,
        )
        .scalar()
    )
    return int(total or 0)


def assert_can_ask(db: Session, user: User) -> None:
    if is_admin_user(user):
        return
    sub = ensure_subscription(db, user)
    caps = plan_capabilities(sub.plan)
    if caps["asks_unlimited"]:
        return
    used = get_asks_used(db, user.id)
    limit = caps["asks_limit_monthly"]
    if used >= limit:
        raise HTTPException(
            402,
            f"Límite de preguntas del chat alcanzado ({limit}/mes en plan {sub.plan.name}). "
            f"Mejora tu plan para continuar.",
        )


def assert_can_use_home_projects(db: Session, user: User) -> None:
    if is_admin_user(user):
        return
    sub = ensure_subscription(db, user)
    caps = plan_capabilities(sub.plan)
    if not caps["home_projects"]:
        raise HTTPException(
            402,
            f"Casa hogar no está incluida en el plan {sub.plan.name}. Mejora tu plan.",
        )


def assert_can_create_home_project(db: Session, user: User) -> None:
    assert_can_use_home_projects(db, user)
    if is_admin_user(user):
        return
    sub = ensure_subscription(db, user)
    caps = plan_capabilities(sub.plan)
    owned = count_owned_home_projects(db, user.id)
    limit = caps["max_projects"]
    if owned >= limit:
        raise HTTPException(
            402,
            f"Límite de proyectos casa hogar alcanzado ({owned}/{limit} en plan {sub.plan.name}). "
            f"Mejora tu plan o archiva un proyecto.",
        )


def assert_can_invite_members(db: Session, user: User) -> None:
    if is_admin_user(user):
        return
    sub = ensure_subscription(db, user)
    caps = plan_capabilities(sub.plan)
    if not caps["team_invites"]:
        raise HTTPException(
            402,
            f"Las invitaciones de equipo están en Enterprise. "
            f"Tu plan actual es {sub.plan.name}.",
        )


def assert_can_use_mobile_app(db: Session, user: User) -> None:
    """App móvil exclusiva de Pro y Enterprise."""
    if is_admin_user(user):
        return
    sub = ensure_subscription(db, user)
    caps = plan_capabilities(sub.plan)
    if not caps["mobile_app"]:
        raise HTTPException(
            402,
            f"La app móvil está incluida en Pro y Enterprise. "
            f"Tu plan actual es {sub.plan.name}.",
        )


def assert_can_export(db: Session, user: User) -> None:
    if is_admin_user(user):
        return
    sub = ensure_subscription(db, user)
    caps = plan_capabilities(sub.plan)
    if not caps["export"]:
        raise HTTPException(
            402,
            f"Exportar reportes no está incluido en el plan {sub.plan.name}. "
            f"Disponible desde Starter.",
        )


def get_documentation_bytes_used(db: Session, user_id: int) -> int:
    """Suma el peso de documentos en proyectos que el usuario posee."""
    total = (
        db.query(func.coalesce(func.sum(HomeProjectDocument.file_size), 0))
        .join(HomeProject, HomeProject.id == HomeProjectDocument.project_id)
        .filter(HomeProject.user_id == user_id)
        .scalar()
    )
    return int(total or 0)


def assert_can_store_documentation(
    db: Session,
    user: User,
    *,
    additional_bytes: int,
) -> None:
    """Valida la cuota de almacenamiento de documentación del plan."""
    if is_admin_user(user):
        return
    sub = ensure_subscription(db, user)
    limit_gb = plan_storage_gb(sub.plan)
    limit_bytes = int(limit_gb * 1024 * 1024 * 1024)
    used = get_documentation_bytes_used(db, user.id)
    if used + max(0, int(additional_bytes)) > limit_bytes:
        used_gb = used / (1024 * 1024 * 1024)
        raise HTTPException(
            402,
            f"Almacenamiento de documentación lleno "
            f"({used_gb:.2f} / {limit_gb:g} GB en plan {sub.plan.name}). "
            f"Libera archivos o mejora tu plan.",
        )


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
    storage_gb = plan_storage_gb(plan)
    storage_used = get_documentation_bytes_used(db, user.id)
    storage_limit_bytes = int(storage_gb * 1024 * 1024 * 1024)
    caps = plan_capabilities(plan)
    asks_used = get_asks_used(db, user.id)
    asks_limit = caps["asks_limit_monthly"]
    asks_remaining = None if caps["asks_unlimited"] or is_unlimited else max(0, asks_limit - asks_used)

    return {
        "plan": {
            "slug": plan.slug,
            "name": plan.name,
            "analyses_limit_monthly": limit,
            "allow_real_model": plan.allow_real_model,
            "max_file_mb": plan.max_file_mb,
            "price_monthly_cents": plan.price_monthly_cents,
            "storage_gb": storage_gb,
            "features": plan.features or {},
            "capabilities": caps,
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
            "asks_used": asks_used,
            "asks_remaining": asks_remaining,
            "asks_limit": None if caps["asks_unlimited"] or is_unlimited else asks_limit,
            "projects_owned": count_owned_home_projects(db, user.id),
            "projects_limit": None if is_unlimited else caps["max_projects"],
            "storage_used_bytes": storage_used,
            "storage_limit_bytes": storage_limit_bytes,
            "storage_used_gb": round(storage_used / (1024 * 1024 * 1024), 3),
            "storage_limit_gb": storage_gb,
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
