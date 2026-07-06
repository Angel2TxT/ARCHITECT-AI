"""
IA nativa de ARCHITECT: responde solo con lo que el sistema ya conoce
(manuales indexados, umbrales normativos y búsqueda web opcional).
Sin APIs de pago ni modelos externos.
"""

from __future__ import annotations

import re
import unicodedata

from rules.catalog import ISSUE_LABELS, NORM_BUNDLE_TITLE, NORM_SOURCES
from rules.norms import CHIAPAS_RULES

from services.web_search_service import web_search_enabled


def _normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def detect_question_intent(question: str) -> str:
    q = _normalize(question)
    if re.search(r"medida|cota|dimensi|ancho|alto|minimo|maximo|cuanto|tabla|neufert", q):
        return "measures"
    if re.search(r"que es|que son|define|significa|concepto|diferencia", q):
        return "definition"
    if re.search(r"como|proceso|pasos|tramite|licencia|permiso|solicitar", q):
        return "procedure"
    if re.search(r"plano|revis|cumple|esta bien|incidencia", q):
        return "plan"
    return "general"


def _clean_snippet(text: str, max_len: int = 420) -> str:
    t = re.sub(r"\s+", " ", (text or "").strip())
    t = re.sub(r"([a-z])([A-Z])", r"\1 \2", t)
    if len(t) > max_len:
        cut = t[:max_len].rsplit(" ", 1)[0]
        t = cut + "…" if cut else t[:max_len] + "…"
    return t


def _format_thresholds_prose(rows: list[dict]) -> str:
    if not rows:
        return ""
    if len(rows) == 1:
        t = rows[0]
        label = ISSUE_LABELS.get(t["code"], t["code"].replace("_", " ").lower())
        unit = "proporción" if t["unit"] == "ratio" else t["unit"]
        return (
            f"El umbral de referencia para {label.lower()} es {t['value']} {unit} "
            f"({t['source']})."
        )

    lines = ["Normativa configurada en ARCHITECT (Chiapas / referencia Tuxtla):"]
    for t in rows[:12]:
        label = ISSUE_LABELS.get(t["code"], t["code"].replace("_", " ").lower())
        unit = "proporción" if t["unit"] == "ratio" else t["unit"]
        lines.append(f"• {label}: {t['value']} {unit} ({t['source']})")
    return "\n".join(lines)


def _built_in_norms_summary() -> str:
    r = CHIAPAS_RULES
    lines = [
        f"Marco normativo base ({NORM_BUNDLE_TITLE}):",
        f"• Puertas: ancho mín. {r.door.min_width_m} m, altura {r.door.min_clear_height_m} m",
        f"• Recintos habitables: dimensión mín. {r.room.min_dimension_m} m, "
        f"área {r.room.min_area_m2} m², altura {r.room.min_clear_height_m} m",
        f"• Ventanas: ancho mín. {r.window.min_width_m} m, iluminación ≥ "
        f"{int(r.window.min_floor_area_ratio * 100)}% del piso (1/8)",
        f"• Circulaciones: pasillo ≥ {r.circulation.corridor_min_width_m} m",
        f"• Accesibilidad: rampa ≥ {r.accessibility.ramp_min_width_m} m",
        "• Referencias legales: "
        + ", ".join(s["name"][:40] for s in NORM_SOURCES[:4])
        + "…",
    ]
    return "\n".join(lines)


def _library_intro(catalog: list[dict]) -> str:
    if not catalog:
        return "ARCHITECT no tiene manuales indexados aún."
    names = [f"«{d['title']}» ({d['pages']} págs.)" for d in catalog[:5]]
    return "Biblioteca consultada: " + ", ".join(names) + "."


def _group_sources_by_doc(sources: list[dict]) -> dict[str, list[dict]]:
    grouped: dict[str, list[dict]] = {}
    for ref in sources:
        grouped.setdefault(ref["doc_title"], []).append(ref)
    return grouped


def _render_manual_section(sources: list[dict], intent: str) -> str:
    if not sources:
        return ""

    grouped = _group_sources_by_doc(sources)
    parts: list[str] = ["De tus manuales y tablas indexadas:"]

    for doc_title, refs in grouped.items():
        parts.append(f"\n📘 {doc_title}")
        for ref in refs[:3]:
            page = ref.get("page", "?")
            sn = _clean_snippet(ref.get("snippet", ""), 360)
            if ref.get("visual_only"):
                parts.append(f"  • Pág. {page} (diagrama/tabla): {sn}")
            else:
                parts.append(f"  • Pág. {page}: {sn}")

    if intent == "definition" and sources:
        best = sources[0]
        if not best.get("visual_only"):
            lead = _clean_snippet(best.get("snippet", ""), 500)
            parts.insert(1, f"En resumen: {lead}")

    return "\n".join(parts)


