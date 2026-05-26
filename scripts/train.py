"""
PASO 4: Entrenar YOLOv8 sobre el dataset convertido.

Uso:
  python scripts/train.py
  python scripts/train.py --epochs 50 --model yolov8n.pt --device cpu
"""

from __future__ import annotations

import argparse
from pathlib import Path

from ultralytics import YOLO


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=Path("config/data.yaml"))
    parser.add_argument("--model", type=str, default="yolov8n.pt")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--device", type=str, default="0", help="0, cpu, o cuda")
    parser.add_argument("--project", type=str, default="runs/detect")
    parser.add_argument("--name", type=str, default="plano_elementos")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    data_yaml = (root / args.data).resolve()

    if not data_yaml.exists():
        raise SystemExit(
            f"Falta {data_yaml}. Primero ejecuta cubicasa_to_yolo.py"
        )

    model = YOLO(args.model)
    results = model.train(
        data=str(data_yaml),
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        project=str(root / args.project),
        name=args.name,
        patience=20,
        save=True,
        plots=True,
    )

    print("Entrenamiento finalizado.")
    print(f"Mejor peso: {results.save_dir / 'weights' / 'best.pt'}")


if __name__ == "__main__":
    main()
