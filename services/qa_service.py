"""
Preguntas de construcción/arquitectura sin plano adjunto.
Combina: manuales indexados, umbrales Chiapas y búsqueda web opcional.
"""

from __future__ import annotations

import re
import unicodedata

from rules.catalog import APPLIED_THRESHOLDS, ISSUE_LABELS, NORM_BUNDLE_TITLE, NORM_SOURCES
from rules.norms import CHIAPAS_RULES

from services.knowledge_service import _load_pages, _score_page, _snippet
from services.web_search_service import search_construction_web, web_search_enabled

# Municipios Chiapas (ampliar según necesidad)
MUNICIPALITIES: dict[str, str] = {
    "ocosingo": "Ocosingo",
    "tuxtla": "Tuxtla Gutiérrez",
    "tuxtla gutierrez": "Tuxtla Gutiérrez",
    "san cristobal": "San Cristóbal de las Casas",
    "san cristóbal": "San Cristóbal de las Casas",
    "tapachula": "Tapachula",
    "comitan": "Comitán",
    "comitán": "Comitán",
    "palenque": "Palenque",
    "villaflores": "Villaflores",
    "chiapas": "Chiapas (estatal)",
}

TOPIC_THRESHOLD_CODES: dict[str, list[str]] = {
    "puerta": ["DOOR_WIDTH_MIN", "DOOR_HEIGHT_MIN"],
    "ventana": ["WINDOW_WIDTH_MIN", "WINDOW_LIGHT_RATIO", "WINDOW_AREA_MIN"],
    "habitacion": ["ROOM_DIMENSION_MIN", "ROOM_AREA_MIN", "ROOM_HEIGHT_MIN"],
    "recinto": ["ROOM_DIMENSION_MIN", "ROOM_AREA_MIN"],
    "pasillo": ["CORRIDOR_WIDTH_MIN"],
    "circulacion": ["CORRIDOR_WIDTH_MIN"],
    "escalera": ["STAIR_WIDTH_UNIFAM", "STAIR_WIDTH_MULTI"],
    "rampa": ["RAMP_WIDTH_MIN"],
    "bano": ["BATHROOM_MIN_AREA", "BATHROOM_VENTILATION"],
    "baño": ["BATHROOM_MIN_AREA"],
    "cocina": ["KITCHEN_REF_AREA"],
    "recamara": ["BEDROOM_MIN_AREA"],
    "altura": ["ROOM_HEIGHT_MIN"],
    "iluminacion": ["WINDOW_LIGHT_RATIO"],
    "ventilacion": ["ROOM_VENTILATION_OPENING"],
    "obra": ["BUILT_AREA_MINOR_WORK"],
    "licencia": ["BUILT_AREA_MINOR_WORK"],
}


def _normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def detect_municipality(question: str) -> str | None:
    q = _normalize(question)
    for key, name in sorted(MUNICIPALITIES.items(), key=lambda x: -len(x[0])):
        if key in q:
            return name
    return None


def _query_terms(question: str) -> list[str]:
    q = _normalize(question)
    terms = [w for w in re.split(r"\W+", q) if len(w) >= 3]
    stop = {
        "que",
        "qué",
        "cual",
        "cuál",
        "cuales",
        "cuáles",
        "como",
        "cómo",
        "para",
        "con",
        "los",
        "las",
        "del",
        "de",
        "la",
        "el",
        "en",
        "un",
        "una",
        "son",
        "esta",
        "este",
        "hay",
        "medidas",
        "oficiales",
    }
    terms = [t for t in terms if t not in stop]
    muni = detect_municipality(question)
    if muni:
        terms.extend(_normalize(muni).split())
    return list(dict.fromkeys(terms))[:12]


def search_knowledge_by_query(question: str, *, max_refs: int = 5) -> list[dict]:
    pages = _load_pages()
    if not pages:
        return []

    terms = _query_terms(question)
    if not terms:
        terms = ["construcción", "habitabilidad"]

    scored: list[tuple[int, dict]] = []
    for page in pages:
        text = page.get("text", "")
        if len(text) < 30:
            continue
        sc = _score_page(text, terms)
        if sc >= 1:
            kw = next((t for t in terms if t in text.lower()), terms[0])
            scored.append(
                (
                    sc,
                    {
                        "doc_title": page["doc_title"],
                        "page": page["page"],
                        "snippet": _snippet(text, kw, radius=200),
                        "source": "manual",
                        "source_file": page.get("source_file"),
                    },
                )
            )

    scored.sort(key=lambda x: -x[0])
    out: list[dict] = []
    seen: set[str] = set()
    for _, ref in scored:
        key = f"{ref['doc_title']}:{ref['page']}"
        if key in seen:
            continue
        seen.add(key)
        out.append(ref)
        if len(out) >= max_refs:
            break
    return out


