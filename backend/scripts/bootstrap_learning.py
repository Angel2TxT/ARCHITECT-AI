"""
Pipeline completo: ingestar manuales PDF y preparar imágenes para entrenamiento.

Uso:
  python scripts/bootstrap_learning.py
  python scripts/bootstrap_learning.py --input data/raw --dpi 150
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingestar PDF y preparar aprendizaje")
    parser.add_argument(
        "--input",
        type=Path,
        default=ROOT / "data" / "knowledge" / "raw",
    )
    parser.add_argument("--dpi", type=int, default=150)
    parser.add_argument(
        "--skip-neufert",
        action="store_true",
        help="Omitir Neufert (muy largo; normas ya en otros manuales)",
    )
    args = parser.parse_args()

    in_dir = (ROOT / args.input).resolve() if not args.input.is_absolute() else args.input
    raw_fallback = ROOT / "data" / "raw"
    if not list(in_dir.glob("*.pdf")) and list(raw_fallback.glob("*.pdf")):
        in_dir = raw_fallback
        dest = ROOT / "data" / "knowledge" / "raw"
        dest.mkdir(parents=True, exist_ok=True)
        for pdf in raw_fallback.glob("*.pdf"):
            target = dest / pdf.name
            if not target.exists():
                shutil.copy2(pdf, target)
        in_dir = dest
        print(f"PDF copiados a {dest}")

    pdfs = sorted(in_dir.glob("*.pdf"))
    if args.skip_neufert:
        pdfs = [p for p in pdfs if "neufert" not in p.name.lower()]
    if not pdfs:
        raise SystemExit(f"No hay PDF en {in_dir}")

    py = sys.executable
    print("=== 1/3 Ingesta conocimiento (texto + imágenes por página) ===")
    for pdf in pdfs:
        print(f"  • {pdf.name}")
    subprocess.run(
        [
            py,
            str(ROOT / "scripts" / "ingest_knowledge_docs.py"),
            "--input",
            str(in_dir),
            "--dpi",
            str(args.dpi),
        ],
        cwd=str(ROOT),
        check=True,
    )

    print("\n=== 2/3 Imágenes para etiquetado YOLO (planos/diagramas) ===")
    _export_training_candidates(ROOT)

    print("\n=== 3/3 Estado de la base de conocimiento ===")
    sys.path.insert(0, str(ROOT))
    from services.knowledge_service import invalidate_cache, knowledge_stats

    invalidate_cache()
    stats = knowledge_stats()
    print(json.dumps(stats, indent=2, ensure_ascii=False))
    print(
        "\nListo. Reinicia: python app.py\n"
        "El análisis citará tus manuales. Para YOLO: etiqueta PNG en "
        "data/training/to_label/images y ejecuta train.py"
    )


def _export_training_candidates(root: Path) -> None:
    processed = root / "data" / "knowledge" / "processed"
    out = root / "data" / "training" / "to_label" / "images"
    out.mkdir(parents=True, exist_ok=True)
    types = {"example_plan", "diagram", "mixed"}
    n = 0
    for manifest_path in processed.glob("*/manifest.json"):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        doc_id = manifest.get("id", manifest_path.parent.name)
        for page in manifest.get("pages", []):
            if page.get("page_type") not in types:
                continue
            src = manifest_path.parent / page.get("image_file", "")
            if not src.is_file():
                continue
            name = f"{doc_id}_p{page['page']:03d}.png"
            dest = out / name
            if not dest.exists():
                shutil.copy2(src, dest)
            n += 1
    print(f"  {n} imagen(es) copiadas a {out.relative_to(root)}")


if __name__ == "__main__":
    main()
