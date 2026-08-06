"""Panel admin: usuarios, métricas y gestión de la plataforma."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from api.deps import require_admin
from db.database import get_db
from db.models import (
    Analysis,
    BillingReceipt,
    Chat,
    GuestTrial,
    HomeProject,
    HomeProjectDocument,
    HomeProjectEvent,
    HomeProjectStatus,
    Message,
    Plan,
    Subscription,
    SubscriptionStatus,
    UsageRecord,
    User,
    UserRole,
)
from services.subscription_service import change_plan, period_key
from services.billing_receipt_service import admin_billing_summary, admin_receipts_list
from services.admin_report_service import (
    build_period_report,
    export_report,
    export_resource,
    parse_report_dates,
)
from services.auth_service import hash_password

router = APIRouter(prefix="/api/admin", tags=["admin"])


class AdminUserUpdate(BaseModel):
    role: str | None = None
    is_active: bool | None = None
    full_name: str | None = Field(default=None, max_length=120)
    email: str | None = Field(default=None, min_length=5, max_length=255)


class AdminUserPlanUpdate(BaseModel):
    plan_slug: str = Field(min_length=2, max_length=32)


class AdminUserCreate(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=6, max_length=128)
    full_name: str = Field(default="", max_length=120)
    role: str = "user"
    plan_slug: str = "free"
    is_active: bool = True


class AdminPlanUpsert(BaseModel):
    slug: str | None = Field(default=None, min_length=2, max_length=32)
    name: str = Field(min_length=2, max_length=80)
    description: str = ""
    price_monthly_cents: int = Field(default=0, ge=0)
    analyses_limit_monthly: int = Field(default=5, ge=0)
    allow_real_model: bool = False
    max_file_mb: int = Field(default=5, ge=1, le=500)
    is_public: bool = True
    sort_order: int = 0
    features: dict | None = None


class AdminSubscriptionUpdate(BaseModel):
    plan_slug: str | None = Field(default=None, min_length=2, max_length=32)
    status: str | None = None


def _safe_count(db: Session, model, *filters) -> int:
    try:
        q = db.query(func.count(model.id))
        for f in filters:
            q = q.filter(f)
        return int(q.scalar() or 0)
    except Exception:
        db.rollback()
        return 0


def _usage_map(db: Session, user_ids: list[int]) -> dict[int, int]:
    if not user_ids:
        return {}
    key = period_key()
    rows = (
        db.query(UsageRecord.user_id, UsageRecord.analyses_count)
        .filter(
            UsageRecord.user_id.in_(user_ids),
            UsageRecord.period_key == key,
        )
        .all()
    )
    return {uid: count for uid, count in rows}


def _user_item(
    db: Session, user: User, usage_map: dict[int, int] | None = None
) -> dict:
    sub = (
        db.query(Subscription)
        .options(joinedload(Subscription.plan))
        .filter(Subscription.user_id == user.id)
        .first()
    )
    plan = sub.plan if sub else None
    if usage_map is not None:
        used = usage_map.get(user.id, 0)
    else:
        row = (
            db.query(UsageRecord.analyses_count)
            .filter(
                UsageRecord.user_id == user.id,
                UsageRecord.period_key == period_key(),
            )
            .first()
        )
        used = int(row[0]) if row else 0
    return {
        "id": user.id,
        "email": user.email,
        "full_name": user.full_name,
        "role": user.role.value,
        "is_active": user.is_active,
        "oauth_provider": user.oauth_provider,
        "avatar_url": user.avatar_url,
        "created_at": user.created_at.isoformat() if user.created_at else None,
        "plan_slug": plan.slug if plan else None,
        "plan_name": plan.name if plan else None,
        "analyses_used": used,
        "analyses_limit": plan.analyses_limit_monthly if plan else None,
    }


def _plan_item(db: Session, plan: Plan) -> dict:
    subscribers = (
        db.query(func.count(Subscription.id))
        .filter(Subscription.plan_id == plan.id)
        .scalar()
        or 0
    )
    return {
        "id": plan.id,
        "slug": plan.slug,
        "name": plan.name,
        "description": plan.description or "",
        "analyses_limit_monthly": plan.analyses_limit_monthly,
        "price_monthly_cents": plan.price_monthly_cents,
        "allow_real_model": plan.allow_real_model,
        "max_file_mb": plan.max_file_mb,
        "storage_gb": (plan.features or {}).get("storage_gb", 1),
        "is_public": plan.is_public,
        "sort_order": plan.sort_order,
        "subscribers": int(subscribers),
        "features": plan.features or {},
    }


@router.get("/stats")
def stats(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    users = _safe_count(db, User)
    active_users = _safe_count(db, User, User.is_active.is_(True))
    admins = _safe_count(db, User, User.role == UserRole.admin)
    google_users = _safe_count(db, User, User.oauth_provider == "google")
    analyses = _safe_count(db, Analysis)
    training = _safe_count(db, Analysis, Analysis.training_eligible.is_(True))
    demo_analyses = _safe_count(db, Analysis, Analysis.is_demo_model.is_(True))
    projects = _safe_count(db, HomeProject)
    active_projects = _safe_count(
        db, HomeProject, HomeProject.status == HomeProjectStatus.active
    )
    chats = _safe_count(db, Chat)
    messages = _safe_count(db, Message)
    guest_trials = _safe_count(db, GuestTrial)
    documents = _safe_count(db, HomeProjectDocument)
    events = _safe_count(db, HomeProjectEvent)
    subscriptions_active = _safe_count(
        db, Subscription, Subscription.status == SubscriptionStatus.active
    )

    key = period_key()
    usage_month = (
        db.query(func.coalesce(func.sum(UsageRecord.analyses_count), 0))
        .filter(UsageRecord.period_key == key)
        .scalar()
        or 0
    )

    plan_rows = (
        db.query(Plan.slug, Plan.name, func.count(Subscription.id))
        .outerjoin(Subscription, Subscription.plan_id == Plan.id)
        .group_by(Plan.id, Plan.slug, Plan.name)
        .order_by(Plan.sort_order.asc())
        .all()
    )

    since_7d = datetime.utcnow() - timedelta(days=7)
    since_30d = datetime.utcnow() - timedelta(days=30)
    users_new_7d = _safe_count(db, User, User.created_at >= since_7d)
    users_new_30d = _safe_count(db, User, User.created_at >= since_30d)
    users_inactive = max(users - active_users, 0)
    analyses_real = max(analyses - demo_analyses, 0)
    home_completed = _safe_count(
        db, HomeProject, HomeProject.status == HomeProjectStatus.completed
    )
    paid_subscribers = (
        db.query(func.count(Subscription.id))
        .join(Plan, Subscription.plan_id == Plan.id)
        .filter(
            Subscription.status == SubscriptionStatus.active,
            Plan.slug != "free",
        )
        .scalar()
        or 0
    )
    billing_receipts_total = int(
        db.query(func.count(BillingReceipt.id)).scalar() or 0
    )
    billing_simulated_revenue_cents = int(
        db.query(func.coalesce(func.sum(BillingReceipt.amount_cents), 0)).scalar() or 0
    )
    billing_by_plan_rows = (
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
    billing_by_plan = [
        {
            "plan_slug": slug,
            "plan_name": name,
            "receipts_count": int(count or 0),
            "simulated_revenue_cents": int(cents or 0),
        }
        for slug, name, count, cents in billing_by_plan_rows
    ]
    guest_analyses = int(
        db.query(func.coalesce(func.sum(GuestTrial.analyses_count), 0)).scalar() or 0
    )
    guest_asks = int(
        db.query(func.coalesce(func.sum(GuestTrial.asks_count), 0)).scalar() or 0
    )

    recent_users = (
        db.query(User)
        .order_by(User.created_at.desc())
        .limit(5)
        .all()
    )
    recent_analyses = (
        db.query(Analysis)
        .options(joinedload(Analysis.user))
        .order_by(Analysis.created_at.desc())
        .limit(5)
        .all()
    )
    recent_events = (
        db.query(HomeProjectEvent)
        .options(
            joinedload(HomeProjectEvent.project),
            joinedload(HomeProjectEvent.actor),
        )
        .order_by(HomeProjectEvent.created_at.desc())
        .limit(8)
        .all()
    )

    plans_breakdown = []
    for slug, name, count in plan_rows:
        subs = int(count or 0)
        plans_breakdown.append(
            {
                "slug": slug,
                "name": name,
                "subscribers": subs,
                "share_pct": round((subs / users) * 100, 1) if users else 0,
            }
        )

    return {
        "users": users,
        "users_active": active_users,
        "users_inactive": users_inactive,
        "users_admin": admins,
        "users_google": google_users,
        "users_email": max(users - google_users, 0),
        "users_new_7d": users_new_7d,
        "users_new_30d": users_new_30d,
        "analyses_total": analyses,
        "analyses_training_eligible": training,
        "analyses_demo": demo_analyses,
        "analyses_real": analyses_real,
        "analyses_this_month": int(usage_month),
        "home_projects": projects,
        "home_projects_active": active_projects,
        "home_projects_completed": home_completed,
        "home_documents": documents,
        "home_events": events,
        "chats": chats,
        "messages": messages,
        "guest_trials": guest_trials,
        "guest_trial_analyses": guest_analyses,
        "guest_trial_asks": guest_asks,
        "subscriptions_active": subscriptions_active,
        "paid_subscribers": int(paid_subscribers),
        "billing_receipts_total": billing_receipts_total,
        "billing_simulated_revenue_cents": billing_simulated_revenue_cents,
        "billing_by_plan": billing_by_plan,
        "period_key": key,
        "plans_breakdown": plans_breakdown,
        "recent_users": [
            {
                "id": u.id,
                "email": u.email,
                "full_name": u.full_name,
                "role": u.role.value,
                "oauth_provider": u.oauth_provider,
                "created_at": u.created_at.isoformat() if u.created_at else None,
            }
            for u in recent_users
        ],
        "recent_analyses": [
            {
                "id": a.id,
                "user_email": a.user.email if a.user else None,
                "original_filename": a.original_filename,
                "is_demo_model": a.is_demo_model,
                "created_at": a.created_at.isoformat() if a.created_at else None,
            }
            for a in recent_analyses
        ],
        "recent_activity": [
            {
                "id": e.id,
                "project_id": e.project_id,
                "project_name": e.project.name if e.project else None,
                "event_type": e.event_type.value,
                "actor_email": e.actor.email if e.actor else None,
                "created_at": e.created_at.isoformat() if e.created_at else None,
            }
            for e in recent_events
        ],
    }


@router.get("/users")
def list_users(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 100,
    offset: int = 0,
    q: str | None = None,
):
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    query = db.query(User)
    if q and q.strip():
        term = f"%{q.strip().lower()}%"
        query = query.filter(
            func.lower(User.email).like(term)
            | func.lower(User.full_name).like(term)
        )
    total = query.count()
    rows = query.order_by(User.created_at.desc()).offset(offset).limit(limit).all()
    usage_map = _usage_map(db, [u.id for u in rows])
    return {
        "total": total,
        "items": [_user_item(db, u, usage_map) for u in rows],
    }


@router.get("/plans")
def list_plans(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    plans = db.query(Plan).order_by(Plan.sort_order.asc()).all()
    return [_plan_item(db, p) for p in plans]


@router.get("/subscriptions")
def list_subscriptions(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 100,
    offset: int = 0,
):
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    base = db.query(Subscription).options(
        joinedload(Subscription.plan),
        joinedload(Subscription.user),
    )
    total = base.count()
    rows = (
        base.order_by(Subscription.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {
        "total": total,
        "items": [
            {
                "id": s.id,
                "user_id": s.user_id,
                "user_email": s.user.email if s.user else None,
                "user_name": s.user.full_name if s.user else "",
                "plan_slug": s.plan.slug if s.plan else None,
                "plan_name": s.plan.name if s.plan else None,
                "status": s.status.value,
                "current_period_start": s.current_period_start.isoformat()
                if s.current_period_start
                else None,
                "current_period_end": s.current_period_end.isoformat()
                if s.current_period_end
                else None,
                "stripe_customer_id": s.stripe_customer_id,
                "created_at": s.created_at.isoformat() if s.created_at else None,
            }
            for s in rows
        ],
    }


@router.get("/analyses")
def list_analyses(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 50,
    offset: int = 0,
):
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    base = db.query(Analysis).options(joinedload(Analysis.user))
    total = base.count()
    rows = (
        base.order_by(Analysis.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {
        "total": total,
        "items": [
            {
                "id": a.id,
                "user_id": a.user_id,
                "user_email": a.user.email if a.user else None,
                "original_filename": a.original_filename,
                "status_text": a.status_text,
                "is_demo_model": a.is_demo_model,
                "training_eligible": a.training_eligible,
                "created_at": a.created_at.isoformat() if a.created_at else None,
            }
            for a in rows
        ],
    }


@router.get("/home-projects")
def list_home_projects(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 50,
    offset: int = 0,
):
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    base = db.query(HomeProject).options(joinedload(HomeProject.user))
    total = base.count()
    rows = (
        base.order_by(HomeProject.updated_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    project_ids = [p.id for p in rows]
    doc_counts: dict[str, int] = {}
    if project_ids:
        for pid, count in (
            db.query(HomeProjectDocument.project_id, func.count(HomeProjectDocument.id))
            .filter(HomeProjectDocument.project_id.in_(project_ids))
            .group_by(HomeProjectDocument.project_id)
            .all()
        ):
            doc_counts[pid] = int(count)
    return {
        "total": total,
        "items": [
            {
                "id": p.id,
                "name": p.name,
                "client_name": p.client_name,
                "location": p.location,
                "status": p.status.value,
                "current_stage": p.current_stage,
                "user_id": p.user_id,
                "owner_email": p.user.email if p.user else None,
                "documents_count": doc_counts.get(p.id, 0),
                "created_at": p.created_at.isoformat() if p.created_at else None,
                "updated_at": p.updated_at.isoformat() if p.updated_at else None,
            }
            for p in rows
        ],
    }


@router.get("/activity")
def list_activity(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 80,
    offset: int = 0,
):
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    base = db.query(HomeProjectEvent).options(
        joinedload(HomeProjectEvent.project),
        joinedload(HomeProjectEvent.actor),
    )
    total = base.count()
    rows = (
        base.order_by(HomeProjectEvent.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {
        "total": total,
        "items": [
            {
                "id": e.id,
                "project_id": e.project_id,
                "project_name": e.project.name if e.project else None,
                "event_type": e.event_type.value,
                "actor_email": e.actor.email if e.actor else None,
                "section_id": e.section_id,
                "created_at": e.created_at.isoformat() if e.created_at else None,
                "metadata": e.metadata_json or {},
            }
            for e in rows
        ],
    }


@router.get("/chats")
def list_chats(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 50,
    offset: int = 0,
):
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    base = db.query(Chat).options(joinedload(Chat.user))
    total = base.count()
    rows = (
        base.order_by(Chat.updated_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    chat_ids = [c.id for c in rows]
    msg_counts: dict[str, int] = {}
    if chat_ids:
        for cid, count in (
            db.query(Message.chat_id, func.count(Message.id))
            .filter(Message.chat_id.in_(chat_ids))
            .group_by(Message.chat_id)
            .all()
        ):
            msg_counts[cid] = int(count)
    return {
        "total": total,
        "items": [
            {
                "id": c.id,
                "user_id": c.user_id,
                "user_email": c.user.email if c.user else None,
                "title": c.title,
                "messages_count": msg_counts.get(c.id, 0),
                "created_at": c.created_at.isoformat() if c.created_at else None,
                "updated_at": c.updated_at.isoformat() if c.updated_at else None,
            }
            for c in rows
        ],
    }


@router.get("/guest-trials")
def list_guest_trials(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 50,
    offset: int = 0,
):
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    base = db.query(GuestTrial)
    total = base.count()
    rows = (
        base.order_by(GuestTrial.last_seen_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return {
        "total": total,
        "items": [
            {
                "id": g.id,
                "analyses_count": g.analyses_count,
                "asks_count": g.asks_count,
                "created_at": g.created_at.isoformat() if g.created_at else None,
                "last_seen_at": g.last_seen_at.isoformat() if g.last_seen_at else None,
            }
            for g in rows
        ],
        "totals": {
            "analyses": int(
                db.query(func.coalesce(func.sum(GuestTrial.analyses_count), 0)).scalar()
                or 0
            ),
            "asks": int(
                db.query(func.coalesce(func.sum(GuestTrial.asks_count), 0)).scalar()
                or 0
            ),
        },
    }


@router.patch("/users/{user_id}")
def update_user(
    user_id: int,
    body: AdminUserUpdate,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "Usuario no encontrado")

    if body.role is not None:
        try:
            new_role = UserRole(body.role)
        except ValueError as exc:
            raise HTTPException(400, "Rol inválido") from exc
        if user.id == admin.id and new_role != UserRole.admin:
            raise HTTPException(400, "No puedes quitarte el rol de administrador")
        user.role = new_role

    if body.is_active is not None:
        if user.id == admin.id and not body.is_active:
            raise HTTPException(400, "No puedes desactivar tu propia cuenta")
        user.is_active = body.is_active

    if body.full_name is not None:
        user.full_name = body.full_name.strip()

    if body.email is not None:
        email = body.email.strip().lower()
        if "@" not in email:
            raise HTTPException(400, "Correo inválido")
        taken = (
            db.query(User)
            .filter(User.email == email, User.id != user.id)
            .first()
        )
        if taken:
            raise HTTPException(400, "Ese correo ya está en uso")
        user.email = email

    if (
        body.role is None
        and body.is_active is None
        and body.full_name is None
        and body.email is None
    ):
        raise HTTPException(400, "Nada que actualizar")

    db.commit()
    db.refresh(user)
    return _user_item(db, user)


@router.post("/users/{user_id}/plan")
def set_user_plan(
    user_id: int,
    body: AdminUserPlanUpdate,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    change_plan(db, user, body.plan_slug.strip().lower(), bypass_checkout=True)
    db.refresh(user)
    return _user_item(db, user)


@router.post("/users/{user_id}/reset-usage")
def reset_user_usage(
    user_id: int,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    key = period_key()
    row = (
        db.query(UsageRecord)
        .filter(UsageRecord.user_id == user.id, UsageRecord.period_key == key)
        .first()
    )
    if row:
        row.analyses_count = 0
    else:
        db.add(UsageRecord(user_id=user.id, period_key=key, analyses_count=0))
    db.commit()
    return _user_item(db, user)


@router.delete("/users/{user_id}")
def delete_user(
    user_id: int,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    if user_id == admin.id:
        raise HTTPException(400, "No puedes eliminar tu propia cuenta desde el panel")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "Usuario no encontrado")

    if user.role == UserRole.admin:
        admins = (
            db.query(func.count(User.id))
            .filter(User.role == UserRole.admin)
            .scalar()
            or 0
        )
        if admins <= 1:
            raise HTTPException(400, "No puedes eliminar al único administrador")

    db.delete(user)
    db.commit()
    return {"ok": True, "deleted_id": user_id}


@router.get("/reports/summary")
def download_summary_report(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    date_from: str = Query(..., alias="from", min_length=10, max_length=10),
    date_to: str = Query(..., alias="to", min_length=10, max_length=10),
    format: str = Query("csv", pattern="^(csv|pdf|xlsx|excel)$"),
):
    try:
        start, end = parse_report_dates(date_from, date_to)
        report = build_period_report(db, start, end)
        content, filename, media_type = export_report(report, format)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc

    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/billing/summary")
def admin_billing_summary_route(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    """Totales de comprobantes y ventas simuladas por plan."""
    return admin_billing_summary(db)


@router.get("/billing/receipts")
def admin_billing_receipts(
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """Listado de comprobantes emitidos (pasarela simulada)."""
    return admin_receipts_list(db, limit=limit, offset=offset)


@router.get("/export/{resource}")
def download_resource_export(
    resource: str,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
    format: str = Query("csv", pattern="^(csv|pdf|xlsx|excel)$"),
):
    try:
        content, filename, media_type = export_resource(db, resource, format)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/users")
def create_user(
    body: AdminUserCreate,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    email = body.email.strip().lower()
    if "@" not in email:
        raise HTTPException(400, "Correo inválido")
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(409, "Ya existe un usuario con ese correo")
    try:
        role = UserRole(body.role)
    except ValueError as exc:
        raise HTTPException(400, "Rol inválido") from exc

    user = User(
        email=email,
        password_hash=hash_password(body.password),
        full_name=(body.full_name or "").strip(),
        role=role,
        is_active=body.is_active,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    change_plan(db, user, (body.plan_slug or "free").strip().lower(), bypass_checkout=True)
    return _user_item(db, user)


@router.post("/plans")
def create_plan(
    body: AdminPlanUpsert,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    slug = (body.slug or body.name).strip().lower().replace(" ", "-")
    slug = "".join(ch for ch in slug if ch.isalnum() or ch in "-_")[:32]
    if len(slug) < 2:
        raise HTTPException(400, "Slug inválido")
    if db.query(Plan).filter(Plan.slug == slug).first():
        raise HTTPException(409, "Ya existe un plan con ese slug")
    plan = Plan(
        slug=slug,
        name=body.name.strip(),
        description=body.description or "",
        price_monthly_cents=body.price_monthly_cents,
        analyses_limit_monthly=body.analyses_limit_monthly,
        allow_real_model=body.allow_real_model,
        max_file_mb=body.max_file_mb,
        is_public=body.is_public,
        sort_order=body.sort_order,
        features=body.features or {},
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return _plan_item(db, plan)


@router.patch("/plans/{plan_id}")
def update_plan(
    plan_id: int,
    body: AdminPlanUpsert,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    plan = db.query(Plan).filter(Plan.id == plan_id).first()
    if not plan:
        raise HTTPException(404, "Plan no encontrado")
    plan.name = body.name.strip()
    plan.description = body.description or ""
    plan.price_monthly_cents = body.price_monthly_cents
    plan.analyses_limit_monthly = body.analyses_limit_monthly
    plan.allow_real_model = body.allow_real_model
    plan.max_file_mb = body.max_file_mb
    plan.is_public = body.is_public
    plan.sort_order = body.sort_order
    if body.features is not None:
        merged = dict(plan.features or {})
        merged.update(body.features)
        # Preserve stripe ids if omitted
        for sticky in ("stripe_price_id", "stripe_product_id"):
            if sticky in (plan.features or {}) and sticky not in body.features:
                merged[sticky] = plan.features[sticky]
        plan.features = merged
    db.commit()
    db.refresh(plan)
    return _plan_item(db, plan)


@router.delete("/plans/{plan_id}")
def deactivate_plan(
    plan_id: int,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    """No borra el plan si tiene suscriptores: lo oculta (is_public=false)."""
    plan = db.query(Plan).filter(Plan.id == plan_id).first()
    if not plan:
        raise HTTPException(404, "Plan no encontrado")
    if plan.slug == "free":
        raise HTTPException(400, "No se puede desactivar el plan Gratis")
    subs = (
        db.query(func.count(Subscription.id)).filter(Subscription.plan_id == plan.id).scalar()
        or 0
    )
    if subs:
        plan.is_public = False
        db.commit()
        return {"ok": True, "action": "hidden", "subscribers": int(subs), "plan": _plan_item(db, plan)}
    db.delete(plan)
    db.commit()
    return {"ok": True, "action": "deleted", "plan_id": plan_id}


@router.patch("/subscriptions/{subscription_id}")
def update_subscription(
    subscription_id: int,
    body: AdminSubscriptionUpdate,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    sub = (
        db.query(Subscription)
        .options(joinedload(Subscription.user), joinedload(Subscription.plan))
        .filter(Subscription.id == subscription_id)
        .first()
    )
    if not sub or not sub.user:
        raise HTTPException(404, "Suscripción no encontrada")
    if body.plan_slug:
        change_plan(db, sub.user, body.plan_slug.strip().lower(), bypass_checkout=True)
        db.refresh(sub)
    if body.status is not None:
        try:
            sub.status = SubscriptionStatus(body.status)
        except ValueError as exc:
            raise HTTPException(400, "Estado inválido") from exc
        db.commit()
        db.refresh(sub)
    return {
        "id": sub.id,
        "user_id": sub.user_id,
        "user_email": sub.user.email if sub.user else None,
        "plan_slug": sub.plan.slug if sub.plan else None,
        "plan_name": sub.plan.name if sub.plan else None,
        "status": sub.status.value,
    }


@router.get("/analyses/{analysis_id}")
def get_analysis(
    analysis_id: int,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    a = (
        db.query(Analysis)
        .options(joinedload(Analysis.user))
        .filter(Analysis.id == analysis_id)
        .first()
    )
    if not a:
        raise HTTPException(404, "Análisis no encontrado")
    return {
        "id": a.id,
        "user_id": a.user_id,
        "user_email": a.user.email if a.user else None,
        "original_filename": a.original_filename,
        "status_text": a.status_text,
        "is_demo_model": a.is_demo_model,
        "training_eligible": a.training_eligible,
        "created_at": a.created_at.isoformat() if a.created_at else None,
        "counts": a.counts_json,
        "issues_count": len(a.issues_json or []),
        "detections_count": len(a.detections_json or []),
    }


@router.delete("/analyses/{analysis_id}")
def delete_analysis(
    analysis_id: int,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    a = db.query(Analysis).filter(Analysis.id == analysis_id).first()
    if not a:
        raise HTTPException(404, "Análisis no encontrado")
    db.delete(a)
    db.commit()
    return {"ok": True, "deleted_id": analysis_id}


@router.get("/chats/{chat_id}")
def get_chat(
    chat_id: str,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    chat = (
        db.query(Chat)
        .options(joinedload(Chat.user))
        .filter(Chat.id == chat_id)
        .first()
    )
    if not chat:
        raise HTTPException(404, "Chat no encontrado")
    messages = (
        db.query(Message)
        .filter(Message.chat_id == chat.id)
        .order_by(Message.created_at.asc())
        .limit(200)
        .all()
    )
    return {
        "id": chat.id,
        "title": chat.title,
        "user_email": chat.user.email if chat.user else None,
        "created_at": chat.created_at.isoformat() if chat.created_at else None,
        "messages": [
            {
                "id": m.id,
                "role": m.role,
                "content": m.content,
                "created_at": m.created_at.isoformat() if m.created_at else None,
            }
            for m in messages
        ],
    }


@router.delete("/chats/{chat_id}")
def delete_chat(
    chat_id: str,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if not chat:
        raise HTTPException(404, "Chat no encontrado")
    db.query(Message).filter(Message.chat_id == chat.id).delete(synchronize_session=False)
    db.delete(chat)
    db.commit()
    return {"ok": True, "deleted_id": chat_id}


@router.delete("/home-projects/{project_id}")
def delete_home_project(
    project_id: str,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    project = db.query(HomeProject).filter(HomeProject.id == project_id).first()
    if not project:
        raise HTTPException(404, "Proyecto no encontrado")
    db.delete(project)
    db.commit()
    return {"ok": True, "deleted_id": project_id}


@router.post("/guest-trials/{trial_id}/reset")
def reset_guest_trial(
    trial_id: str,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    trial = db.query(GuestTrial).filter(GuestTrial.id == trial_id).first()
    if not trial:
        raise HTTPException(404, "Invitado no encontrado")
    trial.analyses_count = 0
    trial.asks_count = 0
    db.commit()
    return {
        "ok": True,
        "id": trial.id,
        "analyses_count": 0,
        "asks_count": 0,
    }


@router.delete("/guest-trials/{trial_id}")
def delete_guest_trial(
    trial_id: str,
    _: Annotated[User, Depends(require_admin)],
    db: Annotated[Session, Depends(get_db)],
):
    trial = db.query(GuestTrial).filter(GuestTrial.id == trial_id).first()
    if not trial:
        raise HTTPException(404, "Invitado no encontrado")
    db.delete(trial)
    db.commit()
    return {"ok": True, "deleted_id": trial_id}

