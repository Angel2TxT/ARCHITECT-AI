"""Cancelación de suscripción y elegibilidad de reembolso."""

from __future__ import annotations

from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session, joinedload

from db.models import (
    BillingReceipt,
    Plan,
    RefundRequest,
    RefundRequestStatus,
    SubscriptionStatus,
    User,
)
from services.subscription_service import (
    _period_bounds,
    ensure_subscription,
    get_asks_used,
    get_usage,
    is_admin_user,
    is_paid_plan,
    plan_capabilities,
    subscription_payload,
)

# Ventana escolar / demo: pocos días + uso bajo de beneficios del plan.
REFUND_WINDOW_DAYS = 7
MAX_ANALYSES_USAGE_RATIO = 0.30
MAX_ASKS_USAGE_RATIO = 0.30


def _latest_paid_receipt(db: Session, user_id: int) -> BillingReceipt | None:
    return (
        db.query(BillingReceipt)
        .filter(BillingReceipt.user_id == user_id, BillingReceipt.amount_cents > 0)
        .order_by(BillingReceipt.created_at.desc())
        .first()
    )


def _pending_refund_for_receipt(
    db: Session, user_id: int, receipt_id: int | None
) -> RefundRequest | None:
    q = db.query(RefundRequest).filter(
        RefundRequest.user_id == user_id,
        RefundRequest.status == RefundRequestStatus.pending,
    )
    if receipt_id is not None:
        q = q.filter(RefundRequest.receipt_id == receipt_id)
    return q.order_by(RefundRequest.created_at.desc()).first()


def evaluate_refund_eligibility(db: Session, user: User) -> dict:
    """
    Candidato a reembolso si:
    - hay un pago reciente (≤ REFUND_WINDOW_DAYS), y
    - no usó la mayor parte de los beneficios del periodo (análisis / preguntas).
    """
    if is_admin_user(user):
        return {
            "eligible": False,
            "window_days": REFUND_WINDOW_DAYS,
            "reasons": ["Las cuentas de administración no solicitan reembolso."],
            "receipt": None,
            "usage": None,
            "pending_request_id": None,
        }

    receipt = _latest_paid_receipt(db, user.id)
    if not receipt:
        return {
            "eligible": False,
            "window_days": REFUND_WINDOW_DAYS,
            "reasons": ["No hay un pago de plan registrado para reembolsar."],
            "receipt": None,
            "usage": None,
            "pending_request_id": None,
        }

    existing_done = (
        db.query(RefundRequest)
        .filter(
            RefundRequest.user_id == user.id,
            RefundRequest.receipt_id == receipt.id,
            RefundRequest.status.in_(
                [RefundRequestStatus.approved, RefundRequestStatus.pending]
            ),
        )
        .first()
    )
    if existing_done and existing_done.status == RefundRequestStatus.approved:
        return {
            "eligible": False,
            "window_days": REFUND_WINDOW_DAYS,
            "reasons": ["Este pago ya tiene un reembolso aprobado."],
            "receipt": _receipt_brief(receipt),
            "usage": None,
            "pending_request_id": None,
        }
    pending = existing_done if existing_done and existing_done.status == RefundRequestStatus.pending else None

    now = datetime.utcnow()
    paid_at = receipt.created_at or now
    days_since = max(0, (now - paid_at).days)
    within_window = days_since <= REFUND_WINDOW_DAYS

    plan = None
    if receipt.plan_id:
        plan = db.query(Plan).filter(Plan.id == receipt.plan_id).first()
    if not plan and receipt.plan_slug:
        plan = db.query(Plan).filter(Plan.slug == receipt.plan_slug).first()

    analyses_limit = int(plan.analyses_limit_monthly) if plan else 5
    caps = plan_capabilities(plan)
    asks_limit = int(caps.get("asks_limit_monthly") or 20)

    usage_row = get_usage(db, user.id)
    analyses_used = int(usage_row.analyses_count or 0)
    asks_used = get_asks_used(db, user.id)

    analyses_ratio = analyses_used / max(1, analyses_limit)
    asks_ratio = asks_used / max(1, asks_limit)
    low_analyses = analyses_ratio <= MAX_ANALYSES_USAGE_RATIO
    low_asks = asks_ratio <= MAX_ASKS_USAGE_RATIO
    low_usage = low_analyses and low_asks

    reasons: list[str] = []
    if not within_window:
        reasons.append(
            f"Pasaron {days_since} días desde el pago (máximo {REFUND_WINDOW_DAYS})."
        )
    if not low_analyses:
        reasons.append(
            f"Usaste {analyses_used}/{analyses_limit} análisis "
            f"({int(analyses_ratio * 100)}%; máximo ~{int(MAX_ANALYSES_USAGE_RATIO * 100)}%)."
        )
    if not low_asks:
        reasons.append(
            f"Usaste {asks_used}/{asks_limit} preguntas al chat "
            f"({int(asks_ratio * 100)}%; máximo ~{int(MAX_ASKS_USAGE_RATIO * 100)}%)."
        )
    if pending:
        reasons.append("Ya tienes una solicitud de reembolso pendiente de revisión.")

    eligible = within_window and low_usage and not pending

    if eligible:
        reasons = [
            f"Pago reciente ({days_since} de {REFUND_WINDOW_DAYS} días) y uso bajo "
            f"de beneficios ({analyses_used}/{analyses_limit} análisis, "
            f"{asks_used}/{asks_limit} preguntas)."
        ]

    return {
        "eligible": eligible,
        "window_days": REFUND_WINDOW_DAYS,
        "days_since_payment": days_since,
        "within_window": within_window,
        "low_usage": low_usage,
        "reasons": reasons,
        "receipt": _receipt_brief(receipt),
        "usage": {
            "analyses_used": analyses_used,
            "analyses_limit": analyses_limit,
            "analyses_ratio": round(analyses_ratio, 3),
            "asks_used": asks_used,
            "asks_limit": asks_limit,
            "asks_ratio": round(asks_ratio, 3),
            "max_usage_ratio": MAX_ANALYSES_USAGE_RATIO,
        },
        "pending_request_id": pending.id if pending else None,
    }


