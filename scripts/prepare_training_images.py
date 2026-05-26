"""
Convierte PDF, imágenes y CAD en PNG listos para etiquetar (YOLO).

Uso:
  python scripts/prepare_training_images.py --input data/training/raw
  python scripts/prepare_training_images.py --input data/training/raw --tiles --tile-size 1280
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "data" / "training" / "to_label" / "images"

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}
PDF_EXT = {".pdf"}
CAD_EXT = {".dxf", ".dwg"}


def safe_stem(path: Path, suffix: str = "") -> str:
    base = path.stem.replace(" ", "_")[:80]
    h = hashlib.md5(str(path).encode()).hexdigest()[:8]
    return f"{base}_{h}{suffix}"


def save_png(png_bytes: bytes, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(png_bytes)


def pdf_to_png_pages(content: bytes, dpi: int) -> list[bytes]:
    import fitz

    doc = fitz.open(stream=content, filetype="pdf")
    pages: list[bytes] = []
    zoom = dpi / 72.0
    mat = fitz.Matrix(zoom, zoom)
    for page in doc:
        pix = page.get_pixmap(matrix=mat, alpha=False)
        pages.append(pix.tobytes("png"))
    doc.close()
    return pages


def file_to_png(path: Path, dpi: int) -> list[tuple[str, bytes]]:
    ext = path.suffix.lower()
    out: list[tuple[str, bytes]] = []

    if ext in IMAGE_EXT:
        with Image.open(path) as im:
            im = im.convert("RGB")
            from io import BytesIO

            buf = BytesIO()
            im.save(buf, format="PNG")
            out.append(("", buf.getvalue()))
        return out

    if ext in PDF_EXT:
        pages = pdf_to_png_pages(path.read_bytes(), dpi)
        for i, png in enumerate(pages):
            out.append((f"_p{i + 1}" if len(pages) > 1 else "", png))
        return out

    if ext in CAD_EXT:
        from services.cad_service import cad_bytes_to_png

        png = cad_bytes_to_png(path.read_bytes(), path.name)
        out.append(("", png))
        return out

    return out


def tile_image(png_bytes: bytes, tile_size: int, overlap: int) -> list[tuple[str, bytes]]:
    from io import BytesIO

    im = Image.open(BytesIO(png_bytes)).convert("RGB")
    w, h = im.size
    if w <= tile_size and h <= tile_size:
        buf = BytesIO()
        im.save(buf, format="PNG")
        return [("", buf.getvalue())]

    tiles: list[tuple[str, bytes]] = []
    step = max(tile_size - overlap, tile_size // 2)
    yi = 0
    ty = 0
    while yi < h:
        xi = 0
        tx = 0
        xh = min(tile_size, h - yi)
        while xi < w:
            xw = min(tile_size, w - xi)
            crop = im.crop((xi, yi, xi + xw, yi + xh))
            buf = BytesIO()
            crop.save(buf, format="PNG")
            tiles.append((f"_t{ty}_{tx}", buf.getvalue()))
            if xi + xw >= w:
                break
            xi += step
            tx += 1
        if yi + xh >= h:
            break
        yi += step
        ty += 1
    return tiles


def collect_files(input_dir: Path) -> list[Path]:
    files: list[Path] = []
    for ext in IMAGE_EXT | PDF_EXT | CAD_EXT:
        files.extend(input_dir.rglob(f"*{ext}"))
    return sorted(files)


def main() -> None:
    parser = argparse.ArgumentParser(description="Preparar PNG para etiquetado YOLO")
    parser.add_argument(
        "--input",
        type=Path,
        default=ROOT / "data" / "training" / "raw",
        help="Carpeta con PDF, PNG, DWG, DXF",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUT,
        help="Salida de PNG",
    )
    parser.add_argument("--dpi", type=int, default=200, help="DPI al rasterizar PDF")
    parser.add_argument(
        "--tiles",
        action="store_true",
        help="Recortar imágenes grandes en tiles",
    )
    parser.add_argument("--tile-size", type=int, default=1280)
    parser.add_argument("--overlap", type=int, default=128)
    args = parser.parse_args()

    input_dir = (ROOT / args.input).resolve() if not args.input.is_absolute() else args.input
    output_dir = (ROOT / args.output).resolve() if not args.output.is_absolute() else args.output

    if not input_dir.is_dir():
        raise SystemExit(
            f"No existe {input_dir}. Crea la carpeta y copia ahí tus planos.\n"
            "Ver docs/ENTRENAMIENTO_PLANOS.md"
        )

    files = collect_files(input_dir)
    if not files:
        raise SystemExit(f"No hay archivos en {input_dir}")

    count = 0
    for path in files:
        try:
            parts = file_to_png(path, args.dpi)
        except Exception as exc:
            print(f"[omitido] {path.name}: {exc}")
            continue

        for part_suffix, png in parts:
            tiles = (
                tile_image(png, args.tile_size, args.overlap)
                if args.tiles
                else [("", png)]
            )
            for tile_suffix, tile_png in tiles:
                name = safe_stem(path, f"{part_suffix}{tile_suffix}.png")
                dest = output_dir / name
                save_png(tile_png, dest)
                count += 1
                print(f"  {dest.relative_to(ROOT)}")

    print(f"\nListo: {count} imagen(es) en {output_dir}")
    print("Siguiente paso: etiquetar en Roboflow/CVAT y exportar YOLO.")
    print("Guía: docs/ENTRENAMIENTO_PLANOS.md")


if __name__ == "__main__":
    main()
