"""Modelos MySQL: usuarios, suscripciones, chats, análisis."""

from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.mysql import JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from db.database import Base


class UserRole(str, enum.Enum):
    admin = "admin"
    support = "support"
    user = "user"


class SubscriptionStatus(str, enum.Enum):
    active = "active"
    trialing = "trialing"
    past_due = "past_due"
    canceled = "canceled"
    expired = "expired"


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("oauth_provider", "oauth_subject", name="uq_users_oauth"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    full_name: Mapped[str] = mapped_column(String(120), default="")
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole), default=UserRole.user, index=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    oauth_provider: Mapped[str | None] = mapped_column(String(32), nullable=True)
    oauth_subject: Mapped[str | None] = mapped_column(String(128), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    subscription: Mapped[Subscription | None] = relationship(
        back_populates="user", uselist=False
    )
    chats: Mapped[list[Chat]] = relationship(back_populates="user")
    analyses: Mapped[list[Analysis]] = relationship(back_populates="user")
    usage_records: Mapped[list[UsageRecord]] = relationship(back_populates="user")
    home_projects: Mapped[list[HomeProject]] = relationship(back_populates="user")
    billing_receipts: Mapped[list["BillingReceipt"]] = relationship(back_populates="user")
    support_tickets: Mapped[list["SupportTicket"]] = relationship(
        back_populates="user",
        foreign_keys="SupportTicket.user_id",
    )
    refund_requests: Mapped[list["RefundRequest"]] = relationship(
        back_populates="user",
        foreign_keys="RefundRequest.user_id",
    )


class Plan(Base):
    __tablename__ = "plans"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    slug: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(Text, default="")
    price_monthly_cents: Mapped[int] = mapped_column(Integer, default=0)
    analyses_limit_monthly: Mapped[int] = mapped_column(Integer, default=0)
    allow_real_model: Mapped[bool] = mapped_column(Boolean, default=False)
    max_file_mb: Mapped[int] = mapped_column(Integer, default=10)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    features: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    subscriptions: Mapped[list[Subscription]] = relationship(back_populates="plan")


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("plans.id"))
    status: Mapped[SubscriptionStatus] = mapped_column(
        Enum(SubscriptionStatus), default=SubscriptionStatus.active
    )
    current_period_start: Mapped[datetime] = mapped_column(DateTime)
    current_period_end: Mapped[datetime] = mapped_column(DateTime)
    stripe_customer_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    stripe_subscription_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    canceled_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )

    user: Mapped[User] = relationship(back_populates="subscription")
    plan: Mapped[Plan] = relationship(back_populates="subscriptions")


class BillingReceipt(Base):
    """Comprobante / ticket de cambio de plan o compra simulada."""

    __tablename__ = "billing_receipts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    receipt_number: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    plan_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("plans.id"), nullable=True)
    plan_slug: Mapped[str] = mapped_column(String(32), default="")
    plan_name: Mapped[str] = mapped_column(String(80), default="")
    amount_cents: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(8), default="MXN")
    billing_mode: Mapped[str] = mapped_column(String(16), default="demo")
    payment_ref: Mapped[str | None] = mapped_column(String(128), nullable=True)
    period_start: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    period_end: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    email_sent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped[User] = relationship(back_populates="billing_receipts")
    plan: Mapped[Plan | None] = relationship()


