"""
IA nativa de ARCHITECT: responde con manuales indexados, umbrales y web opcional.
Sin LLM externo por defecto; si hay LLM_PROVIDER configurado, qa_service lo usa primero.
"""

from __future__ import annotations

import re
import unicodedata

from rules.catalog import ISSUE_LABELS, NORM_BUNDLE_TITLE
from rules.norms import CHIAPAS_RULES


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


def _format_thresholds_prose(rows: list[dict], *, limit: int = 5) -> str:
    if not rows:
        return ""
    rows = rows[:limit]
    if len(rows) == 1:
        t = rows[0]
        label = ISSUE_LABELS.get(t["code"], t["code"].replace("_", " ").lower())
        unit = "proporción" if t["unit"] == "ratio" else t["unit"]
        return (
            f"Umbral de referencia: {label.lower()} = {t['value']} {unit} "
            f"({t['source']})."
        )

    lines = ["Umbrales relevantes (Chiapas / Tuxtla):"]
    for t in rows:
        label = ISSUE_LABELS.get(t["code"], t["code"].replace("_", " ").lower())
        unit = "proporción" if t["unit"] == "ratio" else t["unit"]
        lines.append(f"• {label}: {t['value']} {unit} ({t['source']})")
    return "\n".join(lines)


def _built_in_norms_brief(intent: str) -> str:
    """Resumen corto solo cuando la pregunta pide medidas/normas y no hay match local."""
    r = CHIAPAS_RULES
    if intent == "measures":
        return (
            f"Referencia rápida ({NORM_BUNDLE_TITLE}): "
            f"puerta ≥ {r.door.min_width_m} m; "
            f"pasillo ≥ {r.circulation.corridor_min_width_m} m; "
            f"recinto habitable ≥ {r.room.min_area_m2} m² / "
            f"{r.room.min_clear_height_m} m de altura."
        )
    return (
        f"Marco base ({NORM_BUNDLE_TITLE}): puertas, habitabilidad, ventanas e "
        f"iluminación (≥ {int(r.window.min_floor_area_ratio * 100)}% del piso)."
    )


def _group_sources_by_doc(sources: list[dict]) -> dict[str, list[dict]]:
    grouped: dict[str, list[dict]] = {}
    for ref in sources:
        grouped.setdefault(ref["doc_title"], []).append(ref)
    return grouped


def _lead_from_sources(sources: list[dict], intent: str) -> str:
    """Primera respuesta útil a partir del mejor fragmento."""
    if not sources:
        return ""
    best = sources[0]
    sn = _clean_snippet(best.get("snippet", ""), 520 if intent == "definition" else 380)
    if not sn:
        return ""
    doc = best.get("doc_title") or "manual"
    page = best.get("page", "?")
    if best.get("visual_only"):
        return f"En «{doc}» (pág. {page}, diagrama/tabla): {sn}"
    if intent == "definition":
        return sn
    return f"Según «{doc}» (pág. {page}): {sn}"


def _render_extra_sources(sources: list[dict], *, skip_first: bool = True) -> str:
    if not sources:
        return ""
    refs = sources[1:4] if skip_first and len(sources) > 1 else sources[:3]
    if not refs:
        return ""
    grouped = _group_sources_by_doc(refs)
    parts: list[str] = ["Más detalle en tus manuales:"]
    for doc_title, items in grouped.items():
        parts.append(f"• {doc_title}")
        for ref in items[:2]:
            page = ref.get("page", "?")
            sn = _clean_snippet(ref.get("snippet", ""), 220)
            parts.append(f"  – Pág. {page}: {sn}")
    return "\n".join(parts)


def _wants_plan_application(question: str) -> bool:
    q = _normalize(question)
    return bool(re.search(r"plano|adjunt|dibujo|lamina|mi\s+proyecto|este\s+proyecto", q))


def _plan_hint(question: str) -> str:
    if not _wants_plan_application(question):
        return ""
    return (
        "Si quieres aplicarlo a un plano concreto, adjúntalo y pregunta "
        "«¿Este plano está bien?» o «Dame las medidas del plano»."
    )


def _municipality_disclaimer(municipality: str | None, intent: str) -> str:
    if intent not in ("measures", "procedure", "plan"):
        return ""
    if municipality in ("Tuxtla Gutiérrez", "Chiapas (estatal)"):
        return f"Referencia principal: reglamento de {municipality}."
    if municipality:
        return (
            f"Para {municipality}, confirma el reglamento local en Obras Públicas."
        )
    return "Confirma siempre con el reglamento vigente de tu municipio."


