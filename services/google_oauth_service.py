"""Google OAuth 2.0 (authorization code)."""

from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx
from fastapi import HTTPException
from jose import JWTError, jwt

from services.auth_service import ALGORITHM, SECRET_KEY

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"

OAUTH_STATE_EXPIRE_MINUTES = 10


def google_oauth_configured() -> bool:
    return bool(
        os.getenv("GOOGLE_CLIENT_ID", "").strip()
        and os.getenv("GOOGLE_CLIENT_SECRET", "").strip()
    )


def google_redirect_uri() -> str:
    explicit = os.getenv("GOOGLE_REDIRECT_URI", "").strip()
    if explicit:
        return explicit
    base = os.getenv("APP_BASE_URL", "http://127.0.0.1:8080").rstrip("/")
    return f"{base}/api/auth/google/callback"


def app_frontend_base() -> str:
    return os.getenv("APP_BASE_URL", "http://127.0.0.1:8080").rstrip("/")


def create_oauth_state() -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=OAUTH_STATE_EXPIRE_MINUTES)
    payload = {
        "purpose": "google_oauth",
        "nonce": secrets.token_urlsafe(16),
        "exp": expire,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def verify_oauth_state(state: str) -> None:
    try:
        data = jwt.decode(state, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as exc:
        raise HTTPException(400, "Estado OAuth inválido o expirado") from exc
    if data.get("purpose") != "google_oauth":
        raise HTTPException(400, "Estado OAuth inválido")


def build_google_authorize_url(state: str) -> str:
    client_id = os.getenv("GOOGLE_CLIENT_ID", "").strip()
    if not client_id:
        raise HTTPException(503, "Google OAuth no configurado")
    params = {
        "client_id": client_id,
        "redirect_uri": google_redirect_uri(),
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "access_type": "online",
        "prompt": "select_account",
    }
    return f"{GOOGLE_AUTH_URL}?{urlencode(params)}"


async def exchange_google_code(code: str) -> dict:
    client_id = os.getenv("GOOGLE_CLIENT_ID", "").strip()
    client_secret = os.getenv("GOOGLE_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        raise HTTPException(503, "Google OAuth no configurado")

    async with httpx.AsyncClient(timeout=20.0) as client:
        token_res = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "code": code,
                "client_id": client_id,
                "client_secret": client_secret,
                "redirect_uri": google_redirect_uri(),
                "grant_type": "authorization_code",
            },
        )
        if token_res.status_code != 200:
            raise HTTPException(400, "No se pudo completar el inicio con Google")
        tokens = token_res.json()
        access_token = tokens.get("access_token")
        if not access_token:
            raise HTTPException(400, "Token de Google inválido")

        user_res = await client.get(
            GOOGLE_USERINFO_URL,
            headers={"Authorization": f"Bearer {access_token}"},
        )
        if user_res.status_code != 200:
            raise HTTPException(400, "No se pudo leer el perfil de Google")
        return user_res.json()


def normalize_google_profile(profile: dict) -> dict:
    email = (profile.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(400, "Google no devolvió un correo electrónico")
    if profile.get("email_verified") is False:
        raise HTTPException(400, "El correo de Google no está verificado")
    sub = str(profile.get("sub") or "").strip()
    if not sub:
        raise HTTPException(400, "Identificador de Google inválido")
    name = (profile.get("name") or email.split("@")[0]).strip()[:120]
    avatar = (profile.get("picture") or "").strip()[:512] or None
    return {
        "email": email,
        "oauth_subject": sub,
        "full_name": name,
        "avatar_url": avatar,
    }
