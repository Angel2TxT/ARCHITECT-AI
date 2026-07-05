#!/usr/bin/env python3
"""Sincroniza planes de ARCHITECT con productos/precios en Stripe (test o live)."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

load_dotenv(ROOT / ".env")

from db.database import SessionLocal
from services.stripe_service import STRIPE_SECRET_KEY, sync_plan_prices


def main() -> int:
    if not STRIPE_SECRET_KEY:
        print("ERROR: define STRIPE_SECRET_KEY en .env (usa sk_test_... para pruebas)")
        return 1

    db = SessionLocal()
    try:
        results = sync_plan_prices(db)
    finally:
        db.close()

    if not results:
        print("No hay planes de pago para sincronizar.")
        return 0

    print("Planes sincronizados con Stripe:")
    print(json.dumps(results, indent=2, ensure_ascii=False))
    print("\nLos stripe_price_id quedaron guardados en plans.features")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
