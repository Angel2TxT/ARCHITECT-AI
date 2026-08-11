"""Checkout de planes: pasarela demo (por defecto) y Stripe test/live."""

from __future__ import annotations

import os
import secrets
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

from fastapi import HTTPException
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from db.models import Plan, Subscription, SubscriptionStatus, User
from services.auth_service import ALGORITHM, SECRET_KEY
from services.stripe_service import (
    APP_BASE_URL,
    STRIPE_CURRENCY,
    STRIPE_PUBLISHABLE_KEY,
    build_checkout_line_item,
    create_portal_session,
    ensure_stripe_customer,
    get_stripe,
    is_demo_customer_id,
    stripe_configured,
)
from services.email_service import mail_config_status
from services.subscription_service import (
    change_plan,
    ensure_subscription,
    get_user_subscription,
    is_admin_user,
    is_paid_plan,
    subscription_payload,
)

BILLING_MODE = os.getenv("BILLING_MODE", "demo").strip().lower()
CHECKOUT_TTL_MINUTES = int(os.getenv("BILLING_CHECKOUT_TTL_MINUTES", "45"))
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "").strip()

CHECKOUT_TOKEN_TYPE = "billing_checkout"


def plan_change_quote(current: Plan | None, target: Plan) -> dict[str, Any]:
    """Reglas de cambio: no bajadas; upgrades pagan solo la diferencia de precio."""
    current_price = int(current.price_monthly_cents or 0) if current else 0
    target_price = int(target.price_monthly_cents or 0)
    current_slug = current.slug if current else "free"
    target_slug = target.slug

    if current_slug == target_slug:
        return {
            "allowed": True,
            "already_active": True,
            "code": "already_active",
            "current_price_cents": current_price,
            "list_price_cents": target_price,
            "credit_cents": 0,
            "amount_due_cents": 0,
            "is_upgrade": False,
            "is_downgrade": False,
            "message": "Ya tienes este plan activo.",
        }

    if target_price < current_price:
        return {
            "allowed": False,
            "already_active": False,
            "code": "downgrade_blocked",
            "current_price_cents": current_price,
            "list_price_cents": target_price,
            "credit_cents": 0,
            "amount_due_cents": 0,
            "is_upgrade": False,
            "is_downgrade": True,
            "message": (
                "No puedes bajar a un plan más barato mientras tu plan actual esté activo. "
                "Si necesitas cancelar, usa la opción de cancelar suscripción."
            ),
        }

    credit = current_price if target_price > current_price else 0
    amount_due = max(0, target_price - current_price)
    is_upgrade = current_price > 0 and target_price > current_price
    return {
        "allowed": True,
        "already_active": False,
        "code": "upgrade" if is_upgrade else "new_paid",
        "current_price_cents": current_price,
        "list_price_cents": target_price,
        "credit_cents": credit,
        "amount_due_cents": amount_due,
        "is_upgrade": is_upgrade,
        "is_downgrade": False,
        "message": (
            f"Pagas la diferencia: ${_fmt_cents(amount_due)} (crédito de tu plan actual ${_fmt_cents(credit)})."
            if is_upgrade
            else f"Total a pagar: ${_fmt_cents(amount_due)}."
        ),
    }


def _fmt_cents(cents: int) -> str:
    return f"{max(0, int(cents)) / 100:.0f}"


def assert_plan_change_allowed(
    db: Session,
    user: User,
    target: Plan,
    *,
    allow_admin_bypass: bool = True,
) -> dict[str, Any]:
    if allow_admin_bypass and is_admin_user(user):
        price = int(target.price_monthly_cents or 0)
        return {
            "allowed": True,
            "already_active": False,
            "code": "admin_bypass",
            "current_price_cents": 0,
            "list_price_cents": price,
            "credit_cents": 0,
            "amount_due_cents": price,
            "is_upgrade": False,
            "is_downgrade": False,
            "message": "Cambio de administrador.",
        }
    sub = ensure_subscription(db, user)
    quote = plan_change_quote(sub.plan, target)
    if not quote["allowed"]:
        raise HTTPException(
            status_code=400,
            detail={
                "message": quote["message"],
                "code": quote["code"],
                "current_price_cents": quote["current_price_cents"],
                "list_price_cents": quote["list_price_cents"],
            },
        )
    return quote


