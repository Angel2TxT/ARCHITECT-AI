"""Planes y cambio de suscripción (Stripe listo para conectar)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from api.deps import get_current_user
from api.schemas import PlanChangeRequest
from db.database import get_db
from db.models import Plan, User
from services.subscription_service import change_plan, subscription_payload

router = APIRouter(prefix="/api/billing", tags=["billing"])


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
        }
        for p in plans
    ]


@router.get("/subscription")
def my_subscription(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return subscription_payload(db, user)


@router.post("/change-plan")
def upgrade_plan(
    body: PlanChangeRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    """Cambio manual de plan (luego conectar Stripe Checkout)."""
    return change_plan(db, user, body.plan_slug.strip().lower())
