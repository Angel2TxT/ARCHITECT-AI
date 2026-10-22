"""
Servicio OCR y Detección de Cotas Métricas para Calibración Exacta.

Extrae textos numéricos de cotas (ej: 3.50m, 2.80, NPT +0.15) tanto de
PDFs vectoriales (vía PyMuPDF) como de imágenes rasterizadas (vía EasyOCR / OpenCV),
asociando los textos con líneas de cota para derivar la escala exacta (PPM: px/m).
"""

from __future__ import annotations

import re
import statistics
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import cv2
import numpy as np

# Patrones de cotas arquitectónicas típicas
# Coincide con valores de 0.40m a 45.00m
_COTA_REGEX = re.compile(
    r"(?<![\d\.])([0-4]?\d\.\d{1,2})\s*(?:m|mts|metros)?(?![a-zA-Z\d\.])",
    re.IGNORECASE,
)
_NPT_REGEX = re.compile(
    r"NPT\s*([\+\-]\d{1,2}\.\d{1,2})",
    re.IGNORECASE,
)


@dataclass
class DimensionReading:
    raw_text: str
    value_m: float
    bbox_xyxy: tuple[float, float, float, float]
    line_length_px: float
    calculated_ppm: float
    confidence: float

    def to_dict(self) -> dict[str, Any]:
        return {
            "raw_text": self.raw_text,
            "value_m": round(self.value_m, 2),
            "bbox_xyxy": [round(v, 1) for v in self.bbox_xyxy],
            "line_length_px": round(self.line_length_px, 1),
            "calculated_ppm": round(self.calculated_ppm, 1),
            "confidence": round(self.confidence, 3),
        }


@dataclass
class OcrCalibrationResult:
    success: bool
    suggested_ppm: float | None = None
    confidence: float = 0.0
    readings: list[DimensionReading] = field(default_factory=list)
    method_used: str = "none"
    summary_note: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "success": self.success,
            "suggested_ppm": round(self.suggested_ppm, 1) if self.suggested_ppm else None,
            "confidence": round(self.confidence, 3),
            "readings_count": len(self.readings),
            "readings": [r.to_dict() for r in self.readings],
            "method_used": self.method_used,
            "summary_note": self.summary_note,
        }


_EASYOCR_READER = None


def _get_easyocr_reader():
    global _EASYOCR_READER
    if _EASYOCR_READER is None:
        try:
            import easyocr
            import torch
            use_gpu = torch.cuda.is_available()
            # Cargar detector ligero para inglés/español con aceleración GPU si disponible
            _EASYOCR_READER = easyocr.Reader(["es", "en"], gpu=use_gpu, verbose=False)
        except Exception:
            _EASYOCR_READER = False
    return _EASYOCR_READER if _EASYOCR_READER is not False else None


def _find_cota_line_near_text(
    gray_img: np.ndarray,
    text_bbox: tuple[float, float, float, float],
    margin: int = 70,
) -> float | None:
    """
    Busca una línea de cota paralela cercana al recuadro del texto detectado.
    Devuelve la longitud en píxeles del tramo más representativo.
    """
    h_img, w_img = gray_img.shape[:2]
    x1, y1, x2, y2 = [int(v) for v in text_bbox]

    rx1 = max(0, x1 - margin)
    ry1 = max(0, y1 - margin)
    rx2 = min(w_img, x2 + margin)
    ry2 = min(h_img, y2 + margin)

    roi = gray_img[ry1:ry2, rx1:rx2]
    if roi.size == 0 or roi.shape[0] < 10 or roi.shape[1] < 10:
        return None

    # Detectar bordes de trazo fino típicos de cotas
    edges = cv2.Canny(roi, 50, 150, apertureSize=3)
    lines = cv2.HoughLinesP(
        edges,
        rho=1,
        theta=np.pi / 180,
        threshold=25,
        minLineLength=30,
        maxLineGap=12,
    )

    if lines is None:
        return None

    lengths = []
    for line in lines:
        coords = line.reshape(-1)
        if len(coords) < 4:
            continue
        lx1, ly1, lx2, ly2 = coords[:4]
        dx = float(lx2 - lx1)
        dy = float(ly2 - ly1)
        is_horiz = abs(dx) > abs(dy) * 2.5
        is_vert = abs(dy) > abs(dx) * 2.5

        if is_horiz or is_vert:
            # Coordenadas globales absolutas
            gx1 = int(lx1 + rx1)
            gy1 = int(ly1 + ry1)
            gx2 = int(lx2 + rx1)
            gy2 = int(ly2 + ry1)

            # Rastrear la extensión total continua de la línea de cota en la imagen completa
            full_len = _trace_full_line_length(gray_img, gx1, gy1, gx2, gy2, is_horiz)
            lengths.append(full_len)

    if lengths:
        return float(max(lengths))

    return None


