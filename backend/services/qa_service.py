"""
Preguntas de construcción/arquitectura sin plano adjunto.
Combina: manuales indexados, umbrales Chiapas y búsqueda web opcional.
"""

from __future__ import annotations

import re
import unicodedata

from rules.catalog import APPLIED_THRESHOLDS, ISSUE_LABELS

from services.architect_ai_service import (
    architect_ai_status,
    compose_knowledge_answer,
    format_context_for_llm,
)
from services.knowledge_service import (
    _load_pages,
    get_document_catalog,
    search_knowledge_for_question,
)
from services.llm_service import generate_reasoned_answer, llm_status
from services.web_search_service import search_construction_web

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
    "acceso": ["DOOR_WIDTH_MIN", "DOOR_HEIGHT_MIN"],
    "ventana": ["WINDOW_WIDTH_MIN", "WINDOW_LIGHT_RATIO", "WINDOW_AREA_MIN"],
    "habitacion": ["ROOM_DIMENSION_MIN", "ROOM_AREA_MIN", "ROOM_HEIGHT_MIN"],
    "recinto": ["ROOM_DIMENSION_MIN", "ROOM_AREA_MIN"],
    "recamara": ["ROOM_DIMENSION_MIN", "ROOM_AREA_MIN", "BEDROOM_MIN_AREA"],
    "dormitorio": ["ROOM_DIMENSION_MIN", "ROOM_AREA_MIN", "BEDROOM_MIN_AREA"],
    "pasillo": ["CORRIDOR_WIDTH_MIN"],
    "circulacion": ["CORRIDOR_WIDTH_MIN"],
    "corredor": ["CORRIDOR_WIDTH_MIN"],
    "escalera": ["STAIR_WIDTH_UNIFAM", "STAIR_WIDTH_MULTI"],
    "rampa": ["RAMP_WIDTH_MIN"],
    "bano": ["BATHROOM_MIN_AREA", "BATHROOM_VENTILATION"],
    "baño": ["BATHROOM_MIN_AREA", "BATHROOM_VENTILATION"],
    "sanitario": ["BATHROOM_MIN_AREA", "BATHROOM_VENTILATION"],
    "cocina": ["KITCHEN_REF_AREA"],
    "altura": ["ROOM_HEIGHT_MIN"],
    "iluminacion": ["WINDOW_LIGHT_RATIO"],
    "ventilacion": ["ROOM_VENTILATION_OPENING", "BATHROOM_VENTILATION"],
    "obra": ["BUILT_AREA_MINOR_WORK"],
    "licencia": ["BUILT_AREA_MINOR_WORK"],
    "permiso": ["BUILT_AREA_MINOR_WORK"],
    "estacionamiento": ["PARKING_PCD_WIDTH"],
    "accesibilidad": ["RAMP_WIDTH_MIN", "DOOR_WIDTH_MIN"],
    "neufert": ["ROOM_DIMENSION_MIN", "CORRIDOR_WIDTH_MIN", "STAIR_WIDTH_UNIFAM"],
    "losa": ["ROOM_HEIGHT_MIN"],
    "muro": ["WALL_COVERAGE_LOW"],
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


def _thresholds_for_question(question: str) -> list[dict]:
    """Solo umbrales ligados al tema; no volcar toda la tabla por keywords genéricos."""
    q = _normalize(question)
    codes: list[str] = []
    for topic, topic_codes in TOPIC_THRESHOLD_CODES.items():
        if topic in q:
            codes.extend(topic_codes)

    # Pedido explícito de norma/mínimo legal → ampliar un poco, no toda la tabla
    wants_norms = bool(
        re.search(
            r"norma\s+minim|minimo\s+legal|cuanto\s+exige|medida\s+oficial|"
            r"tabla\s+oficial|reglamento|umbrales?",
            q,
        )
    )
    if wants_norms and not codes:
        # Temas frecuentes como respaldo corto
        codes = [
            "DOOR_WIDTH_MIN",
            "DOOR_HEIGHT_MIN",
            "CORRIDOR_WIDTH_MIN",
            "ROOM_AREA_MIN",
            "ROOM_HEIGHT_MIN",
            "WINDOW_LIGHT_RATIO",
        ]
    elif wants_norms and len(codes) < 3:
        codes.extend(
            [
                "DOOR_WIDTH_MIN",
                "CORRIDOR_WIDTH_MIN",
                "ROOM_AREA_MIN",
            ]
        )

    # "neufert" sin otro topic: dimensiones tipicas, no dump completo
    if "neufert" in q and not codes:
        codes = [
            "ROOM_DIMENSION_MIN",
            "CORRIDOR_WIDTH_MIN",
            "STAIR_WIDTH_UNIFAM",
            "DOOR_WIDTH_MIN",
        ]

    if not codes:
        return []

    code_set = set(codes)
    rows = []
    for t in APPLIED_THRESHOLDS:
        if t["code"] not in code_set:
            continue
        rows.append(
            {
                **t,
                "label": ISSUE_LABELS.get(t["code"], str(t["code"]).replace("_", " ")),
            }
        )
    return rows[:6]


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


