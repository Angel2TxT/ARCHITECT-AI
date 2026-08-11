"""Comprobantes de compra / cambio de plan (proyecto escolar, pasarela demo)."""

from __future__ import annotations

import io
import logging
import os
import zipfile
from datetime import datetime

from fastapi import HTTPException
import fitz
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from db.models import BillingReceipt, Plan, User
from services.billing_checkout_service import billing_mode
from services.email_service import is_mail_configured, send_billing_receipt_email

APP_BASE_URL = os.getenv("APP_BASE_URL", "http://localhost:3000").rstrip("/")
logger = logging.getLogger(__name__)

_PDF_CHAR_REPLACEMENTS = {
    "—": "-",
    "–": "-",
    "«": '"',
    "»": '"',
    "á": "a",
    "é": "e",
    "í": "i",
    "ó": "o",
    "ú": "u",
    "Á": "A",
    "É": "E",
    "Í": "I",
    "Ó": "O",
    "Ú": "U",
    "ñ": "n",
    "Ñ": "N",
    "ü": "u",
    "Ü": "U",
}


def _pdf_safe_text(value: str | None) -> str:
    """Helvetica en fpdf2 solo soporta Latin-1; normaliza texto dinámico."""
    if not value:
        return ""
    text = str(value)
    for src, dst in _PDF_CHAR_REPLACEMENTS.items():
        text = text.replace(src, dst)
    return text.encode("latin-1", "replace").decode("latin-1")


def _format_money(cents: int, currency: str = "MXN") -> str:
    if not cents:
        return "Gratis"
    symbol = "$" if currency.upper() == "MXN" else currency.upper() + " "
    return f"{symbol}{(cents / 100):,.2f} {currency.upper()}"


def _next_receipt_number(db: Session) -> str:
    prefix = datetime.utcnow().strftime("AR-%Y%m")
    pattern = f"{prefix}-%"
    count = (
        db.query(func.count(BillingReceipt.id))
        .filter(BillingReceipt.receipt_number.like(pattern))
        .scalar()
        or 0
    )
    return f"{prefix}-{count + 1:05d}"


def _email_status(receipt: BillingReceipt) -> str:
    if receipt.email_sent_at:
        return "sent"
    if not is_mail_configured():
        return "not_configured"
    return "failed"


def receipt_payload(receipt: BillingReceipt) -> dict:
    return {
        "id": receipt.id,
        "receipt_number": receipt.receipt_number,
        "plan_slug": receipt.plan_slug,
        "plan_name": receipt.plan_name,
        "amount_cents": receipt.amount_cents,
        "amount_label": _format_money(receipt.amount_cents, receipt.currency),
        "currency": receipt.currency,
        "billing_mode": receipt.billing_mode,
        "payment_ref": receipt.payment_ref,
        "period_start": receipt.period_start.isoformat() if receipt.period_start else None,
        "period_end": receipt.period_end.isoformat() if receipt.period_end else None,
        "email_sent_at": receipt.email_sent_at.isoformat() if receipt.email_sent_at else None,
        "email_status": _email_status(receipt),
        "created_at": receipt.created_at.isoformat() if receipt.created_at else None,
        "download_url": f"/api/billing/receipts/{receipt.id}/pdf",
    }


def list_user_receipts(db: Session, user_id: int, *, limit: int = 50) -> list[dict]:
    rows = (
        db.query(BillingReceipt)
        .filter(BillingReceipt.user_id == user_id)
        .order_by(BillingReceipt.created_at.desc())
        .limit(min(limit, 100))
        .all()
    )
    return [receipt_payload(r) for r in rows]


def get_user_receipt(db: Session, user_id: int, receipt_id: int) -> BillingReceipt:
    row = (
        db.query(BillingReceipt)
        .filter(BillingReceipt.id == receipt_id, BillingReceipt.user_id == user_id)
        .first()
    )
    if not row:
        raise HTTPException(404, "Comprobante no encontrado")
    return row


