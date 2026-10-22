"""Prueba gratuita sin iniciar sesión (límite por visitante)."""

from __future__ import annotations

import os
import uuid
from datetime import datetime

from fastapi import HTTPException, Request, Response
from sqlalchemy.orm import Session

from db.models import GuestTrial

GUEST_COOKIE = "plano_guest_id"
MAX_ANALYSES = int(os.getenv("GUEST_TRIAL_MAX_ANALYSES", "1"))
MAX_ASKS = int(os.getenv("GUEST_TRIAL_MAX_ASKS", "1"))
MAX_FILE_MB = int(os.getenv("GUEST_TRIAL_MAX_FILE_MB", "15"))


def trial_exhausted_message() -> str:
    return (
        "Tu prueba gratuita terminó. Inicia sesión o crea una cuenta "
        "para seguir usando la IA sin límites de prueba."
    )


def raise_trial_exhausted() -> None:
    raise HTTPException(
        status_code=402,
        detail={
            "code": "trial_exhausted",
            "message": trial_exhausted_message(),
            "login_url": "/login",
        },
    )


def get_guest_id(request: Request, response: Response) -> str:
    gid = request.cookies.get(GUEST_COOKIE)
    if not gid or len(gid) < 8:
        gid = str(uuid.uuid4())
        response.set_cookie(
            GUEST_COOKIE,
            gid,
            max_age=365 * 24 * 3600,
            httponly=True,
            samesite="lax",
            path="/",
        )
    return gid


def get_or_create_guest(db: Session, guest_id: str) -> GuestTrial:
    row = db.query(GuestTrial).filter(GuestTrial.id == guest_id).first()
    if row:
        row.last_seen_at = datetime.utcnow()
        return row
    row = GuestTrial(id=guest_id)
    db.add(row)
    db.flush()
    return row


def guest_trial_payload(row: GuestTrial) -> dict:
    analyses_left = max(0, MAX_ANALYSES - row.analyses_count)
    asks_left = max(0, MAX_ASKS - row.asks_count)
    return {
        "guest": True,
        "analyses_used": row.analyses_count,
        "analyses_limit": MAX_ANALYSES,
        "analyses_remaining": analyses_left,
        "asks_used": row.asks_count,
        "asks_limit": MAX_ASKS,
        "asks_remaining": asks_left,
        "trial_available": analyses_left > 0 or asks_left > 0,
        "trial_exhausted": analyses_left <= 0 and asks_left <= 0,
        "max_file_mb": MAX_FILE_MB,
    }


def assert_guest_can_analyze(db: Session, guest_id: str, file_size_bytes: int) -> GuestTrial:
    row = get_or_create_guest(db, guest_id)
    if row.analyses_count >= MAX_ANALYSES:
        raise_trial_exhausted()
    max_bytes = MAX_FILE_MB * 1024 * 1024
    if file_size_bytes > max_bytes:
        raise HTTPException(
            413,
            f"En la prueba gratuita el archivo máximo es {MAX_FILE_MB} MB.",
        )
    return row


def assert_guest_can_ask(db: Session, guest_id: str) -> GuestTrial:
    row = get_or_create_guest(db, guest_id)
    if row.asks_count >= MAX_ASKS:
        raise_trial_exhausted()
    return row


def record_guest_analysis(db: Session, guest_id: str) -> dict:
    row = get_or_create_guest(db, guest_id)
    row.analyses_count += 1
    db.commit()
    db.refresh(row)
    return guest_trial_payload(row)


def record_guest_ask(db: Session, guest_id: str) -> dict:
    row = get_or_create_guest(db, guest_id)
    row.asks_count += 1
    db.commit()
    db.refresh(row)
    return guest_trial_payload(row)
