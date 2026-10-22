"""
PASO 3: Convertir anotaciones SVG de CubiCasa5K a formato YOLO (detección).

Lee model.svg + F1_scaled.png por muestra y genera .txt con bboxes normalizados.

Uso:
  python scripts/cubicasa_to_yolo.py --input data/raw/cubicasa5k
  python scripts/cubicasa_to_yolo.py --input data/raw/cubicasa5k --max-samples 200
"""

from __future__ import annotations

import argparse
import random
import re
import shutil
from pathlib import Path
from xml.etree import ElementTree as ET

import yaml
from PIL import Image
from tqdm import tqdm

# Índices YOLO (deben coincidir con config/data.yaml)
CLASS_TO_ID = {
    "door": 0,
    "window": 1,
    "wall": 2,
    "room": 3,
}

SVG_NS = {"svg": "http://www.w3.org/2000/svg"}
POINTS_RE = re.compile(r"[\d.\-eE]+")


def load_class_mapping(config_path: Path) -> dict[str, str]:
    with open(config_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    label_to_yolo: dict[str, str] = {}
    for svg_name, yolo_name in cfg.get("icons", {}).items():
        label_to_yolo[svg_name] = yolo_name
    for name in cfg.get("walls", []):
        label_to_yolo[name] = "wall"
    for name in cfg.get("rooms", []):
        label_to_yolo[name] = "room"
    return label_to_yolo


def parse_points(points_str: str) -> list[tuple[float, float]]:
    nums = [float(x) for x in POINTS_RE.findall(points_str)]
    if len(nums) < 4:
        return []
    pairs = list(zip(nums[0::2], nums[1::2]))
    return pairs


def polygon_to_bbox(
    points: list[tuple[float, float]], img_w: int, img_h: int
) -> tuple[float, float, float, float] | None:
    if not points:
        return None
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    x_min, x_max = min(xs), max(xs)
    y_min, y_max = min(ys), max(ys)
    bw = x_max - x_min
    bh = y_max - y_min
    if bw < 2 or bh < 2:
        return None

    cx = (x_min + x_max) / 2.0 / img_w
    cy = (y_min + y_max) / 2.0 / img_h
    nw = bw / img_w
    nh = bh / img_h

    cx = max(0.0, min(1.0, cx))
    cy = max(0.0, min(1.0, cy))
    nw = max(0.001, min(1.0, nw))
    nh = max(0.001, min(1.0, nh))
    return cx, cy, nw, nh


def iter_polygons(svg_path: Path) -> list[tuple[str, list[tuple[float, float]]]]:
    tree = ET.parse(svg_path)
    root = tree.getroot()
    results: list[tuple[str, list[tuple[float, float]]]] = []

    for elem in root.iter():
        tag = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag
        if tag not in ("polygon", "polyline", "rect"):
            continue

        label = (
            elem.get("class")
            or elem.get("id")
            or elem.get("{http://www.w3.org/1999/xlink}label")
        )
        if not label:
            parent = None
            for p in root.iter():
                if elem in list(p):
                    parent = p
                    break
            if parent is not None:
                label = parent.get("id") or parent.get("class")

        if not label:
            continue

        points: list[tuple[float, float]] = []
        if tag == "rect":
            x = float(elem.get("x", 0))
            y = float(elem.get("y", 0))
            w = float(elem.get("width", 0))
            h = float(elem.get("height", 0))
            points = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        else:
            raw = elem.get("points", "")
            points = parse_points(raw)

        if points:
            results.append((label.strip(), points))

    for g in root.iter():
        if g.tag.split("}")[-1] != "g":
            continue
        group_id = (g.get("id") or g.get("class") or "").strip()
        if not group_id:
            continue
        for child in g:
            ctag = child.tag.split("}")[-1]
            if ctag not in ("polygon", "polyline", "rect"):
                continue
            if ctag == "rect":
                x = float(child.get("x", 0))
                y = float(child.get("y", 0))
                w = float(child.get("width", 0))
                h = float(child.get("height", 0))
                pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
            else:
                pts = parse_points(child.get("points", ""))
            if pts:
                results.append((group_id, pts))

    return results


def resolve_dataset_root(user_path: Path) -> Path:
    """Encuentra la carpeta con planos (model.svg), no solo el repo de código."""
    if not user_path.exists():
        return user_path

    if find_samples(user_path):
        return user_path

    for sub in ("dataset", "data", "colorful", "high_quality", "high_quality_architectural"):
        candidate = user_path / sub
        if candidate.exists() and find_samples(candidate):
            print(f"[INFO] Dataset encontrado en: {candidate}")
            return candidate

    alt = user_path.parent / "dataset"
    if alt.exists() and find_samples(alt):
        print(f"[INFO] Dataset encontrado en: {alt}")
        return alt

    for svg in user_path.rglob("model.svg"):
        p = svg.parent
        for _ in range(10):
            if find_samples(p):
                print(f"[INFO] Dataset encontrado en: {p}")
                return p
            if p.parent == p:
                break
            p = p.parent

    return user_path


def find_samples(cubicasa_root: Path) -> list[Path]:
    samples = []
    for svg in cubicasa_root.rglob("model.svg"):
        sample_dir = svg.parent
        img = sample_dir / "F1_scaled.png"
        if not img.exists():
            for alt in ("F1_original.png", "F1_scaled.jpg", "image.png"):
                candidate = sample_dir / alt
                if candidate.exists():
                    img = candidate
                    break
            else:
                continue
        samples.append(sample_dir)
    return sorted(set(samples))


def load_split_ids(splits_dir: Path | None) -> tuple[list[str] | None, list[str] | None]:
    if splits_dir is None or not splits_dir.exists():
        return None, None

    train_file = val_file = None
    for name in ("train.txt", "val.txt"):
        for path in splits_dir.rglob(name):
            if name == "train.txt":
                train_file = path
            else:
                val_file = path

    def read_ids(path: Path | None) -> list[str] | None:
        if path is None:
            return None
        return [line.strip() for line in path.read_text().splitlines() if line.strip()]

    return read_ids(train_file), read_ids(val_file)


def sample_id(sample_dir: Path, cubicasa_root: Path) -> str:
    rel = sample_dir.relative_to(cubicasa_root)
    return str(rel).replace("\\", "/")


def convert_sample(
    sample_dir: Path,
    label_map: dict[str, str],
    out_images: Path,
    out_labels: Path,
    stem: str,
) -> int:
    svg_path = sample_dir / "model.svg"
    img_path = sample_dir / "F1_scaled.png"
    if not img_path.exists():
        for alt in ("F1_original.png", "F1_scaled.jpg"):
            p = sample_dir / alt
            if p.exists():
                img_path = p
                break

    with Image.open(img_path) as im:
        img_w, img_h = im.size

    yolo_lines: list[str] = []
    for svg_label, points in iter_polygons(svg_path):
        yolo_class = label_map.get(svg_label)
        if yolo_class is None:
            continue
        bbox = polygon_to_bbox(points, img_w, img_h)
        if bbox is None:
            continue
        cx, cy, nw, nh = bbox
        class_id = CLASS_TO_ID[yolo_class]
        yolo_lines.append(
            f"{class_id} {cx:.6f} {cy:.6f} {nw:.6f} {nh:.6f}"
        )

    if not yolo_lines:
        return 0

    dest_img = out_images / f"{stem}.png"
    dest_lbl = out_labels / f"{stem}.txt"
    shutil.copy2(img_path, dest_img)
    dest_lbl.write_text("\n".join(yolo_lines) + "\n", encoding="utf-8")
    return len(yolo_lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Raíz del dataset CubiCasa extraído",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("datasets/cubicasa_yolo"),
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("config/classes.yaml"),
    )
    parser.add_argument(
        "--splits-dir",
        type=Path,
        default=None,
        help="Carpeta con train.txt/val.txt del repo CubiCasa5k",
    )
    parser.add_argument("--max-samples", type=int, default=0)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    cubicasa_root = resolve_dataset_root((root / args.input).resolve())
    out_root = (root / args.output).resolve()
    config_path = (root / args.config).resolve()

    if not cubicasa_root.exists():
        raise SystemExit(f"No existe la ruta: {cubicasa_root}")

    label_map = load_class_mapping(config_path)
    samples = find_samples(cubicasa_root)
    if not samples:
        zip_hint = root / "data" / "raw" / "cubicasa5k.zip"
        zip_mb = zip_hint.stat().st_size / 1e6 if zip_hint.exists() else 0
        msg = [
            "No se encontraron muestras (model.svg + F1_scaled.png).",
            "",
            f"Ruta revisada: {cubicasa_root}",
        ]
        if zip_mb and zip_mb < 500:
            msg += [
                "",
                f"Tu cubicasa5k.zip pesa ~{zip_mb:.0f} MB (es el repo de código).",
                "Necesitas el dataset de Zenodo (~5100 MB):",
                "  python scripts/download_dataset.py --force",
                "Luego:",
                "  python scripts/cubicasa_to_yolo.py --input data/raw/dataset",
            ]
        else:
            msg += [
                "",
                "Descarga el dataset (~5 GB) y extrae:",
                "  python scripts/download_dataset.py --force",
                "  python scripts/cubicasa_to_yolo.py --input data/raw/dataset",
            ]
        raise SystemExit("\n".join(msg))

    train_ids, val_ids = load_split_ids(
        (root / args.splits_dir).resolve() if args.splits_dir else None
    )

    if args.max_samples > 0:
        random.seed(args.seed)
        samples = random.sample(samples, min(args.max_samples, len(samples)))

    for split in ("train", "val"):
        (out_root / "images" / split).mkdir(parents=True, exist_ok=True)
        (out_root / "labels" / split).mkdir(parents=True, exist_ok=True)

    counts = {"train": 0, "val": 0, "boxes": 0}
    for sample_dir in tqdm(samples, desc="Convirtiendo"):
        sid = sample_id(sample_dir, cubicasa_root)
        if train_ids is not None and val_ids is not None:
            if sid in val_ids or any(sid.endswith(v) for v in val_ids):
                split = "val"
            elif sid in train_ids or any(sid.endswith(t) for t in train_ids):
                split = "train"
            else:
                split = "val" if random.random() < 0.15 else "train"
        else:
            split = "val" if random.random() < 0.15 else "train"

        stem = sid.replace("/", "_")
        n = convert_sample(
            sample_dir,
            label_map,
            out_root / "images" / split,
            out_root / "labels" / split,
            stem,
        )
        if n:
            counts[split] += 1
            counts["boxes"] += n

    print(f"Muestras train: {counts['train']}")
    print(f"Muestras val:   {counts['val']}")
    print(f"Cajas totales:  {counts['boxes']}")
    print(f"Dataset YOLO en: {out_root}")
    print()
    print("Siguiente paso:")
    print("  python scripts/train.py")


if __name__ == "__main__":
    main()
