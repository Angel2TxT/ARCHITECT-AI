"""
Extrae cifras normativas del texto ingestado (ayuda a ampliar rules/norms.py).

Uso:
  python scripts/extract_norm_hints.py
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "data" / "knowledge" / "processed"

METER_RE = re.compile(
    r"(\d+[.,]\d+|\d+)\s*(?:m\b|metros?|m\.|m²|m2)",
    re.IGNORECASE,
)


def main() -> None:
    hits: Counter[str] = Counter()
    samples: list[str] = []

    for manifest_path in PROCESSED.glob("*/manifest.json"):
        doc = manifest_path.parent
        for txt in (doc / "pages").glob("*.txt"):
            text = txt.read_text(encoding="utf-8", errors="ignore")
            if len(text) < 30:
                continue
            for m in METER_RE.finditer(text):
                val = m.group(0).replace(",", ".")
                hits[val] += 1
            if "puerta" in text.lower() and "m" in text.lower():
                line = next(
                    (ln.strip() for ln in text.splitlines() if "puerta" in ln.lower()[:80]),
                    "",
                )
                if line and len(samples) < 15:
                    samples.append(f"{manifest_path.parent.name}/{txt.name}: {line[:120]}")

    print("=== Medidas más mencionadas en tus manuales ===")
    for val, n in hits.most_common(25):
        print(f"  {val:12}  ({n}×)")

    print("\n=== Muestras con 'puerta' ===")
    for s in samples:
        print(f"  {s}")

    out = ROOT / "data" / "knowledge" / "norm_hints.json"
    out.write_text(
        json.dumps(
            {"top_measures": hits.most_common(40), "door_samples": samples},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"\nGuardado: {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
