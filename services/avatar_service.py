"""Subida y almacenamiento de fotos de perfil."""

from __future__ import annotations

import io
from pathlib import Path

from fastapi import HTTPException, UploadFile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
AVATAR_DIR = ROOT / "data" / "avatars"
ALLOWED_TYPES = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
MAX_BYTES = 3 * 1024 * 1024  # 3 MB
AVATAR_SIZE = 256


def ensure_avatar_dir() -> Path:
    AVATAR_DIR.mkdir(parents=True, exist_ok=True)
    return AVATAR_DIR


def avatar_public_url(user_id: int) -> str:
    return f"/media/avatars/{user_id}.jpg"


def avatar_path(user_id: int) -> Path:
    return AVATAR_DIR / f"{user_id}.jpg"


async def save_user_avatar(user_id: int, upload: UploadFile) -> str:
    content_type = (upload.content_type or "").lower().strip()
    if content_type not in ALLOWED_TYPES:
        raise HTTPException(400, "Formato no válido. Usa JPG, PNG o WEBP.")

    raw = await upload.read()
    if not raw:
        raise HTTPException(400, "Archivo vacío")
    if len(raw) > MAX_BYTES:
        raise HTTPException(400, "La imagen supera 3 MB")

    try:
        img = Image.open(io.BytesIO(raw))
        img = img.convert("RGB")
    except Exception as exc:
        raise HTTPException(400, "No se pudo leer la imagen") from exc

    # Recorte centrado cuadrado + resize
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    img = img.resize((AVATAR_SIZE, AVATAR_SIZE), Image.Resampling.LANCZOS)

    ensure_avatar_dir()
    out = avatar_path(user_id)
    img.save(out, format="JPEG", quality=88, optimize=True)
    return avatar_public_url(user_id)


def delete_user_avatar(user_id: int) -> None:
    path = avatar_path(user_id)
    if path.is_file():
        path.unlink()
