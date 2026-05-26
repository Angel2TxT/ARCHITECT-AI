"""
PASO 1: Descargar CubiCasa5K (~5 GB comprimido, ~15 GB extraído).

Uso:
  python scripts/download_dataset.py
  python scripts/download_dataset.py --output data/raw
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

import requests

ZENODO_URL = (
    "https://zenodo.org/record/2613548/files/cubicasa5k.zip?download=1"
)
# El dataset real pesa ~5.1 GB; el repo de GitHub ~60 MB
MIN_DATASET_BYTES = 1_000_000_000
SPLITS_REPO = "https://github.com/CubiCasa/CubiCasa5k/archive/refs/heads/master.zip"


def download(url: str, dest: Path, label: str, *, force: bool = False) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        size = dest.stat().st_size
        bad = dest.name == "cubicasa5k.zip" and size < MIN_DATASET_BYTES
        if force or bad:
            if bad:
                print(f"[AVISO] Zip incompleto ({size / 1e6:.0f} MB). Re-descargando...")
            dest.unlink()
        elif not force:
            print(f"[OK] Ya existe: {dest} ({size / 1e9:.2f} GB)")
            return

    print(f"Descargando {label}...")
    print(f"  URL: {url}")
    print(f"  -> {dest}")
    print("  (puede tardar 30-60 min; no cierres la terminal)")

    headers = {}
    mode = "wb"
    downloaded = 0
    if dest.exists() and dest.stat().st_size > 0 and not force:
        downloaded = dest.stat().st_size
        headers["Range"] = f"bytes={downloaded}-"
        mode = "ab"
        print(f"  Reanudando desde {downloaded / 1e6:.0f} MB...")

    with requests.get(url, stream=True, headers=headers, timeout=60) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0)) + downloaded
        with open(dest, mode) as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if not chunk:
                    continue
                f.write(chunk)
                downloaded += len(chunk)
                if total > 0:
                    pct = min(100, downloaded * 100 // total)
                    sys.stdout.write(
                        f"\r  Progreso: {pct}% ({downloaded / 1e9:.2f} GB)"
                    )
                    sys.stdout.flush()
    print()


def extract_zip(zip_path: Path, out_dir: Path) -> None:
    print(f"Extrayendo {zip_path.name} -> {out_dir}")
    out_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(out_dir)
    print("[OK] Extracción lista.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Descarga CubiCasa5K")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/raw"),
        help="Carpeta donde guardar el dataset extraído",
    )
    parser.add_argument(
        "--skip-splits",
        action="store_true",
        help="No descargar splits train/val del repo oficial",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Volver a descargar aunque el zip ya exista",
    )
    parser.add_argument(
        "--extract-only",
        action="store_true",
        help="Solo extraer el zip (no descargar de nuevo)",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    data_dir = root / args.output
    zip_path = data_dir / "cubicasa5k.zip"

    if not args.extract_only:
        download(ZENODO_URL, zip_path, "CubiCasa5K (Zenodo)", force=args.force)
    elif not zip_path.exists():
        raise SystemExit(f"No existe {zip_path}. Coloca el zip ahí o ejecuta sin --extract-only.")
    else:
        print(f"[OK] Usando zip existente: {zip_path} ({zip_path.stat().st_size / 1e9:.2f} GB)")
    size = zip_path.stat().st_size
    if size < MIN_DATASET_BYTES:
        raise SystemExit(
            f"\nEl archivo {zip_path} tiene solo {size / 1e6:.0f} MB.\n"
            "Debe ser ~5100 MB (dataset con planos).\n"
            "Bórralo y ejecuta: python scripts/download_dataset.py --force\n"
            "Descarga manual: https://zenodo.org/record/2613548"
        )
    extract_zip(zip_path, data_dir / "dataset")

    if not args.skip_splits:
        splits_zip = data_dir / "cubicasa_splits.zip"
        download(SPLITS_REPO, splits_zip, "splits del repo CubiCasa5k")
        extract_zip(splits_zip, data_dir / "splits_repo")

    print()
    dataset_root = data_dir / "dataset"
    print("Siguiente paso:")
    print(
        "  python scripts/cubicasa_to_yolo.py "
        f"--input {dataset_root}"
    )
    print()
    print(
        "Nota: NO uses data/raw/cubicasa5k (solo código del repo). "
        "Usa data/raw/dataset tras extraer el zip de Zenodo (~5 GB)."
    )


if __name__ == "__main__":
    main()
