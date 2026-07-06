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
    parse_report_dates,
)

router = APIRouter(prefix="/api/admin", tags=["admin"])


class AdminUserUpdate(BaseModel):
    role: str | None = None
    is_active: bool | None = None


class AdminUserPlanUpdate(BaseModel):
    plan_slug: str = Field(min_length=2, max_length=32)


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
        "slug": plan.slug,
        "name": plan.name,
        "description": plan.description or "",
        "analyses_limit_monthly": plan.analyses_limit_monthly,
        "price_monthly_cents": plan.price_monthly_cents,
        "allow_real_model": plan.allow_real_model,
        "max_file_mb": plan.max_file_mb,
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

    if body.role is None and body.is_active is None:
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

