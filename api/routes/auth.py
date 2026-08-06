"""Registro, login, perfil y Google OAuth."""

from __future__ import annotations

from calendar import monthrange
from datetime import datetime
from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from api.db_errors import http_db_error
from api.deps import get_current_user
from api.schemas import (
    AuthResponse,
    ForgotPasswordRequest,
    LoginRequest,
    RegisterRequest,
    ResetPasswordRequest,
    UserOut,
)
from db.database import get_db
from db.models import Plan, Subscription, SubscriptionStatus, User, UserRole
from services.auth_service import create_access_token, hash_password, verify_password
from services.avatar_service import delete_user_avatar, save_user_avatar
from services.google_oauth_service import (
    app_frontend_base,
    build_google_authorize_url,
    create_oauth_state,
    exchange_google_code,
    google_oauth_configured,
    normalize_google_profile,
    verify_oauth_state,
)
from services.subscription_service import subscription_payload
from services.user_oauth_service import find_or_create_google_user
from services.password_reset_service import (
    request_password_reset,
    reset_password_with_token,
    validate_reset_token,
)

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _period_bounds(now: datetime | None = None) -> tuple[datetime, datetime]:
    now = now or datetime.utcnow()
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_day = monthrange(start.year, start.month)[1]
    end = start.replace(day=last_day, hour=23, minute=59, second=59)
    return start, end


def _user_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role.value,
        avatar_url=user.avatar_url,
    )


def _auth_response(db: Session, user: User) -> AuthResponse:
    token = create_access_token(user.id, user.email, user.role.value)
    return AuthResponse(
        access_token=token,
        user=_user_out(user),
        subscription=subscription_payload(db, user),
    )


@router.post("/register", response_model=AuthResponse)
def register(body: RegisterRequest, db: Annotated[Session, Depends(get_db)]):
    try:
        email = body.email.strip().lower()
        existing = db.query(User).filter(User.email == email).first()
        if existing:
            if existing.oauth_provider == "google" and not existing.password_hash:
                raise HTTPException(
                    400,
                    "Este correo ya está registrado con Google. Usa «Continuar con Google».",
                )
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
        if not user:
            raise HTTPException(401, "Correo o contraseña incorrectos")
        if not user.password_hash:
            raise HTTPException(
                401,
                "Esta cuenta usa Google. Inicia sesión con «Continuar con Google».",
            )
        if not verify_password(body.password, user.password_hash):
            raise HTTPException(401, "Correo o contraseña incorrectos")
        if not user.is_active:
            raise HTTPException(403, "Cuenta desactivada")
        return _auth_response(db, user)
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.get("/google/enabled")
def google_enabled():
    return {"enabled": google_oauth_configured()}


@router.get("/google")
def google_login_start():
    if not google_oauth_configured():
        raise HTTPException(503, "Google OAuth no configurado en el servidor")
    state = create_oauth_state()
    return RedirectResponse(build_google_authorize_url(state), status_code=302)


@router.get("/google/callback")
async def google_login_callback(
    db: Annotated[Session, Depends(get_db)],
    code: str = "",
    state: str = "",
    error: str = "",
):
    base = app_frontend_base()
    if error:
        return RedirectResponse(
            f"{base}/login?oauth_error={quote(error)}",
            status_code=302,
        )
    if not code or not state:
        return RedirectResponse(
            f"{base}/login?oauth_error={quote('Faltan parámetros de Google')}",
            status_code=302,
        )
    try:
        verify_oauth_state(state)
        profile_raw = await exchange_google_code(code)
        profile = normalize_google_profile(profile_raw)
        user = find_or_create_google_user(db, profile)
        token = create_access_token(user.id, user.email, user.role.value)
        return RedirectResponse(
            f"{base}/login?access_token={quote(token)}",
            status_code=302,
        )
    except HTTPException as exc:
        return RedirectResponse(
            f"{base}/login?oauth_error={quote(str(exc.detail))}",
            status_code=302,
        )
    except Exception as exc:
        return RedirectResponse(
            f"{base}/login?oauth_error={quote('Error al iniciar con Google')}",
            status_code=302,
        )


@router.get("/me")
def me(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return {
        "user": _user_out(user),
        "subscription": subscription_payload(db, user),
    }


@router.post("/me/avatar")
async def upload_avatar(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    file: UploadFile = File(...),
):
    """Sube o reemplaza la foto de perfil (JPG/PNG/WEBP, máx. 3 MB)."""
    try:
        url = await save_user_avatar(user.id, file)
        # cache-bust para que el navegador recargue la imagen
        stamped = f"{url}?v={int(datetime.utcnow().timestamp())}"
        user.avatar_url = stamped
        db.add(user)
        db.commit()
        db.refresh(user)
        return {"ok": True, "avatar_url": user.avatar_url, "user": _user_out(user)}
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.delete("/me/avatar")
def remove_avatar(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Quita la foto de perfil y vuelve a las iniciales."""
    try:
        delete_user_avatar(user.id)
        user.avatar_url = None
        db.add(user)
        db.commit()
        db.refresh(user)
        return {"ok": True, "avatar_url": None, "user": _user_out(user)}
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.post("/forgot-password")
def forgot_password(
    body: ForgotPasswordRequest,
    db: Annotated[Session, Depends(get_db)],
):
    """Envía enlace de recuperación al correo (cuentas con contraseña local)."""
    try:
        return request_password_reset(db, body.email)
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.get("/reset-password/validate")
def reset_password_validate(token: str, db: Annotated[Session, Depends(get_db)]):
    """Comprueba si el token del enlace sigue siendo válido."""
    try:
        return validate_reset_token(db, token)
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.post("/reset-password")
def reset_password(body: ResetPasswordRequest, db: Annotated[Session, Depends(get_db)]):
    """Establece nueva contraseña con token del correo."""
    try:
        return reset_password_with_token(db, body.token, body.password)
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc
