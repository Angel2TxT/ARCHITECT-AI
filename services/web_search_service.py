"""
Búsqueda web opcional para normativa municipal y temas de construcción.
"""

from __future__ import annotations

import os
import re


def web_search_enabled() -> bool:
    return os.getenv("WEB_SEARCH_ENABLED", "true").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )


def search_construction_web(
    query: str,
    *,
    max_results: int = 4,
    region: str = "mx-es",
) -> list[dict]:
    """
    Devuelve [{title, url, snippet, source: "web"}]
    """
    if not web_search_enabled():
        return []

    q = (query or "").strip()
    if len(q) < 4:
        return []

    # Enriquecer búsqueda para normativa en México
    if not re.search(r"chiapas|méxico|mexico|reglamento|construcción", q, re.I):
        q = f"{q} construcción arquitectura Chiapas México reglamento"

    results: list[dict] = []
    try:
        try:
            from ddgs import DDGS
        except ImportError:
            from duckduckgo_search import DDGS

        with DDGS() as ddgs:
            for item in ddgs.text(q, region=region, max_results=max_results):
                results.append(
                    {
                        "title": (item.get("title") or "").strip(),
                        "url": item.get("href") or item.get("link") or "",
                        "snippet": (item.get("body") or item.get("snippet") or "").strip(),
                        "source": "web",
                    }
                )
    except Exception:
        return []

    return [r for r in results if r.get("snippet") or r.get("title")]
