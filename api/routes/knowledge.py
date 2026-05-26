"""Base de conocimiento (manuales PDF procesados)."""

from __future__ import annotations

from fastapi import APIRouter

from services.knowledge_service import knowledge_stats

router = APIRouter(tags=["knowledge"])


@router.get("/api/knowledge")
def get_knowledge_status():
    """Estado de manuales ingestados (texto + imágenes por página)."""
    stats = knowledge_stats()
    return {
        **stats,
        "ingest_command": "python scripts/ingest_knowledge_docs.py",
        "docs": "docs/CONOCIMIENTO_DOCUMENTOS.md",
        "ready": stats["pages"] > 0,
    }
