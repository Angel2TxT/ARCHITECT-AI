"""Preguntas de construcción sin plano (manuales + web opcional)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Form, HTTPException
from sqlalchemy.orm import Session

from api.deps import get_current_user
from db.database import get_db
from db.models import Chat, Message, User
from services.qa_service import answer_construction_question
from services.architect_ai_service import architect_ai_status
from services.llm_service import llm_status
from services.web_search_service import web_search_enabled
from services.subscription_service import assert_can_ask, is_admin_user, record_ask_usage, subscription_payload

router = APIRouter(tags=["ask"])


@router.get("/api/ask/status")
def ask_status():
    from services.knowledge_service import knowledge_stats

    k = knowledge_stats()
    pages = k.get("pages", 0)
    catalog = k.get("catalog") or []
    return {
        "knowledge_ready": pages > 0,
        "knowledge_pages": pages,
        "web_search_enabled": web_search_enabled(),
        "document_catalog": catalog,
        **llm_status(),
        **architect_ai_status(knowledge_pages=pages, catalog=catalog),
    }


@router.post("/api/ask")
async def ask_construction(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    message: str = Form(...),
    chat_id: str = Form(""),
):
    q = (message or "").strip()
    if len(q) < 3:
        raise HTTPException(400, "Escribe tu pregunta (mínimo 3 caracteres).")

    assert_can_ask(db, user)

    result = answer_construction_question(q)

    chat: Chat | None = None
    if chat_id.strip():
        chat = (
            db.query(Chat)
            .filter(Chat.id == chat_id.strip(), Chat.user_id == user.id)
            .first()
        )
    if not chat:
        chat = Chat(
            id=str(uuid.uuid4()),
            user_id=user.id,
            title=q[:120],
        )
        db.add(chat)
        db.flush()
    elif chat.title == "Nuevo chat":
        chat.title = q[:120]

    db.add(
        Message(
            chat_id=chat.id,
            role="user",
            content={"text": q, "type": "question"},
        )
    )

    assistant_content = {
        "text": result["text"],
        "type": "qa",
        "municipality": result.get("municipality"),
        "local_sources": result.get("local_sources"),
        "web_sources": result.get("web_sources"),
        "thresholds": result.get("thresholds"),
        "web_search_used": result.get("web_search_used"),
        "assistant_mode": result.get("assistant_mode"),
        "llm_used": result.get("llm_used"),
    }
    db.add(
        Message(
            chat_id=chat.id,
            role="assistant",
            content=assistant_content,
        )
    )
    chat.updated_at = datetime.utcnow()
    db.commit()

    if not is_admin_user(user):
        record_ask_usage(db, user.id)

    result["chat_id"] = chat.id
    result["subscription"] = subscription_payload(db, user)
    return result