def _trace_full_line_length(
    gray_img: np.ndarray,
    gx1: int,
    gy1: int,
    gx2: int,
    gy2: int,
    is_horizontal: bool,
    threshold: int = 180,
) -> float:
    """Rastrea la longitud continua de una línea de cota a lo largo de la imagen."""
    h, w = gray_img.shape[:2]
    if is_horizontal:
        y = int(np.clip((gy1 + gy2) // 2, 0, h - 1))
        mid_x = int(np.clip((gx1 + gx2) // 2, 0, w - 1))

        # Rastrear a la izquierda
        left_x = mid_x
        while left_x > 0 and gray_img[y, left_x] < threshold:
            left_x -= 1

        # Rastrear a la derecha
        right_x = mid_x
        while right_x < w - 1 and gray_img[y, right_x] < threshold:
            right_x += 1

        traced = float(right_x - left_x)
        return traced if traced >= 30 else float(np.hypot(gx2 - gx1, gy2 - gy1))
    else:
        x = int(np.clip((gx1 + gx2) // 2, 0, w - 1))
        mid_y = int(np.clip((gy1 + gy2) // 2, 0, h - 1))

        top_y = mid_y
        while top_y > 0 and gray_img[top_y, x] < threshold:
            top_y -= 1

        bot_y = mid_y
        while bot_y < h - 1 and gray_img[bot_y, x] < threshold:
            bot_y += 1

        traced = float(bot_y - top_y)
        return traced if traced >= 30 else float(np.hypot(gx2 - gx1, gy2 - gy1))



def extract_dimensions_from_pdf(pdf_path: str | Path) -> list[tuple[str, float, tuple[float, float, float, float]]]:
    """
    Extrae cotas vectoriales directas de un PDF utilizando PyMuPDF (fitz).
    Devuelve lista de (raw_text, value_m, bbox_xyxy).
    """
    results = []
    try:
        import fitz
        doc = fitz.open(str(pdf_path))
        if len(doc) == 0:
            return []

        page = doc[0]
        words = page.get_text("words")  # (x0, y0, x1, y1, word, block_no, line_no, word_no)

        for w in words:
            text = str(w[4]).strip()
            match = _COTA_REGEX.search(text)
            if match:
                try:
                    val = float(match.group(1))
                    # Filtrar valores lógicos de cotas arquitectónicas (entre 0.60 m y 25.0 m)
                    if 0.60 <= val <= 25.0:
                        bbox = (float(w[0]), float(w[1]), float(w[2]), float(w[3]))
                        results.append((text, val, bbox))
                except ValueError:
                    pass
    except Exception:
        pass

    return results


def calibrate_scale_from_ocr(
    image: np.ndarray | str | Path,
    pdf_path: str | Path | None = None,
) -> OcrCalibrationResult:
    """
    Ejecuta calibración métrica automática mediante OCR de cotas.
    Prioriza PyMuPDF si existe PDF fuente; de lo contrario utiliza EasyOCR en la imagen.
    """
    readings: list[DimensionReading] = []

    # Cargar imagen en escala de grises para procesamiento morfológico
    if isinstance(image, (str, Path)):
        img = cv2.imread(str(image))
    else:
        img = image

    if img is None:
        return OcrCalibrationResult(success=False, summary_note="Imagen inválida para OCR")

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if len(img.shape) == 3 else img

    method = "easyocr"

    # Intento 1: Texto vectorial desde PDF si está disponible
    if pdf_path and Path(pdf_path).is_file():
        pdf_dims = extract_dimensions_from_pdf(pdf_path)
        if pdf_dims:
            method = "pymupdf_vector"
            for raw_text, val_m, bbox in pdf_dims:
                line_len = _find_cota_line_near_text(gray, bbox)
                if line_len and line_len > 25:
                    calc_ppm = line_len / val_m
                    if 25.0 <= calc_ppm <= 450.0:
                        readings.append(
                            DimensionReading(
                                raw_text=raw_text,
                                value_m=val_m,
                                bbox_xyxy=bbox,
                                line_length_px=line_len,
                                calculated_ppm=calc_ppm,
                                confidence=0.90,
                            )
                        )

    # Intento 2: EasyOCR en imagen si no hubo suficientes lecturas vectoriales
    if len(readings) < 2:
        reader = _get_easyocr_reader()
        if reader is not None:
            method = "easyocr_raster"
            try:
                # Optimización de rendimiento: Escalar imagen a max 1800px si es muy grande
                # para agilizar la inferencia OCR sin perder precisión en cotas
                h_orig, w_orig = gray.shape[:2]
                max_dim = max(h_orig, w_orig)
                scale = 1.0
                gray_for_ocr = gray
                if max_dim > 1800:
                    scale = 1800.0 / float(max_dim)
                    gray_for_ocr = cv2.resize(gray, (int(w_orig * scale), int(h_orig * scale)), interpolation=cv2.INTER_AREA)

                ocr_results = reader.readtext(gray_for_ocr, detail=1, paragraph=False)
                for bbox_coords, text, conf in ocr_results:
                    if conf < 0.40:
                        continue
                    # Reescalar coordenadas si se redujo la imagen
                    if scale != 1.0:
                        inv_scale = 1.0 / scale
                        bbox_coords = [[p[0] * inv_scale, p[1] * inv_scale] for p in bbox_coords]
                    match = _COTA_REGEX.search(str(text))
                    if match:
                        try:
                            val_m = float(match.group(1))
                            if 0.60 <= val_m <= 25.0:
                                # Convertir 4 esquinas a bbox [x1, y1, x2, y2]
                                xs = [p[0] for p in bbox_coords]
                                ys = [p[1] for p in bbox_coords]
                                bbox = (float(min(xs)), float(min(ys)), float(max(xs)), float(max(ys)))

                                line_len = _find_cota_line_near_text(gray, bbox)
                                if line_len and line_len > 25:
                                    calc_ppm = line_len / val_m
                                    if 25.0 <= calc_ppm <= 450.0:
                                        readings.append(
                                            DimensionReading(
                                                raw_text=text,
                                                value_m=val_m,
                                                bbox_xyxy=bbox,
                                                line_length_px=line_len,
                                                calculated_ppm=calc_ppm,
                                                confidence=float(conf),
                                            )
                                        )
                        except ValueError:
                            pass
            except Exception:
                pass

    if not readings:
        return OcrCalibrationResult(
            success=False,
            method_used=method,
            summary_note="No se identificaron cotas legibles con líneas asociadas",
        )

    # Filtrar outliers mediante mediana y desviación
    ppms = [r.calculated_ppm for r in readings]
    med_ppm = float(statistics.median(ppms))

    # Conservar lecturas cercanas a la mediana (dentro del 25% de dispersión)
    consistent_readings = [r for r in readings if abs(r.calculated_ppm - med_ppm) / med_ppm <= 0.25]

    if not consistent_readings:
        final_ppm = med_ppm
        final_conf = 0.50
    else:
        final_ppm = float(statistics.mean(r.calculated_ppm for r in consistent_readings))
        final_conf = min(0.95, 0.65 + (len(consistent_readings) * 0.08))

    return OcrCalibrationResult(
        success=True,
        suggested_ppm=final_ppm,
        confidence=final_conf,
        readings=consistent_readings or readings,
        method_used=method,
        summary_note=(
            f"Escala calculada por cotas ({method}): {final_ppm:.1f} px/m "
            f"con {len(consistent_readings or readings)} mediciones consistentes."
        ),
    )