class UsageRecord(Base):
    """Contador de análisis y preguntas por usuario y período (YYYY-MM)."""

    __tablename__ = "usage_records"
    __table_args__ = (UniqueConstraint("user_id", "period_key", name="uq_usage_period"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    period_key: Mapped[str] = mapped_column(String(7), index=True)
    analyses_count: Mapped[int] = mapped_column(Integer, default=0)
    asks_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="usage_records")


class Chat(Base):
    __tablename__ = "chats"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(120), default="Nuevo chat")
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now(), index=True
    )

    user: Mapped[User] = relationship(back_populates="chats")
    messages: Mapped[list[Message]] = relationship(
        back_populates="chat", order_by="Message.created_at"
    )


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    chat_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("chats.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[str] = mapped_column(String(16))
    content: Mapped[dict] = mapped_column(JSON)
    analysis_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("analyses.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )

    chat: Mapped[Chat] = relationship(back_populates="messages")
    analysis: Mapped[Analysis | None] = relationship(back_populates="message")


class GuestTrial(Base):
    """Uso de prueba sin cuenta (identificado por cookie)."""

    __tablename__ = "guest_trials"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    analyses_count: Mapped[int] = mapped_column(Integer, default=0)
    asks_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )


class Analysis(Base):
    """Cada validación guardada para historial y futuro entrenamiento."""

    __tablename__ = "analyses"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    chat_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("chats.id", ondelete="SET NULL"), nullable=True
    )
    original_filename: Mapped[str] = mapped_column(String(255), default="plano.png")
    source_path: Mapped[str] = mapped_column(String(512))
    annotated_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
    weights_path: Mapped[str] = mapped_column(String(512), default="")
    pixels_per_meter: Mapped[float] = mapped_column(default=100.0)
    confidence: Mapped[float] = mapped_column(default=0.25)
    user_prompt: Mapped[str] = mapped_column(Text, default="")
    status_text: Mapped[str] = mapped_column(String(255), default="")
    is_demo_model: Mapped[bool] = mapped_column(Boolean, default=False)
    detections_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
    issues_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
    counts_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    corrections_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
    training_eligible: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )

    user: Mapped[User] = relationship(back_populates="analyses")
    message: Mapped[Message | None] = relationship(back_populates="analysis")


class HomeProjectStatus(str, enum.Enum):
    active = "active"
    on_hold = "on_hold"
    completed = "completed"
    canceled = "canceled"


class HomeStageStatus(str, enum.Enum):
    pending = "pending"
    in_progress = "in_progress"
    completed = "completed"
    blocked = "blocked"


class HomeProject(Base):
    """Proyecto de construcción de casa hogar (9 etapas metodológicas)."""

    __tablename__ = "home_projects"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(160))
    client_name: Mapped[str] = mapped_column(String(120), default="")
    location: Mapped[str] = mapped_column(String(200), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[HomeProjectStatus] = mapped_column(
        Enum(HomeProjectStatus), default=HomeProjectStatus.active, index=True
    )
    current_stage: Mapped[int] = mapped_column(Integer, default=1)
    metadata_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    user: Mapped[User] = relationship(back_populates="home_projects")
    stages: Mapped[list[HomeProjectStage]] = relationship(
        back_populates="project",
        order_by="HomeProjectStage.stage_number",
        cascade="all, delete-orphan",
    )
    documents: Mapped[list[HomeProjectDocument]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
    )
    sections: Mapped[list["HomeProjectSection"]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
        order_by="HomeProjectSection.sort_order",
    )
    members: Mapped[list["HomeProjectMember"]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
    )
    ai_reviews: Mapped[list["HomeProjectAiReview"]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
    )


class HomeProjectSectionStatus(str, enum.Enum):
    pending = "pending"
    in_progress = "in_progress"
    needs_details = "needs_details"
    needs_correction = "needs_correction"
    completed = "completed"


class HomeProjectMemberRole(str, enum.Enum):
    editor = "editor"
    viewer = "viewer"


class HomeProjectSection(Base):
    """Apartado documental por etapa (plantilla del catálogo o creado por el equipo)."""

    __tablename__ = "home_project_sections"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("home_projects.id", ondelete="CASCADE"), index=True
    )
    stage_number: Mapped[int] = mapped_column(Integer, index=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text, default="")
    catalog_key: Mapped[str | None] = mapped_column(String(80), nullable=True, index=True)
    slots_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[HomeProjectSectionStatus] = mapped_column(
        Enum(HomeProjectSectionStatus), default=HomeProjectSectionStatus.pending
    )
    created_by: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    assigned_to_user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    is_catalog: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    project: Mapped[HomeProject] = relationship(back_populates="sections")
    assignee: Mapped[User | None] = relationship(foreign_keys=[assigned_to_user_id])
    documents: Mapped[list["HomeProjectDocument"]] = relationship(
        back_populates="section",
        cascade="all, delete-orphan",
    )
    comments: Mapped[list["HomeProjectSectionComment"]] = relationship(
        back_populates="section",
        cascade="all, delete-orphan",
        order_by="HomeProjectSectionComment.created_at",
    )


