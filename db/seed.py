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
        "description": "Ideal para conocer ARCHITECT sin compromiso.",
        "price_monthly_cents": 0,
        "analyses_limit_monthly": 5,
        "allow_real_model": False,
        "max_file_mb": 5,
        "sort_order": 0,
        "features": {
            "ideal_for": "Probar la plataforma",
            "support": "comunidad",
            "export": False,
            "mobile_app": False,
            "home_projects": True,
            "team_invites": False,
            "max_projects": 1,
            "asks_limit_monthly": 20,
            "storage_gb": 1,
            "benefits": [
                "5 análisis de planos al mes",
                "20 preguntas al chat / mes",
                "1 proyecto casa hogar · 1 GB docs",
                "Modelo demo",
                "Archivos hasta 5 MB por carga",
            ],
        },
    },
    {
        "slug": "starter",
        "name": "Starter",
        "description": "Ideal para estudiantes y proyectos pequeños.",
        "price_monthly_cents": 30000,
        "analyses_limit_monthly": 30,
        "allow_real_model": True,
        "max_file_mb": 10,
        "sort_order": 1,
        "features": {
            "ideal_for": "Estudiantes y freelancers",
            "support": "email",
            "export": True,
            "mobile_app": False,
            "home_projects": True,
            "team_invites": False,
            "max_projects": 3,
            "asks_limit_monthly": 200,
            "storage_gb": 5,
            "benefits": [
                "30 análisis de planos al mes",
                "Hasta 3 proyectos casa hogar · 5 GB",
                "Análisis con modelo real (imagen y PDF)",
                "Exportar reportes PDF",
                "Archivos hasta 10 MB · Soporte por correo",
            ],
        },
    },
    {
        "slug": "pro",
        "name": "Pro",
        "description": "Ideal para obra y despacho individual.",
        "price_monthly_cents": 50000,
        "analyses_limit_monthly": 150,
        "allow_real_model": True,
        "max_file_mb": 20,
        "sort_order": 2,
        "features": {
            "ideal_for": "Profesionales en obra",
            "recommended": True,
            "support": "prioritario",
            "export": True,
            "mobile_app": True,
            "home_projects": True,
            "team_invites": False,
            "max_projects": 20,
            "asks_limit_monthly": 9999,
            "storage_gb": 25,
            "benefits": [
                "150 análisis de planos al mes",
                "Hasta 20 proyectos · 25 GB docs",
                "IA con normas de Chiapas e indexación",
                "App móvil ARCHITECT incluida",
                "Archivos hasta 20 MB · Soporte prioritario",
            ],
        },
    },
    {
        "slug": "enterprise",
        "name": "Enterprise",
        "description": "Ideal para equipos y despachos con alto volumen.",
        "price_monthly_cents": 90000,
        "analyses_limit_monthly": 9999,
        "allow_real_model": True,
        "max_file_mb": 50,
        "sort_order": 3,
        "features": {
            "ideal_for": "Equipos y constructoras",
            "support": "dedicado",
            "export": True,
            "mobile_app": True,
            "sla": True,
            "home_projects": True,
            "team_invites": True,
            "max_projects": 9999,
            "asks_limit_monthly": 9999,
            "storage_gb": 100,
            "benefits": [
                "Análisis y chat ilimitados",
                "Proyectos ilimitados · 100 GB docs",
                "Equipos, invitaciones y colaboración",
                "App móvil ARCHITECT incluida",
                "Archivos hasta 50 MB · Soporte dedicado con SLA",
            ],
        },
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
                if key == "features":
                    # Reemplaza beneficios/flags del seed; conserva claves externas (p. ej. Stripe).
                    merged = dict(existing.features or {})
                    incoming = dict(val or {})
                    for sticky in ("stripe_price_id", "stripe_product_id"):
                        if sticky in merged and sticky not in incoming:
                            incoming[sticky] = merged[sticky]
                    setattr(existing, key, incoming)
                else:
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
