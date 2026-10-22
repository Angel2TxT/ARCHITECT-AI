"""JWT y contraseñas (bcrypt directo, compatible con bcrypt 4.x)."""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

import bcrypt
from jose import JWTError, jwt

SECRET_KEY = os.getenv("JWT_SECRET_KEY", "cambia-esto-en-produccion-plano-ia-2024")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_HOURS = int(os.getenv("JWT_EXPIRE_HOURS", "168"))


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def create_access_token(
    user_id: int,
    email: str,
    role: str,
    *,
    impersonator_id: int | None = None,
    expire_hours: int | None = None,
) -> str:
    hours = expire_hours if expire_hours is not None else ACCESS_TOKEN_EXPIRE_HOURS
    if impersonator_id is not None and expire_hours is None:
        hours = min(hours, 4)
    expire = datetime.now(timezone.utc) + timedelta(hours=hours)
    payload = {
        "sub": str(user_id),
        "email": email,
        "role": role,
        "exp": expire,
    }
    if impersonator_id is not None:
        payload["imp"] = str(impersonator_id)
        payload["impersonation"] = True
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
