"""
Convierte ResPlan (CC BY 4.0) a dataset YOLO raster + labels.

ResPlan: ~17 000 plantas residenciales vectoriales con puertas, ventanas,
muros, baños, cocinas, etc. Licencia abierta — apto para entrenamiento.

Uso:
  python scripts/resplan_to_yolo.py
  python scripts/resplan_to_yolo.py --max-samples 3000 --imgsz 1024
"""

from __future__ import annotations

import argparse
import pickle
import random
from pathlib import Path

from PIL import Image, ImageDraw
from tqdm import tqdm

# Clases ampliadas (alineadas con pipeline / holistic tipado)
CLASS_TO_ID = {
    "door": 0,
    "window": 1,
    "wall": 2,
    "room": 3,
    "stair": 4,
    "bathroom": 5,
    "kitchen": 6,
    "parking": 7,
}

# Campos ResPlan -> clase YOLO
FIELD_TO_CLASS = {
    "door": "door",
    "front_door": "door",
    "window": "window",
    "wall": "wall",
    "stair": "stair",
    "bathroom": "bathroom",
    "kitchen": "kitchen",
    "parking": "parking",
    "bedroom": "room",
    "living": "room",
    "storage": "room",
    "balcony": "room",
    "veranda": "room",
    "garden": "room",
}

DRAW_ORDER = [
    "garden",
    "land",
    "parking",
    "balcony",
    "veranda",
    "living",
    "bedroom",
    "storage",
    "kitchen",
    "bathroom",
    "inner",
    "wall",
    "stair",
    "window",
    "door",
    "front_door",
]

FILL = {
    "garden": (220, 235, 210),
    "land": (235, 235, 230),
    "parking": (210, 210, 220),
    "balcony": (225, 230, 240),
    "veranda": (225, 230, 240),
    "living": (245, 240, 230),
    "bedroom": (235, 245, 250),
    "storage": (240, 240, 240),
    "kitchen": (250, 235, 220),
    "bathroom": (220, 240, 250),
    "inner": (250, 250, 248),
    "wall": (40, 40, 40),
    "stair": (180, 160, 140),
    "window": (120, 180, 220),
    "door": (160, 90, 60),
    "front_door": (140, 70, 50),
}


def _iter_polygons(geom):
    if geom is None or geom.is_empty:
        return
    if geom.geom_type == "Polygon":
        yield geom
    elif geom.geom_type == "MultiPolygon":
        for g in geom.geoms:
            if not g.is_empty:
                yield g


def _union_bounds(plan: dict) -> tuple[float, float, float, float] | None:
    xs: list[float] = []
    ys: list[float] = []
    for key in FIELD_TO_CLASS:
        geom = plan.get(key)
        if geom is None or geom.is_empty:
            continue
        minx, miny, maxx, maxy = geom.bounds
        xs.extend([minx, maxx])
        ys.extend([miny, maxy])
    if not xs:
        return None
    pad = 2.0
    return min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad


def _world_to_px(
    x: float,
    y: float,
    bounds: tuple[float, float, float, float],
    scale: float,
    img_h: int,
) -> tuple[float, float]:
    minx, miny, _, _ = bounds
    # Y invertida (imagen: origen arriba)
    px = (x - minx) * scale
    py = img_h - (y - miny) * scale
    return px, py


def _poly_pixels(poly, bounds, scale, img_h) -> list[tuple[float, float]]:
    coords = list(poly.exterior.coords)
    return [_world_to_px(x, y, bounds, scale, img_h) for x, y in coords]


