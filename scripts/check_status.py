"""Muestra qué falta para que la app pueda analizar planos."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIN_ZIP = 1_000_000_000


def ok(p: Path) -> str:
    return "OK" if p.exists() else "FALTA"


def main() -> None:
    zip_path = ROOT / "data" / "raw" / "cubicasa5k.zip"
    dataset = ROOT / "data" / "raw" / "dataset"
    cubicasa = ROOT / "data" / "raw" / "cubicasa5k"
    extracted = dataset if dataset.exists() else (cubicasa if cubicasa.exists() else None)
    yolo_ds = ROOT / "datasets" / "cubicasa_yolo"
    demo_ds = ROOT / "datasets" / "demo_yolo"
    weights = list((ROOT / "runs" / "detect").rglob("best.pt")) if (ROOT / "runs" / "detect").exists() else []

    print("\n=== Estado Plano IA ===\n")

    if zip_path.exists():
        mb = zip_path.stat().st_size / 1e6
        print(f"Zip CubiCasa: {mb:.0f} MB", end="")
        print(" (OK)" if zip_path.stat().st_size >= MIN_ZIP else " (INCOMPLETO, necesita ~5100 MB)")
    else:
        print("Zip CubiCasa: FALTA")

    if extracted:
        svgs = len(list(extracted.rglob("model.svg")))
        print(f"Dataset extraído: OK ({extracted.relative_to(ROOT)}, {svgs} planos)")
    else:
        print("Dataset extraído: FALTA")
    print(f"Dataset YOLO convertido: {ok(yolo_ds / 'images' / 'train')}")
    print(f"Dataset demo (rápido): {ok(demo_ds / 'images' / 'train')}")

    if weights:
        print(f"Modelo best.pt: OK ({len(weights)} encontrado(s))")
        for w in weights[:3]:
            print(f"  -> {w}")
    else:
        print("Modelo best.pt: FALTA")

    print()
    if not weights:
        print("Para probar YA la interfaz (5-15 min CPU):")
        print("  python scripts/train_demo.py")
        print()
        print("Para modelo real con CubiCasa5K:")
        print("  python scripts/download_dataset.py --force")
        print("  python scripts/cubicasa_to_yolo.py --input data/raw/dataset --max-samples 200")
        print("  python scripts/train.py --epochs 50 --device cpu")
    print()


if __name__ == "__main__":
    main()
