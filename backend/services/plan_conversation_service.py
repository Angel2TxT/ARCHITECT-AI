"""
Servicio conversacional sobre planos arquitectónicos analizados.
Permite continuar la conversación en el chat sobre el plano analizado:
- Responder preguntas sobre medidas y dimensiones de recintos, puertas y vanos.
- Explicar incidencias normativas detectadas y cómo remediarlas.
- Resolver dudas de distribución, habitabilidad y cumplimiento de reglamento.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any

from core.measures_report import CLASS_LABELS_ES, build_measures_report
from rules.catalog import ISSUE_LABELS
from rules.engine import Detection
from services.feedback_service import dict_to_detection
from services.llm_service import generate_reasoned_answer, llm_configured, llm_status

PLAN_CONVERSATION_SYSTEM_PROMPT = """Eres el arquitecto técnico e inspector principal de ARCHITECT.
Estás conversando con el usuario sobre un plano arquitectónico que ya fue analizado previamente en este chat.

REGLAS DE CONVERSACIÓN:
1. Responde de forma clara, natural, profesional y directa en español.
2. Utiliza SIEMPRE los DATOS REALES del plano adjuntos (medidas calculadas, recintos detectados, errores y avisos normativos).
3. Si el usuario pide las medidas o dimensiones ("dame las medidas", "cuánto mide...", "área", "dimensiones"):
   - Entrega las dimensiones (ancho, largo y área en m²) de cada espacio y vano de forma limpia y estructurada con viñetas.
   - Especifica las medidas de puertas y ventanas si están disponibles.
   - Menciona la escala utilizada en píxeles por metro (px/m).
4. Si el usuario pregunta por errores, avisos o normativa:
   - Explica con precisión qué elemento no cumple, cuánto mide vs cuánto exige el reglamento (ej. Art. 150 para puertas, Art. 145 para habitabilidad).
   - Explica el siguiente paso práctico para corregir el plano (ej. "ampliar el vano de la puerta al menos a 0.90 m").
5. Si el usuario hace preguntas de seguimiento o consejos ("¿qué opinas?", "¿está bien la cocina?", "¿cómo lo soluciono?"):
   - Razona sobre la distribución real de los espacios y la habitabilidad basándote en los datos del plano.
