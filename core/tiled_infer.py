"""
Inferencia YOLO por tiles + fusión NMS.

Planos grandes a imgsz fijo pierden vanos y muros finos; recortar en ventanas
solapadas y reunir cajas mejora mucho el recall sin reentrenar.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from rules.engine import Detection

# Si el lado mayor supera esto, se activa tiling.
TILE_TRIGGER_PX = 1400
TILE_SIZE = 1280
TILE_OVERLAP = 256
IOU_MERGE = 0.45


@dataclass
class InferSettings:
    imgsz: int
    use_tiles: bool
    tile_size: int
    overlap: int
    note: str


def choose_infer_settings(width: int, height: int) -> InferSettings:
    side = max(int(width), int(height))
    if side >= 2400:
        imgsz = 1280
    elif side >= 1400:
        imgsz = 960
    else:
        imgsz = 640

    use_tiles = side >= TILE_TRIGGER_PX
    if use_tiles:
        note = f"tiles {TILE_SIZE}px overlap {TILE_OVERLAP} · imgsz {imgsz}"
    else:
        note = f"imagen completa · imgsz {imgsz}"
    return InferSettings(
        imgsz=imgsz,
        use_tiles=use_tiles,
        tile_size=TILE_SIZE,
        overlap=TILE_OVERLAP,
        note=note,
    )


def _iou(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    if inter <= 0:
        return 0.0
    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def merge_detections_nms(
    detections: list[Detection],
    *,
    iou_thresh: float = IOU_MERGE,
) -> list[Detection]:
    """NMS por clase: conserva la caja de mayor confianza."""
    by_cls: dict[str, list[Detection]] = {}
    for d in detections:
        by_cls.setdefault(d.class_name, []).append(d)

    kept: list[Detection] = []
    for group in by_cls.values():
        group = sorted(group, key=lambda x: x.confidence, reverse=True)
        selected: list[Detection] = []
        for cand in group:
            if all(_iou(cand.bbox_xyxy, s.bbox_xyxy) < iou_thresh for s in selected):
                selected.append(cand)
        kept.extend(selected)
    return kept


def iter_tile_windows(
    width: int,
    height: int,
    tile_size: int = TILE_SIZE,
    overlap: int = TILE_OVERLAP,
) -> list[tuple[int, int, int, int]]:
    """Ventanas (x1, y1, x2, y2) cubriendo la imagen."""
    if width <= tile_size and height <= tile_size:
        return [(0, 0, width, height)]

    step = max(tile_size - overlap, tile_size // 2)
    windows: list[tuple[int, int, int, int]] = []
    y = 0
    while True:
        y2 = min(y + tile_size, height)
        y1 = max(0, y2 - tile_size) if y2 == height else y
        x = 0
        while True:
            x2 = min(x + tile_size, width)
            x1 = max(0, x2 - tile_size) if x2 == width else x
            windows.append((x1, y1, x2, y2))
            if x2 >= width:
                break
            x += step
        if y2 >= height:
            break
        y += step
    return windows


def predict_detections(
    model,
    image_bgr: np.ndarray,
    names: dict,
    conf: float,
    *,
    settings: InferSettings | None = None,
) -> tuple[list[Detection], InferSettings]:
    """
    Ejecuta YOLO a imagen completa o por tiles según tamaño.
    Devuelve detecciones en coordenadas de imagen completa.
    """
    h, w = image_bgr.shape[:2]
    settings = settings or choose_infer_settings(w, h)

    if not settings.use_tiles:
        results = model.predict(
            source=image_bgr,
            conf=conf,
            imgsz=settings.imgsz,
            verbose=False,
        )
        return _boxes_to_detections(results, names), settings

    all_dets: list[Detection] = []
    for x1, y1, x2, y2 in iter_tile_windows(w, h, settings.tile_size, settings.overlap):
        crop = image_bgr[y1:y2, x1:x2]
        if crop.size == 0:
            continue
        results = model.predict(
            source=crop,
            conf=conf,
            imgsz=settings.imgsz,
            verbose=False,
        )
        for det in _boxes_to_detections(results, names):
            bx1, by1, bx2, by2 = det.bbox_xyxy
            all_dets.append(
                Detection(
                    class_name=det.class_name,
                    bbox_xyxy=(bx1 + x1, by1 + y1, bx2 + x1, by2 + y1),
                    confidence=det.confidence,
                )
            )

    # Pase global a resolución reducida para capturar recintos grandes
    # que un tile pequeño fragmenta.
    scale = min(1.0, 1600 / max(w, h, 1))
    if scale < 0.99:
        small = cv2.resize(
            image_bgr,
            (max(1, int(w * scale)), max(1, int(h * scale))),
            interpolation=cv2.INTER_AREA,
        )
        results = model.predict(
            source=small,
            conf=max(conf, 0.12),
            imgsz=settings.imgsz,
            verbose=False,
        )
        inv = 1.0 / scale
        for det in _boxes_to_detections(results, names):
            if det.class_name not in ("room", "wall"):
                continue
            bx1, by1, bx2, by2 = det.bbox_xyxy
            all_dets.append(
                Detection(
                    class_name=det.class_name,
                    bbox_xyxy=(bx1 * inv, by1 * inv, bx2 * inv, by2 * inv),
                    confidence=det.confidence * 0.95,
                )
            )

    return merge_detections_nms(all_dets), settings


def _boxes_to_detections(results, names: dict) -> list[Detection]:
    detections: list[Detection] = []
    for r in results:
        if r.boxes is None:
            continue
        for box in r.boxes:
            cls_id = int(box.cls[0])
            name = names.get(cls_id, str(cls_id)) if isinstance(names, dict) else names[cls_id]
            detections.append(
                Detection(
                    class_name=str(name),
                    bbox_xyxy=tuple(float(v) for v in box.xyxy[0].tolist()),
                    confidence=float(box.conf[0]),
                )
            )
    return detections
