"""Registro, login y perfil."""

from __future__ import annotations

from calendar import monthrange
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from api.db_errors import http_db_error
from api.deps import get_current_user
from api.schemas import AuthResponse, LoginRequest, RegisterRequest, UserOut
from db.database import get_db
from db.models import Plan, Subscription, SubscriptionStatus, User, UserRole
from services.auth_service import create_access_token, hash_password, verify_password
from services.subscription_service import subscription_payload

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _period_bounds(now: datetime | None = None) -> tuple[datetime, datetime]:
    now = now or datetime.utcnow()
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_day = monthrange(start.year, start.month)[1]
    end = start.replace(day=last_day, hour=23, minute=59, second=59)
    return start, end


def _auth_response(db: Session, user: User) -> AuthResponse:
    token = create_access_token(user.id, user.email, user.role.value)
    return AuthResponse(
        access_token=token,
        user=UserOut(
            id=user.id,
            email=user.email,
            full_name=user.full_name,
            role=user.role.value,
        ),
        subscription=subscription_payload(db, user),
    )


@router.post("/register", response_model=AuthResponse)
def register(body: RegisterRequest, db: Annotated[Session, Depends(get_db)]):
    try:
        email = body.email.strip().lower()
        if db.query(User).filter(User.email == email).first():
            raise HTTPException(400, "Este correo ya está registrado")

        free = db.query(Plan).filter(Plan.slug == "free").first()
        if not free:
            raise HTTPException(503, "Base de datos sin planes. Ejecuta: python scripts/init_db.py")

        user = User(
            email=email,
            password_hash=hash_password(body.password),
            full_name=body.full_name.strip() or email.split("@")[0],
            role=UserRole.user,
        )
        db.add(user)
        db.flush()

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
        db.commit()
        db.refresh(user)
        return _auth_response(db, user)
    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        raise http_db_error(exc) from exc


@router.post("/login", response_model=AuthResponse)
def login(body: LoginRequest, db: Annotated[Session, Depends(get_db)]):
    try:
        email = body.email.strip().lower()
        user = db.query(User).filter(User.email == email).first()
        if not user or not verify_password(body.password, user.password_hash):
            raise HTTPException(401, "Correo o contraseña incorrectos")
        if not user.is_active:
            raise HTTPException(403, "Cuenta desactivada")
        return _auth_response(db, user)
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.get("/me")
def me(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return {
        "user": UserOut(
            id=user.id,
            email=user.email,
            full_name=user.full_name,
            role=user.role.value,
        ),
        "subscription": subscription_payload(db, user),
    }
