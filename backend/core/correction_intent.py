"""Detecta cuando el usuario corrige una detección del plano."""

from __future__ import annotations

import re
from dataclasses import dataclass

CLASS_ALIASES: dict[str, str] = {
    "ventana": "window",
    "ventanas": "window",
    "puerta": "door",
    "puertas": "door",
    "muro": "wall",
    "muros": "wall",
    "pared": "wall",
    "paredes": "wall",
    "recinto": "room",
    "recintos": "room",
    "habitacion": "room",
    "habitación": "room",
    "habitaciones": "room",
}

CLASS_LABELS_ES: dict[str, str] = {
    "window": "Ventana",
    "door": "Puerta",
    "wall": "Muro",
    "room": "Recinto",
}

CORRECTION_MARKERS = (
    "no es",
    "no hay",
    "no era",
    "incorrecto",
    "mal detect",
    "equivocad",
    "falso positivo",
    "correg",
    "corrige",
    "marcaste mal",
    "detectaste mal",
    "en realidad",
    "deberia ser",
    "debería ser",
    "ahi hay",
    "ahí hay",
    "es un muro",
    "es muro",
    "aprende",
)


@dataclass(frozen=True)
class CorrectionIntent:
    is_correction: bool
    target_class: str | None = None
    new_class: str | None = None
    action: str = "reject"  # reject | relabel
    detection_index: int | None = None
    raw_note: str = ""


def _normalize(text: str) -> str:
    t = (text or "").lower()
    t = t.replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u")
    return t


def _classes_in_text(t: str) -> list[str]:
    found: list[str] = []
    for alias, canonical in CLASS_ALIASES.items():
        if re.search(rf"\b{re.escape(alias)}\b", t):
            if canonical not in found:
                found.append(canonical)
    return found


def _ordinal_index(t: str) -> int | None:
    m = re.search(r"\b(primer|primera|1er|1ra|segund|2d[oa]|tercer|3er|3ra|cuart)\b", t)
    if not m:
        m = re.search(r"\bventana\s+(\d+)\b", t)
        if m:
            return max(0, int(m.group(1)) - 1)
        return None
    word = m.group(1)
    if word.startswith("primer") or word.startswith("1"):
        return 0
    if word.startswith("segund") or word.startswith("2"):
        return 1
    if word.startswith("tercer") or word.startswith("3"):
        return 2
    if word.startswith("cuart"):
        return 3
    return None


def pick_detection_index(
    detections: list[dict],
    target_class: str,
    *,
    ordinal: int | None = None,
) -> int | None:
    indices = [i for i, d in enumerate(detections) if d.get("class") == target_class]
    if not indices:
        return None
    if ordinal is not None and ordinal < len(indices):
        return indices[ordinal]
    if len(indices) == 1:
        return indices[0]
    best = max(indices, key=lambda i: float(detections[i].get("confidence") or 0))
    return best


def parse_correction_message(text: str) -> CorrectionIntent:
    raw = (text or "").strip()
    t = _normalize(raw)
    if len(t) < 8:
        return CorrectionIntent(is_correction=False)

    if not any(m in t for m in CORRECTION_MARKERS):
        return CorrectionIntent(is_correction=False)

    classes = _classes_in_text(t)
    target = classes[0] if classes else None
    new_class = classes[1] if len(classes) > 1 else None

    if target and not new_class:
        if "muro" in t or "pared" in t:
            new_class = "wall"
        elif "puerta" in t:
            new_class = "door"
        elif "recinto" in t or "habitacion" in t:
            new_class = "room"

    action = "relabel" if new_class and new_class != target else "reject"
    if action == "relabel" and not new_class:
        action = "reject"

    ordinal = _ordinal_index(t)
    return CorrectionIntent(
        is_correction=True,
        target_class=target,
        new_class=new_class if action == "relabel" else None,
        action=action,
        detection_index=None,
        raw_note=raw[:500],
    )
