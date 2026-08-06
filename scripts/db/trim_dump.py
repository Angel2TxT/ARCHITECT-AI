"""Limpia architect_current.sql: deja esquema completo + INSERT solo de tablas clave."""
from __future__ import annotations

import re
from pathlib import Path

SQL = Path(__file__).resolve().parent / "architect_current.sql"

# Datos de catálogo / arranque. El resto queda solo con CREATE TABLE vacío.
KEEP_INSERTS = {"plans", "users", "subscriptions"}


def main() -> None:
    text = SQL.read_text(encoding="utf-8", errors="replace")
    out: list[str] = []
    removed = 0
    kept = 0
    for line in text.splitlines(keepends=True):
        if line.startswith("INSERT INTO"):
            m = re.match(r"INSERT INTO `([^`]+)`", line)
            table = m.group(1) if m else ""
            if table not in KEEP_INSERTS:
                removed += 1
                print(f"  omitir {table}: {len(line)} chars")
                continue
            kept += 1
            print(f"  conservar {table}: {len(line)} chars")
        out.append(line)

    SQL.write_text("".join(out), encoding="utf-8", newline="\n")
    size = SQL.stat().st_size
    print(f"Listo: {kept} INSERT conservados, {removed} omitidos, {size} bytes -> {SQL}")


if __name__ == "__main__":
    main()
