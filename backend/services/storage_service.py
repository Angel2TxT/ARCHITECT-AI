"""Guarda planos originales y anotados en disco."""

from __future__ import annotations

import base64
import uuid
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
UPLOADS_ROOT = ROOT / "data" / "uploads"

ALLOWED_PROJECT_DOC_EXT = {
    ".pdf", ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff",
    ".dxf", ".dwg", ".doc", ".docx", ".xls", ".xlsx",
}
MAX_PROJECT_DOC_MB = 25


def project_doc_dir(user_id: int, project_id: str) -> Path:
    d = UPLOADS_ROOT / str(user_id) / "projects" / project_id
    d.mkdir(parents=True, exist_ok=True)
    return d


def save_project_document(
    user_id: int,
    project_id: str,
    doc_id: int,
    content: bytes,
    filename: str,
) -> Path:
    ext = Path(filename or "documento.bin").suffix.lower() or ".bin"
    if ext not in ALLOWED_PROJECT_DOC_EXT:
        raise ValueError(f"Extensión no permitida: {ext}")
    safe_name = Path(filename or "documento").name.replace("..", "_")
    dest = project_doc_dir(user_id, project_id) / f"{doc_id}_{safe_name}"
    dest.write_bytes(content)
    return dest


def analysis_dir(user_id: int, analysis_id: int) -> Path:
    d = UPLOADS_ROOT / str(user_id) / str(analysis_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def save_source_file(user_id: int, analysis_id: int, content: bytes, filename: str) -> Path:
    ext = Path(filename or "plano.png").suffix or ".png"
    dest = analysis_dir(user_id, analysis_id) / f"source{ext}"
    dest.write_bytes(content)
    return dest


def save_annotated_jpeg(user_id: int, analysis_id: int, image_b64: str) -> Path:
    raw = base64.b64decode(image_b64)
    dest = analysis_dir(user_id, analysis_id) / "annotated.jpg"
    dest.write_bytes(raw)
    return dest


IMAGE_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".bmp",
    ".tif",
    ".tiff",
}


def resolve_analysis_raster_path(source_path: str | Path) -> Path:
    """Ruta de imagen lista para YOLO a partir de un análisis guardado."""
    src = Path(source_path)
    base = src.parent
    converted = base / "converted.png"
    if converted.is_file():
        return converted
    if src.suffix.lower() in IMAGE_EXTENSIONS and src.is_file():
        return src
    raise FileNotFoundError(
        f"No hay imagen raster del análisis en {base}. Vuelve a adjuntar el plano."
    )


def save_annotated_from_rgb(user_id: int, analysis_id: int, rgb: np.ndarray) -> Path:
    dest = analysis_dir(user_id, analysis_id) / "annotated.jpg"
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    cv2.imwrite(str(dest), bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 88])
    return dest