def _format_web(web: list[dict]) -> str:
    if not web:
        return ""
    lines = ["Fuentes públicas (verifica en sitio oficial):"]
    for w in web[:3]:
        title = w.get("title") or "Enlace"
        snip = _clean_snippet(w.get("snippet") or "", 180)
        url = w.get("url") or ""
        line = f"• {title}: {snip}"
        if url:
            line += f"\n  {url}"
        lines.append(line)
    return "\n".join(lines)


def _smart_offline_answer(question: str) -> str:
    q = _normalize(question)
    if re.search(r"cemento|concreto|material|bulto|varilla|block|ladrillo|arena|grava", q):
        return (
            "Orientación técnica sobre dosificación y materiales de obra:\n"
            "• Concreto estructural (f'c=200 a 250 kg/cm² para losas, castillos y trabes): "
            "Proporción en volumen 1:2:3 (1 bulto de cemento de 50 kg, 2 botes de arena, 3 botes de grava de 3/4 pulg. y ~18-20 L de agua).\n"
            "• Rendimiento: 1 m³ de concreto estructural requiere aproximadamente 7 a 7.5 sacos de cemento.\n"
            "• Losas de entrepiso/azotea: Losa maciza de 10 cm requiere 0.10 m³ de concreto por m² y armado con varilla de 3/8 pulg. a cada 15 o 20 cm.\n"
            "• Muros de block (15x20x40 cm): Rinden ~12.5 piezas por m² más mortero proporción 1:4 (cemento-arena)."
        )
    if re.search(r"cimentacion|zapata|cimiento|cadena|desplante", q):
        return (
            "Criterios para cimentaciones residenciales:\n"
            "• Mampostería de piedra braza: Muy empleada en suelos estables, corona mínima de 30 cm y base entre 60 y 90 cm según carga.\n"
            "• Zapatas de concreto armado: Para terrenos arcillosos o deformables, con base mínima de 15 a 20 cm de espesor y contratrabes de rigidez.\n"
            "• Cadena de desplante: Sección mínima de 15x20 cm armada con 4 varillas de 3/8 pulg. y estribos de 1/4 pulg. a cada 15 cm para repartir cargas y cortar humedad."
        )
    if re.search(r"costo|precio|presupuesto|cuanto\s+cuesta|cuanto\s+sale|m2|metro\s+cuadrado", q):
        return (
            "Costos paramétricos de referencia para edificación residencial (México):\n"
            "• Obra negra básica (cimentación, muros, losas): ~$3,500 a $5,500 MXN por m².\n"
            "• Obra gris con instalaciones hidrosanitarias y eléctricas: ~$6,000 a $8,500 MXN por m².\n"
            "• Obra terminada con acabados medios: ~$9,500 a $14,000 MXN por m².\n"
            "• Nota: Los costos varían por topografía, mecánica de suelos, acabados y fletes locales."
        )
    if re.search(r"licencia|permiso|tramite|dro|director\s+responsable|municipio", q):
        return (
            "Procedimiento estándar para licencias de construcción residencial:\n"
            "1. Constancia de Alineamiento y Número Oficial vigente.\n"
            "2. Planos arquitectónicos y ejecutivos completos (plantas, cortes, fachadas, instalaciones y cimentación).\n"
            "3. Firma de Director Responsable de Obra (D.R.O.) cuando la superficie supera obra menor (más de 40 a 60 m²).\n"
            "4. Pago de derechos de construcción en la tesorería municipal y predial al corriente."
        )
    if re.search(r"sala|comedor|estancia|cochera|estacionamiento|jardin|patio", q):
        return (
            "Dimensiones funcionales recomendadas (Neufert / Habitabilidad):\n"
            "• Sala de estar: Mínimo 3.00 × 3.00 m (9.00 m²) para conjunto modular y circulación cómoda.\n"
            "• Comedor: Mínimo 2.80 × 2.80 m para mesa de 6 sillas con holgura perimetral libre de 80 cm.\n"
            "• Cajón de estacionamiento: Mínimo 2.50 × 5.00 m (y 3.80 × 5.00 m para accesibilidad universal PCD).\n"
            "• Patio de servicio: Área mínima libre de 4.00 a 6.00 m² con ventilación natural directa."
        )
    return (
        "Asesoría técnica de ARCHITECT:\n"
        "• Dimensiones mínimas reglamentarias: Puertas principales ≥ 0.90 m, recámaras ≥ 0.80 m, pasillos ≥ 1.20 m, recámara principal ≥ 7.29 m² y altura libre de losa ≥ 2.50 m en Chiapas.\n"
        "• Auditoría de planos: Puedes adjuntar tu plano en imagen o PDF para escanear cotas, vanos e incidencias normativas de habitabilidad.\n"
        "• Consultas de obra: Pregunta sobre cálculo de materiales, cimentaciones, losas, acabados, instalaciones o presupuestos."
    )


