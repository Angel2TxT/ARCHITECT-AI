"""
PASO 5: Detectar elementos en un plano nuevo.

Uso:
  python scripts/infer.py --image mi_plano.png --weights runs/detect/plano_elementos/weights/best.pt
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from ultralytics import YOLO


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--output", type=Path, default=Path("output"))
    args = parser.parse_args()

    if not args.image.exists():
        raise SystemExit(f"No existe la imagen: {args.image}")
    if not args.weights.exists():
        raise SystemExit(f"No existe el modelo: {args.weights}")

    model = YOLO(str(args.weights))
    results = model.predict(
        source=str(args.image),
        conf=args.conf,
        save=True,
        project=str(args.output),
        name="detecciones",
    )

    detections = []
    names = model.names
    for r in results:
        for box in r.boxes:
            cls_id = int(box.cls[0])
            xyxy = box.xyxy[0].tolist()
            conf = float(box.conf[0])
            detections.append(
                {
                    "class": names[cls_id],
                    "confidence": round(conf, 4),
                    "bbox_xyxy": [round(v, 2) for v in xyxy],
                }
            )

    out_json = args.output / "detecciones" / f"{args.image.stem}_detections.json"
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(
        json.dumps(detections, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    print(f"Detecciones guardadas: {out_json}")
    for d in detections:
        print(f"  - {d['class']} ({d['confidence']})")


if __name__ == "__main__":
    main()
