"""
Pipeline completo: detectar + validar reglas.

Uso:
  python scripts/validate_plano.py --image plano.png --weights best.pt --ppm 120
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from ultralytics import YOLO

from rules import DEFAULT_RULES, ValidationEngine
from rules.engine import Detection
from rules.norms import PlanRules


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument(
        "--ppm",
        type=float,
        default=100.0,
        help="Píxeles por metro (escala del plano)",
    )
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--output", type=Path, default=Path("output/validacion"))
    args = parser.parse_args()

    model = YOLO(str(args.weights))
    results = model.predict(source=str(args.image), conf=args.conf, verbose=False)

    detections: list[Detection] = []
    names = model.names
    for r in results:
        for box in r.boxes:
            cls_id = int(box.cls[0])
            detections.append(
                Detection(
                    class_name=names[cls_id],
                    bbox_xyxy=tuple(box.xyxy[0].tolist()),
                    confidence=float(box.conf[0]),
                )
            )

    rules = PlanRules(
        pixels_per_meter=args.ppm,
        door=DEFAULT_RULES.door,
        window=DEFAULT_RULES.window,
        room=DEFAULT_RULES.room,
    )
    engine = ValidationEngine(rules=rules)
    issues = engine.validate(detections)

    report = {
        "image": str(args.image),
        "pixels_per_meter": args.ppm,
        "detections_count": len(detections),
        "issues": [
            {
                "code": i.code,
                "message": i.message,
                "severity": i.severity,
                "class": i.related_class,
                "bbox_xyxy": i.bbox_xyxy,
            }
            for i in issues
        ],
    }

    args.output.mkdir(parents=True, exist_ok=True)
    out_path = args.output / f"{args.image.stem}_report.json"
    out_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print(f"Detecciones: {len(detections)}")
    print(f"Incidencias: {len(issues)}")
    for issue in issues:
        prefix = "ERROR" if issue.severity == "error" else "AVISO"
        print(f"  [{prefix}] {issue.code}: {issue.message}")
    print(f"\nInforme: {out_path}")


if __name__ == "__main__":
    main()
