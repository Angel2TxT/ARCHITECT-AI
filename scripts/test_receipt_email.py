#!/usr/bin/env python3
"""Envia un correo de comprobante de prueba (HTML + PDF adjunto)."""

from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")

from db.database import SessionLocal
from db.models import BillingReceipt, User
from services.billing_receipt_service import receipt_to_pdf
from services.email_service import is_mail_configured, mail_config_status, send_billing_receipt_email


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: python scripts/test_receipt_email.py destino@correo.com")
        return 1

    to = sys.argv[1].strip().lower()
    status = mail_config_status()
    print("Estado SMTP:", status)
    if not is_mail_configured():
        print("FAIL: Completa MAIL_* en .env")
        return 1

    db = SessionLocal()
    receipt = db.query(BillingReceipt).order_by(BillingReceipt.id.desc()).first()
    user = db.get(User, receipt.user_id) if receipt else db.query(User).first()
    if not receipt or not user:
        print("FAIL: No hay comprobantes/usuarios en la base de datos")
        return 1

    pdf = receipt_to_pdf(receipt, user)
    base = status.get("from_address") or "http://localhost:8000"
    app_base = __import__("os").getenv("APP_BASE_URL", "http://localhost:8000").rstrip("/")
    ok = send_billing_receipt_email(
        to_email=to,
        user_name=user.full_name or user.email,
        receipt_number=receipt.receipt_number,
        plan_name=receipt.plan_name,
        amount_label=f"${receipt.amount_cents / 100:,.2f} {receipt.currency}",
        download_url=f"{app_base}/legacy-app?account=1&receipt_id={receipt.id}",
        pdf_bytes=pdf,
        pdf_filename=f"ARCHITECT-{receipt.receipt_number}.pdf",
        period_label=datetime.utcnow().strftime("%d/%m/%Y"),
        payment_ref=receipt.payment_ref,
    )
    db.close()
    if not ok:
        print("FAIL: No se pudo enviar el correo de prueba")
        return 1
    print(f"OK: Correo de comprobante enviado a {to}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
