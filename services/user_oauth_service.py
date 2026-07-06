"""Operaciones de usuarios vía OAuth y admin."""

from __future__ import annotations

from calendar import monthrange
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from db.models import Plan, Subscription, SubscriptionStatus, User, UserRole


def _period_bounds(now: datetime | None = None) -> tuple[datetime, datetime]:
    now = now or datetime.utcnow()
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_day = monthrange(start.year, start.month)[1]
    end = start.replace(day=last_day, hour=23, minute=59, second=59)
    return start, end


def _attach_free_subscription(db: Session, user: User) -> None:
    if user.subscription:
        return
    free = db.query(Plan).filter(Plan.slug == "free").first()
    if not free:
        raise HTTPException(503, "Base de datos sin planes. Ejecuta: python scripts/init_db.py")
    start, end = _period_bounds()
    db.add(
        Subscription(
            user_id=user.id,
            plan_id=free.id,
            status=SubscriptionStatus.active,
            current_period_start=start,
            current_period_end=end,
        )
    )


def find_or_create_google_user(db: Session, profile: dict) -> User:
    """Login o registro con Google (mismo flujo)."""
    email = profile["email"]
    sub = profile["oauth_subject"]

    by_oauth = (
        db.query(User)
        .filter(User.oauth_provider == "google", User.oauth_subject == sub)
        .first()
    )
    if by_oauth:
        if not by_oauth.is_active:
            raise HTTPException(403, "Cuenta desactivada")
        by_oauth.full_name = profile.get("full_name") or by_oauth.full_name
        by_oauth.avatar_url = profile.get("avatar_url") or by_oauth.avatar_url
        if by_oauth.email != email:
            conflict = db.query(User).filter(User.email == email, User.id != by_oauth.id).first()
            if conflict:
                raise HTTPException(
                    409,
                    "Ese correo de Google ya está asociado a otra cuenta",
                )
            by_oauth.email = email
        db.commit()
        db.refresh(by_oauth)
        return by_oauth

    by_email = db.query(User).filter(User.email == email).first()
    if by_email:
        if not by_email.is_active:
            raise HTTPException(403, "Cuenta desactivada")
        if by_email.oauth_provider and by_email.oauth_provider != "google":
            raise HTTPException(409, "Este correo usa otro proveedor de acceso")
        by_email.oauth_provider = "google"
        by_email.oauth_subject = sub
        by_email.full_name = profile.get("full_name") or by_email.full_name
        by_email.avatar_url = profile.get("avatar_url") or by_email.avatar_url
        db.commit()
        db.refresh(by_email)
        return by_email

    user = User(
        email=email,
        password_hash=None,
        full_name=profile.get("full_name") or email.split("@")[0],
        role=UserRole.user,
        oauth_provider="google",
        oauth_subject=sub,
        avatar_url=profile.get("avatar_url"),
    )
    db.add(user)
    db.flush()
    _attach_free_subscription(db, user)
    db.commit()
    db.refresh(user)
    return user