def billing_mode() -> str:
    if BILLING_MODE == "stripe" and stripe_configured():
        return "stripe"
    return "demo"


def billing_public_config() -> dict[str, Any]:
    mode = billing_mode()
    mail = mail_config_status()
    return {
        "mode": mode,
        "checkout_required_for_paid_plans": True,
        "stripe_publishable_key": STRIPE_PUBLISHABLE_KEY if mode == "stripe" else None,
        "stripe_configured": stripe_configured(),
        "billing_mode_env": BILLING_MODE,
        "mail_configured": mail["configured"],
        "mail_provider": mail.get("provider"),
    }


def _checkout_expiry() -> datetime:
    from datetime import timedelta

    return datetime.now(timezone.utc) + timedelta(minutes=CHECKOUT_TTL_MINUTES)


def create_checkout_token(
    *,
    user_id: int,
    plan_slug: str,
    return_url: str,
    amount_due_cents: int | None = None,
    credit_cents: int = 0,
    list_price_cents: int | None = None,
) -> str:
    payload = {
        "typ": CHECKOUT_TOKEN_TYPE,
        "uid": user_id,
        "plan": plan_slug,
        "return_url": return_url,
        "exp": _checkout_expiry(),
        "jti": secrets.token_urlsafe(12),
        "credit_cents": int(credit_cents or 0),
    }
    if amount_due_cents is not None:
        payload["amount_due_cents"] = int(amount_due_cents)
    if list_price_cents is not None:
        payload["list_price_cents"] = int(list_price_cents)
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_checkout_token(token: str) -> dict[str, Any]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as exc:
        raise HTTPException(400, "Sesión de pago inválida o expirada") from exc
    if payload.get("typ") != CHECKOUT_TOKEN_TYPE:
        raise HTTPException(400, "Token de checkout inválido")
    return payload


def _normalize_return_url(return_url: str | None) -> str:
    default = "/legacy-app"
    if not return_url:
        return default
    value = return_url.strip()
    if not value.startswith("/") or value.startswith("//"):
        return default
    return value


def _plan_or_404(db: Session, plan_slug: str) -> Plan:
    plan = (
        db.query(Plan)
        .filter(Plan.slug == plan_slug, Plan.is_public.is_(True))
        .first()
    )
    if not plan:
        raise HTTPException(404, "Plan no encontrado")
    return plan


def _checkout_url(session_token: str) -> str:
    """Ruta relativa para conservar el puerto/origen actual del navegador."""
    return f"/checkout?token={quote(session_token, safe='')}"


def checkout_session_preview(db: Session, token: str) -> dict[str, Any]:
    payload = decode_checkout_token(token)
    user = db.get(User, int(payload["uid"]))
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    plan = _plan_or_404(db, str(payload["plan"]))
    sub = ensure_subscription(db, user)
    quote = plan_change_quote(sub.plan, plan)
    list_price = int(payload.get("list_price_cents", plan.price_monthly_cents or 0))
    amount_due = int(
        payload.get(
            "amount_due_cents",
            quote["amount_due_cents"] if quote["allowed"] else list_price,
        )
    )
    credit = int(payload.get("credit_cents", quote.get("credit_cents", 0)))
    return {
        "mode": billing_mode(),
        **billing_public_config(),
        "plan": {
            "slug": plan.slug,
            "name": plan.name,
            "description": plan.description,
            "price_monthly_cents": plan.price_monthly_cents,
            "analyses_limit_monthly": plan.analyses_limit_monthly,
            "max_file_mb": plan.max_file_mb,
            "storage_gb": (plan.features or {}).get("storage_gb", 1),
            "allow_real_model": plan.allow_real_model,
        },
        "user_email": user.email,
        "current_plan_slug": sub.plan.slug if sub.plan else "free",
        "current_price_cents": quote["current_price_cents"],
        "list_price_cents": list_price,
        "credit_cents": credit,
        "amount_due_cents": amount_due,
        "is_upgrade": bool(credit > 0 and amount_due < list_price),
        "quote_message": quote.get("message"),
        "return_url": payload.get("return_url") or "/legacy-app",
        "expires_at": datetime.fromtimestamp(payload["exp"], tz=timezone.utc).isoformat(),
    }


