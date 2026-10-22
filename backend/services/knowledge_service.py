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
import unicodedata
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

# Sinónimos para ampliar búsqueda en preguntas libres
QUERY_SYNONYMS: dict[str, list[str]] = {
    "puerta": ["puerta", "acceso", "vano", "entrada"],
    "ventana": ["ventana", "vanos", "iluminacion", "luz"],
    "cocina": ["cocina", "kitchen", "alacena"],
    "recamara": ["recamara", "dormitorio", "habitacion", "cuarto"],
    "bano": ["bano", "sanitario", "wc", "lavabo"],
    "baño": ["bano", "sanitario", "wc"],
    "pasillo": ["pasillo", "circulacion", "corredor"],
    "escalera": ["escalera", "escalones", "gradas"],
    "rampa": ["rampa", "accesibilidad", "discapacidad"],
    "losa": ["losa", "placa", "forjado", "entrepiso"],
    "muro": ["muro", "pared", "cerramiento"],
    "medida": ["medida", "dimension", "cota", "tamano", "ancho", "alto"],
    "casa": ["casa", "vivienda", "hogar", "unifamiliar"],
    "plano": ["plano", "planta", "lamina", "proyecto"],
    "neufert": ["neufert", "antropometria", "ergonomia", "mobiliario"],
    "licencia": ["licencia", "permiso", "tramite", "obra"],
    "ventilacion": ["ventilacion", "aire", "renovacion"],
    "estacionamiento": ["estacionamiento", "garage", "cochera"],
}

# Perfil de cada documento indexado (para enrutar preguntas a la biblioteca correcta)
DOCUMENT_PROFILES: list[dict] = [
    {
        "id": "manual_casa",
        "title_hint": "manual+casa",
        "keywords": [
            "manual",
            "progresiva",
            "etapa",
            "familia",
            "vivienda",
            "construir",
            "adaptacion",
            "patio",
            "clima",
        ],
        "summary": (
            "Manual de vivienda progresiva: proceso de diseño, etapas de construcción, "
            "criterios de adaptación y datos generales de la casa tipo."
        ),
    },
    {
        "id": "medidas_casa",
        "title_hint": "medidas-de-una-casa",
        "keywords": [
            "medidas",
            "casa",
            "espacio",
            "minimo",
            "tabla",
            "recamara",
            "cocina",
            "bano",
            "comedor",
            "sala",
        ],
        "summary": (
            "Tablas gráficas de medidas mínimas recomendadas para espacios de una vivienda."
        ),
    },
    {
        "id": "neufert",
        "title_hint": "neufert",
        "keywords": [
            "neufert",
            "antropometria",
            "ergonomia",
            "mobiliario",
            "altura",
            "circulacion",
            "escalera",
            "accesibilidad",
        ],
        "summary": (
            "Neufert (parte 1): referencia antropométrica y dimensiones de arquitectura."
        ),
    },
]

_PAGE_CACHE: list[dict] | None = None


def _normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def expand_query_terms(question: str) -> list[str]:
    q = _normalize(question)
    raw = [w for w in re.split(r"\W+", q) if len(w) >= 3]
    stop = {
        "que",
        "cual",
        "como",
        "para",
        "con",
        "los",
        "las",
        "del",
        "una",
        "uno",
        "son",
        "hay",
        "tipo",
        "tipos",
        "sobre",
        "dime",
        "explica",
    }
    terms = [w for w in raw if w not in stop]
    expanded: list[str] = []
    for term in terms:
        expanded.append(term)
        for key, syns in QUERY_SYNONYMS.items():
            if term == key or term in syns:
                expanded.extend(syns)
    return list(dict.fromkeys(expanded))[:24]


def get_document_catalog() -> list[dict]:
    """Catálogo de documentos indexados con resumen."""
    pages = _load_pages()
    if not pages:
        return []

    by_doc: dict[str, dict] = {}
    for page in pages:
        title = page["doc_title"]
        if title not in by_doc:
            profile = next(
                (
                    p
                    for p in DOCUMENT_PROFILES
                    if p["title_hint"] in _normalize(title)
                ),
                None,
            )
            by_doc[title] = {
                "title": title,
                "pages": 0,
                "text_pages": 0,
                "diagram_pages": 0,
                "source_file": page.get("source_file"),
                "summary": profile["summary"] if profile else "Documento indexado en ARCHITECT.",
            }
        by_doc[title]["pages"] += 1
        if len(page.get("text", "")) >= 40:
            by_doc[title]["text_pages"] += 1
        if page.get("page_type") == "diagram":
            by_doc[title]["diagram_pages"] += 1

    return sorted(by_doc.values(), key=lambda d: d["title"].lower())