def _receipt_brief(receipt: BillingReceipt) -> dict:
    return {
        "id": receipt.id,
        "receipt_number": receipt.receipt_number,
        "plan_slug": receipt.plan_slug,
        "plan_name": receipt.plan_name,
        "amount_cents": receipt.amount_cents,
        "currency": receipt.currency,
        "created_at": receipt.created_at.isoformat() if receipt.created_at else None,
        "amount_label": f"${(receipt.amount_cents or 0) / 100:.0f} {receipt.currency}",
    }


def cancel_subscription(db: Session, user: User) -> dict:
    """Baja el plan de pago a gratis y evalúa si es candidato a reembolso."""
    if is_admin_user(user):
        raise HTTPException(400, "Las cuentas admin no cancelan suscripción aquí")

    sub = ensure_subscription(db, user)
    plan = sub.plan
    if not plan or not is_paid_plan(plan):
        raise HTTPException(400, "No tienes una suscripción de pago activa")

    eligibility = evaluate_refund_eligibility(db, user)
    free = db.query(Plan).filter(Plan.slug == "free").first()
    if not free:
        raise HTTPException(503, "Plan gratis no configurado")

    canceled_plan = {"slug": plan.slug, "name": plan.name, "price_monthly_cents": plan.price_monthly_cents}
    start, end = _period_bounds()
    sub.plan_id = free.id
    sub.status = SubscriptionStatus.active
    sub.current_period_start = start
    sub.current_period_end = end
    sub.canceled_at = datetime.utcnow()
    sub.stripe_subscription_id = None
    db.add(sub)
    db.commit()

    return {
        "ok": True,
        "message": "Suscripción cancelada. Quedaste en el plan Gratis.",
        "canceled_plan": canceled_plan,
        "subscription": subscription_payload(db, user),
        "refund_eligibility": eligibility,
    }


