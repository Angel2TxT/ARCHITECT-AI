"""Envío de push con Firebase Cloud Messaging (FCM)."""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session

from db.models import UserDeviceToken

logger = logging.getLogger("architect.fcm")

_ROOT = Path(__file__).resolve().parents[1]
_app = None
_init_attempted = False


def _credentials_path() -> Path | None:
    raw = (os.getenv("FIREBASE_CREDENTIALS_PATH") or "").strip()
    if not raw:
        return None
    path = Path(raw)
    if not path.is_absolute():
        path = _ROOT / path
    return path if path.is_file() else None


def fcm_configured() -> bool:
    path = _credentials_path()
    return path is not None


def _get_app():
    global _app, _init_attempted
    if _app is not None:
        return _app
    if _init_attempted:
        return None
    _init_attempted = True

    path = _credentials_path()
    if path is None:
        logger.info("FCM desactivado: falta FIREBASE_CREDENTIALS_PATH o el archivo")
        return None

    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            cred = credentials.Certificate(str(path))
            _app = firebase_admin.initialize_app(cred)
        else:
            _app = firebase_admin.get_app()
        return _app
    except Exception as exc:
        logger.warning("No se pudo inicializar Firebase Admin: %s", exc)
        return None


def register_device_token(
    db: Session,
    user_id: int,
    token: str,
    *,
    platform: str = "android",
) -> UserDeviceToken:
    token = (token or "").strip()
    if not token:
        raise ValueError("token vacío")
    platform = (platform or "android").strip().lower()[:16] or "android"

    row = (
        db.query(UserDeviceToken)
        .filter(UserDeviceToken.token == token)
        .first()
    )
    if row:
        row.user_id = user_id
        row.platform = platform
    else:
        row = UserDeviceToken(user_id=user_id, token=token, platform=platform)
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def unregister_device_token(db: Session, user_id: int, token: str) -> bool:
    token = (token or "").strip()
    if not token:
        return False
    row = (
        db.query(UserDeviceToken)
        .filter(
            UserDeviceToken.user_id == user_id,
            UserDeviceToken.token == token,
        )
        .first()
    )
    if not row:
        return False
    db.delete(row)
    db.commit()
    return True


def _delete_invalid_tokens(db: Session, tokens: list[str]) -> None:
    if not tokens:
        return
    (
        db.query(UserDeviceToken)
        .filter(UserDeviceToken.token.in_(tokens))
        .delete(synchronize_session=False)
    )
    db.commit()


def send_push_to_user(
    db: Session,
    user_id: int,
    *,
    title: str,
    body: str = "",
    data: dict[str, Any] | None = None,
) -> int:
    """Envía push a todos los dispositivos del usuario. No lanza excepciones."""
    if not _get_app():
        return 0

    rows = (
        db.query(UserDeviceToken)
        .filter(UserDeviceToken.user_id == user_id)
        .all()
    )
    if not rows:
        return 0

    try:
        from firebase_admin import messaging
    except Exception as exc:
        logger.warning("firebase_admin.messaging no disponible: %s", exc)
        return 0

    payload = {str(k): str(v) for k, v in (data or {}).items() if v is not None}
    sent = 0
    invalid: list[str] = []

    for row in rows:
        message = messaging.Message(
            notification=messaging.Notification(
                title=(title or "ARCHITECT")[:160],
                body=(body or "")[:500],
            ),
            data=payload,
            token=row.token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="architect_default",
                ),
            ),
        )
        try:
            messaging.send(message)
            sent += 1
        except messaging.UnregisteredError:
            invalid.append(row.token)
        except Exception as exc:
            err = str(exc).lower()
            if "not-found" in err or "unregistered" in err or "invalid" in err:
                invalid.append(row.token)
            else:
                logger.warning("FCM error user=%s: %s", user_id, exc)

    if invalid:
        try:
            _delete_invalid_tokens(db, invalid)
        except Exception as exc:
            logger.warning("No se pudieron limpiar tokens FCM: %s", exc)

    return sent