def render_plan(plan: dict, imgsz: int) -> tuple[Image.Image, list[tuple[int, float, float, float, float]]]:
    """Devuelve (imagen RGB, labels YOLO cx cy w h normalizados)."""
    bounds = _union_bounds(plan)
    if bounds is None:
        raise ValueError("plan sin geometría útil")

    minx, miny, maxx, maxy = bounds
    bw = max(maxx - minx, 1e-6)
    bh = max(maxy - miny, 1e-6)
    scale = (imgsz - 4) / max(bw, bh)
    img_w = max(32, int(bw * scale) + 4)
    img_h = max(32, int(bh * scale) + 4)

    img = Image.new("RGB", (img_w, img_h), (255, 255, 255))
    draw = ImageDraw.Draw(img)

    for key in DRAW_ORDER:
        geom = plan.get(key)
        if geom is None or geom.is_empty:
            continue
        color = FILL.get(key, (200, 200, 200))
        for poly in _iter_polygons(geom):
            pts = _poly_pixels(poly, bounds, scale, img_h)
            if len(pts) < 3:
                continue
            draw.polygon(pts, fill=color, outline=(60, 60, 60) if key == "wall" else None)

    labels: list[tuple[int, float, float, float, float]] = []
    for key, cls_name in FIELD_TO_CLASS.items():
        geom = plan.get(key)
        if geom is None or geom.is_empty:
            continue
        cls_id = CLASS_TO_ID[cls_name]
        for poly in _iter_polygons(geom):
            minx_g, miny_g, maxx_g, maxy_g = poly.bounds
            x1, y2 = _world_to_px(minx_g, miny_g, bounds, scale, img_h)
            x2, y1 = _world_to_px(maxx_g, maxy_g, bounds, scale, img_h)
            # y1 es arriba (menor), y2 abajo tras inversión
            xa, xb = sorted([x1, x2])
            ya, yb = sorted([y1, y2])
            # Filtrar fragmentos minúsculos (ruido)
            if (xb - xa) < 2 or (yb - ya) < 2:
                continue
            # Paredes muy finas: ampliar un poco para visibilidad YOLO
            if cls_name == "wall" and (xb - xa) < 4:
                mid = (xa + xb) / 2
                xa, xb = mid - 2, mid + 2
            if cls_name == "wall" and (yb - ya) < 4:
                mid = (ya + yb) / 2
                ya, yb = mid - 2, mid + 2
            cx = ((xa + xb) / 2) / img_w
            cy = ((ya + yb) / 2) / img_h
            nw = (xb - xa) / img_w
            nh = (yb - ya) / img_h
            cx = max(0.0, min(1.0, cx))
            cy = max(0.0, min(1.0, cy))
            nw = max(0.001, min(1.0, nw))
            nh = max(0.001, min(1.0, nh))
            # Evitar rooms que cubren casi toda la imagen (inner-like)
            if cls_name == "room" and nw * nh > 0.55:
                continue
            labels.append((cls_id, cx, cy, nw, nh))

    return img, labels


def main() -> None:
    parser = argparse.ArgumentParser(description="ResPlan → YOLO")
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("data/raw/resplan/ResPlan.pkl"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("datasets/resplan_yolo"),
    )
    parser.add_argument("--imgsz", type=int, default=1024)
    parser.add_argument("--max-samples", type=int, default=4000)
    parser.add_argument("--val-ratio", type=float, default=0.12)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    pkl_path = (root / args.input).resolve() if not args.input.is_absolute() else args.input
    out_root = (root / args.output).resolve() if not args.output.is_absolute() else args.output

    if not pkl_path.is_file():
        raise SystemExit(
            f"No está {pkl_path}. Descarga ResPlan:\n"
            "  https://github.com/m-agour/ResPlan/releases/download/1.0.0/ResPlan.zip"
        )

    print(f"Cargando {pkl_path}…")
    with pkl_path.open("rb") as f:
        plans = pickle.load(f)
    if not isinstance(plans, list):
        raise SystemExit("Formato ResPlan inesperado (se esperaba list).")

    random.seed(args.seed)
    indices = list(range(len(plans)))
    random.shuffle(indices)
    if args.max_samples and args.max_samples < len(indices):
        indices = indices[: args.max_samples]

    n_val = max(1, int(len(indices) * args.val_ratio))
    val_idx = set(indices[:n_val])
    train_idx = [i for i in indices if i not in val_idx]

    for split in ("train", "val"):
        (out_root / "images" / split).mkdir(parents=True, exist_ok=True)
        (out_root / "labels" / split).mkdir(parents=True, exist_ok=True)

    def export(idxs: list[int], split: str) -> int:
        ok = 0
        for i in tqdm(idxs, desc=f"ResPlan→YOLO [{split}]"):
            plan = plans[i]
            try:
                img, labels = render_plan(plan, args.imgsz)
            except Exception:
                continue
            if not labels:
                continue
            stem = f"resplan_{plan.get('id', i)}"
            img_path = out_root / "images" / split / f"{stem}.png"
            lbl_path = out_root / "labels" / split / f"{stem}.txt"
            img.save(img_path, format="PNG", optimize=True)
            lbl_path.write_text(
                "\n".join(f"{c} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}" for c, cx, cy, w, h in labels),
                encoding="utf-8",
            )
            ok += 1
        return ok

    n_train = export(train_idx, "train")
    n_val_ok = export(list(val_idx), "val")

    yaml_path = root / "config" / "data_resplan.yaml"
    yaml_path.write_text(
        "\n".join(
            [
                f"# Generado por resplan_to_yolo.py — CC BY 4.0 (ResPlan)",
                f"path: {out_root.as_posix()}",
                "train: images/train",
                "val: images/val",
                f"nc: {len(CLASS_TO_ID)}",
                "names:",
                *[f"  {i}: {name}" for name, i in sorted(CLASS_TO_ID.items(), key=lambda x: x[1])],
                "",
            ]
        ),
        encoding="utf-8",
    )

    print(f"Listo: train={n_train} val={n_val_ok}")
    print(f"Dataset: {out_root}")
    print(f"Config:  {yaml_path}")
    print(
        "Entrena:\n"
        f"  python scripts/train.py --data config/data_resplan.yaml "
        f"--model yolov8s.pt --epochs 60 --imgsz 640 --batch 4 --device cpu "
        f"--name plano_resplan_s"
    )


if __name__ == "__main__":
    main()