def request_refund(db: Session, user: User, *, reason: str = "") -> dict:
    sub = ensure_subscription(db, user)
    # Pedir reembolso tras cancelar (o si ya quedó en gratis tras baja).
    on_paid = bool(sub.plan and is_paid_plan(sub.plan))
    if on_paid and not sub.canceled_at:
        raise HTTPException(
            400,
            "Primero cancela tu suscripción. Si cumples la ventana de días y el uso bajo, "
            "podrás pedir el reembolso.",
        )

    eligibility = evaluate_refund_eligibility(db, user)
    if not eligibility.get("eligible"):
        detail = "; ".join(eligibility.get("reasons") or ["No eres candidato a reembolso"])
        raise HTTPException(400, detail)

    receipt_info = eligibility.get("receipt") or {}
    receipt_id = receipt_info.get("id")
    amount = int(receipt_info.get("amount_cents") or 0)

    row = RefundRequest(
        user_id=user.id,
        receipt_id=receipt_id,
        amount_cents=amount,
        currency=receipt_info.get("currency") or "MXN",
        status=RefundRequestStatus.pending,
        eligible_at_request=True,
        reason=(reason or "").strip()[:2000],
        eligibility_json=eligibility,
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    return {
        "ok": True,
        "message": "Solicitud de reembolso enviada. El equipo la revisará.",
        "request": refund_payload(row),
        "eligibility": eligibility,
    }


def refund_payload(row: RefundRequest) -> dict:
    return {
        "id": row.id,
        "status": row.status.value if hasattr(row.status, "value") else str(row.status),
        "amount_cents": row.amount_cents,
        "currency": row.currency,
        "eligible_at_request": bool(row.eligible_at_request),
        "reason": row.reason or "",
        "admin_note": row.admin_note or "",
        "receipt_id": row.receipt_id,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "reviewed_at": row.reviewed_at.isoformat() if row.reviewed_at else None,
    }


def list_user_refunds(db: Session, user_id: int) -> list[dict]:
    rows = (
        db.query(RefundRequest)
        .filter(RefundRequest.user_id == user_id)
        .order_by(RefundRequest.created_at.desc())
        .limit(20)
        .all()
    )
    return [refund_payload(r) for r in rows]


def list_admin_refunds(db: Session, *, status: str | None = None, limit: int = 50) -> list[dict]:
    q = db.query(RefundRequest).options(
        joinedload(RefundRequest.user),
        joinedload(RefundRequest.receipt),
    )
    if status:
        try:
            st = RefundRequestStatus(status)
            q = q.filter(RefundRequest.status == st)
        except ValueError:
            pass
    rows = q.order_by(RefundRequest.created_at.desc()).limit(limit).all()
    out = []
    for r in rows:
        item = refund_payload(r)
        item["user_email"] = r.user.email if r.user else ""
        item["user_name"] = r.user.full_name if r.user else ""
        item["receipt_number"] = r.receipt.receipt_number if r.receipt else None
        out.append(item)
    return out


def review_refund(
    db: Session,
    admin: User,
    request_id: int,
    *,
    approve: bool,
    admin_note: str = "",
) -> dict:
    row = db.query(RefundRequest).filter(RefundRequest.id == request_id).first()
    if not row:
        raise HTTPException(404, "Solicitud no encontrada")
    if row.status != RefundRequestStatus.pending:
        raise HTTPException(400, "Esta solicitud ya fue revisada")

    row.status = RefundRequestStatus.approved if approve else RefundRequestStatus.rejected
    row.admin_note = (admin_note or "").strip()[:2000]
    row.reviewed_by = admin.id
    row.reviewed_at = datetime.utcnow()
    db.add(row)
    db.commit()
    db.refresh(row)
    return {
        "ok": True,
        "request": refund_payload(row),
        "message": "Reembolso aprobado (simulado)." if approve else "Solicitud rechazada.",
    }