def start_checkout(
    db: Session,
    user: User,
    plan_slug: str,
    *,
    return_url: str | None = None,
) -> dict[str, Any]:
    plan_slug = plan_slug.strip().lower()
    plan = _plan_or_404(db, plan_slug)
    safe_return = _normalize_return_url(return_url)
    quote = assert_plan_change_allowed(db, user, plan)

    if quote.get("already_active"):
        return {
            "status": "already_active",
            "mode": billing_mode(),
            "subscription": subscription_payload(db, user),
        }

    amount_due = int(quote["amount_due_cents"])
    credit = int(quote["credit_cents"])
    list_price = int(quote["list_price_cents"])

    # Admin, plan gratis (solo si cotización lo permite) o upgrade con $0.
    if not is_paid_plan(plan) or is_admin_user(user) or amount_due <= 0:
        subscription = change_plan(
            db,
            user,
            plan_slug,
            bypass_checkout=True,
            payment_ref=None,
        )
        return {
            "status": "completed",
            "mode": billing_mode(),
            "subscription": subscription,
            "amount_due_cents": amount_due,
            "credit_cents": credit,
        }

    mode = billing_mode()
    if mode == "stripe":
        stripe_payload = _start_stripe_checkout(
            db,
            user,
            plan,
            safe_return,
            amount_due_cents=amount_due,
            credit_cents=credit,
        )
        return {
            "status": "checkout_required",
            "amount_due_cents": amount_due,
            "credit_cents": credit,
            "list_price_cents": list_price,
            **stripe_payload,
        }

    session_token = create_checkout_token(
        user_id=user.id,
        plan_slug=plan_slug,
        return_url=safe_return,
        amount_due_cents=amount_due,
        credit_cents=credit,
        list_price_cents=list_price,
    )
    return {
        "status": "checkout_required",
        "mode": "demo",
        "session_token": session_token,
        "checkout_url": _checkout_url(session_token),
        "return_url": safe_return,
        "amount_due_cents": amount_due,
        "credit_cents": credit,
        "list_price_cents": list_price,
        "plan": {
            "slug": plan.slug,
            "name": plan.name,
            "price_monthly_cents": plan.price_monthly_cents,
        },
    }


def _issue_purchase_receipt(
    db: Session,
    user: User,
    plan_slug: str,
    payment_ref: str,
    *,
    amount_cents: int | None = None,
) -> dict[str, Any] | None:
    plan = _plan_or_404(db, plan_slug)
    if not is_paid_plan(plan):
        return None
    sub = get_user_subscription(db, user)
    if not sub or not sub.current_period_start or not sub.current_period_end:
        return None
    from services.billing_receipt_service import record_plan_purchase, receipt_payload

    receipt = record_plan_purchase(
        db,
        user,
        plan,
        payment_ref=payment_ref,
        period_start=sub.current_period_start,
        period_end=sub.current_period_end,
        amount_cents=amount_cents,
        send_email=True,
    )
    return receipt_payload(receipt)


