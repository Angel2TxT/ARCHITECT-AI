"""
Calibración automática de escala (px/m) y confianza YOLO por plano.

Usa todas las clases detectables: puertas, ventanas, habitaciones y circulación.
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass

from rules.engine import Detection
from rules.norms import CHIAPAS_RULES

DOOR_REF_WIDTH_M = CHIAPAS_RULES.door.min_width_m
WINDOW_REF_WIDTH_M = CHIAPAS_RULES.window.min_width_m
ROOM_REF_SIDE_M = CHIAPAS_RULES.room.min_dimension_m
CORRIDOR_REF_M = CHIAPAS_RULES.circulation.corridor_min_width_m

PPM_MIN = 25.0
PPM_MAX = 450.0
CONF_MIN = 0.08
CONF_MAX = 0.55


@dataclass
class AutoCalibration:
    pixels_per_meter: float
    confidence: float
    ppm_note: str
    conf_note: str
    scout_detections: int

    @property
    def summary(self) -> str:
        return (
            f"Escala automática: {self.pixels_per_meter:.0f} px/m "
            f"({self.ppm_note}). Confianza: {self.confidence:.2f} ({self.conf_note})."
        )


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _ppm_from_doors(detections: list[Detection]) -> tuple[float | None, str]:
    doors = [
        d
        for d in detections
        if d.class_name == "door"
        and d.confidence >= 0.12
        and 18 <= d.width_px <= 280
    ]
    widths = [d.width_px for d in doors]
    if len(widths) >= 2:
        med = statistics.median(widths)
        return _clamp(med / DOOR_REF_WIDTH_M, PPM_MIN, PPM_MAX), f"{len(widths)} puertas"
    if len(widths) == 1:
        return _clamp(widths[0] / DOOR_REF_WIDTH_M, PPM_MIN, PPM_MAX), "1 puerta"
    return None, ""


def _ppm_from_windows(detections: list[Detection]) -> tuple[float | None, str]:
    wins = [
        d
        for d in detections
        if d.class_name == "window"
        and d.confidence >= 0.12
        and 12 <= d.width_px <= 200
    ]
    if len(wins) < 2:
        return None, ""
    med = statistics.median(d.width_px for d in wins)
    return _clamp(med / WINDOW_REF_WIDTH_M, PPM_MIN, PPM_MAX), f"{len(wins)} ventanas"


def _ppm_from_rooms(detections: list[Detection]) -> tuple[float | None, str]:
    rooms = [d for d in detections if d.class_name == "room" and d.confidence >= 0.15]
    if not rooms:
        return None, ""
    sides = []
    for d in rooms:
        side = min(d.width_px, d.height_px)
        if side > 80:
            sides.append(side)
    if not sides:
        return None, ""
    med = statistics.median(sides)
    return _clamp(med / ROOM_REF_SIDE_M, PPM_MIN, PPM_MAX), f"{len(sides)} recintos"


def _ppm_from_corridors(detections: list[Detection]) -> tuple[float | None, str]:
    rooms = [d for d in detections if d.class_name == "room" and d.confidence >= 0.12]
    for d in rooms:
        short = min(d.width_px, d.height_px)
        long = max(d.width_px, d.height_px)
        if long / max(short, 1) >= 3.2 and 40 < short < 220:
            return _clamp(short / CORRIDOR_REF_M, PPM_MIN, PPM_MAX), "circulación"
    return None, ""


def estimate_pixels_per_meter(
    detections: list[Detection],
    image_width_px: int,
    image_height_px: int = 0,
) -> tuple[float, str]:
    estimates: list[tuple[float, str, int]] = []

    ppm, note = _ppm_from_doors(detections)
    if ppm is not None:
        estimates.append((ppm, f"puertas ({note})", 4))
    ppm, note = _ppm_from_windows(detections)
    if ppm is not None:
        estimates.append((ppm, f"ventanas ({note})", 3))
    ppm, note = _ppm_from_rooms(detections)
    if ppm is not None:
        estimates.append((ppm, f"recintos ({note})", 3))
    ppm, note = _ppm_from_corridors(detections)
    if ppm is not None:
        estimates.append((ppm, note, 2))

    if estimates:
        estimates.sort(key=lambda x: -x[2])
        values = [e[0] for e in estimates]
        ppm = statistics.median(values)
        parts = [e[1] for e in estimates[:3]]
        return ppm, " · ".join(parts)

    span = max(image_width_px, image_height_px) or image_width_px
    if span > 100:
        ppm = _clamp(span / 14.0, PPM_MIN, PPM_MAX)
        return ppm, "ancho del plano (~14 m estimados)"

    return 100.0, "valor por defecto"


def estimate_confidence(detections: list[Detection], *, is_demo: bool = False) -> tuple[float, str]:
    n = len(detections)
    classes = {d.class_name for d in detections}

    if n == 0:
        return (0.12 if is_demo else 0.10), "sin detecciones: umbral bajo"

    if n > 220:
        return _clamp(0.42, CONF_MIN, CONF_MAX), f"muchas detecciones ({n}): filtrar ruido"

    if n > 120:
        return _clamp(0.32, CONF_MIN, CONF_MAX), f"detecciones altas ({n})"

    if n > 60:
        return _clamp(0.26, CONF_MIN, CONF_MAX), "cantidad moderada-alta"

    if len(classes) >= 3 and n >= 12:
        return _clamp(0.22, CONF_MIN, CONF_MAX), "plano con varios elementos"

    if n < 8:
        return _clamp(0.12, CONF_MIN, CONF_MAX), "pocas detecciones: sensibilidad alta"

    return _clamp(0.18, CONF_MIN, CONF_MAX), "equilibrio general"


def calibrate_from_scout(
    scout_detections: list[Detection],
    image_width_px: int,
    image_height_px: int = 0,
    *,
    is_demo: bool = False,
    manual_ppm: float | None = None,
    manual_conf: float | None = None,
) -> AutoCalibration:
    if manual_ppm and manual_ppm > 0:
        ppm = _clamp(manual_ppm, PPM_MIN, PPM_MAX)
        ppm_note = "ajuste manual"
    else:
        ppm, ppm_note = estimate_pixels_per_meter(
            scout_detections, image_width_px, image_height_px
        )

    if manual_conf and manual_conf > 0:
        conf = _clamp(manual_conf, CONF_MIN, CONF_MAX)
        conf_note = "ajuste manual"
    else:
        conf, conf_note = estimate_confidence(scout_detections, is_demo=is_demo)

    return AutoCalibration(
        pixels_per_meter=ppm,
        confidence=conf,
        ppm_note=ppm_note,
        conf_note=conf_note,
        scout_detections=len(scout_detections),
    )
