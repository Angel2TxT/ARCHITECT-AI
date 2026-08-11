"""Prueba correo Brevo (API o SMTP). Uso: python scripts/test_mail.py destino@correo.com"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")

from services.email_service import mail_config_status, send_email  # noqa: E402


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: python scripts/test_mail.py destino@correo.com")
        return 1

    to = sys.argv[1].strip().lower()
    status = mail_config_status()
    print("Estado correo:", status)

    if not status.get("configured"):
        print("\nFAIL: Completa MAIL_* / BREVO_API_KEY en .env (ver docs/MAIL_BREVO_SETUP.md)")
        if status.get("missing"):
            print("Faltan:", ", ".join(status["missing"]))
        return 1

    try:
        send_email(
            to=to,
            subject="Prueba ARCHITECT — Brevo OK",
            text_body=(
                "Si recibes este correo, Brevo está bien configurado.\n\n"
                "Los comprobantes de compra se enviarán igual.\n\n— ARCHITECT"
            ),
            html_body="<p>Si recibes este correo, <strong>Brevo</strong> está bien configurado.</p>",
        )
    except Exception as exc:
        print(f"\nFAIL: {exc}")
        return 1

    print(f"\nOK: Correo enviado a {to} vía {status.get('mailer')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
