"""Historial de chats en MySQL."""

from __future__ import annotations

import uuid
from typing import Annotated

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from api.db_errors import http_db_error
from api.deps import get_current_user
from api.schemas import ChatCreate, ChatOut, MessageOut
from db.database import get_db
from db.models import Analysis, Chat, Message, User


class MessageCreate(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    text: str = Field(max_length=8000)

router = APIRouter(prefix="/api/chats", tags=["chats"])


def _chat_out(chat: Chat, message_count: int = 0) -> ChatOut:
    return ChatOut(
        id=chat.id,
        title=chat.title,
        updated_at=chat.updated_at.isoformat() if chat.updated_at else "",
        message_count=message_count,
    )


def _message_out(m: Message) -> MessageOut:
    raw = m.content
    if isinstance(raw, dict):
        content = dict(raw)
        # Evita respuestas gigantes; la app usa analysis_id si hace falta la imagen.
        if content.get("image_base64"):
            content["image_base64"] = None
            content["has_image"] = True
    elif isinstance(raw, str):
        content = {"text": raw}
    else:
        content = {"text": ""}

    return MessageOut(
        id=m.id,
        role=m.role or "user",
        content=content,
        created_at=m.created_at.isoformat() if m.created_at else None,
    )


@router.get("", response_model=list[ChatOut])
def list_chats(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    limit: int = 40,
):
    try:
        rows = (
            db.query(Chat)
            .filter(Chat.user_id == user.id)
            .order_by(Chat.updated_at.desc())
            .limit(min(limit, 100))
            .all()
        )
        out = []
        for c in rows:
            cnt = (
                db.query(func.count(Message.id))
                .filter(Message.chat_id == c.id)
                .scalar()
                or 0
            )
            out.append(_chat_out(c, cnt))
        return out
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.post("", response_model=ChatOut)
def create_chat(
    body: ChatCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    chat = Chat(id=str(uuid.uuid4()), user_id=user.id, title=body.title[:120])
    db.add(chat)
    db.commit()
    db.refresh(chat)
    return _chat_out(chat)


@router.get("/{chat_id}")
def get_chat(
    chat_id: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    try:
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id, Chat.user_id == user.id)
            .first()
        )
        if not chat:
            raise HTTPException(404, "Chat no encontrado")
        message_ids = [
            row[0]
            for row in db.query(Message.id)
            .filter(Message.chat_id == chat_id)
            .order_by(Message.id.asc())
            .all()
        ]
        messages = (
            db.query(Message).filter(Message.id.in_(message_ids)).all()
            if message_ids
            else []
        )
        messages.sort(key=lambda m: m.id)
        return {
            "chat": _chat_out(chat, len(messages)),
            "messages": [_message_out(m) for m in messages],
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise http_db_error(exc) from exc


@router.delete("/{chat_id}")
def delete_chat(
    chat_id: str,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    try:
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id, Chat.user_id == user.id)
            .first()
        )
        if not chat:
            raise HTTPException(404, "Chat no encontrado")

        # Desvincular análisis (el plano sigue en historial, sin chat fantasma)
        db.query(Analysis).filter(
            Analysis.chat_id == chat_id,
            Analysis.user_id == user.id,
        ).update({Analysis.chat_id: None}, synchronize_session=False)

        db.query(Message).filter(Message.chat_id == chat_id).delete(
            synchronize_session=False
        )
        db.delete(chat)
        db.commit()
        return {"ok": True, "chat_id": chat_id}
    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        raise http_db_error(exc) from exc


@router.post("/{chat_id}/messages")
def add_message(
    chat_id: str,
    body: MessageCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    try:
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id, Chat.user_id == user.id)
            .first()
        )
        if not chat:
            raise HTTPException(404, "Chat no encontrado")
        msg = Message(
            chat_id=chat_id,
            role=body.role,
            content={"text": body.text},
        )
        db.add(msg)
        if body.role == "user" and chat.title == "Nuevo chat":
            chat.title = body.text[:120]
        chat.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(msg)
        return _message_out(msg)
    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        raise http_db_error(exc) from exc
