"""Verificación de correo electrónico mediante código numérico de 6 dígitos."""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.schemas import _normalize_email
from db.models import EmailVerificationCode, User
from services.auth_service import SECRET_KEY, verify_password
from services.email_service import send_verification_code_email

CODE_TTL_SECONDS = 300  # 5 minutos
RESEND_COOLDOWN_SECONDS = 60  # 60 segundos
MAX_ATTEMPTS_PER_CODE = 5
_CODE_RE = re.compile(r"^\d{6}$")


def _hash_code(user_id: int, code: str) -> str:
    payload = f"{user_id}:{code}".encode("utf-8")
    return hmac.new(SECRET_KEY.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def _generate_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def issue_verification_code(
    db: Session,
    user: User,
    *,
    enforce_cooldown: bool = True,
) -> dict[str, int]:
    """Genera un nuevo código de 6 dígitos, invalida los anteriores y lo envía por correo."""
    if user.email_verified:
        raise HTTPException(400, "Este correo electrónico ya está verificado")

    now = datetime.utcnow()
    if enforce_cooldown:
        latest = (
            db.query(EmailVerificationCode)
            .filter(
                EmailVerificationCode.user_id == user.id,
                EmailVerificationCode.consumed_at.is_(None),
            )
            .order_by(EmailVerificationCode.id.desc())
            .first()
        )
        if latest and latest.created_at:
            elapsed = (now - latest.created_at).total_seconds()
            if elapsed < RESEND_COOLDOWN_SECONDS:
                remaining = int(RESEND_COOLDOWN_SECONDS - elapsed) + 1
                raise HTTPException(
                    429,
                    {
                        "code": "RESEND_COOLDOWN",
                        "message": f"Espera {remaining} segundos antes de solicitar un nuevo código",
                        "retry_after_seconds": remaining,
                    },
                )

    # Invalidar cualquier código previo activo.
    (
        db.query(EmailVerificationCode)
        .filter(
            EmailVerificationCode.user_id == user.id,
            EmailVerificationCode.consumed_at.is_(None),
        )
        .update({EmailVerificationCode.consumed_at: now}, synchronize_session=False)
    )

    code = _generate_code()
    row = EmailVerificationCode(
        user_id=user.id,
        code_hash=_hash_code(user.id, code),
        expires_at=now + timedelta(seconds=CODE_TTL_SECONDS),
        attempts=0,
        created_at=now,
    )
    db.add(row)
    db.commit()

    send_verification_code_email(
        to_email=user.email,
        user_name=user.full_name or user.email.split("@")[0],
        code=code,
        expires_minutes=CODE_TTL_SECONDS // 60,
    )

    return {
        "expires_in_seconds": CODE_TTL_SECONDS,
        "cooldown_seconds": RESEND_COOLDOWN_SECONDS,
    }


def verify_email_code(db: Session, *, email: str, code: str) -> User:
    """Valida el código de 6 dígitos, controla intentos/expiración y activa la cuenta."""
    norm_email = _normalize_email(email)
    clean_code = (code or "").strip()
    if not _CODE_RE.fullmatch(clean_code):
        raise HTTPException(422, "El código debe tener exactamente 6 dígitos numéricos")

    user = db.query(User).filter(User.email == norm_email).first()
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    if not user.is_active:
        raise HTTPException(403, "Cuenta desactivada")
    if user.email_verified:
        raise HTTPException(
            400,
            {
                "code": "ALREADY_VERIFIED",
                "message": "Este correo electrónico ya está verificado.",
            },
        )

    now = datetime.utcnow()
    row = (
        db.query(EmailVerificationCode)
        .filter(
            EmailVerificationCode.user_id == user.id,
            EmailVerificationCode.consumed_at.is_(None),
        )
        .order_by(EmailVerificationCode.id.desc())
        .first()
    )
    if not row:
        raise HTTPException(
            400,
            {
                "code": "NO_ACTIVE_CODE",
                "message": "No hay un código activo. Solicita uno nuevo.",
            },
        )

    if now > row.expires_at:
        row.consumed_at = now
        db.commit()
        raise HTTPException(
            400,
            {
                "code": "CODE_EXPIRED",
                "message": "El código ha expirado. Solicita uno nuevo.",
            },
        )

    if row.attempts >= MAX_ATTEMPTS_PER_CODE:
        row.consumed_at = now
        db.commit()
        raise HTTPException(
            429,
            {
                "code": "MAX_ATTEMPTS_EXCEEDED",
                "message": "Has superado el máximo de 5 intentos. Solicita un nuevo código.",
            },
        )

    expected_hash = _hash_code(user.id, clean_code)
    if not hmac.compare_digest(expected_hash, row.code_hash):
        row.attempts += 1
        if row.attempts >= MAX_ATTEMPTS_PER_CODE:
            row.consumed_at = now
            db.commit()
            raise HTTPException(
                429,
                {
                    "code": "MAX_ATTEMPTS_EXCEEDED",
                    "message": "Código incorrecto. Has superado el máximo de 5 intentos. Solicita un nuevo código.",
                },
            )
        remaining = MAX_ATTEMPTS_PER_CODE - row.attempts
        db.commit()
        raise HTTPException(
            400,
            {
                "code": "INVALID_CODE",
                "message": f"Código incorrecto. Te quedan {remaining} intento(s).",
            },
        )

    row.consumed_at = now
    user.email_verified = True
    db.commit()
    db.refresh(user)
    return user


def update_unverified_email(
    db: Session,
    *,
    current_email: str,
    new_email: str,
    password: str | None = None,
) -> User:
    """Permite corregir el correo electrónico antes de completar la verificación."""
    norm_current = _normalize_email(current_email)
    norm_new = _normalize_email(new_email)

    user = db.query(User).filter(User.email == norm_current).first()
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    if user.email_verified:
        raise HTTPException(400, "La cuenta ya está verificada")
    if password is not None and (
        not user.password_hash or not verify_password(password, user.password_hash)
    ):
        raise HTTPException(401, "Contraseña incorrecta")

    if norm_new != norm_current:
        conflict = db.query(User).filter(User.email == norm_new, User.id != user.id).first()
        if conflict:
            raise HTTPException(400, "Este correo ya está registrado")
        user.email = norm_new
        db.add(user)
        db.flush()

    issue_verification_code(
        db,
        user,
        enforce_cooldown=(norm_new == norm_current),
    )
    db.refresh(user)
    return user


def get_verification_status(db: Session, *, email: str) -> dict[str, int | bool]:
    """Devuelve el estado y temporizadores vigentes desde el backend (fuente de verdad)."""
    norm_email = _normalize_email(email)
    base: dict[str, int | bool] = {
        "requires_verification": False,
        "expires_in_seconds": 0,
        "resend_available_in_seconds": 0,
        "ttl_seconds": CODE_TTL_SECONDS,
        "cooldown_seconds": RESEND_COOLDOWN_SECONDS,
        "attempts_remaining": 0,
    }
    if not norm_email:
        return base

    user = db.query(User).filter(User.email == norm_email).first()
    if not user or not user.is_active or user.email_verified:
        return base

    now = datetime.utcnow()
    row = (
        db.query(EmailVerificationCode)
        .filter(
            EmailVerificationCode.user_id == user.id,
            EmailVerificationCode.consumed_at.is_(None),
        )
        .order_by(EmailVerificationCode.id.desc())
        .first()
    )

    expires_in = 0
    resend_in = 0
    attempts_remaining = 0
    if row:
        if row.expires_at and row.expires_at > now:
            expires_in = max(0, int((row.expires_at - now).total_seconds()))
        if row.created_at:
            elapsed = (now - row.created_at).total_seconds()
            if elapsed < RESEND_COOLDOWN_SECONDS:
                resend_in = max(0, int(RESEND_COOLDOWN_SECONDS - elapsed) + 1)
        attempts_remaining = max(0, MAX_ATTEMPTS_PER_CODE - (row.attempts or 0))

    return {
        "requires_verification": True,
        "expires_in_seconds": expires_in,
        "resend_available_in_seconds": resend_in,
        "ttl_seconds": CODE_TTL_SECONDS,
        "cooldown_seconds": RESEND_COOLDOWN_SECONDS,
        "attempts_remaining": attempts_remaining,
    }

