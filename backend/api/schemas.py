"""Esquemas Pydantic."""

from __future__ import annotations

import re

from pydantic import BaseModel, Field, field_validator

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _normalize_email(value: str) -> str:
    email = value.strip().lower()
    if not _EMAIL_RE.match(email):
        raise ValueError("Correo electrónico inválido")
    return email


class RegisterRequest(BaseModel):
    email: str
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(default="", max_length=120)

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        return _normalize_email(v)


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

    class Config:
        from_attributes = True


class UpdateProfileRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=120)


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
    access_token: str
    token_type: str = "bearer"
    user: UserOut
    subscription: dict
    impersonation: bool = False
    impersonator: dict | None = None


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


class MessageOut(BaseModel):
    id: int | None = None
    role: str
    content: dict
    created_at: str | None = None
