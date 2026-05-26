"""Planes por defecto y usuario admin opcional."""

from __future__ import annotations

import os
from calendar import monthrange
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from db.models import Plan, Subscription, SubscriptionStatus, User, UserRole
from services.auth_service import hash_password

DEFAULT_PLANS = [
    {
        "slug": "free",
        "name": "Gratis",
        "description": "Prueba la IA con límite mensual y modelo demo.",
        "price_monthly_cents": 0,
        "analyses_limit_monthly": 5,
        "allow_real_model": False,
        "max_file_mb": 5,
        "sort_order": 0,
        "features": {"support": "comunidad", "export": False},
    },
    {
        "slug": "starter",
        "name": "Starter",
        "description": "Para estudiantes y proyectos pequeños.",
        "price_monthly_cents": 9900,
        "analyses_limit_monthly": 30,
        "allow_real_model": True,
        "max_file_mb": 10,
        "sort_order": 1,
        "features": {"support": "email", "export": True},
    },
    {
        "slug": "pro",
        "name": "Pro",
        "description": "Uso profesional recurrente en obra.",
        "price_monthly_cents": 29900,
        "analyses_limit_monthly": 150,
        "allow_real_model": True,
        "max_file_mb": 20,
        "sort_order": 2,
        "features": {"support": "prioritario", "export": True, "api": True},
    },
    {
        "slug": "enterprise",
        "name": "Enterprise",
        "description": "Equipos y despachos con volumen alto.",
        "price_monthly_cents": 99900,
        "analyses_limit_monthly": 9999,
        "allow_real_model": True,
        "max_file_mb": 50,
        "sort_order": 3,
        "features": {"support": "dedicado", "export": True, "api": True, "sla": True},
    },
]


def _period_bounds(now: datetime | None = None) -> tuple[datetime, datetime]:
    now = now or datetime.utcnow()
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_day = monthrange(start.year, start.month)[1]
    end = start.replace(day=last_day, hour=23, minute=59, second=59)
    return start, end


def seed_plans(db: Session) -> None:
    for data in DEFAULT_PLANS:
        existing = db.query(Plan).filter(Plan.slug == data["slug"]).first()
        if existing:
            for key, val in data.items():
                setattr(existing, key, val)
        else:
            db.add(Plan(**data))
    db.commit()


def seed_admin(db: Session) -> None:
    email = os.getenv("ADMIN_EMAIL", "admin@planoia.com").strip().lower()
    password = os.getenv("ADMIN_PASSWORD", "admin123")
    user = db.query(User).filter(User.email == email).first()
    if not user:
        user = User(
            email=email,
            password_hash=hash_password(password),
            full_name="Administrador",
            role=UserRole.admin,
        )
        db.add(user)
        db.flush()
    else:
        user.role = UserRole.admin

    free_plan = db.query(Plan).filter(Plan.slug == "free").first()
    if free_plan and not user.subscription:
        start, end = _period_bounds()
        db.add(
            Subscription(
                user_id=user.id,
                plan_id=free_plan.id,
                status=SubscriptionStatus.active,
                current_period_start=start,
                current_period_end=end,
            )
        )
    db.commit()


def run_seed(db: Session) -> None:
    seed_plans(db)
    seed_admin(db)