6. NO inventes elementos que no existan en el plano analizado.
7. NO cites manuales genéricos de construcción que no tengan relación con este plano a menos que el usuario pregunte explícitamente por un manual o libro.
8. Formato: respuesta directa, estructurada con negritas (**), viñetas con guion (- ) y emojis arquitectónicos discretos (📐, 🚪, 🪟, ⚠️, ✅).
"""


def _normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s or "")
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def is_measure_request(text: str) -> bool:
    """Detecta si el mensaje del usuario pide medidas o dimensiones del plano."""
    q = _normalize(text)
    return bool(
        re.search(
            r"\b(medida|medidas|cota|cotas|dimension|dimensiones|ancho|anchos|"
            r"alto|altos|largo|largos|superficie|superficies|area|areas|"
            r"cuanto\s+mide|cuanto\s+tienen|tamano|tamanos)\b",
            q,
        )
    )


def format_plan_context(analysis: Any) -> tuple[str, dict]:
    """
    Extrae las medidas y datos del análisis para incluirlos en el prompt de la LLM.
    """
    detections_raw = getattr(analysis, "detections_json", None) or []
    issues_raw = getattr(analysis, "issues_json", None) or []
    counts_raw = getattr(analysis, "counts_json", None) or {}
    ppm = float(getattr(analysis, "pixels_per_meter", 0.0) or 100.0)
    filename = getattr(analysis, "original_filename", "plano")

    detections: list[Detection] = []
    for d in detections_raw:
        if isinstance(d, dict):
            try:
                detections.append(dict_to_detection(d))
            except Exception:
                pass

    measures = build_measures_report(detections, ppm)

    measures_lines: list[str] = []
    for item in measures.get("items", []):
        t = item.get("tipo", "Elemento")
        w = item.get("ancho_m", 0)
        h = item.get("largo_m", 0)
        a = item.get("area_m2", 0)
        num = item.get("num", 1)
        measures_lines.append(f"- #{num} {t}: ancho {w} m × largo {h} m (superficie {a} m²)")

    issues_lines: list[str] = []
    for iss in issues_raw:
        if isinstance(iss, dict):
            sev = iss.get("severity", "aviso")
            lbl = iss.get("label") or iss.get("code") or "Incidencia"
            msg = iss.get("message") or ""
            ref = iss.get("norm_ref") or ""
            ref_str = f" [{ref}]" if ref else ""
            issues_lines.append(f"- [{sev.upper()}] {lbl}: {msg}{ref_str}")

    context_text = (
        f"DATOS DEL PLANO ACTUALMENTE EN EL CHAT:\n"
        f"- Archivo: {filename}\n"
        f"- Escala calculada: {ppm:.1f} píxeles/metro\n"
        f"- Elementos detectados: {len(detections)}\n"
        f"- Errores normativos: {counts_raw.get('errors', 0)}\n"
        f"- Avisos normativos: {counts_raw.get('warnings', 0)}\n\n"
        f"LISTADO DE ESPACIOS Y MEDIDAS CALCULADAS:\n"
        f"{chr(10).join(measures_lines) if measures_lines else 'Sin elementos calculados.'}\n\n"
        f"INCIDENCIAS Y ERRORES REPORTADOS:\n"
        f"{chr(10).join(issues_lines[:15]) if issues_lines else 'Sin incidencias pendientes.'}\n"
    )

    return context_text, measures


def answer_plan_conversation(
    question: str,
    analysis: Any,
    *,
    recent_messages: list[dict] | None = None,
) -> dict:
    """
    Genera una respuesta conversacional precisa sobre el plano analizado.
    """
    q = (question or "").strip()
    context_text, measures = format_plan_context(analysis)
    wants_measures = is_measure_request(q)

    # Conversación reciente (últimos 3 mensajes si existen)
    chat_snippet = ""
    if recent_messages:
        snippets = []
        for m in recent_messages[-4:]:
            role = "Usuario" if m.get("role") == "user" else "IA ARCHITECT"
            txt = (m.get("text") or (m.get("content") or {}).get("text") or "")[:200]
            if txt:
                snippets.append(f"{role}: {txt}")
        if snippets:
            chat_snippet = "HISTORIAL RECIENTE DEL CHAT:\n" + "\n".join(snippets) + "\n\n"

    user_instruction = (
        f"{chat_snippet}"
        f"{context_text}\n"
        f"PREGUNTA DEL USUARIO:\n«{q}»\n\n"
        "Instrucción: Responde a la pregunta del usuario sobre este plano específico de forma concisa, "
        "útil y bien estructurada."
    )

    llm_resp = generate_reasoned_answer(
        user_instruction,
        system_prompt=PLAN_CONVERSATION_SYSTEM_PROMPT,
        user_instruction="Responde directamente al usuario sobre su plano.",
    )

    if llm_resp and len(llm_resp.strip()) > 30:
        return {
            "text": llm_resp.strip(),
            "type": "plan_conversation",
            "analysis_id": getattr(analysis, "id", None),
            "measures_report": measures,
            "llm_used": True,
            "assistant_mode": "architect_plan",
        }

    # Fallback determinista si LLM está offline o falla
    if wants_measures:
        filename = getattr(analysis, "original_filename", "tu plano")
        items = measures.get("items", [])
        if items:
            lines = [f"📐 **Medidas estimadas en {filename}:**\n"]
            for it in items:
                lines.append(
                    f"- **{it['tipo']} #{it['num']}:** {it['ancho_m']} m de ancho × "
                    f"{it['largo_m']} m de largo (Área: **{it['area_m2']} m²**)"
                )
            ppm = getattr(analysis, "pixels_per_meter", 100.0)
            lines.append(f"\n*Escala usada:* {ppm:.0f} px/m.")
            return {
                "text": "\n".join(lines),
                "type": "plan_conversation",
                "analysis_id": getattr(analysis, "id", None),
                "measures_report": measures,
                "llm_used": False,
                "assistant_mode": "architect_plan",
            }
        else:
            return {
                "text": "No se encontraron elementos con medidas en el plano actual.",
                "type": "plan_conversation",
                "analysis_id": getattr(analysis, "id", None),
                "measures_report": measures,
                "llm_used": False,
                "assistant_mode": "architect_plan",
            }

    # Fallback general
    counts = getattr(analysis, "counts_json", {}) or {}
    err_n = counts.get("errors", 0)
    warn_n = counts.get("warnings", 0)
    return {
        "text": (
            f"Sobre tu plano analizado (**{getattr(analysis, 'original_filename', 'plano')}**):\n\n"
            f"- **Estado:** {getattr(analysis, 'status_text', 'Analizado')}\n"
            f"- **Incidencias:** {err_n} errores y {warn_n} avisos normativos.\n"
            f"¿Deseas conocer las medidas de los espacios o los detalles de cada error?"
        ),
        "type": "plan_conversation",
        "analysis_id": getattr(analysis, "id", None),
        "measures_report": measures,
        "llm_used": False,
        "assistant_mode": "architect_plan",
    }
