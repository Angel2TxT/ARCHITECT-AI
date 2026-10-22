"""
Entrena un modelo DEMO pequeño para probar la interfaz sin descargar 5 GB.

Uso:
  python scripts/train_demo.py

Genera: runs/detect/demo_planos/weights/best.pt
"""

from __future__ import annotations

import random
from pathlib import Path

import numpy as np
import yaml
from PIL import Image, ImageDraw
from ultralytics import YOLO

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "datasets" / "demo_yolo"
NAMES = ["door", "window", "wall", "room"]


def _box_to_yolo(x1, y1, x2, y2, w: int, h: int, cls: int) -> str:
    cx = (x1 + x2) / 2 / w
    cy = (y1 + y2) / 2 / h
    bw = (x2 - x1) / w
    bh = (y2 - y1) / h
    return f"{cls} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}"


def create_sample(idx: int, split: str) -> None:
    w, h = 640, 640
    img = Image.new("RGB", (w, h), (250, 250, 245))
    draw = ImageDraw.Draw(img)
    lines = []
    rng = random.Random(idx)

    # muro exterior
    margin = 40
    draw.rectangle([margin, margin, w - margin, h - margin], outline=(30, 30, 30), width=4)
    lines.append(_box_to_yolo(margin, margin, w - margin, h - margin, w, h, 2))

    # habitación
    rx1, ry1 = margin + 20, margin + 20
    rx2, ry2 = w // 2 - 10, h - margin - 20
    draw.rectangle([rx1, ry1, rx2, ry2], outline=(120, 120, 120), width=2)
    lines.append(_box_to_yolo(rx1, ry1, rx2, ry2, w, h, 3))

    # puerta
    dw = rng.randint(40, 70)
    dx1 = w // 2 - dw // 2
    dy1 = h - margin - 5
    draw.rectangle([dx1, dy1 - 8, dx1 + dw, dy1], fill=(139, 90, 43))
    lines.append(_box_to_yolo(dx1, dy1 - 25, dx1 + dw, dy1, w, h, 0))

    # ventana
    wx1, wy1 = w - margin - 80, margin + 60
    draw.rectangle([wx1, wy1, wx1 + 55, wy1 + 40], outline=(70, 130, 200), width=3)
    lines.append(_box_to_yolo(wx1, wy1, wx1 + 55, wy1 + 40, w, h, 1))

    img_dir = OUT / "images" / split
    lbl_dir = OUT / "labels" / split
    img_dir.mkdir(parents=True, exist_ok=True)
    lbl_dir.mkdir(parents=True, exist_ok=True)

    stem = f"demo_{idx:03d}"
    img.save(img_dir / f"{stem}.png")
    (lbl_dir / f"{stem}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_dataset(n_train: int = 40, n_val: int = 8) -> Path:
    if OUT.exists():
        import shutil
        shutil.rmtree(OUT)
    for i in range(n_train):
        create_sample(i, "train")
    for i in range(n_val):
        create_sample(100 + i, "val")

    cfg = {
        "path": str(OUT.resolve()),
        "train": "images/train",
        "val": "images/val",
        "nc": 4,
        "names": {i: n for i, n in enumerate(NAMES)},
    }
    cfg_path = OUT / "data.yaml"
    cfg_path.write_text(yaml.dump(cfg, allow_unicode=True), encoding="utf-8")
    return cfg_path


def main() -> None:
    print("Generando planos sintéticos de demo...")
    cfg = build_dataset()

    print("Entrenando YOLOv8n (demo, ~5-15 min en CPU)...")
    model = YOLO("yolov8n.pt")
    results = model.train(
        data=str(cfg),
        epochs=30,
        imgsz=640,
        batch=4,
        device="cpu",
        project=str(ROOT / "runs" / "detect"),
        name="demo_planos",
        patience=8,
        verbose=True,
    )

    best = Path(results.save_dir) / "weights" / "best.pt"
    print()
    print("=" * 50)
    print("Modelo demo listo:")
    print(f"  {best}")
    print()
    print("En la app -> Ajustes -> pega esa ruta")
    print("O reinicia la app (detecta best.pt automático)")
    print("=" * 50)


if __name__ == "__main__":
    main()