# Paleta ARCHITECT (checkout / app)
_PDF_BLACK = (9 / 255, 9 / 255, 11 / 255)
_PDF_WHITE = (1, 1, 1)
_PDF_MUTED = (113 / 255, 113 / 255, 122 / 255)
_PDF_MUTED_LIGHT = (161 / 255, 161 / 255, 170 / 255)
_PDF_BORDER = (228 / 255, 228 / 255, 231 / 255)
_PDF_SURFACE = (250 / 255, 250 / 255, 250 / 255)
_PDF_GREEN = (134 / 255, 239 / 255, 172 / 255)
_PDF_GREEN_DARK = (22 / 255, 101 / 255, 52 / 255)
_PDF_AMBER_BG = (254 / 255, 243 / 255, 199 / 255)
_PDF_AMBER_BORDER = (251 / 255, 191 / 255, 36 / 255)
_PDF_AMBER_TEXT = (146 / 255, 64 / 255, 14 / 255)


def _pdf_text(value: str | None) -> str:
    if not value:
        return ""
    return str(value).replace("\r", " ").strip()


def _pdf_text_width(text: str, *, font: str, size: float) -> float:
    return fitz.get_text_length(text, fontname=font, fontsize=size)


def _pdf_draw_card(page: fitz.Page, rect: fitz.Rect) -> None:
    page.draw_rect(rect, fill=_PDF_SURFACE, color=_PDF_BORDER, width=0.6)


def _pdf_label_row(page: fitz.Page, x: float, y: float, label: str, value: str, width: float) -> float:
    page.insert_text((x, y), label.upper(), fontsize=8, fontname="hebo", color=_PDF_MUTED)
    page.insert_text((x + 118, y), _pdf_text(value), fontsize=10, fontname="helv", color=_PDF_BLACK)
    return y + 17


def receipt_to_pdf(receipt: BillingReceipt, user: User) -> bytes:
    """Genera PDF con PyMuPDF (colores y layout fieles a la marca)."""
    doc = fitz.open()
    page = doc.new_page(width=595, height=842)
    margin = 42.0
    content_w = 595 - (margin * 2)
    y = 0.0

    page.draw_rect(fitz.Rect(0, 0, 595, 94), fill=_PDF_BLACK, color=_PDF_BLACK)
    page.draw_rect(fitz.Rect(0, 94, 595, 99), fill=_PDF_GREEN, color=_PDF_GREEN)
    page.draw_circle(fitz.Point(margin + 4, 76), 2.2, fill=_PDF_WHITE, color=_PDF_WHITE)

    page.insert_text((margin, 36), "ARCHITECT", fontsize=24, fontname="hebo", color=_PDF_WHITE)
    page.insert_text(
        (margin, 56),
        "Comprobante de suscripcion  |  Proyecto escolar",
        fontsize=9,
        fontname="helv",
        color=_PDF_MUTED_LIGHT,
    )
    page.insert_text(
        (margin + 12, 76),
        "PASARELA SIMULADA",
        fontsize=7,
        fontname="hebo",
        color=_PDF_MUTED_LIGHT,
    )

    y = 118
    page.insert_text((margin, y), "COMPROBANTE EMITIDO", fontsize=8, fontname="hebo", color=_PDF_MUTED)
    y += 20
    page.insert_text((margin, y), _pdf_text(receipt.receipt_number), fontsize=18, fontname="hebo", color=_PDF_BLACK)
    y += 18
    created = (
        receipt.created_at.strftime("%d/%m/%Y %H:%M UTC")
        if receipt.created_at
        else "-"
    )
    page.insert_text((margin, y), f"Fecha de emision: {created}", fontsize=9, fontname="helv", color=_PDF_MUTED)
    y += 26

    hero_h = 78.0
    hero = fitz.Rect(margin, y, margin + content_w, y + hero_h)
    _pdf_draw_card(page, hero)
    page.insert_text((margin + 14, y + 22), "PLAN CONTRATADO", fontsize=8, fontname="hebo", color=_PDF_MUTED)
    plan_name = _pdf_text(receipt.plan_name)
    amount = _format_money(receipt.amount_cents, receipt.currency)
    page.insert_text((margin + 14, y + 42), plan_name, fontsize=15, fontname="hebo", color=_PDF_BLACK)
    amount_w = _pdf_text_width(amount, font="hebo", size=18)
    page.insert_text(
        (margin + content_w - amount_w - 14, y + 44),
        amount,
        fontsize=18,
        fontname="hebo",
        color=_PDF_GREEN_DARK,
    )
    page.insert_text(
        (margin + 14, y + 60),
        "Suscripcion mensual simulada",
        fontsize=8,
        fontname="helv",
        color=_PDF_MUTED,
    )
    y += hero_h + 16

    rows = [
        ("Cliente", _pdf_text(user.full_name or user.email)),
        ("Correo", _pdf_text(user.email)),
        (
            "Periodo",
            (
                f"{receipt.period_start.strftime('%d/%m/%Y')} - "
                f"{receipt.period_end.strftime('%d/%m/%Y')}"
                if receipt.period_start and receipt.period_end
                else "-"
            ),
        ),
        ("Modo de pago", f"Pasarela simulada ({receipt.billing_mode})"),
    ]
    if receipt.payment_ref:
        rows.append(("Referencia", _pdf_text(receipt.payment_ref)))

    detail_h = 28 + (len(rows) * 17)
    detail = fitz.Rect(margin, y, margin + content_w, y + detail_h)
    _pdf_draw_card(page, detail)
    page.insert_text((margin + 14, y + 20), "Detalle", fontsize=11, fontname="hebo", color=_PDF_BLACK)
    row_y = y + 36
    for label, value in rows:
        row_y = _pdf_label_row(page, margin + 14, row_y, label, value, content_w - 28)
    y += detail_h + 18

    legal_text = (
        "DOCUMENTO ACADEMICO - NO ES FACTURA FISCAL. "
        "Generado con fines de demostracion en proyecto escolar ARCHITECT. "
        "La pasarela de pago es simulada; no hubo cargo real ni procesamiento "
        "por un tercero autorizado. No tiene validez tributaria ni comercial."
    )
    legal = fitz.Rect(margin, y, margin + content_w, y + 78)
    page.draw_rect(legal, fill=_PDF_AMBER_BG, color=_PDF_AMBER_BORDER, width=0.8)
    page.insert_text((margin + 12, y + 18), "AVISO LEGAL", fontsize=8, fontname="hebo", color=_PDF_AMBER_TEXT)
    page.insert_textbox(
        fitz.Rect(margin + 12, y + 26, margin + content_w - 12, y + 72),
        legal_text,
        fontsize=8,
        fontname="helv",
        color=_PDF_AMBER_TEXT,
        align=fitz.TEXT_ALIGN_LEFT,
    )

    footer = "ARCHITECT  |  Proyecto escolar  |  Pasarela simulada (demo)"
    footer_w = _pdf_text_width(footer, font="helv", size=8)
    page.insert_text(
        ((595 - footer_w) / 2, 820),
        footer,
        fontsize=8,
        fontname="helv",
        color=_PDF_MUTED,
    )

    pdf_bytes = doc.tobytes(deflate=True)
    doc.close()
    return pdf_bytes


