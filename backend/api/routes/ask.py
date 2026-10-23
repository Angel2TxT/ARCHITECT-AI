"""Preguntas de construcción sin plano (manuales + web opcional)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Form, HTTPException
from sqlalchemy.orm import Session

from api.deps import get_current_user
from db.database import get_db
from db.models import Analysis, Chat, Message, User
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
    analysis_id: int = Form(0),
):
    q = (message or "").strip()
    if len(q) < 3:
        raise HTTPException(400, "Escribe tu pregunta (mínimo 3 caracteres).")

    assert_can_ask(db, user)

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

    # 1. Buscar si hay un plano analizado en este chat o especificado por ID
    target_analysis: Analysis | None = None
    if analysis_id > 0:
        target_analysis = (
            db.query(Analysis)
            .filter(Analysis.id == analysis_id, Analysis.user_id == user.id)
            .first()
        )
    if not target_analysis and chat:
        target_analysis = (
            db.query(Analysis)
            .filter(Analysis.chat_id == chat.id, Analysis.user_id == user.id)
            .order_by(Analysis.id.desc())
            .first()
        )
        if not target_analysis:
            last_analysis_msg = (
                db.query(Message)
                .filter(Message.chat_id == chat.id, Message.analysis_id.isnot(None))
                .order_by(Message.id.desc())
                .first()
            )
            if last_analysis_msg and last_analysis_msg.analysis_id:
                target_analysis = (
                    db.query(Analysis)
                    .filter(Analysis.id == last_analysis_msg.analysis_id, Analysis.user_id == user.id)
                    .first()
                )

    # 2. Si hay un plano asociado, responder de forma conversacional sobre el plano real
    if target_analysis:
        from services.plan_conversation_service import answer_plan_conversation

        recent_msgs: list[dict] = []
        if chat:
            recent_rows = (
                db.query(Message)
                .filter(Message.chat_id == chat.id)
                .order_by(Message.id.desc())
                .limit(4)
                .all()
            )
            recent_msgs = [
                {"role": m.role, "text": (m.content or {}).get("text", "")}
                for m in reversed(recent_rows)
            ]

        result = answer_plan_conversation(
            q,
            target_analysis,
            recent_messages=recent_msgs,
        )
    else:
        result = answer_construction_question(q)

    db.add(
        Message(
            chat_id=chat.id,
            role="user",
            content={"text": q, "type": "question"},
            analysis_id=target_analysis.id if target_analysis else None,
        )
    )

    assistant_content = {
        "text": result["text"],
        "type": result.get("type", "qa"),
        "analysis_id": target_analysis.id if target_analysis else None,
        "measures_report": result.get("measures_report"),
        "municipality": result.get("municipality"),
        "local_sources": result.get("local_sources"),
        "web_sources": result.get("web_sources"),
        "thresholds": result.get("thresholds"),
        "web_search_used": result.get("web_search_used"),
        "assistant_mode": result.get("assistant_mode", "architect"),
        "llm_used": result.get("llm_used", False),
    }
    db.add(
        Message(
            chat_id=chat.id,
            role="assistant",
            content=assistant_content,
            analysis_id=target_analysis.id if target_analysis else None,
        )
    )
    chat.updated_at = datetime.utcnow()
    db.commit()

    record_ask_usage(db, user)

    result["chat_id"] = chat.id
    result["subscription"] = subscription_payload(db, user)
    result["analysis_id"] = target_analysis.id if target_analysis else None
    result.update(assistant_content)
    return result
