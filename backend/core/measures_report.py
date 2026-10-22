"""
Tabla de medidas estimadas a partir de detecciones YOLO y escala (px/m).
"""

from __future__ import annotations

from collections import defaultdict

from rules.engine import Detection

CLASS_LABELS_ES: dict[str, str] = {
    "door": "Puerta",
    "window": "Ventana",
    "wall": "Muro",
    "room": "Recinto",
}

TYPE_ORDER = ("Puerta", "Ventana", "Muro", "Recinto")


def _dims_m(det: Detection, ppm: float) -> tuple[float, float, float]:
    w_m = det.width_px / ppm
    h_m = det.height_px / ppm
    return w_m, h_m, w_m * h_m


def build_measures_report(
    detections: list[Detection],
    pixels_per_meter: float,
    *,
    auto_calibrated: bool = False,
) -> dict:
    ppm = max(float(pixels_per_meter), 1.0)
    items: list[dict] = []

    sorted_dets = sorted(
        detections,
        key=lambda d: (
            TYPE_ORDER.index(CLASS_LABELS_ES.get(d.class_name, d.class_name))
            if CLASS_LABELS_ES.get(d.class_name) in TYPE_ORDER
            else 99,
            -d.area_px,
        ),
    )

    for num, det in enumerate(sorted_dets, start=1):
        w_m, h_m, area_m2 = _dims_m(det, ppm)
        tipo = CLASS_LABELS_ES.get(det.class_name, det.class_name.capitalize())
        items.append(
            {
                "num": num,
                "tipo": tipo,
                "ancho_m": round(w_m, 2),
                "largo_m": round(h_m, 2),
                "area_m2": round(area_m2, 2),
                "confianza_pct": round(det.confidence * 100),
            }
        )

    if not items:
        text = (
            "No detecté puertas, ventanas, muros ni recintos en este plano.\n"
            "Prueba con una sola planta por imagen, buena resolución y calibración automática activada."
        )
        return {
            "items": [],
            "text": text,
            "pixels_per_meter": round(ppm, 1),
            "total": 0,
        }

    by_type: dict[str, list[dict]] = defaultdict(list)
    for it in items:
        by_type[it["tipo"]].append(it)

    lines = [
        f"Medidas estimadas en tu plano ({len(items)} elementos detectados):",
        "",
    ]
    for tipo in TYPE_ORDER:
        group = by_type.get(tipo, [])
        if not group:
            continue
        plural = tipo + ("s" if tipo != "Muro" else "s")
        lines.append(f"{plural} ({len(group)}):")
        for it in group:
            lines.append(
                f"  {it['num']}. Ancho {it['ancho_m']} m × largo {it['largo_m']} m "
                f"(superficie {it['area_m2']} m², confianza {it['confianza_pct']} %)"
            )
        lines.append("")

    escala = f"Escala usada: {ppm:.0f} píxeles por metro"
    if auto_calibrated:
        escala += " (calibración automática)"
    lines.append(escala)
    lines.append(
        "Nota: medidas aproximadas por visión artificial; no sustituyen las cotas "
        "del dibujo ni un levantamiento en obra."
    )

    return {
        "items": items,
        "text": "\n".join(lines).strip(),
        "pixels_per_meter": round(ppm, 1),
        "total": len(items),
    }