class HomeProjectSectionComment(Base):
    """Comentarios en un apartado (estilo hilo de revisión)."""

    __tablename__ = "home_project_section_comments"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    section_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("home_project_sections.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    section: Mapped[HomeProjectSection] = relationship(back_populates="comments")
    author: Mapped[User] = relationship()


class HomeProjectEventType(str, enum.Enum):
    section_assigned = "section_assigned"
    section_status_changed = "section_status_changed"
    section_reopened = "section_reopened"
    section_comment_added = "section_comment_added"
    section_comment_deleted = "section_comment_deleted"
    document_uploaded = "document_uploaded"
    document_deleted = "document_deleted"
    member_invited = "member_invited"
    member_joined = "member_joined"
    member_removed = "member_removed"
    stage_completed = "stage_completed"
    stage_reopened = "stage_reopened"
    stage_advanced = "stage_advanced"
    ai_review_created = "ai_review_created"
    ai_finding_updated = "ai_finding_updated"


class HomeProjectAiReviewStatus(str, enum.Enum):
    open = "open"
    resolved = "resolved"
    dismissed = "dismissed"


class HomeProjectAiReview(Base):
    """Paquete de revisión IA de un plano ligado a un entregable del expediente."""

    __tablename__ = "home_project_ai_reviews"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("home_projects.id", ondelete="CASCADE"), index=True
    )
    stage_number: Mapped[int] = mapped_column(Integer, index=True)
    section_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("home_project_sections.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    document_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("home_project_documents.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    analysis_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("analyses.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_by: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    status: Mapped[HomeProjectAiReviewStatus] = mapped_column(
        Enum(HomeProjectAiReviewStatus),
        default=HomeProjectAiReviewStatus.open,
        index=True,
    )
    scope_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    exclusions_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
    verdict_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    findings_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    project: Mapped[HomeProject] = relationship(back_populates="ai_reviews")
    section: Mapped[HomeProjectSection | None] = relationship()
    document: Mapped[HomeProjectDocument | None] = relationship()
    analysis: Mapped[Analysis | None] = relationship()
    creator: Mapped[User | None] = relationship(foreign_keys=[created_by])


class HomeProjectEvent(Base):
    """Auditoría de actividades en un proyecto (estilo GitHub)."""

    __tablename__ = "home_project_events"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("home_projects.id", ondelete="CASCADE"), index=True
    )
    actor_user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    event_type: Mapped[HomeProjectEventType] = mapped_column(
        Enum(HomeProjectEventType), index=True
    )
    section_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("home_project_sections.id", ondelete="SET NULL"), nullable=True, index=True
    )
    document_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("home_project_documents.id", ondelete="SET NULL"), nullable=True, index=True
    )
    comment_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("home_project_section_comments.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    metadata_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )

    project: Mapped[HomeProject] = relationship()
    actor: Mapped[User | None] = relationship(foreign_keys=[actor_user_id])
    section: Mapped[HomeProjectSection | None] = relationship(foreign_keys=[section_id])


class HomeProjectMember(Base):
    __tablename__ = "home_project_members"
    __table_args__ = (
        UniqueConstraint("project_id", "user_id", name="uq_home_project_member"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("home_projects.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[HomeProjectMemberRole] = mapped_column(
        Enum(HomeProjectMemberRole), default=HomeProjectMemberRole.editor
    )
    joined_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )

    project: Mapped[HomeProject] = relationship(back_populates="members")
    user: Mapped[User] = relationship()


class HomeProjectInvite(Base):
    __tablename__ = "home_project_invites"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("home_projects.id", ondelete="CASCADE"), index=True
    )
    email: Mapped[str] = mapped_column(String(255), index=True)
    role: Mapped[HomeProjectMemberRole] = mapped_column(
        Enum(HomeProjectMemberRole), default=HomeProjectMemberRole.editor
    )
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    invited_by: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class HomeProjectDocument(Base):
    """Documentos por etapa: PDF, fotos de sitio, planos, etc."""

    __tablename__ = "home_project_documents"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("home_projects.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    stage_number: Mapped[int] = mapped_column(Integer, index=True)
    section_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("home_project_sections.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    slot_key: Mapped[str | None] = mapped_column(String(80), nullable=True, index=True)
    original_filename: Mapped[str] = mapped_column(String(255))
    stored_path: Mapped[str] = mapped_column(String(512))
    mime_type: Mapped[str] = mapped_column(String(120), default="application/octet-stream")
    file_size: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )

    project: Mapped[HomeProject] = relationship(back_populates="documents")
    section: Mapped[HomeProjectSection | None] = relationship(back_populates="documents")
    uploader: Mapped[User] = relationship()


class HomeProjectStage(Base):
    """Instancia de cada una de las 9 etapas por proyecto."""

    __tablename__ = "home_project_stages"
    __table_args__ = (
        UniqueConstraint("project_id", "stage_number", name="uq_home_project_stage"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    project_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("home_projects.id", ondelete="CASCADE"), index=True
    )
    stage_number: Mapped[int] = mapped_column(Integer, index=True)
    slug: Mapped[str] = mapped_column(String(40))
    title: Mapped[str] = mapped_column(String(120))
    status: Mapped[HomeStageStatus] = mapped_column(
        Enum(HomeStageStatus), default=HomeStageStatus.pending
    )
    checklist_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
    notes: Mapped[str] = mapped_column(Text, default="")
    ai_guidance: Mapped[str] = mapped_column(Text, default="")
    analysis_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("analyses.id", ondelete="SET NULL"), nullable=True
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    project: Mapped[HomeProject] = relationship(back_populates="stages")
    analysis: Mapped[Analysis | None] = relationship()


class RefundRequestStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class RefundRequest(Base):
    """Solicitud de reembolso tras cancelar (o con uso bajo en la ventana de días)."""

    __tablename__ = "refund_requests"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    receipt_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("billing_receipts.id", ondelete="SET NULL"), nullable=True
    )
    amount_cents: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(8), default="MXN")
    status: Mapped[RefundRequestStatus] = mapped_column(
        Enum(RefundRequestStatus), default=RefundRequestStatus.pending, index=True
    )
    eligible_at_request: Mapped[bool] = mapped_column(Boolean, default=False)
    reason: Mapped[str] = mapped_column(Text, default="")
    admin_note: Mapped[str] = mapped_column(Text, default="")
    eligibility_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    reviewed_by: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )

    user: Mapped[User] = relationship(
        back_populates="refund_requests", foreign_keys=[user_id]
    )
    receipt: Mapped[BillingReceipt | None] = relationship()
    reviewer: Mapped[User | None] = relationship(foreign_keys=[reviewed_by])