def record_plan_purchase(
    db: Session,
    user: User,
    plan: Plan,
    *,
    payment_ref: str | None,
    period_start: datetime,
    period_end: datetime,
    amount_cents: int | None = None,
    send_email: bool = True,
) -> BillingReceipt:
    """Registra ticket y opcionalmente envía correo con PDF adjunto."""
    if (plan.price_monthly_cents or 0) <= 0:
        raise ValueError("Solo se emiten comprobantes para planes de pago")

    charged = (
        int(plan.price_monthly_cents or 0)
        if amount_cents is None
        else max(0, int(amount_cents))
    )
    receipt = BillingReceipt(
        receipt_number=_next_receipt_number(db),
        user_id=user.id,
        plan_id=plan.id,
        plan_slug=plan.slug,
        plan_name=plan.name,
        amount_cents=charged,
        currency=os.getenv("STRIPE_CURRENCY", "mxn").upper(),
        billing_mode=billing_mode(),
        payment_ref=payment_ref,
        period_start=period_start,
        period_end=period_end,
    )
    db.add(receipt)
    db.commit()
    db.refresh(receipt)

    if send_email:
        try:
            _try_send_receipt_email(db, receipt, user)
        except Exception:
            logger.exception(
                "Comprobante %s creado pero fallo envio PDF/correo",
                receipt.receipt_number,
            )

    return receipt


