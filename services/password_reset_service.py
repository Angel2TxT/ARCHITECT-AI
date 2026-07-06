"""Tokens de recuperación de contraseña (JWT, 1 h)."""

from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import HTTPException
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from db.models import User
from services.auth_service import ALGORITHM, SECRET_KEY, hash_password
from services.email_service import is_mail_configured, send_password_reset_email

RESET_TOKEN_TYPE = "password_reset"
RESET_TTL_MINUTES = int(os.getenv("PASSWORD_RESET_TTL_MINUTES", "60"))
APP_BASE_URL = os.getenv("APP_BASE_URL", "http://localhost:3000").rstrip("/")


def _reset_expiry() -> datetime:
    return datetime.now(timezone.utc) + timedelta(minutes=RESET_TTL_MINUTES)


def create_reset_token(*, user_id: int, email: str) -> str:
    payload = {
        "typ": RESET_TOKEN_TYPE,
        "uid": user_id,
        "email": email,
        "exp": _reset_expiry(),
        "jti": secrets.token_urlsafe(10),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_reset_token(token: str) -> dict[str, Any]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as exc:
        raise HTTPException(400, "Enlace inválido o expirado. Solicita uno nuevo.") from exc
    if payload.get("typ") != RESET_TOKEN_TYPE:
        raise HTTPException(400, "Token de recuperación inválido")
    return payload


def reset_url(token: str) -> str:
    return f"{APP_BASE_URL}/login?reset={token}"


def request_password_reset(db: Session, email: str) -> dict[str, str]:
    """Envía correo si la cuenta existe y tiene contraseña local."""
    email = email.strip().lower()
    user = db.query(User).filter(User.email == email).first()

    # Respuesta genérica (no revelar si el correo existe)
    generic = {
        "status": "sent",
        "message": "Si el correo está registrado, recibirás instrucciones en unos minutos.",
    }

    if not user or not user.is_active or not user.password_hash:
        return generic

    if not is_mail_configured():
        raise HTTPException(
            503,
            "Recuperación por correo no disponible. Configura MAIL_* en .env o contacta al administrador.",
        )

    token = create_reset_token(user_id=user.id, email=user.email)
    url = reset_url(token)
    sent = send_password_reset_email(
        to_email=user.email,
        user_name=user.full_name or user.email,
        reset_url=url,
        expires_minutes=RESET_TTL_MINUTES,
    )
    if not sent:
        raise HTTPException(500, "No se pudo enviar el correo. Intenta más tarde.")

    return generic


def reset_password_with_token(db: Session, token: str, new_password: str) -> dict[str, str]:
    payload = decode_reset_token(token)
    user_id = int(payload["uid"])
    user = db.get(User, user_id)
    if not user or user.email != str(payload.get("email", "")).lower():
        raise HTTPException(400, "Enlace inválido o expirado.")
    if not user.is_active:
        raise HTTPException(403, "Cuenta desactivada")
    if not user.password_hash:
        raise HTTPException(
            400,
            "Esta cuenta usa Google. Inicia sesión con «Continuar con Google».",
        )

    user.password_hash = hash_password(new_password)
    db.commit()
    return {"status": "ok", "message": "Contraseña actualizada. Ya puedes iniciar sesión."}


def validate_reset_token(db: Session, token: str) -> dict[str, str]:
    payload = decode_reset_token(token)
    user = db.get(User, int(payload["uid"]))
    if not user or user.email != str(payload.get("email", "")).lower():
        raise HTTPException(400, "Enlace inválido o expirado.")
    return {"valid": True, "email": user.email}
