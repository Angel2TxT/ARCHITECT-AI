"""Esquemas Pydantic."""

from __future__ import annotations

import re

from pydantic import BaseModel, EmailStr, Field, TypeAdapter, field_validator

_EMAIL_ADAPTER = TypeAdapter(EmailStr)
_FORBIDDEN_EMAIL_CHARS = frozenset('<>/\\"\' \t\r\n&;')
_ALLOWED_NAME_EXTRA = frozenset(" -'’")


def validate_full_name(value: str) -> str:
    """Valida el nombre mediante lista blanca de letras Unicode, espacios, guiones y apóstrofes."""
    name = (value or "").strip()
    if not name:
        raise ValueError("El nombre no puede estar vacío")
    if len(name) < 2:
        raise ValueError("El nombre debe tener al menos 2 caracteres")
    if len(name) > 120:
        raise ValueError("El nombre no puede exceder 120 caracteres")
    if not any(ch.isalpha() for ch in name):
        raise ValueError("El nombre debe contener al menos una letra")
    for ch in name:
        if not (ch.isalpha() or ch in _ALLOWED_NAME_EXTRA):
            raise ValueError(
                "El nombre contiene caracteres no permitidos; solo se aceptan letras, espacios, guiones y apóstrofes"
            )
    return name


def _normalize_email(value: str) -> str:
    email = (value or "").strip().lower()
    if not email:
        raise ValueError("El correo electrónico no puede estar vacío")
    if any(ch in _FORBIDDEN_EMAIL_CHARS for ch in email):
        raise ValueError(
            "Correo electrónico inválido: contiene caracteres no permitidos"
        )
    try:
        validated = str(_EMAIL_ADAPTER.validate_python(email)).lower()
    except Exception as exc:
        raise ValueError("Correo electrónico inválido") from exc
    domain = validated.split("@", 1)[1] if "@" in validated else ""
    if "." not in domain:
        raise ValueError("Correo electrónico inválido")
    return validated


class RegisterRequest(BaseModel):
    email: str
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(default="", max_length=120)

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        return _normalize_email(v)

    @field_validator("full_name")
    @classmethod
    def valid_full_name(cls, v: str) -> str:
        return validate_full_name(v)


class LoginRequest(BaseModel):
    email: str
    password: str

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        return _normalize_email(v)


class ForgotPasswordRequest(BaseModel):
    email: str

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        return _normalize_email(v)


class ResetPasswordRequest(BaseModel):
    token: str = Field(min_length=10)
    password: str = Field(min_length=8, max_length=128)


class UserOut(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    avatar_url: str | None = None
    has_password: bool = True
    oauth_provider: str | None = None
    email_verified: bool = True

    class Config:
        from_attributes = True


class UpdateProfileRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=120)

    @field_validator("full_name")
    @classmethod
    def valid_full_name(cls, v: str) -> str:
        return validate_full_name(v)


class ChangePasswordRequest(BaseModel):
    current_password: str | None = None
    new_password: str = Field(min_length=8, max_length=128)


class DeleteAccountRequest(BaseModel):
    password: str | None = None
    confirm_email: str | None = None


class RefundRequestCreate(BaseModel):
    reason: str = Field(default="", max_length=2000)


class RefundReviewRequest(BaseModel):
    approve: bool
    admin_note: str = Field(default="", max_length=2000)


class AuthResponse(BaseModel):
    access_token: str = ""
    token_type: str = "bearer"
    user: UserOut
    subscription: dict
    impersonation: bool = False
    impersonator: dict | None = None
    requires_verification: bool = False
    verification_expires_in_seconds: int | None = None
    verification_cooldown_seconds: int | None = None


class VerifyEmailRequest(BaseModel):
    email: str
    code: str = Field(min_length=6, max_length=6)

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        return _normalize_email(v)


class ResendVerificationRequest(BaseModel):
    email: str

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        return _normalize_email(v)


class UpdateUnverifiedEmailRequest(BaseModel):
    current_email: str
    new_email: str
    password: str | None = None

    @field_validator("current_email", "new_email")
    @classmethod
    def valid_emails(cls, v: str) -> str:
        return _normalize_email(v)


class PlanChangeRequest(BaseModel):
    plan_slug: str


class CheckoutStartRequest(BaseModel):
    plan_slug: str
    return_url: str | None = None


class CheckoutCompleteRequest(BaseModel):
    session_token: str


class PortalStartRequest(BaseModel):
    return_url: str | None = None


class ChatCreate(BaseModel):
    title: str = "Nuevo chat"


class ChatOut(BaseModel):
    id: str
    title: str
    updated_at: str
    message_count: int = 0
    last_analysis_id: int | None = None


class MessageOut(BaseModel):
    id: int | None = None
    role: str
    content: dict
    created_at: str | None = None
