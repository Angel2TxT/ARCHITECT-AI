"""
Base de conocimiento: manuales, reglamentos y guías con texto + imágenes.

Los PDF de construcción suelen traer:
- Texto normativo (qué exige la regla)
- Diagramas y ejemplos (cómo interpretar / qué hacer)
- Planos de ejemplo (entrenamiento YOLO si se etiquetan)

Este módulo indexa el texto extraído para citarlo en el análisis.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KNOWLEDGE_RAW = ROOT / "data" / "knowledge" / "raw"
KNOWLEDGE_PROCESSED = ROOT / "data" / "knowledge" / "processed"

# Palabras clave por código de incidencia → búsqueda en manuales
ISSUE_SEARCH_TERMS: dict[str, list[str]] = {
    "DOOR_WIDTH_MIN": ["puerta", "ancho", "0.90", "acceso", "vano"],
    "DOOR_HEIGHT_MIN": ["puerta", "altura", "2.10", "accesibilidad"],
    "WINDOW_LIGHT_RATIO": ["iluminación", "ventana", "1/8", "octava"],
    "ROOM_DIMENSION_MIN": ["habitable", "2.70", "dimensión", "recinto"],
    "ROOM_AREA_MIN": ["área", "superficie", "7.29", "habitable"],
    "CORRIDOR_WIDTH_MIN": ["circulación", "pasillo", "1.20"],
    "BATHROOM_VENTILATION": ["sanitario", "baño", "ventilación"],
    "BUILT_AREA_MINOR_WORK": ["obra menor", "superficie", "licencia", "40"],
    "CONSTRUCTION_MANUAL_REVIEW": ["estructura", "instalación", "corte", "accesibilidad"],
}

_PAGE_CACHE: list[dict] | None = None


def _load_pages() -> list[dict]:
    global _PAGE_CACHE
    if _PAGE_CACHE is not None:
        return _PAGE_CACHE

    pages: list[dict] = []
    if not KNOWLEDGE_PROCESSED.exists():
        _PAGE_CACHE = pages
        return pages

    for manifest_path in KNOWLEDGE_PROCESSED.glob("*/manifest.json"):
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        doc_title = manifest.get("title", manifest_path.parent.name)
        for p in manifest.get("pages", []):
            text_path = manifest_path.parent / p.get("text_file", "")
            text = ""
            if text_path.is_file():
                text = text_path.read_text(encoding="utf-8", errors="ignore")
            pages.append(
                {
                    "doc_id": manifest.get("id", manifest_path.parent.name),
                    "doc_title": doc_title,
                    "page": p.get("page", 0),
                    "page_type": p.get("page_type", "mixed"),
                    "text": text,
                    "image_file": p.get("image_file"),
                    "source_file": manifest.get("source_file"),
                }
            )
    _PAGE_CACHE = pages
    return pages


def invalidate_cache() -> None:
    global _PAGE_CACHE
    _PAGE_CACHE = None


def knowledge_stats() -> dict:
    docs = list(KNOWLEDGE_PROCESSED.glob("*/manifest.json")) if KNOWLEDGE_PROCESSED.exists() else []
    pages = _load_pages()
    by_type: dict[str, int] = {}
    for p in pages:
        t = p.get("page_type", "mixed")
        by_type[t] = by_type.get(t, 0) + 1
    return {
        "documents": len(docs),
        "pages": len(pages),
        "raw_folder": str(KNOWLEDGE_RAW),
        "processed_folder": str(KNOWLEDGE_PROCESSED),
        "page_types": by_type,
    }


def _score_page(text: str, terms: list[str]) -> int:
    lower = text.lower()
    score = 0
    for term in terms:
        if term.lower() in lower:
            score += 2 if re.search(r"\d", term) else 1
    return score


def find_references(
    issue_codes: list[str],
    *,
    max_refs: int = 4,
    min_score: int = 2,
    extra_terms: list[str] | None = None,
) -> list[dict]:
    """Fragmentos de manuales relacionados con las incidencias detectadas."""
    pages = _load_pages()
    if not pages:
        return []

    terms_set: list[str] = []
    for code in issue_codes:
        terms_set.extend(ISSUE_SEARCH_TERMS.get(code, []))
    if extra_terms:
        terms_set.extend(extra_terms)
    if not terms_set:
        terms_set = ["construcción", "plano", "habitabilidad"]

    scored: list[tuple[int, dict]] = []
    for page in pages:
        if len(page.get("text", "")) < 40:
            continue
        sc = _score_page(page["text"], terms_set)
        if sc >= min_score:
            snippet = _snippet(page["text"], terms_set[0] if terms_set else "")
            scored.append(
                (
                    sc,
                    {
                        "doc_title": page["doc_title"],
                        "page": page["page"],
                        "page_type": page["page_type"],
                        "snippet": snippet,
                        "source_file": page.get("source_file"),
                    },
                )
            )

    scored.sort(key=lambda x: -x[0])
    seen: set[str] = set()
    refs: list[dict] = []
    for _, ref in scored:
        key = f"{ref['doc_title']}:{ref['page']}"
        if key in seen:
            continue
        seen.add(key)
        refs.append(ref)
        if len(refs) >= max_refs:
            break

    if len(refs) < max_refs:
        for page in pages:
            if len(page.get("text", "")) < 80:
                continue
            if page.get("page_type") not in ("mixed", "regulation_text"):
                continue
            key = f"{page['doc_title']}:{page['page']}"
            if key in seen:
                continue
            refs.append(
                {
                    "doc_title": page["doc_title"],
                    "page": page["page"],
                    "page_type": page["page_type"],
                    "snippet": _snippet(page["text"], terms_set[0] if terms_set else ""),
                    "source_file": page.get("source_file"),
                }
            )
            seen.add(key)
            if len(refs) >= max_refs:
                break
    return refs


def _snippet(text: str, keyword: str, radius: int = 140) -> str:
    lower = text.lower()
    idx = lower.find(keyword.lower()) if keyword else -1
    if idx < 0:
        clean = " ".join(text.split())
        return clean[:280] + ("…" if len(clean) > 280 else "")
    start = max(0, idx - radius)
    end = min(len(text), idx + radius)
    chunk = " ".join(text[start:end].split())
    if start > 0:
        chunk = "…" + chunk
    if end < len(text):
        chunk += "…"
    return chunk


def _issue_code(issue) -> str:
    if isinstance(issue, dict):
        return str(issue.get("code", ""))
    return str(getattr(issue, "code", ""))


def references_for_issues(issues: list) -> list[dict]:
    codes = list({_issue_code(i) for i in issues if _issue_code(i)})
    return find_references(codes)