def complete_demo_checkout(db: Session, user: User, session_token: str) -> dict[str, Any]:
    payload = decode_checkout_token(session_token)
    if int(payload["uid"]) != user.id:
        raise HTTPException(403, "Esta sesión de pago pertenece a otra cuenta")
    plan_slug = str(payload["plan"])
    plan = _plan_or_404(db, plan_slug)
    # Revalidar: no permitir completar si el usuario ya no puede subir a ese plan.
    quote = assert_plan_change_allowed(db, user, plan, allow_admin_bypass=False)
    amount_due = int(payload.get("amount_due_cents", quote["amount_due_cents"]))
    payment_ref = f"demo_sub_{payload.get('jti', secrets.token_hex(8))}"
    subscription = change_plan(
        db,
        user,
        plan_slug,
        bypass_checkout=True,
        payment_ref=payment_ref,
    )
    receipt = _issue_purchase_receipt(
        db,
        user,
        plan_slug,
        payment_ref,
        amount_cents=amount_due,
    )
    return {
        "status": "completed",
        "mode": "demo",
        "return_url": payload.get("return_url") or "/legacy-app",
        "subscription": subscription,
        "receipt": receipt,
        "amount_due_cents": amount_due,
        "credit_cents": int(payload.get("credit_cents", quote["credit_cents"])),
    }


def _start_stripe_checkout(
    db: Session,
    user: User,
    plan: Plan,
    return_url: str,
    *,
    amount_due_cents: int,
    credit_cents: int = 0,
) -> dict[str, Any]:
    stripe = get_stripe()
    sub = get_user_subscription(db, user)
    customer_id = ensure_stripe_customer(db, user, sub)

    success_url = (
        f"{APP_BASE_URL}/checkout/success"
        f"?session_id={{CHECKOUT_SESSION_ID}}&return_url={quote(return_url, safe='')}"
    )
    cancel_url = (
        f"{APP_BASE_URL}/legacy-app"
        f"?checkout_canceled=1&return_url={quote(return_url, safe='')}"
    )

    list_price = int(plan.price_monthly_cents or 0)
    is_partial_upgrade = credit_cents > 0 and amount_due_cents < list_price
    meta = {
        "user_id": str(user.id),
        "plan_slug": plan.slug,
        "amount_due_cents": str(amount_due_cents),
        "credit_cents": str(credit_cents),
        "list_price_cents": str(list_price),
    }

    if is_partial_upgrade:
        # Cobro único de la diferencia; el plan se activa al completar.
        session = stripe.checkout.Session.create(
            mode="payment",
            customer=customer_id,
            line_items=[
                {
                    "price_data": {
                        "currency": STRIPE_CURRENCY,
                        "unit_amount": amount_due_cents,
                        "product_data": {
                            "name": f"ARCHITECT — Mejora a {plan.name}",
                            "description": (
                                f"Diferencia de plan (crédito ${_fmt_cents(credit_cents)})."
                            )[:500],
                            "metadata": {"plan_slug": plan.slug},
                        },
                    },
                    "quantity": 1,
                }
            ],
            success_url=success_url,
            cancel_url=cancel_url,
            client_reference_id=str(user.id),
            metadata=meta,
        )
    else:
        session = stripe.checkout.Session.create(
            mode="subscription",
            customer=customer_id,
            line_items=[build_checkout_line_item(plan)],
            success_url=success_url,
            cancel_url=cancel_url,
            client_reference_id=str(user.id),
            metadata=meta,
            subscription_data={
                "metadata": {
                    "user_id": str(user.id),
                    "plan_slug": plan.slug,
                }
            },
        )
    return {
        "mode": "stripe",
        "session_token": session.id,
        "checkout_url": session.url,
        "return_url": return_url,
        "plan": {
            "slug": plan.slug,
            "name": plan.name,
            "price_monthly_cents": plan.price_monthly_cents,
        },
    }


