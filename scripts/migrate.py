"""Solo migraciones (sin seed). Uso: python scripts/migrate.py"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")

from db.migrations import apply_pending_migrations

if __name__ == "__main__":
    print("Aplicando migraciones...")
    apply_pending_migrations()
    print("OK — migraciones aplicadas.")
