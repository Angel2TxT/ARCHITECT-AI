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

from rules.catalog import ISSUE_LABELS
from rules.engine import Detection
from services.llm_service import generate_reasoned_answer, llm_configured, llm_status

PLAN_CONVERSATION_SYSTEM_PROMPT = """Eres el arquitecto técnico e inspector principal de ARCHITECT.
Estás conversando con el usuario en un chat donde previamente se analizó un plano arquitectónico o documento técnico.

REGLAS DE CONVERSACIÓN:
1. Responde de forma clara, natural, profesional y directa en español.
2. Si el usuario pregunta sobre el plano analizado, utiliza SIEMPRE los DATOS REALES del plano adjuntos (medidas calculadas, recintos detectados, errores y avisos normativos).
3. Si el usuario pide las medidas o dimensiones ("dame las medidas", "cuánto mide...", "área", "dimensiones"):
   - Entrega las dimensiones (ancho, largo y área en m²) de cada espacio y vano de forma limpia y estructurada con viñetas.
   - Especifica las medidas de puertas y ventanas si están disponibles.
   - Menciona la escala utilizada en píxeles por metro (px/m).
4. Si el usuario pregunta por errores, avisos o normativa sobre el plano:
   - Explica con precisión qué elemento no cumple, cuánto mide vs cuánto exige el reglamento (ej. Art. 150 para puertas, Art. 145 para habitabilidad).
   - Explica el siguiente paso práctico para corregir el plano (ej. "ampliar el vano de la puerta al menos a 0.90 m").
5. Si el usuario hace preguntas de seguimiento o consejos sobre el diseño analizado ("¿qué opinas?", "¿está bien la cocina?", "¿cómo lo soluciono?"):
   - Razona sobre la distribución real de los espacios y la habitabilidad basándote en los datos del plano.
6. NO inventes elementos que no existan en el plano analizado.
7. NO cites manuales genéricos de construcción que no tengan relación con este plano a menos que el usuario pregunte explícitamente por un manual o libro.
8. DIRECTIVA DE CAMBIO DE TEMA Y CONSULTAS GENERALES:
   Si la pregunta del usuario es una consulta general o técnica de arquitectura, ingeniería o construcción que no guarda relación con el plano analizado (por ejemplo: tiempos de fraguado de concreto, normativa sísmica general, cálculo de zapatas, costos paramétricos, saludos o teoría de diseño), respóndela directamente con tu conocimiento profesional, SIN forzar menciones al plano previo ni inventar conexiones artificiales con él.
9. Formato: respuesta directa, estructurada con negritas (**), viñetas con guion (- ) y emojis arquitectónicos discretos (📐, 🚪, 🪟, ⚠️, ✅).
"""


def _normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s or "")
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def is_measure_request(text: str) -> bool:
    """Detecta si el mensaje del usuario pide medidas o dimensiones."""
    q = _normalize(text)
    return bool(
        re.search(
            r"\b(medida|medidas|cota|cotas|dimension|dimensiones|ancho|anchos|"
            r"alto|altos|largo|largos|superficie|superficies|area|areas|"
            r"cuanto\s+mide|cuanto\s+tienen|tamano|tamanos)\b",
            q,
        )
    )


