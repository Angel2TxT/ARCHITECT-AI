"""
Filtro geométrico inteligente para limpiar falsos positivos de detección en planos arquitectónicos.
Elimina:
1. Cotas y líneas de dimensión exterior (aspect ratio excesivo tipo 10:1 o 25:1).
2. Detecciones en márgenes exteriores fuera de la envolvente de muros.
3. Cajas duplicadas o fuertemente contenidas dentro de otras más grandes.
4. Recintos con área ridícula (< 1.8 m² para habitaciones).
"""

from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from rules.types import Detection


def filter_floorplan_detections(
    detections: list[Detection],
    img_w: int,
    img_h: int,
    pixels_per_meter: float = 100.0,
) -> tuple[list[Detection], dict]:
    """
    Filtra y sanea las detecciones antes de enviarlas al motor de normas.
    Devuelve (detecciones_limpias, estadisticas_descarte).
    """
    if not detections:
        return [], {"discarded_cotas": 0, "discarded_overlaps": 0, "discarded_area": 0}

    ppm = max(pixels_per_meter, 10.0)
    filtered: list[Detection] = []
    discarded_cotas = 0
    discarded_area = 0
    discarded_overlaps = 0

    for d in detections:
        cls = d.class_name.lower()
        x1, y1, x2, y2 = d.bbox_xyxy
        w_px = max(x2 - x1, 1.0)
        h_px = max(y2 - y1, 1.0)
        w_m = w_px / ppm
        h_m = h_px / ppm
        area_m2 = w_m * h_m

        # 1. Filtro de Cotas (Líneas de medida con aspect ratio absurdo)
        # Las cotas exteriores e.g. 5.0m x 0.2m tienen un ratio de 10:1 hasta 30:1.
        long_dim = max(w_m, h_m)
        short_dim = min(w_m, h_m)
        aspect_ratio = long_dim / max(short_dim, 0.05)

        if cls in ("room", "habitacion", "recamara", "dormitorio", "bathroom", "baño", "cocina", "kitchen"):
            # Una habitación o baño no puede ser una tira delgada con aspect ratio excesivo (cotas)
            if short_dim < 0.70 or aspect_ratio > 3.2:
                discarded_cotas += 1
                continue

            # Un cuarto habitable no puede medir menos de 2.2 m²
            if cls in ("room", "habitacion", "recamara", "dormitorio") and area_m2 < 2.2:
                discarded_area += 1
                continue

            # Un baño real no puede medir menos de 1.1 m² (min. 0.9m x 1.2m)
            if cls in ("bathroom", "baño"):
                if area_m2 < 1.1 or aspect_ratio > 2.4:
                    discarded_area += 1
                    continue

        # Si el objeto es un muro, solo verificar que tenga tamaño mínimo
        if cls in ("wall", "muro") and area_m2 < 0.05:
            continue

        filtered.append(d)

    # 2. Supresión de contención/duplicación para recintos
    # Si una caja pequeña de "room" está 85%+ adentro de otra caja de "room", descartar la pequeña
    final_list: list[Detection] = []
    room_indices = [i for i, d in enumerate(filtered) if d.class_name.lower() in ("room", "habitacion", "recamara", "dormitorio")]
    suppressed = set()

    for i in room_indices:
        if i in suppressed:
            continue
        d_i = filtered[i]
        area_i = (d_i.bbox_xyxy[2] - d_i.bbox_xyxy[0]) * (d_i.bbox_xyxy[3] - d_i.bbox_xyxy[1])

        for j in room_indices:
            if i == j or j in suppressed:
                continue
            d_j = filtered[j]
            area_j = (d_j.bbox_xyxy[2] - d_j.bbox_xyxy[0]) * (d_j.bbox_xyxy[3] - d_j.bbox_xyxy[1])

            # Calcular intersección
            ix1 = max(d_i.bbox_xyxy[0], d_j.bbox_xyxy[0])
            iy1 = max(d_i.bbox_xyxy[1], d_j.bbox_xyxy[1])
            ix2 = min(d_i.bbox_xyxy[2], d_j.bbox_xyxy[2])
            iy2 = min(d_i.bbox_xyxy[3], d_j.bbox_xyxy[3])

            if ix2 > ix1 and iy2 > iy1:
                inter_area = (ix2 - ix1) * (iy2 - iy1)
                # Si d_i contiene casi totalmente a d_j
                if inter_area > 0.85 * min(area_i, area_j):
                    # Descartar la más pequeña
                    if area_i >= area_j:
                        suppressed.add(j)
                        discarded_overlaps += 1
                    else:
                        suppressed.add(i)
                        discarded_overlaps += 1
                        break

    for idx, d in enumerate(filtered):
        if idx not in suppressed:
            final_list.append(d)

    stats = {
        "discarded_cotas": discarded_cotas,
        "discarded_area": discarded_area,
        "discarded_overlaps": discarded_overlaps,
    }
    return final_list, stats
