"""Helpers Stripe: clientes, precios y portal (modo test/live)."""

from __future__ import annotations

import os
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from db.models import Plan, Subscription, User

STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "").strip()
STRIPE_PUBLISHABLE_KEY = os.getenv("STRIPE_PUBLISHABLE_KEY", "").strip()
STRIPE_CURRENCY = os.getenv("STRIPE_CURRENCY", "mxn").strip().lower()
APP_BASE_URL = os.getenv("APP_BASE_URL", "http://127.0.0.1:8080").rstrip("/")


def stripe_configured() -> bool:
    return bool(STRIPE_SECRET_KEY)


def is_demo_customer_id(customer_id: str | None) -> bool:
    if not customer_id:
        return True
    value = customer_id.strip()
    return value.startswith("demo_cus_")


def get_stripe():
    if not STRIPE_SECRET_KEY:
        raise HTTPException(503, "STRIPE_SECRET_KEY no configurada")
    try:
        import stripe
    except ImportError as exc:
        raise HTTPException(
            503,
            "Paquete stripe no instalado. Ejecuta: pip install stripe",
        ) from exc
    stripe.api_key = STRIPE_SECRET_KEY
    return stripe


def plan_stripe_price_id(plan: Plan) -> str | None:
    features = plan.features or {}
    price_id = features.get("stripe_price_id")
    if isinstance(price_id, str) and price_id.startswith("price_"):
        return price_id
    return None


def ensure_stripe_customer(db: Session, user: User, sub: Subscription | None) -> str:
    stripe = get_stripe()
    if sub and sub.stripe_customer_id and not is_demo_customer_id(sub.stripe_customer_id):
        return sub.stripe_customer_id

    customer = stripe.Customer.create(
        email=user.email,
        name=user.full_name or user.email,
        metadata={"user_id": str(user.id), "app": "architect"},
    )
    if sub:
        sub.stripe_customer_id = customer.id
        db.commit()
    return customer.id


def build_checkout_line_item(plan: Plan) -> dict[str, Any]:
    price_id = plan_stripe_price_id(plan)
    if price_id:
        return {"price": price_id, "quantity": 1}
    return {
        "price_data": {
            "currency": STRIPE_CURRENCY,
            "unit_amount": plan.price_monthly_cents,
            "recurring": {"interval": "month"},
            "product_data": {
                "name": f"ARCHITECT — {plan.name}",
                "description": (plan.description or "")[:500],
                "metadata": {"plan_slug": plan.slug},
            },
        },
        "quantity": 1,
    }


def sync_plan_prices(db: Session) -> list[dict[str, Any]]:
    """Crea/actualiza productos y precios en Stripe; guarda stripe_price_id en plans.features."""
    stripe = get_stripe()
    results: list[dict[str, Any]] = []

    plans = (
        db.query(Plan)
        .filter(Plan.is_public.is_(True), Plan.price_monthly_cents > 0)
        .order_by(Plan.sort_order.asc())
        .all()
    )

    for plan in plans:
        features = dict(plan.features or {})
        existing_price_id = plan_stripe_price_id(plan)
        product_id = features.get("stripe_product_id")

        if existing_price_id:
            try:
                price = stripe.Price.retrieve(existing_price_id)
                product_id = str(price.product)
                if price.unit_amount != plan.price_monthly_cents:
                    price = stripe.Price.create(
                        product=product_id,
                        currency=STRIPE_CURRENCY,
                        unit_amount=plan.price_monthly_cents,
                        recurring={"interval": "month"},
                        metadata={"plan_slug": plan.slug},
                    )
                    features["stripe_price_id"] = price.id
                stripe.Product.modify(
                    product_id,
                    name=f"ARCHITECT — {plan.name}",
                    description=(plan.description or "")[:500],
                    metadata={"plan_slug": plan.slug},
                )
                results.append(
                    {
                        "slug": plan.slug,
                        "stripe_product_id": product_id,
                        "stripe_price_id": features.get("stripe_price_id", existing_price_id),
                        "action": "updated",
                    }
                )
            except Exception:
                existing_price_id = None
                features.pop("stripe_price_id", None)
                features.pop("stripe_product_id", None)

        if not existing_price_id:
            product = stripe.Product.create(
                name=f"ARCHITECT — {plan.name}",
                description=(plan.description or "")[:500],
                metadata={"plan_slug": plan.slug},
            )
            price = stripe.Price.create(
                product=product.id,
                currency=STRIPE_CURRENCY,
                unit_amount=plan.price_monthly_cents,
                recurring={"interval": "month"},
                metadata={"plan_slug": plan.slug},
            )
            features["stripe_product_id"] = product.id
            features["stripe_price_id"] = price.id
            results.append(
                {
                    "slug": plan.slug,
                    "stripe_product_id": product.id,
                    "stripe_price_id": price.id,
                    "action": "created",
                }
            )

        features["stripe_product_id"] = features.get("stripe_product_id") or product_id
        plan.features = features
        db.add(plan)

    db.commit()
    return results


def create_portal_session(db: Session, user: User, return_url: str | None = None) -> dict[str, str]:
    from services.subscription_service import get_user_subscription

    sub = get_user_subscription(db, user)
    if not sub or not sub.stripe_customer_id or is_demo_customer_id(sub.stripe_customer_id):
        raise HTTPException(
            400,
            "No tienes una suscripción de pago en Stripe. Contrata un plan de pago primero.",
        )
    if not sub.stripe_subscription_id or str(sub.stripe_subscription_id).startswith("demo_sub_"):
        raise HTTPException(400, "Tu suscripción activa no está vinculada a Stripe.")

    stripe = get_stripe()
    safe_return = return_url if return_url and return_url.startswith("/") else "/legacy-app"
    portal = stripe.billing_portal.Session.create(
        customer=sub.stripe_customer_id,
        return_url=f"{APP_BASE_URL}{safe_return}",
    )
    return {"url": portal.url}
