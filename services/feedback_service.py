"""Correcciones del usuario sobre detecciones YOLO (aprendizaje supervisado)."""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from core.correction_intent import (
    CLASS_LABELS_ES,
    CorrectionIntent,
    _ordinal_index,
    pick_detection_index,
)
from rules.engine import Detection

ROOT = Path(__file__).resolve().parents[1]
FEEDBACK_DIR = ROOT / "data" / "training" / "feedback"


def detection_to_dict(det: Detection, idx: int) -> dict:
    return {
        "idx": idx,
        "class": det.class_name,
        "label": CLASS_LABELS_ES.get(det.class_name, det.class_name),
        "confidence": round(det.confidence, 3),
        "width_px": round(det.width_px, 1),
        "height_px": round(det.height_px, 1),
        "bbox": [round(x, 1) for x in det.bbox_xyxy],
    }


def dict_to_detection(item: dict) -> Detection:
    bbox = item.get("bbox") or item.get("bbox_xyxy")
    if not bbox or len(bbox) != 4:
        x1 = float(item.get("x1", 0))
        y1 = float(item.get("y1", 0))
        w = float(item.get("width_px", 10))
        h = float(item.get("height_px", 10))
        bbox = [x1, y1, x1 + w, y1 + h]
    return Detection(
        class_name=item["class"],
        bbox_xyxy=tuple(float(v) for v in bbox),
        confidence=float(item.get("confidence", 1.0)),
    )


def normalize_stored_detections(raw: list | None) -> list[dict]:
    if not raw:
        return []
    out: list[dict] = []
    for i, item in enumerate(raw):
        if not isinstance(item, dict):
            continue
        row = dict(item)
        row.setdefault("idx", i)
        row.setdefault("class", row.get("class_name", "unknown"))
        row.setdefault("label", CLASS_LABELS_ES.get(row["class"], row["class"]))
        if "bbox" not in row and "bbox_xyxy" in row:
            row["bbox"] = list(row["bbox_xyxy"])
        out.append(row)
    return out


def apply_corrections(
    detections: list[dict], corrections: list[dict] | None
) -> list[dict]:
    """Devuelve lista de detecciones activas tras aplicar rechazos y re-etiquetas."""
    active = [dict(d) for d in detections]
    rejected: set[int] = set()
    relabels: dict[int, str] = {}

    for c in corrections or []:
        idx = c.get("detection_index")
        if idx is None:
            continue
        action = c.get("action", "reject")
        if action == "reject":
            rejected.add(int(idx))
        elif action == "relabel" and c.get("new_class"):
            relabels[int(idx)] = c["new_class"]

    result: list[dict] = []
    for i, d in enumerate(active):
        if i in rejected:
            continue
        row = dict(d)
        if i in relabels:
            row["class"] = relabels[i]
            row["label"] = CLASS_LABELS_ES.get(relabels[i], relabels[i])
        row["idx"] = len(result)
        result.append(row)
    return result


def build_correction_record(
    *,
    detection_index: int,
    action: str,
    from_class: str,
    new_class: str | None = None,
    note: str = "",
    source: str = "ui",
) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "detection_index": detection_index,
        "action": action,
        "from_class": from_class,
        "new_class": new_class,
        "note": (note or "")[:500],
        "source": source,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


def resolve_correction_from_intent(
    intent: CorrectionIntent,
    detections: list[dict],
) -> tuple[dict | None, str | None]:
    if not intent.is_correction:
        return None, None

    target = intent.target_class
    if not target:
        classes_present = {d.get("class") for d in detections}
        if "window" in classes_present and any(
            w in intent.raw_note.lower() for w in ("ventana", "muro", "pared")
        ):
            target = "window"
        else:
            return None, "Indica qué elemento corregir (ventana, puerta, muro…)."

    idx = intent.detection_index
    if idx is None:
        idx = pick_detection_index(
            detections,
            target,
            ordinal=_ordinal_from_intent(intent),
        )
    if idx is None:
        return None, f"No encontré una detección de tipo «{CLASS_LABELS_ES.get(target, target)}»."

    det = detections[idx] if 0 <= idx < len(detections) else None
    if not det:
        return None, "Índice de detección inválido."

    action = intent.action
    new_class = intent.new_class
    if action == "relabel" and not new_class:
        action = "reject"

    record = build_correction_record(
        detection_index=idx,
        action=action,
        from_class=det.get("class", target),
        new_class=new_class if action == "relabel" else None,
        note=intent.raw_note,
        source="chat",
    )
    return record, None


def _ordinal_from_intent(intent: CorrectionIntent) -> int | None:
    return _ordinal_index(intent.raw_note.lower())


def append_correction(existing: list | None, record: dict) -> list[dict]:
    rows = list(existing or [])
    dup = any(
        r.get("detection_index") == record.get("detection_index")
        and r.get("action") == record.get("action")
        and r.get("new_class") == record.get("new_class")
        for r in rows
    )
    if not dup:
        rows.append(record)
    return rows


def export_correction_for_training(
    user_id: int,
    analysis_id: int,
    record: dict,
    *,
    image_path: str | None = None,
) -> None:
    FEEDBACK_DIR.mkdir(parents=True, exist_ok=True)
    path = FEEDBACK_DIR / f"user_{user_id}.jsonl"
    payload = {
        "analysis_id": analysis_id,
        "image_path": image_path,
        **record,
    }
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def correction_ack_text(record: dict, remaining: list[dict]) -> str:
    from_class = record.get("from_class", "")
    label_from = CLASS_LABELS_ES.get(from_class, from_class)
    action = record.get("action", "reject")
    note = record.get("note", "")

    if action == "relabel":
        new_class = record.get("new_class", "")
        label_to = CLASS_LABELS_ES.get(new_class, new_class)
        msg = (
            f"Entendido: quité la etiqueta «{label_from}» y la marqué como «{label_to}» "
            f"en esa zona del plano."
        )
    else:
        msg = f"Entendido: eliminé la detección incorrecta de «{label_from}»."

    if note:
        msg += f"\nTu nota: «{note[:200]}»"

    msg += (
        "\n\nRevisé de nuevo las reglas con tus correcciones aplicadas. "
        "Esta corrección quedó guardada para mejorar futuros análisis."
    )
    n_win = sum(1 for d in remaining if d.get("class") == "window")
    n_wall = sum(1 for d in remaining if d.get("class") == "wall")
    if from_class in ("window", "wall") or record.get("new_class") in ("window", "wall"):
        msg += f"\nAhora en el plano: {n_win} ventana(s), {n_wall} muro(s) detectados."
    return msg