class SupportTicketStatus(str, enum.Enum):
    open = "open"
    pending = "pending"
    resolved = "resolved"
    closed = "closed"


class SupportTicketPriority(str, enum.Enum):
    normal = "normal"
    high = "high"


class SupportTicket(Base):
    """Ticket de soporte humano (no confundir con chats de IA)."""

    __tablename__ = "support_tickets"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    assigned_to: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    subject: Mapped[str] = mapped_column(String(160))
    status: Mapped[SupportTicketStatus] = mapped_column(
        Enum(SupportTicketStatus), default=SupportTicketStatus.open, index=True
    )
    priority: Mapped[SupportTicketPriority] = mapped_column(
        Enum(SupportTicketPriority), default=SupportTicketPriority.normal
    )
    related_chat_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    related_analysis_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("analyses.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now(), index=True
    )

    user: Mapped[User] = relationship(
        back_populates="support_tickets", foreign_keys=[user_id]
    )
    assignee: Mapped[User | None] = relationship(foreign_keys=[assigned_to])
    messages: Mapped[list["SupportMessage"]] = relationship(
        back_populates="ticket",
        order_by="SupportMessage.created_at",
        cascade="all, delete-orphan",
    )


class SupportMessage(Base):
    __tablename__ = "support_messages"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    ticket_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("support_tickets.id", ondelete="CASCADE"), index=True
    )
    author_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    body: Mapped[str] = mapped_column(Text)
    is_staff: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )

    ticket: Mapped[SupportTicket] = relationship(back_populates="messages")
    author: Mapped[User] = relationship()
