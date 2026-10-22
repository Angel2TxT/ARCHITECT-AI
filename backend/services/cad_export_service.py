"""
Servicio de exportación a formato CAD estándar (DXF R2010) con ezdxf.
Organiza los elementos arquitectónicos detectados en capas estándar:
- MUROS (Color 7 / Lineweight 0.50mm)
- PUERTAS (Color 30 / Lineweight 0.25mm con arco de abatimiento)
- VENTANAS (Color 4 Cyan / Lineweight 0.25mm)
- RECINTOS (Color 140 / Etiquetas de texto y área en m²)
- ESCALERAS (Color 8 Gris / Huellas de peldaños)
"""

from __future__ import annotations

import io
import math
from typing import Any

import ezdxf
from ezdxf.enums import TextEntityAlignment


def export_detections_to_dxf(
    detections: list[dict | Any],
    pixels_per_meter: float = 100.0,
    project_title: str = "ARCHITECT - Exportación CAD",
) -> bytes:
    """
    Convierte una lista de detecciones en un archivo vectorial DXF (bytes).
    Convierte píxeles a metros y traslada el origen para que (0,0) esté abajo a la izquierda.
    """
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()

    # Definición de capas profesionales
    doc.layers.add("MUROS", color=7)
    doc.layers.add("PUERTAS", color=30)
    doc.layers.add("VENTANAS", color=4)
    doc.layers.add("RECINTOS", color=140)
    doc.layers.add("ESCALERAS", color=8)
    doc.layers.add("TEXTO_INFO", color=2)

    ppm = pixels_per_meter if pixels_per_meter > 0 else 100.0
    scale = 1.0 / ppm

    # Determinar altura máxima para invertir Y
    max_y_px = 0.0
    for d in detections:
        bbox = _get_bbox(d)
        if bbox:
            max_y_px = max(max_y_px, bbox[3])

    if max_y_px <= 0:
        max_y_px = 1000.0

    def to_cad(x: float, y: float) -> tuple[float, float]:
        # X normal, Y invertida (origen CAD abajo-izquierda)
        return round(x * scale, 3), round((max_y_px - y) * scale, 3)

    for d in detections:
        cls_name = _get_class(d)
        bbox = _get_bbox(d)
        if not bbox:
            continue

        x1, y1, x2, y2 = bbox
        cx1, cy1 = to_cad(x1, y1)  # cy1 es arriba en px -> mayor en CAD
        cx2, cy2 = to_cad(x2, y2)  # cy2 es abajo en px -> menor en CAD

        min_cx = min(cx1, cx2)
        max_cx = max(cx1, cx2)
        min_cy = min(cy1, cy2)
        max_cy = max(cy1, cy2)

        w = max_cx - min_cx
        h = max_cy - min_cy

        # 1. MUROS
        if cls_name == "wall":
            poly_pts = _get_polygon(d)
            if poly_pts and len(poly_pts) >= 3:
                cad_pts = [to_cad(px, py) for px, py in poly_pts]
                msp.add_lwpolyline(cad_pts, close=True, dxfattribs={"layer": "MUROS"})
            else:
                rect_pts = [
                    (min_cx, min_cy),
                    (max_cx, min_cy),
                    (max_cx, max_cy),
                    (min_cx, max_cy),
                ]
                msp.add_lwpolyline(rect_pts, close=True, dxfattribs={"layer": "MUROS"})

        # 2. PUERTAS (Vano + arco de abatimiento)
        elif cls_name in ("door", "front_door"):
            # Rectángulo marco
            rect_pts = [
                (min_cx, min_cy),
                (max_cx, min_cy),
                (max_cx, max_cy),
                (min_cx, max_cy),
            ]
            msp.add_lwpolyline(rect_pts, close=True, dxfattribs={"layer": "PUERTAS"})

            # Arco de abatimiento
            radius = max(w, h)
            if radius > 0.2:
                msp.add_arc(
                    center=(min_cx, min_cy),
                    radius=radius,
                    start_angle=0,
                    end_angle=90,
                    dxfattribs={"layer": "PUERTAS"},
                )

        # 3. VENTANAS
        elif cls_name == "window":
            rect_pts = [
                (min_cx, min_cy),
                (max_cx, min_cy),
                (max_cx, max_cy),
                (min_cx, max_cy),
            ]
            msp.add_lwpolyline(rect_pts, close=True, dxfattribs={"layer": "VENTANAS"})
            # Línea central de vidrio
            if w >= h:
                mid_y = (min_cy + max_cy) / 2
                msp.add_line((min_cx, mid_y), (max_cx, mid_y), dxfattribs={"layer": "VENTANAS"})
            else:
                mid_x = (min_cx + max_cx) / 2
                msp.add_line((mid_x, min_cy), (mid_x, max_cy), dxfattribs={"layer": "VENTANAS"})

        # 4. RECINTOS (Etiquetas con nombre y área)
        elif cls_name in ("room", "bedroom", "living", "bathroom", "kitchen", "parking"):
            area_m2 = round(w * h, 2)
            poly_pts = _get_polygon(d)
            if poly_pts and len(poly_pts) >= 3:
                cad_pts = [to_cad(px, py) for px, py in poly_pts]
                msp.add_lwpolyline(cad_pts, close=True, dxfattribs={"layer": "RECINTOS"})

            label = cls_name.upper()
            if area_m2 >= 0.5:
                label += f"\n{area_m2} m²"
            center_x = (min_cx + max_cx) / 2
            center_y = (min_cy + max_cy) / 2
            msp.add_text(
                label,
                height=0.25,
                dxfattribs={"layer": "RECINTOS"},
            ).set_placement((center_x, center_y), align=TextEntityAlignment.MIDDLE_CENTER)

        # 5. ESCALERAS
        elif cls_name == "stair":
            rect_pts = [
                (min_cx, min_cy),
                (max_cx, min_cy),
                (max_cx, max_cy),
                (min_cx, max_cy),
            ]
            msp.add_lwpolyline(rect_pts, close=True, dxfattribs={"layer": "ESCALERAS"})
            steps = 8
            if h >= w:
                step_h = h / steps
                for i in range(1, steps):
                    sy = min_cy + i * step_h
                    msp.add_line((min_cx, sy), (max_cx, sy), dxfattribs={"layer": "ESCALERAS"})
            else:
                step_w = w / steps
                for i in range(1, steps):
                    sx = min_cx + i * step_w
                    msp.add_line((sx, min_cy), (sx, max_cy), dxfattribs={"layer": "ESCALERAS"})

    # Pie de plano / Metadatos
    msp.add_text(
        f"{project_title} | Escala: 1:{int(ppm)}",
        height=0.35,
        dxfattribs={"layer": "TEXTO_INFO"},
    ).set_placement((0.0, -1.0), align=TextEntityAlignment.BOTTOM_LEFT)

    stream = io.StringIO()
    doc.write(stream)
    return stream.getvalue().encode("utf-8")


def _get_class(det: Any) -> str:
    if isinstance(det, dict):
        return str(det.get("class") or det.get("class_name") or "").lower()
    return getattr(det, "class_name", "").lower()


def _get_bbox(det: Any) -> tuple[float, float, float, float] | None:
    if isinstance(det, dict):
        b = det.get("bbox") or det.get("bbox_xyxy")
        if b and len(b) == 4:
            return (float(b[0]), float(b[1]), float(b[2]), float(b[3]))
        return None
    if hasattr(det, "bbox_xyxy"):
        return tuple(float(v) for v in det.bbox_xyxy)  # type: ignore[return-value]
    return None


def _get_polygon(det: Any) -> list[tuple[float, float]] | None:
    if isinstance(det, dict):
        p = det.get("polygon")
        if p and isinstance(p, list) and len(p) >= 3:
            return [(float(pt[0]), float(pt[1])) for pt in p]
        return None
    if hasattr(det, "polygon") and det.polygon and len(det.polygon) >= 3:
        return [(float(pt[0]), float(pt[1])) for pt in det.polygon]
    return None
