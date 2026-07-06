"""Planes, checkout demo/Stripe y suscripción."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Header, Request
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.deps import get_current_user
from api.schemas import (
    CheckoutCompleteRequest,
    CheckoutStartRequest,
    PlanChangeRequest,
    PortalStartRequest,
)
from db.database import get_db
from db.models import Plan, User
from services.billing_checkout_service import (
    billing_public_config,
    checkout_session_preview,
    complete_demo_checkout,
    complete_stripe_checkout,
    handle_stripe_webhook,
    start_billing_portal,
    start_checkout,
)
from services.billing_receipt_service import (
    export_user_receipts_zip,
    list_user_receipts,
    receipt_payload,
    receipt_pdf_bytes,
    resend_receipt_email,
)
from services.subscription_service import (
    change_plan,
    is_admin_user,
    subscription_payload,
    user_usage_history,
)

router = APIRouter(prefix="/api/billing", tags=["billing"])


@router.get("/config")
def billing_config():
    return billing_public_config()


@router.get("/plans")
def list_plans(db: Annotated[Session, Depends(get_db)]):
    plans = (
        db.query(Plan)
        .filter(Plan.is_public.is_(True))
        .order_by(Plan.sort_order.asc())
        .all()
    )
    return [
        {
            "slug": p.slug,
            "name": p.name,
            "description": p.description,
            "price_monthly_cents": p.price_monthly_cents,
            "analyses_limit_monthly": p.analyses_limit_monthly,
            "allow_real_model": p.allow_real_model,
            "max_file_mb": p.max_file_mb,
            "features": p.features or {},
            "requires_checkout": (p.price_monthly_cents or 0) > 0,
        }
        for p in plans
    ]


@router.get("/subscription")
def my_subscription(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return subscription_payload(db, user)


@router.post("/checkout")
def create_checkout(
    body: CheckoutStartRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Inicia checkout para planes de pago; el plan gratis se activa al instante."""
    return start_checkout(
        db,
        user,
        body.plan_slug.strip().lower(),
        return_url=body.return_url,
    )


@router.get("/checkout/session")
def get_checkout_session(
    token: str,
    db: Annotated[Session, Depends(get_db)],
):
    """Vista previa de la sesión (pasarela demo) sin exponer datos sensibles."""
    return checkout_session_preview(db, token)


@router.post("/checkout/complete")
def finish_demo_checkout(
    body: CheckoutCompleteRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Confirma pago en modo demo tras la pasarela simulada."""
    return complete_demo_checkout(db, user, body.session_token)


@router.get("/checkout/stripe/complete")
def finish_stripe_checkout(
    session_id: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return complete_stripe_checkout(db, session_id, user=user)


@router.post("/portal")
def open_billing_portal(
    body: PortalStartRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Portal de Stripe para actualizar tarjeta, cancelar o cambiar plan."""
    return start_billing_portal(db, user, return_url=body.return_url)


@router.post("/webhook/stripe")
async def stripe_webhook(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    stripe_signature: Annotated[str | None, Header(alias="Stripe-Signature")] = None,
):
    if not stripe_signature:
        from fastapi import HTTPException

        raise HTTPException(400, "Falta cabecera Stripe-Signature")
    payload = await request.body()
    return handle_stripe_webhook(db, payload, stripe_signature)


@router.get("/usage-history")
def my_usage_history(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    months: int = 6,
):
    """Uso mensual de análisis para gráfica en perfil."""
    return {"history": user_usage_history(db, user, months=months)}


@router.get("/receipts")
def my_receipts(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Historial de comprobantes de compra / cambio de plan."""
    return {"receipts": list_user_receipts(db, user.id)}


@router.get("/receipts/export/zip")
def export_receipts_zip(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Descarga todos los comprobantes del usuario en un ZIP."""
    filename, content = export_user_receipts_zip(db, user)
    return Response(
        content=content,
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/receipts/{receipt_id}")
def receipt_detail(
    receipt_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    from services.billing_receipt_service import get_user_receipt

    receipt = get_user_receipt(db, user.id, receipt_id)
    return receipt_payload(receipt)


@router.get("/receipts/{receipt_id}/pdf")
def download_receipt_pdf(
    receipt_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    filename, content = receipt_pdf_bytes(db, user, receipt_id)
    return Response(
        content=content,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "no-store, no-cache, must-revalidate",
            "Pragma": "no-cache",
        },
    )


@router.post("/receipts/{receipt_id}/email")
def email_receipt(
    receipt_id: int,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Reenvía el comprobante PDF al correo del usuario."""
    return resend_receipt_email(db, user, receipt_id)


@router.post("/change-plan")
def upgrade_plan(
    body: PlanChangeRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Solo baja a plan gratis o uso admin. Planes de pago → POST /checkout."""
    slug = body.plan_slug.strip().lower()
    if is_admin_user(user):
        return change_plan(db, user, slug, bypass_checkout=True)
    return change_plan(db, user, slug, bypass_checkout=False)