def _thresholds_for_question(question: str) -> list[dict]:
    q = _normalize(question)
    codes: list[str] = []
    for topic, topic_codes in TOPIC_THRESHOLD_CODES.items():
        if topic in q:
            codes.extend(topic_codes)

    if not codes or re.search(
        r"medida\s+oficial|norma\s+minim|minimo\s+legal|cuanto\s+exige|tabla\s+oficial",
        q,
    ):
        codes = [t["code"] for t in APPLIED_THRESHOLDS]
    elif re.search(r"medida|cota|dimensi", q) and len(codes) < 3:
        codes = [t["code"] for t in APPLIED_THRESHOLDS[:8]]

    code_set = set(codes)
    rows = [t for t in APPLIED_THRESHOLDS if t["code"] in code_set]
    return rows[:14]


def _format_thresholds(rows: list[dict]) -> str:
    if not rows:
        return ""
    lines = [f"Umbrales de referencia ({NORM_BUNDLE_TITLE}):"]
    for t in rows:
        label = ISSUE_LABELS.get(t["code"], str(t["code"]).replace("_", " ").lower())
        unit = t["unit"]
        if unit == "ratio":
            unit = "proporción"
        lines.append(f"• {label}: {t['value']} {unit} — {t['source']}")
    return "\n".join(lines)


def _is_plan_measures_question(question: str) -> bool:
    q = _normalize(question)
    if not re.search(r"medida|cota|dimensi|ancho|alto|metro|superficie", q):
        return False
    return bool(
        re.search(
            r"plano|este|ese|mi\s|adjunt|dibujo|lamina|lámina|todas?\s+las?\s+medidas|"
            r"dame\s+las|listar|cuantas?\s+medidas",
            q,
        )
    )


def answer_construction_question(question: str) -> dict:
    q = (question or "").strip()

    if _is_plan_measures_question(q):
        return {
            "text": (
                "Para obtener las medidas de tu plano, adjunta el archivo con el clip "
                "y escribe, por ejemplo: «Dame todas las medidas del plano».\n\n"
                "Si ya analizaste el plano en este chat, puedes repetir la misma pregunta "
                "y el sistema reutilizará el último archivo sin volver a subirlo."
            ),
            "municipality": None,
            "local_sources": [],
            "web_sources": [],
            "thresholds": [],
            "web_search_used": False,
            "knowledge_pages": len(_load_pages()),
        }

    municipality = detect_municipality(q)
    local = search_knowledge_by_query(q, max_refs=5)
    thresholds = _thresholds_for_question(q)
    web: list[dict] = []

    web_query = q
    if municipality:
        web_query = f"reglamento construcción {municipality} Chiapas medidas oficiales"
    web = search_construction_web(web_query, max_results=4)

    parts: list[str] = []

    if municipality:
        parts.append(
            f"Pregunta sobre **{municipality}**. "
            "Cada municipio de Chiapas puede tener su propio reglamento; "
            "abajo: referencia estatal/municipal base, tus manuales y enlaces web."
        )
    else:
        parts.append(
            f"Respuesta sobre construcción y arquitectura ({NORM_BUNDLE_TITLE}). "
            "Confirma siempre con el reglamento del ayuntamiento de tu localidad."
        )

    th_text = _format_thresholds(thresholds)
    if th_text:
        parts.append(th_text)

    if local:
        parts.append("\nDe tus manuales indexados:")
        for ref in local[:4]:
            parts.append(
                f"• {ref['doc_title']} (pág. {ref['page']}): {ref['snippet'][:320]}"
            )
    elif not web:
        parts.append(
            "\nNo encontré fragmentos en los PDF que subiste. "
            "Ejecuta `python scripts/ingest_knowledge_docs.py` si agregaste manuales nuevos."
        )

    if web:
        parts.append("\nEn la web (verifica en fuente oficial):")
        for w in web[:4]:
            title = w.get("title") or "Enlace"
            snip = (w.get("snippet") or "")[:240]
            url = w.get("url") or ""
            line = f"• {title}: {snip}"
            if url:
                line += f" ({url})"
            parts.append(line)
    elif web_search_enabled():
        parts.append(
            "\n(No obtuve resultados web en este momento; intenta de nuevo o revisa WEB_SEARCH_ENABLED.)"
        )
    else:
        parts.append(
            "\nBúsqueda web desactivada. Activa WEB_SEARCH_ENABLED=true en `.env`."
        )

    if municipality and municipality not in ("Tuxtla Gutiérrez", "Chiapas (estatal)"):
        parts.append(
            f"\nPara {municipality}: solicita en Dirección de Obras o el ayuntamiento "
            "el reglamento de construcción vigente y las tablas de medidas locales. "
            "Hasta entonces usa la referencia de Tuxtla Gutiérrez como guía habitual en el estado."
        )

    if not _is_plan_measures_question(q):
        parts.append(
            "\nPara revisar tu plano concreto, adjunta el archivo y pregunta "
            "por ejemplo: «¿Este plano está bien?» o «Dame todas las medidas del plano»."
        )

    text = "\n".join(parts).replace("**", "")

    return {
        "text": text,
        "municipality": municipality,
        "local_sources": local,
        "web_sources": web,
        "thresholds": thresholds,
        "web_search_used": bool(web),
        "knowledge_pages": len(_load_pages()),
    }