def _gather_qa_context(question: str) -> dict:
    municipality = detect_municipality(question)
    catalog = get_document_catalog()
    local = search_knowledge_for_question(question, max_refs=8)
    thresholds = _thresholds_for_question(question)

    web_query = question
    if municipality:
        web_query = f"reglamento construcción {municipality} Chiapas medidas oficiales"
    web = search_construction_web(web_query, max_results=4)

    return {
        "municipality": municipality,
        "local_sources": local,
        "web_sources": web,
        "thresholds": thresholds,
        "web_search_used": bool(web),
        "knowledge_pages": len(_load_pages()),
        "document_catalog": catalog,
    }


def _is_meta_capability_question(question: str) -> bool:
    q = _normalize(question)
    return bool(
        re.search(
            r"cualquier\s+pregunta|respondes\s+(ya\s+)?|puedes\s+(responder|contestar|ayudar)|"
            r"que\s+puedes\s+(hacer|responder)|para\s+que\s+sirves|eres\s+(una\s+)?ia|"
            r"como\s+funcionas|tienes\s+(ia|llm|gemini|inteligencia)|razon(as|ar)|"
            r"me\s+contestas|sabes\s+de\s+todo",
            q,
        )
    )


def _meta_capability_answer() -> str:
    llm = llm_status()
    if llm.get("llm_configured"):
        mode = (
            f"Sí: con Gemini ({llm.get('llm_model') or 'activo'}) razono sobre tu pregunta "
            "usando manuales indexados, umbrales de Chiapas y web si está activa."
        )
    else:
        mode = (
            "Respondo con manuales indexados y umbrales locales. "
            "Para razonar con un LLM, configura LLM_PROVIDER=gemini en .env."
        )
    return (
        f"{mode}\n\n"
        "Alcance: arquitectura, medidas, normativa y obra (sobre todo Chiapas/México). "
        "No soy un chat generalista: si preguntas algo fuera de eso, te lo digo.\n\n"
        "Para un plano concreto, adjúntalo y pregunta p. ej. «¿Este plano está bien?»."
    )


def answer_construction_question(question: str) -> dict:
    q = (question or "").strip()
    catalog = get_document_catalog()
    pages_count = len(_load_pages())

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
            "knowledge_pages": pages_count,
            "document_catalog": catalog,
            "assistant_mode": "architect",
            "llm_used": False,
            **llm_status(),
            **architect_ai_status(knowledge_pages=pages_count, catalog=catalog),
        }

    if _is_meta_capability_question(q):
        # Preguntas sobre el propio asistente: LLM si puede; si no, texto corto (sin RAG).
        meta_ctx = format_context_for_llm(
            q,
            {
                "municipality": None,
                "local_sources": [],
                "web_sources": [],
                "thresholds": [],
            },
        )
        llm_text = generate_reasoned_answer(meta_ctx)
        return {
            "text": llm_text or _meta_capability_answer(),
            "municipality": None,
            "local_sources": [],
            "web_sources": [],
            "thresholds": [],
            "web_search_used": False,
            "knowledge_pages": pages_count,
            "document_catalog": catalog,
            "assistant_mode": "architect",
            "llm_used": bool(llm_text),
            **llm_status(),
            **architect_ai_status(knowledge_pages=pages_count, catalog=catalog),
        }

    ctx = _gather_qa_context(q)
    llm_text = generate_reasoned_answer(format_context_for_llm(q, ctx))
    text = llm_text or compose_knowledge_answer(q, ctx)
    used_llm = bool(llm_text)

    return {
        "text": text,
        "municipality": ctx["municipality"],
        "local_sources": ctx["local_sources"],
        "web_sources": ctx["web_sources"],
        "thresholds": ctx["thresholds"],
        "web_search_used": ctx["web_search_used"],
        "knowledge_pages": ctx["knowledge_pages"],
        "document_catalog": catalog,
        "assistant_mode": "architect",
        "llm_used": used_llm,
        **llm_status(),
        **architect_ai_status(knowledge_pages=ctx["knowledge_pages"], catalog=catalog),
    }
