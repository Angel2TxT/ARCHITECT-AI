"""
Texto ordenado para respuestas de análisis de plano (con LLM opcional).
Sintetiza la conclusión en un veredicto técnico ejecutivo directo (estilo Apple),
sin duplicar viñetas de hallazgos que ya se muestran en la tarjeta interactiva.
"""

from __future__ import annotations

from services.llm_service import generate_reasoned_answer, llm_configured

ANALYSIS_SYSTEM_PROMPT = """Eres el asistente de ARCHITECT al revisar un plano arquitectónico en planta.

Tu misión es emitir un veredicto técnico ejecutivo, directo, sobrio y elegante (estilo Apple).

Reglas ESTRICTAS:
1. Longitud máxima: 1 a 2 oraciones breves (entre 30 y 45 palabras en total).
2. NUNCA generes listas con viñetas (- o *), ni enumeraciones, ni títulos de secciones como "PRINCIPALES HALLAZGOS" o "Siguiente paso". El desglose completo de incidencias ya aparece en la tarjeta interactiva y en el plano marcado.
3. Dictamen claro: indica si el plano aprueba o requiere adecuaciones normativas (mencionando municipio o reglamento si aplica) y señala el ajuste prioritario más crítico (por ejemplo, ancho de acceso o ventilación).
4. Tono sobrio, profesional y de alta gama. Cero relleno, cero disclaimers, cero repetición de datos.
"""


def _issue_bullets(issues_summary: list[dict], *, limit: int = 5) -> list[str]:
    lines: list[str] = []
    for g in (issues_summary or [])[:limit]:
        label = g.get("label") or g.get("code") or "Incidencia"
        count = g.get("count", 1)
        sample = (g.get("sample_message") or "").strip()
        if sample:
            lines.append(f"- {label} ({count}×): {sample}")
        else:
            lines.append(f"- {label} ({count}×)")
    return lines


def _detection_line(detections_summary: list[dict] | None, det_count: int) -> str:
    if not detections_summary:
        return f"Elementos detectados: {det_count}."
    bits = []
    for d in detections_summary[:6]:
        label = d.get("label") or d.get("class") or "?"
        bits.append(f"{label} {d.get('count', 0)}")
    return "Detecté: " + ", ".join(bits) + "."


def format_analysis_context_for_llm(data: dict) -> str:
    errors = int((data.get("counts") or {}).get("errors") or 0)
    warnings = int((data.get("counts") or {}).get("warnings") or 0)
    det_count = int((data.get("counts") or {}).get("detections") or 0)
    intent = data.get("analysis_intent") or {}
    verdict = data.get("verdict") or {}
    juris = data.get("jurisdiction_title") or data.get("jurisdiction") or ""
    lines = [
        "DATOS DEL ANÁLISIS DE PLANO:",
        f"- Enfoque: {intent.get('title') or 'Revisión'}",
        f"- Jurisdicción: {juris}",
        f"- Detecciones: {det_count}",
        f"- Errores: {errors}",
        f"- Avisos: {warnings}",
        f"- Veredicto: {verdict.get('tone') or '—'} — {verdict.get('headline') or ''}",
    ]
    if verdict.get("detail"):
        lines.append(f"- Detalle: {verdict['detail']}")
    for g in (data.get("issues_summary") or [])[:3]:
        lines.append(
            f"- Incidencia: {g.get('label') or g.get('code')} "
            f"({g.get('count', 1)}×) {(g.get('sample_message') or '')[:120]}"
        )
    return "\n".join(lines)


def _maybe_llm_polish(draft: str, data: dict) -> tuple[str, bool]:
    if not llm_configured():
        return draft, False
    if (data.get("analysis_intent") or {}).get("list_measures"):
        return draft, False
    ctx = format_analysis_context_for_llm(data)
    polished = generate_reasoned_answer(
        f"Borrador base:\n{draft}\n\n"
        f"Datos del análisis:\n{ctx}",
        system_prompt=ANALYSIS_SYSTEM_PROMPT,
        user_instruction=(
            "Redacta un veredicto ejecutivo conciso de 1 a 2 oraciones (máximo 45 palabras). "
            "PROHIBIDO usar viñetas, guiones, listas o títulos de secciones: "
            "el usuario ya cuenta con la tarjeta interactiva y el plano marcado. "
            "Solo da el veredicto general y el ajuste prioritario."
        ),
    )
    if polished and len(polished) > 25:
        # Filtro de seguridad anti-slop: remover viñetas o encabezados redundantes
        clean_lines = []
        for line in polished.splitlines():
            s = line.strip()
            if not s:
                continue
            if s.startswith(("-", "*", "•")) or (len(s) > 2 and s[:2] in ("1.", "2.", "3.", "4.")):
                continue
            if any(s.upper().startswith(pfx) for pfx in ("PRINCIPALES", "HALLAZGOS", "SIGUIENTE PASO", "OBSERVACIONES")):
                continue
            clean_lines.append(s)
        cleaned = " ".join(clean_lines).strip()
        if cleaned and len(cleaned) > 20:
            return cleaned, True
        return polished.strip(), True
    return draft, False