def compose_knowledge_answer(question: str, ctx: dict) -> str:
    """
    Respuesta directa: primero lo útil, luego fuentes breves.
    Sin aperturas de biblioteca ni listados masivos.
    """
    municipality = ctx.get("municipality")
    local = ctx.get("local_sources") or []
    thresholds = ctx.get("thresholds") or []
    web = ctx.get("web_sources") or []
    intent = detect_question_intent(question)

    parts: list[str] = []

    lead = _lead_from_sources(local, intent)
    if lead:
        parts.append(lead)
    else:
        threshold_text = _format_thresholds_prose(thresholds, limit=5)
        if threshold_text:
            parts.append(threshold_text)
        elif intent in ("measures", "plan"):
            parts.append(_built_in_norms_brief(intent))
        elif web:
            first = web[0]
            sn = _clean_snippet(first.get("snippet") or "", 280)
            title = first.get("title") or "fuente pública"
            parts.append(f"Según {title}: {sn}" if sn else f"Referencia: {title}")
        else:
            parts.append(_smart_offline_answer(question))

    # Umbrales solo si aportan y no fueron ya el lead
    if lead and thresholds:
        thr = _format_thresholds_prose(thresholds, limit=4)
        if thr:
            parts.append(thr)

    extra = _render_extra_sources(local, skip_first=True)
    if extra:
        parts.append(extra)

    web_block = _format_web(web)
    if web_block:
        parts.append(web_block)

    disc = _municipality_disclaimer(municipality, intent)
    if disc:
        parts.append(disc)

    hint = _plan_hint(question)
    if hint:
        parts.append(hint)

    return "\n\n".join(p for p in parts if p.strip())


def format_context_for_llm(question: str, ctx: dict) -> str:
    """Empaqueta el contexto RAG de forma compacta para el LLM."""
    lines = [f"Pregunta del usuario:\n{question.strip()}\n"]

    municipality = ctx.get("municipality")
    if municipality:
        lines.append(f"Municipio detectado: {municipality}")

    local = ctx.get("local_sources") or []
    if local:
        lines.append("\nFragmentos de manuales indexados:")
        for ref in local[:6]:
            page = ref.get("page", "?")
            title = ref.get("doc_title") or "doc"
            sn = _clean_snippet(ref.get("snippet", ""), 320)
            lines.append(f"- [{title} p.{page}] {sn}")

    thresholds = ctx.get("thresholds") or []
    if thresholds:
        lines.append("\nUmbrales normativos configurados:")
        for t in thresholds[:6]:
            label = ISSUE_LABELS.get(t["code"], t["code"])
            unit = "proporción" if t["unit"] == "ratio" else t["unit"]
            lines.append(f"- {label}: {t['value']} {unit} ({t['source']})")

    web = ctx.get("web_sources") or []
    if web:
        lines.append("\nResultados web:")
        for w in web[:4]:
            lines.append(
                f"- {w.get('title') or 'Fuente'}: "
                f"{_clean_snippet(w.get('snippet') or '', 200)} "
                f"({w.get('url') or ''})"
            )

    if not local and not thresholds and not web:
        lines.append(
            "\n(Aplica tu conocimiento general experto en arquitectura, ingeniería civil y construcción "
            "para entregar una respuesta completa, práctica, didáctica y profesional.)"
        )

    return "\n".join(lines)


def architect_ai_status(*, knowledge_pages: int = 0, catalog: list[dict] | None = None) -> dict:
    cat = catalog or []
    return {
        "architect_ai_enabled": True,
        "architect_ai_ready": knowledge_pages > 0,
        "knowledge_pages": knowledge_pages,
        "document_catalog": cat,
        "documents_count": len(cat),
    }
