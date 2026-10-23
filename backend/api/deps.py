"""Dependencias FastAPI: DB y usuario autenticado."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, UserRole
from services.auth_service import decode_token
from services.subscription_service import is_admin_user

security = HTTPBearer(auto_error=False)


def _attach_impersonator(user: User | None, payload: dict | None, db: Session) -> None:
    if not user:
        return
    imp_id = payload.get("imp") if payload else None
    if imp_id:
        try:
            user.impersonator_id = int(imp_id)
            user.impersonator = (
                db.query(User).filter(User.id == user.impersonator_id).first()
            )
            user.is_impersonated = bool(user.impersonator)
        except (ValueError, TypeError):
            user.impersonator_id = None
            user.impersonator = None
            user.is_impersonated = False
    else:
        user.impersonator_id = None
        user.impersonator = None
        user.is_impersonated = False


def get_current_user(
    db: Annotated[Session, Depends(get_db)],
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
) -> User:
    if not creds or not creds.credentials:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Inicia sesión para continuar",
            headers={"WWW-Authenticate": "Bearer"},
        )
    payload = decode_token(creds.credentials)
    if not payload or "sub" not in payload:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token inválido o expirado")
    user = db.query(User).filter(User.id == int(payload["sub"])).first()
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Usuario no válido")
    _attach_impersonator(user, payload, db)
    return user


def get_optional_user(
    db: Annotated[Session, Depends(get_db)],
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
) -> User | None:
    if not creds or not creds.credentials:
        return None
    payload = decode_token(creds.credentials)
    if not payload or "sub" not in payload:
        return None
    user = db.query(User).filter(User.id == int(payload["sub"])).first()
    _attach_impersonator(user, payload, db)
    return user


def require_admin(user: Annotated[User, Depends(get_current_user)]) -> User:
    if not is_admin_user(user):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Solo administradores")
    return user


def require_support_staff(user: Annotated[User, Depends(get_current_user)]) -> User:
    """Admin o agente de soporte (inbox de tickets)."""
    from services.support_service import is_staff_user

    if not is_staff_user(user):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Se requiere rol de soporte o admin")
    return user