def complete_stripe_checkout(
    db: Session,
    session_id: str,
    *,
    user: User | None = None,
) -> dict[str, Any]:
    stripe = get_stripe()
    session = stripe.checkout.Session.retrieve(session_id, expand=["subscription"])

    if session.status not in ("complete",) and session.payment_status not in ("paid", "no_payment_required"):
        raise HTTPException(402, "El pago no se completó")

    user_id = int(session.metadata.get("user_id") or session.client_reference_id or "0")
    plan_slug = str(session.metadata.get("plan_slug", "")).strip().lower()
    db_user = db.get(User, user_id)
    if not db_user or not plan_slug:
        raise HTTPException(400, "Sesión de Stripe inválida")

    if user and user.id != user_id:
        raise HTTPException(403, "Esta sesión de pago pertenece a otra cuenta")

    sub = get_user_subscription(db, db_user)
    payment_ref = str(
        session.subscription.id
        if getattr(session, "subscription", None)
        else session.id
    )
    amount_due = None
    raw_amount = (session.metadata or {}).get("amount_due_cents")
    if raw_amount is not None and str(raw_amount).isdigit():
        amount_due = int(raw_amount)

    if (
        sub
        and sub.stripe_subscription_id == payment_ref
        and sub.plan
        and sub.plan.slug == plan_slug
    ):
        return {
            "status": "already_active",
            "mode": "stripe",
            "subscription": subscription_payload(db, db_user),
        }

    subscription = change_plan(
        db,
        db_user,
        plan_slug,
        bypass_checkout=True,
        payment_ref=payment_ref,
        stripe_customer_id=str(session.customer) if session.customer else None,
    )
    receipt = _issue_purchase_receipt(
        db,
        db_user,
        plan_slug,
        payment_ref,
        amount_cents=amount_due,
    )
    return {
        "status": "completed",
        "mode": "stripe",
        "subscription": subscription,
        "receipt": receipt,
        "amount_due_cents": amount_due,
    }


def start_billing_portal(
    db: Session,
    user: User,
    *,
    return_url: str | None = None,
) -> dict[str, str]:
    return create_portal_session(db, user, return_url)


def _set_subscription_status_by_stripe_id(
    db: Session,
    stripe_sub_id: str,
    status: SubscriptionStatus,
) -> None:
    row = (
        db.query(Subscription)
        .filter(Subscription.stripe_subscription_id == stripe_sub_id)
        .first()
    )
    if row:
        row.status = status
        db.commit()


def handle_stripe_webhook(db: Session, payload: bytes, signature: str) -> dict[str, str]:
    if not STRIPE_WEBHOOK_SECRET:
        raise HTTPException(503, "STRIPE_WEBHOOK_SECRET no configurado")

    stripe = get_stripe()
    try:
        event = stripe.Webhook.construct_event(payload, signature, STRIPE_WEBHOOK_SECRET)
    except Exception as exc:
        raise HTTPException(400, f"Webhook inválido: {exc}") from exc

    event_type = event["type"]
    data_object = event["data"]["object"]

    if event_type == "checkout.session.completed":
        complete_stripe_checkout(db, data_object["id"])

    elif event_type == "customer.subscription.deleted":
        stripe_sub_id = str(data_object.get("id", ""))
        row = (
            db.query(Subscription)
            .filter(Subscription.stripe_subscription_id == stripe_sub_id)
            .first()
        )
        if row and row.user:
            change_plan(db, row.user, "free", bypass_checkout=True, payment_ref=None)

    elif event_type == "customer.subscription.updated":
        stripe_sub_id = str(data_object.get("id", ""))
        stripe_status = str(data_object.get("status", ""))
        status_map = {
            "active": SubscriptionStatus.active,
            "trialing": SubscriptionStatus.trialing,
            "past_due": SubscriptionStatus.past_due,
            "canceled": SubscriptionStatus.canceled,
            "unpaid": SubscriptionStatus.past_due,
        }
        if stripe_status in status_map:
            _set_subscription_status_by_stripe_id(db, stripe_sub_id, status_map[stripe_status])

    elif event_type == "invoice.payment_failed":
        stripe_sub_id = str(data_object.get("subscription", ""))
        if stripe_sub_id:
            _set_subscription_status_by_stripe_id(db, stripe_sub_id, SubscriptionStatus.past_due)

    return {"status": "ok"}