def _visual_ref(page: dict, *, reason: str) -> dict:
    return {
        "doc_title": page["doc_title"],
        "page": page["page"],
        "page_type": page.get("page_type", "diagram"),
        "snippet": reason,
        "source": "manual",
        "source_file": page.get("source_file"),
        "visual_only": True,
    }


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
        "catalog": get_document_catalog(),
    }


def _priority_doc_hints(terms: list[str]) -> list[str]:
    hints: list[str] = []
    joined = " ".join(terms)
    for profile in DOCUMENT_PROFILES:
        if profile["title_hint"] in joined:
            hints.append(profile["title_hint"])
            continue
        if sum(1 for k in profile["keywords"] if k in terms) >= 2:
            hints.append(profile["title_hint"])
    return hints


def search_knowledge_for_question(question: str, *, max_refs: int = 8) -> list[dict]:
    """
    Busca en toda la biblioteca indexada: texto extraído + referencias visuales
    cuando el PDF es principalmente diagramas (Neufert, medidas de casa).
    """
    pages = _load_pages()
    if not pages:
        return []

    terms = expand_query_terms(question)
    if not terms:
        terms = ["construccion", "vivienda", "habitabilidad"]

    priority_hints = _priority_doc_hints(terms)
    out: list[dict] = []
    seen: set[str] = set()

    for hint in priority_hints:
        doc_pages = [p for p in pages if hint in _normalize(p["doc_title"])]
        if not doc_pages:
            continue
        sample = next(
            (p for p in doc_pages if len(p.get("text", "")) >= 40),
            doc_pages[len(doc_pages) // 2],
        )
        key = f"{sample['doc_title']}:{sample['page']}"
        if key in seen:
            continue
        profile = next((p for p in DOCUMENT_PROFILES if p["title_hint"] in hint), None)
        if len(sample.get("text", "")) >= 40:
            kw = next((t for t in terms if t in sample["text"].lower()), terms[0])
            out.append(
                {
                    "doc_title": sample["doc_title"],
                    "page": sample["page"],
                    "page_type": sample.get("page_type"),
                    "snippet": _snippet(sample["text"], kw, radius=220),
                    "source": "manual",
                    "source_file": sample.get("source_file"),
                    "visual_only": False,
                }
            )
        else:
            summary = profile["summary"] if profile else "Documento de referencia indexado."
            out.append(
                _visual_ref(
                    sample,
                    reason=(
                        f"{summary} "
                        f"Ver «{sample['doc_title']}», pág. {sample['page']} "
                        "(tabla/diagrama en tu biblioteca)."
                    ),
                )
            )
        seen.add(key)

    scored: list[tuple[int, dict]] = []
    for page in pages:
        text = page.get("text", "")
        title_n = _normalize(page["doc_title"])
        title_bonus = sum(3 for t in terms if t in title_n)
        for hint in priority_hints:
            if hint in title_n:
                title_bonus += 8

        if len(text) >= 20:
            sc = _score_page(text, terms) + title_bonus
            if page.get("page_type") in ("regulation_text", "mixed"):
                sc += 1
            if sc >= 1:
                kw = next((t for t in terms if t in text.lower()), terms[0])
                scored.append(
                    (
                        sc,
                        {
                            "doc_title": page["doc_title"],
                            "page": page["page"],
                            "page_type": page.get("page_type"),
                            "snippet": _snippet(text, kw, radius=220),
                            "source": "manual",
                            "source_file": page.get("source_file"),
                            "visual_only": False,
                        },
                    )
                )
        elif title_bonus >= 5:
            scored.append(
                (
                    title_bonus,
                    _visual_ref(
                        page,
                        reason=(
                            f"Referencia visual en «{page['doc_title']}» (pág. {page['page']}). "
                            "Tabla o diagrama indexado en ARCHITECT."
                        ),
                    ),
                )
            )

    scored.sort(key=lambda x: -x[0])
    per_doc: dict[str, int] = {}
    for ref in out:
        per_doc[ref["doc_title"]] = per_doc.get(ref["doc_title"], 0) + 1

    for _, ref in scored:
        key = f"{ref['doc_title']}:{ref['page']}"
        if key in seen:
            continue
        doc = ref["doc_title"]
        if per_doc.get(doc, 0) >= 3:
            continue
        seen.add(key)
        per_doc[doc] = per_doc.get(doc, 0) + 1
        out.append(ref)
        if len(out) >= max_refs:
            break

    return out


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