def _try_send_receipt_email(db: Session, receipt: BillingReceipt, user: User) -> bool:
    if not is_mail_configured():
        return False
    pdf_bytes = receipt_to_pdf(receipt, user)
    download_url = f"{APP_BASE_URL}/legacy-app?account=1&receipt_id={receipt.id}"
    period_label = None
    if receipt.period_start and receipt.period_end:
        period_label = (
            f"{receipt.period_start.strftime('%d/%m/%Y')} - "
            f"{receipt.period_end.strftime('%d/%m/%Y')}"
        )
    sent = send_billing_receipt_email(
        to_email=user.email,
        user_name=user.full_name or user.email,
        receipt_number=receipt.receipt_number,
        plan_name=receipt.plan_name,
        amount_label=_format_money(receipt.amount_cents, receipt.currency),
        download_url=download_url,
        pdf_bytes=pdf_bytes,
        pdf_filename=f"ARCHITECT-{receipt.receipt_number}.pdf",
        period_label=period_label,
        payment_ref=receipt.payment_ref,
    )
    if sent:
        receipt.email_sent_at = datetime.utcnow()
        db.commit()
    return sent


def resend_receipt_email(db: Session, user: User, receipt_id: int) -> dict:
    receipt = get_user_receipt(db, user.id, receipt_id)
    if not is_mail_configured():
        raise HTTPException(
            503,
            "Correo no configurado. Revisa MAIL_* en .env o descarga el PDF desde tu perfil.",
        )
    sent = _try_send_receipt_email(db, receipt, user)
    if not sent:
        raise HTTPException(500, "No se pudo enviar el correo")
    return {"status": "sent", "receipt": receipt_payload(receipt)}


def receipt_pdf_bytes(db: Session, user: User, receipt_id: int) -> tuple[str, bytes]:
    receipt = get_user_receipt(db, user.id, receipt_id)
    filename = f"ARCHITECT-{receipt.receipt_number}.pdf"
    return filename, receipt_to_pdf(receipt, user)


def export_user_receipts_zip(db: Session, user: User) -> tuple[str, bytes]:
    receipts = (
        db.query(BillingReceipt)
        .filter(BillingReceipt.user_id == user.id)
        .order_by(BillingReceipt.created_at.desc())
        .all()
    )
    if not receipts:
        raise HTTPException(404, "No tienes comprobantes para exportar")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for receipt in receipts:
            pdf_name = f"ARCHITECT-{receipt.receipt_number}.pdf"
            zf.writestr(pdf_name, receipt_to_pdf(receipt, user))
    stamp = datetime.utcnow().strftime("%Y%m%d")
    return f"ARCHITECT-comprobantes-{stamp}.zip", buf.getvalue()


def admin_receipts_list(db: Session, *, limit: int = 100, offset: int = 0) -> dict:
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    q = db.query(BillingReceipt).options(joinedload(BillingReceipt.user))
    total = q.count()
    rows = q.order_by(BillingReceipt.created_at.desc()).offset(offset).limit(limit).all()
    return {
        "total": total,
        "items": [
            {
                **receipt_payload(r),
                "user_email": r.user.email if r.user else None,
                "user_name": r.user.full_name if r.user else None,
            }
            for r in rows
        ],
    }


def admin_billing_summary(db: Session) -> dict:
    total_receipts = db.query(func.count(BillingReceipt.id)).scalar() or 0
    revenue_cents = (
        db.query(func.coalesce(func.sum(BillingReceipt.amount_cents), 0)).scalar() or 0
    )
    by_plan = (
        db.query(
            BillingReceipt.plan_slug,
            BillingReceipt.plan_name,
            func.count(BillingReceipt.id),
            func.coalesce(func.sum(BillingReceipt.amount_cents), 0),
        )
        .group_by(BillingReceipt.plan_slug, BillingReceipt.plan_name)
        .order_by(func.count(BillingReceipt.id).desc())
        .all()
    )
    return {
        "receipts_total": int(total_receipts),
        "simulated_revenue_cents": int(revenue_cents),
        "simulated_revenue_label": _format_money(int(revenue_cents)),
        "by_plan": [
            {
                "plan_slug": slug,
                "plan_name": name,
                "receipts_count": int(count or 0),
                "simulated_revenue_cents": int(cents or 0),
                "simulated_revenue_label": _format_money(int(cents or 0)),
            }
            for slug, name, count, cents in by_plan
        ],
    }