def _opening_for_intent(intent: str, municipality: str | None) -> str:
    place = f" en {municipality}" if municipality else ""
    openings = {
        "measures": (
            f"Revisé la biblioteca de ARCHITECT{place} (manuales + normas). "
            "Esto es lo relevante para medidas y dimensiones:"
        ),
        "definition": (
            "Según la documentación indexada en ARCHITECT, "
            "esto es lo que encontré sobre tu pregunta:"
        ),
        "procedure": (
            f"Con los manuales y normas disponibles{place}, "
            "esta es la orientación que puedo darte:"
        ),
        "plan": (
            "Para revisar tu plano necesito el archivo, "
            "pero con la biblioteca actual te adelanto:"
        ),
        "general": (
            f"Con base en toda la biblioteca de ARCHITECT{place} "
            "(3 manuales indexados + normativa Chiapas), te respondo:"
        ),
    }
    return openings.get(intent, openings["general"])


def _municipality_note(municipality: str | None) -> str:
    if not municipality:
        return (
            "Confirma siempre con el reglamento vigente del ayuntamiento de tu municipio."
        )
    if municipality in ("Tuxtla Gutiérrez", "Chiapas (estatal)"):
        return (
            f"Para {municipality}, ARCHITECT usa como referencia principal "
            "el reglamento de construcción de Tuxtla Gutiérrez y el marco estatal."
        )
    return (
        f"Para {municipality}: verifica en Dirección de Obras el reglamento local. "
        "Esta respuesta combina tus manuales indexados con la referencia estatal."
    )


def _plan_hint(question: str) -> str:
    q = _normalize(question)
    if re.search(r"plano|adjunt|dibujo|lamina", q):
        return ""
    return (
        "Para aplicarlo a tu proyecto concreto, adjunta el plano y pregunta "
        "«¿Este plano está bien?» o «Dame las medidas del plano»."
    )


def compose_knowledge_answer(question: str, ctx: dict) -> str:
    """Redacta respuesta conversacional solo con el contexto recopilado."""
    municipality = ctx.get("municipality")
    local = ctx.get("local_sources") or []
    thresholds = ctx.get("thresholds") or []
    web = ctx.get("web_sources") or []
    catalog = ctx.get("document_catalog") or []
    intent = detect_question_intent(question)

    parts: list[str] = [
        _opening_for_intent(intent, municipality),
        _library_intro(catalog),
    ]

    manual_block = _render_manual_section(local, intent)
    if manual_block:
        parts.append(manual_block)

    threshold_text = _format_thresholds_prose(thresholds)
    if threshold_text:
        parts.append(threshold_text)
    elif intent in ("measures", "general", "plan") and not local:
        parts.append(_built_in_norms_summary())

    if not local and not thresholds:
        parts.append(
            "No encontré coincidencias claras en el texto extraído de los PDF. "
            "Muchas páginas de Neufert y «Las medidas de una casa» son diagramas; "
            "ARCHITECT las referencia por número de página. "
            "Prueba preguntar con palabras como: cocina, recámara, Neufert, escalera, puerta."
        )

    if web:
        parts.append("Fuentes públicas relacionadas (verifica en sitio oficial):")
        for w in web[:3]:
            title = w.get("title") or "Enlace"
            snip = _clean_snippet(w.get("snippet") or "", 200)
            url = w.get("url") or ""
            line = f"• {title}: {snip}"
            if url:
                line += f"\n  {url}"
            parts.append(line)
    elif web_search_enabled() and intent in ("procedure", "general", "measures"):
        parts.append(
            "No obtuve resultados web adicionales en este momento."
        )

    parts.append(_municipality_note(municipality))

    hint = _plan_hint(question)
    if hint:
        parts.append(hint)

    return "\n\n".join(p for p in parts if p.strip())


def architect_ai_status(*, knowledge_pages: int = 0, catalog: list[dict] | None = None) -> dict:
    cat = catalog or []
    return {
        "architect_ai_enabled": True,
        "architect_ai_ready": knowledge_pages > 0,
        "knowledge_pages": knowledge_pages,
        "document_catalog": cat,
        "documents_count": len(cat),
    }
