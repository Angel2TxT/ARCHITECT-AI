"""
Ingesta documentos de construcción/arquitectura (PDF) con texto e imágenes.

Extrae por página:
- PNG (para revisar diagramas y ejemplos)
- TXT (texto normativo / instrucciones)
- manifest.json (índice del documento)

Uso:
  python scripts/ingest_knowledge_docs.py
  python scripts/ingest_knowledge_docs.py --input data/knowledge/raw --dpi 180
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IN = ROOT / "data" / "knowledge" / "raw"
DEFAULT_OUT = ROOT / "data" / "knowledge" / "processed"


def doc_id_from_path(path: Path) -> str:
    h = hashlib.md5(str(path.resolve()).encode()).hexdigest()[:10]
    safe = re.sub(r"[^\w\-]", "_", path.stem)[:40]
    return f"{safe}_{h}"


def classify_page(text: str, has_large_image: bool) -> str:
    """Tipos: regulation_text | diagram | example_plan | mixed | sparse"""
    t = text.lower()
    word_count = len(text.split())

    plan_hints = sum(
        1
        for w in (
            "planta",
            "plano",
            "escala",
            "sección",
            "seccion",
            "fachada",
            "corte",
            "eje",
            "norte",
        )
        if w in t
    )
    rule_hints = sum(
        1
        for w in (
            "artículo",
            "articulo",
            "mínimo",
            "minimo",
            "máximo",
            "maximo",
            "deberá",
            "debera",
            "norma",
            "reglamento",
            "metros",
            "m²",
        )
        if w in t
    )
    legend_hints = sum(
        1
        for w in ("simbología", "simbolo", "símbolo", "leyenda", "convenciones", "diagrama")
        if w in t
    )

    if word_count < 25 and has_large_image:
        return "diagram"
    if legend_hints >= 2 or ("símbolo" in t and has_large_image):
        return "diagram"
    if plan_hints >= 3 and has_large_image:
        return "example_plan"
    if rule_hints >= 3 and word_count >= 80:
        return "regulation_text"
    if word_count >= 50:
        return "mixed"
    return "sparse"


def ingest_pdf(path: Path, out_root: Path, dpi: int) -> Path:
    import fitz

    doc_id = doc_id_from_path(path)
    dest = out_root / doc_id
    pages_dir = dest / "pages"
    pages_dir.mkdir(parents=True, exist_ok=True)

    pdf = fitz.open(path)
    zoom = dpi / 72.0
    mat = fitz.Matrix(zoom, zoom)
    page_entries: list[dict] = []

    for i, page in enumerate(pdf):
        num = i + 1
        text = page.get_text("text").strip()
        pix = page.get_pixmap(matrix=mat, alpha=False)
        img_name = f"{num:03d}.png"
        txt_name = f"{num:03d}.txt"
        (pages_dir / img_name).write_bytes(pix.tobytes("png"))
        (pages_dir / txt_name).write_text(text, encoding="utf-8")

        # Heurística: página con poco texto y pixmap grande → diagrama/plano
        has_large_image = pix.width * pix.height > 400_000 and len(text) < 400
        page_type = classify_page(text, has_large_image)

        page_entries.append(
            {
                "page": num,
                "page_type": page_type,
                "image_file": f"pages/{img_name}",
                "text_file": f"pages/{txt_name}",
                "text_chars": len(text),
                "use_for": _suggest_use(page_type),
            }
        )

    pdf.close()

    manifest = {
        "id": doc_id,
        "title": path.stem,
        "source_file": path.name,
        "pages_count": len(page_entries),
        "pages": page_entries,
        "hint": (
            "diagram/example_plan → revisar imágenes para entrenar o leyenda; "
            "regulation_text → reglas en rules/norms.py y citas en análisis"
        ),
    }
    (dest / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return dest


def _suggest_use(page_type: str) -> str:
    return {
        "regulation_text": "normativa_y_citas",
        "diagram": "leyenda_y_referencia_visual",
        "example_plan": "entrenamiento_yolo_si_etiquetas",
        "mixed": "normativa_y_entrenamiento",
        "sparse": "revisar_imagen_manual",
    }.get(page_type, "revisar")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingestar manuales PDF de construcción")
    parser.add_argument("--input", type=Path, default=DEFAULT_IN)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--dpi", type=int, default=180)
    args = parser.parse_args()

    in_dir = (ROOT / args.input).resolve() if not args.input.is_absolute() else args.input
    out_dir = (ROOT / args.output).resolve() if not args.output.is_absolute() else args.output

    if not in_dir.is_dir():
        raise SystemExit(
            f"Crea {in_dir} y coloca ahí tus PDF (reglamentos, manuales, guías).\n"
            "Ver docs/CONOCIMIENTO_DOCUMENTOS.md"
        )

    pdfs = sorted(in_dir.rglob("*.pdf"))
    if not pdfs:
        raise SystemExit(f"No hay PDF en {in_dir}")

    try:
        from services.knowledge_service import invalidate_cache
    except ImportError:
        invalidate_cache = lambda: None

    for pdf in pdfs:
        try:
            dest = ingest_pdf(pdf, out_dir, args.dpi)
            print(f"OK {pdf.name} -> {dest.relative_to(ROOT)}")
        except Exception as exc:
            print(f"ERROR {pdf.name}: {exc}")

    invalidate_cache()
    print(f"\nProcesados {len(pdfs)} documento(s).")
    print("Reinicia app.py para que el análisis cite fragmentos del manual.")
    print("Imágenes en: data/knowledge/processed/<id>/pages/*.png")


if __name__ == "__main__":
    main()
