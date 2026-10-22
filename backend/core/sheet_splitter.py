"""
Pre-procesador de láminas arquitectónicas: Aislamiento inteligente de planta.

Detecta y enmascara cajetines (pie de plano), notas marginales y bordes
técnicos para alimentar a YOLO y OCR con la región pura de la planta arquitectónica,
eliminando falsos positivos en textos, firmas y simbología marginal.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import cv2
import numpy as np


@dataclass
class SheetRegions:
    is_split: bool
    main_plan_bbox: tuple[int, int, int, int]  # (x1, y1, x2, y2)
    title_block_bbox: tuple[int, int, int, int] | None = None
    marginal_regions: list[tuple[int, int, int, int]] = field(default_factory=list)
    confidence: float = 0.0
    note: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "is_split": self.is_split,
            "main_plan_bbox": list(self.main_plan_bbox),
            "title_block_bbox": list(self.title_block_bbox) if self.title_block_bbox else None,
            "marginal_regions_count": len(self.marginal_regions),
            "confidence": round(self.confidence, 3),
            "note": self.note,
        }


def detect_sheet_layout(image_bgr: np.ndarray) -> SheetRegions:
    """
    Analiza la composición espacial de la lámina para identificar el cajetín
    (típicamente en la franja inferior o lateral derecha) y la región central
    de la planta arquitectónica.
    """
    h, w = image_bgr.shape[:2]

    # Para imágenes pequeñas (< 1000px) asumimos planta recortada directa
    if max(w, h) < 1000:
        return SheetRegions(
            is_split=False,
            main_plan_bbox=(0, 0, w, h),
            confidence=0.95,
            note="Planta previamente aislada / imagen compacta",
        )

    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY) if len(image_bgr.shape) == 3 else image_bgr

    # Umbralizado adaptativo para capturar líneas y textos
    thresh = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 25, 10
    )

    # 1. Búsqueda de cajetín (Title Block):
    # En convenciones mexicanas / latinoamericanas, el cajetín se ubica:
    # A) Esquina inferior derecha (último 30% ancho, último 25% alto)
    # B) Toda la franja lateral derecha (último 18% ancho)
    # C) Toda la franja inferior (último 15% alto)
    title_bbox: tuple[int, int, int, int] | None = None

    # Zona candidata: esquina inferior derecha
    cx1, cy1 = int(w * 0.70), int(h * 0.75)
    corner_roi = thresh[cy1:h, cx1:w]
    density_corner = float(np.count_nonzero(corner_roi)) / max(corner_roi.size, 1)

    # Zona candidata: tira lateral derecha
    rx1, ry1 = int(w * 0.82), 0
    right_roi = thresh[ry1:h, rx1:w]
    density_right = float(np.count_nonzero(right_roi)) / max(right_roi.size, 1)

    # Zona candidata: tira inferior
    bx1, by1 = 0, int(h * 0.85)
    bottom_roi = thresh[by1:h, bx1:w]
    density_bottom = float(np.count_nonzero(bottom_roi)) / max(bottom_roi.size, 1)

    # El cajetín tiene alta concentración de líneas y texto (> 4% de píxeles encendidos)
    main_x1, main_y1 = int(w * 0.02), int(h * 0.02)
    main_x2, main_y2 = int(w * 0.98), int(h * 0.98)
    note = "Lámina completa sin cajetín dominante"

    if density_corner > 0.05 and density_corner > density_right * 1.2:
        title_bbox = (cx1, cy1, w, h)
        # La planta ocupa el resto superior e izquierdo
        main_x2 = max(main_x1 + 200, cx1 - 10)
        main_y2 = max(main_y1 + 200, cy1 - 10)
        note = "Cajetín detectado en esquina inferior derecha"
    elif density_right > 0.06:
        title_bbox = (rx1, 0, w, h)
        main_x2 = max(main_x1 + 200, rx1 - 15)
        note = "Franja de cajetín detectada en margen lateral derecho"
    elif density_bottom > 0.06:
        title_bbox = (0, by1, w, h)
        main_y2 = max(main_y1 + 200, by1 - 15)
        note = "Franja de cajetín detectada en margen inferior"

    is_split = title_bbox is not None

    return SheetRegions(
        is_split=is_split,
        main_plan_bbox=(main_x1, main_y1, main_x2, main_y2),
        title_block_bbox=title_bbox,
        confidence=0.85 if is_split else 0.60,
        note=note,
    )


def extract_isolated_plan(
    image_bgr: np.ndarray,
) -> tuple[np.ndarray, tuple[int, int], SheetRegions]:
    """
    Devuelve la imagen recortada de la planta, el desplazamiento (offset_x, offset_y)
    respecto a la lámina original y los metadatos de las regiones.
    """
    regions = detect_sheet_layout(image_bgr)
    x1, y1, x2, y2 = regions.main_plan_bbox

    if not regions.is_split:
        return image_bgr, (0, 0), regions

    cropped = image_bgr[y1:y2, x1:x2]
    # Si por alguna anomalía el recorte es vacío, devolver original
    if cropped.size == 0 or cropped.shape[0] < 50 or cropped.shape[1] < 50:
        return image_bgr, (0, 0), regions

    return cropped, (x1, y1), regions
