"""Endpoints móviles para autenticación, estado, análisis y casa hogar."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from api.deps import get_current_user
from api.routes.analyze import analyze as analyze_endpoint
from api.routes.auth import (
    _user_out,
    login as login_endpoint,
    patch_me as patch_me_endpoint,
    register as register_endpoint,
)
from api.schemas import LoginRequest, RegisterRequest, UpdateProfileRequest
from db.database import get_db
from db.models import User
from services.subscription_service import subscription_payload

router = APIRouter(prefix="/api/mobile", tags=["mobile"])


@router.get("/health")
def mobile_health():
    """Endpoint de comprobación para la app móvil."""
    return {
        "ok": True,
        "service": "mobile",
        "message": "API móvil lista",
        "version": "1.1",
        "endpoints": [
            "/api/mobile/health",
            "/api/mobile/register",
            "/api/mobile/login",
            "/api/mobile/me",
            "/api/mobile/analyze",
            "/api/mobile/home-projects",
            "/api/mobile/home-projects/catalog",
            "/api/mobile/home-projects/{id}/stages/{n}/ai-reviews",
            "/api/mobile/home-projects/{id}/sections/{sid}/slots",
        ],
    }


@router.post("/register")
def mobile_register(
    body: RegisterRequest,
    db: Annotated[Session, Depends(get_db)],
):
    """Crea una cuenta nueva y la guarda en la base de datos."""
    result = register_endpoint(body, db)
    return {
        "ok": True,
        "access_token": result.access_token,
        "token_type": result.token_type,
        "user": result.user,
        "subscription": result.subscription,
    }


@router.post("/login")
def mobile_login(
    body: LoginRequest,
    db: Annotated[Session, Depends(get_db)],
):
    """Inicia sesión y devuelve JWT para la app móvil."""
    result = login_endpoint(body, db)
    return {
        "ok": True,
        "access_token": result.access_token,
        "token_type": result.token_type,
        "user": result.user,
        "subscription": result.subscription,
    }


@router.get("/me")
def mobile_me(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Devuelve el perfil del usuario autenticado para la app móvil."""
    return {
        "ok": True,
        "user": _user_out(user),
        "subscription": subscription_payload(db, user),
    }


@router.patch("/me")
def mobile_patch_me(
    body: UpdateProfileRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Actualiza el nombre del perfil."""
    result = patch_me_endpoint(body, user, db)
    return {"ok": True, "user": result.get("user")}


@router.post("/analyze")
async def mobile_analyze(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    file: UploadFile = File(...),
    auto_calibrate: str = Form("1"),
    ppm: float = Form(0.0),
    conf: float = Form(0.0),
    weights: str = Form(""),
    message: str = Form(""),
    chat_id: str = Form(""),
):
    """Sube un plano desde la app móvil y devuelve el resultado de análisis."""
    return await analyze_endpoint(
        user=user,
        db=db,
        file=file,
        auto_calibrate=auto_calibrate,
        ppm=ppm,
        conf=conf,
        weights=weights,
        message=message,
        chat_id=chat_id,
    )