def is_plan_context_query(text: str) -> bool:
    """
    Determina si la consulta del usuario hace referencia explícita o contextual
    al plano, archivo o análisis arquitectónico previo en el chat.
    Evita forzar el contexto de planos cuando el usuario hace preguntas técnicas
    generales o cambia de tema.
    """
    q = _normalize(text)
    if not q:
        return False

    # 1. Petición explícita o deíctica de medidas del plano analizado:
    # "dame las medidas", "medidas del plano", "¿cuánto mide la cocina?", "¿cuánto mide la puerta de acceso?"
    # PERO se descarta si es pregunta normativa/estándar general ("medida mínima según reglamento", "altura estándar")
    is_general_normative = bool(
        re.search(
            r"\b(minima|minimas|minimo|minimos|maxima|maximas|maximo|maximos|"
            r"estandar|estandares|recomendad[ao]s?|segun\s+(la\s+)?norma|"
            r"segun\s+(el\s+)?reglamento|por\s+norma|reglamentari[ao]s?|"
            r"debe\s+tener|deberia\s+tener|cuanto\s+debe|que\s+exige)\b",
            q,
        )
    )

    has_explicit_plan_ref = bool(
        re.search(
            r"\b(este\s+plano|mi\s+plano|el\s+plano|del\s+plano|en\s+el\s+plano|"
            r"al\s+plano|que\s+subi|el\s+que\s+subi|archivo\s+adjunto|imagen\s+adjunta|"
            r"este\s+croquis|este\s+dibujo|en\s+este\s+diseno|en\s+mi\s+diseno|"
            r"en\s+mi\s+archivo|este\s+cuarto|esta\s+recamara|este\s+bano|esta\s+cocina|"
            r"esta\s+puerta|esta\s+ventana|en\s+este\s+espacio|en\s+esta\s+zona|aqui|ahi)\b",
            q,
        )
    )

    if is_measure_request(q):
        if is_general_normative and not has_explicit_plan_ref:
            return False
        # Si pide directamente "dame las medidas" o referencia su plano o elementos del mismo
        if has_explicit_plan_ref or re.search(
            r"\b(dame\s+las\s+medidas|pasa(me)?\s+las\s+medidas|cuales\s+son\s+las\s+medidas|"
            r"que\s+medidas\s+tiene|resumen\s+de\s+medidas|tabla\s+de\s+medidas|"
            r"todas\s+las\s+medidas|lista\s+de\s+medidas|cuanto\s+mide\s+(la|el|cada)|"
            r"dimensiones\s+y\s+area|superficie\s+total|cotas\s+de\s+las?)\b",
            q,
        ):
            return True

    # 2. Descartar consultas conceptuales, saludos o preguntas teóricas generales
    general_patterns = bool(
        re.search(
            r"\b(que\s+es|que\s+significa|que\s+diferencia|diferencia\s+entre|"
            r"definicion\s+de|concepto\s+de|como\s+se\s+calcula|como\s+se\s+disena|"
            r"cuales\s+son\s+las\s+normas|cual\s+es\s+la\s+norma|cuanto\s+tiempo\s+tarda|"
            r"que\s+tipo\s+de|a\s+que\s+profundidad|como\s+tramitar|requisitos\s+para|"
            r"que\s+permiso|costo\s+de|precio\s+de|presupuesto\s+de|tiempo\s+de\s+fraguado|"
            r"concreto|cemento|varilla|ladrillo|block|mortero|pintura|impermeabilizante|"
            r"hola|buenos\s+dias|buenas\s+tardes|buenas\s+noches|gracias|adios)\b",
            q,
        )
    )
    if general_patterns and not has_explicit_plan_ref:
        return False

    # 3. Referencias a auditoría, incidencias, errores o feedback de distribución
    audit_refs = bool(
        re.search(
            r"\b((los|que|cuales|hay|mis)\s+errores|(las|que|cuales|hay|mis)\s+incidencias|"
            r"(las|que|cuales|hay|mis)\s+observaciones|(los|que|cuales|hay|mis)\s+avisos|"
            r"errores\s+normativos|el\s+analisis|el\s+dictamen|la\s+auditoria|"
            r"por\s+que\s+no\s+cumple|por\s+que\s+fallo|como\s+lo\s+soluciono|"
            r"como\s+lo\s+corrijo|como\s+corregir|como\s+arreglar|"
            r"(esta\s+bien|como\s+ves|que\s+opinas(\s+de)?)\s+la\s+distribucion)\b",
            q,
        )
    )
    if audit_refs:
        return True

    # 4. Modificaciones o consultas de distribución/habitabilidad con referencia al plano
    if has_explicit_plan_ref:
        action_on_element = bool(
            re.search(
                r"\b(puedo\s+mover|puedo\s+quitar|puedo\s+ampliar|cabe\s+un|cabe\s+una|"
                r"cumple|no\s+cumple|esta\s+bien|que\s+opinas|como\s+lo\s+ves|"
                r"distribucion|habitabilidad|puerta|ventana|bano|cocina|sala|recamara|pasillo|"
                r"error|errores|aviso|avisos|incidencia|incidencias|observacion|observaciones|"
                r"encontraste|revisaste|analizaste|articulo\s+\d+)\b",
                q,
            )
        )
        if action_on_element:
            return True

    return False


def format_plan_context(analysis: Any) -> tuple[str, dict]:
    """
    Extrae las medidas y datos del análisis para incluirlos en el prompt de la LLM.
    """
    detections_raw = getattr(analysis, "detections_json", None) or []
    issues_raw = getattr(analysis, "issues_json", None) or []
    counts_raw = getattr(analysis, "counts_json", None) or {}
    ppm = float(getattr(analysis, "pixels_per_meter", 0.0) or 100.0)
    filename = getattr(analysis, "original_filename", "plano")

    from services.feedback_service import dict_to_detection
    from core.measures_report import build_measures_report

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