def compose_analysis_reply(data: dict) -> tuple[str, list[str] | None, bool]:
    """
    Arma el texto principal del análisis.
    Devuelve (texto, steps, llm_used).
    """
    if data.get("status") == "documento_no_valido" or data.get("is_floor_plan") is False:
        custom_text = data.get("text") or data.get("rejection_reason")
        if custom_text:
            return custom_text, None, False
        reason = data.get("rejection_reason") or "El documento no corresponde a un plano arquitectónico en planta."
        text = (
            f"⚠️ **Archivo no reconocido como plano arquitectónico**\n\n"
            f"{reason}\n\n"
            f"Por favor sube una lámina o plano arquitectónico en planta (distribución de espacios, muros y vanos) para realizar la revisión normativa."
        )
        return text, None, False

    errors = int((data.get("counts") or {}).get("errors") or 0)
    warnings = int((data.get("counts") or {}).get("warnings") or 0)
    det_count = int((data.get("counts") or {}).get("detections") or 0)

    intent = data.get("analysis_intent") or {}
    intent_title = intent.get("title") or "Revisión del plano"
    conversational = bool(intent.get("conversational"))
    list_measures = bool(intent.get("list_measures"))
    measures_report = data.get("measures_report") or {}
    verdict = data.get("verdict") or {}
    issues = data.get("issues_summary") or []
    dets = data.get("detections_summary") or []
    steps: list[str] | None = None

    parts: list[str] = []

    note = (data.get("conversion_note") or "").strip()
    if note:
        parts.append(note)

    if list_measures and measures_report.get("text"):
        body = measures_report["text"].strip()
        draft = "\n\n".join(p for p in ([note, body] if note else [body]) if p)
        text, used = _maybe_llm_polish(draft, data)
        return text, None, used

    if det_count == 0:
        if data.get("is_demo_model"):
            draft = (
                "No se reconocieron puertas, ventanas ni muros claros en este plano. "
                "Para planos reales se sugiere subir un recorte nítido en planta o usar el modelo entrenado desde Ajustes."
            )
        else:
            draft = (
                "No se detectaron elementos claros en el dibujo. "
                "Asegúrate de subir una vista en planta nítida y con buen contraste para realizar la auditoría."
            )
        text, used = _maybe_llm_polish(draft, data)
        return text, steps, used

    juris = data.get("jurisdiction_title") or data.get("jurisdiction")
    juris_bit = f" ({juris})" if juris else ""

    if conversational and verdict.get("headline"):
        lead = verdict["headline"].strip()
        detail = (verdict.get("detail") or "").strip()
        verdict_text = f"{lead}. {detail}" if detail and detail not in lead else lead
        parts.append(verdict_text)
    elif errors == 0 and warnings == 0:
        parts.append(
            f"El plano aprueba satisfactoriamente la revisión «{intent_title}»{juris_bit}. "
            f"No se detectaron infracciones normativas en los {det_count} elementos analizados."
        )
    else:
        status_phrase = (
            "requiere adecuaciones normativas"
            if errors > 0
            else "presenta observaciones menores de habitabilidad"
        )
        primary_fix = ""
        if issues:
            top = issues[0]
            label = top.get("label") or top.get("code") or "dimensión"
            sample = (top.get("sample_message") or "").strip()
            if sample:
                primary_fix = f" Ajuste principal: {label} ({sample})."
            else:
                primary_fix = f" Ajuste principal: {label}."

        parts.append(
            f"El plano {status_phrase}{juris_bit}: se registraron "
            f"{errors} error{'es' if errors != 1 else ''} y {warnings} aviso{'s' if warnings != 1 else ''}.{primary_fix}"
        )

    draft = "\n\n".join(p for p in parts if p and str(p).strip())
    text, used = _maybe_llm_polish(draft, data)
    return text, steps, used
