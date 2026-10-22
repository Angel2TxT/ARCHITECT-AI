"""
Texto ordenado para respuestas de análisis de plano (con LLM opcional).
"""

from __future__ import annotations

from services.llm_service import generate_reasoned_answer, llm_configured

ANALYSIS_SYSTEM_PROMPT = """Eres el asistente de ARCHITECT al revisar un plano arquitectónico en planta.

Reglas:
1. Responde en español claro y directo. Conclusión primero, luego 3–6 viñetas con guion (- ).
2. Usa SOLO los datos del análisis (conteos, incidencias, veredicto, hallazgos). No inventes medidas ni normas.
3. Si hay errores/avisos, nómbralos de forma concreta (tipo + cantidad). Si todo OK, dilo sin relleno.
4. Incluye 1 línea de siguiente paso práctico (qué revisar en el plano marcado).
5. No pegues comandos de terminal, listados de biblioteca ni disclaimers largos.
6. Máximo ~120 palabras.
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
    lines = [
        "Resultado del análisis de plano ARCHITECT:",
        f"- Enfoque: {intent.get('title') or 'Revisión'}",
        f"- Detecciones: {det_count}",
        f"- Errores: {errors}",
        f"- Avisos: {warnings}",
        f"- Veredicto: {verdict.get('tone') or '—'} — {verdict.get('headline') or ''}",
    ]
    if verdict.get("detail"):
        lines.append(f"- Detalle: {verdict['detail']}")
    for g in (data.get("issues_summary") or [])[:6]:
        lines.append(
            f"- Incidencia: {g.get('label') or g.get('code')} "
            f"({g.get('count', 1)}×) {(g.get('sample_message') or '')[:160]}"
        )
    for d in (data.get("detections_summary") or [])[:6]:
        lines.append(
            f"- Elemento: {d.get('label') or d.get('class')}: {d.get('count')}"
        )
    for cf in (data.get("custom_findings") or [])[:4]:
        lines.append(f"- Hallazgo ({cf.get('severity')}): {cf.get('message')}")
    return "\n".join(lines)


def _maybe_llm_polish(draft: str, data: dict) -> tuple[str, bool]:
    if not llm_configured():
        return draft, False
    if (data.get("analysis_intent") or {}).get("list_measures"):
        return draft, False
    ctx = format_analysis_context_for_llm(data)
    polished = generate_reasoned_answer(
        f"Borrador interno (puedes mejorarlo, sin inventar datos):\n{draft}\n\n"
        f"Datos del motor:\n{ctx}",
        system_prompt=ANALYSIS_SYSTEM_PROMPT,
        user_instruction=(
            "Redacta la respuesta final al usuario sobre este plano. "
            "Si el borrador ya es correcto, solo ordénalo y aclara."
        ),
    )
    if polished and len(polished) > 40:
        return polished, True
    return draft, False


def compose_analysis_reply(data: dict) -> tuple[str, list[str] | None, bool]:
    """
    Arma el texto principal del análisis.
    Devuelve (texto, steps, llm_used).
    """
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
    custom = data.get("custom_findings") or []
    steps: list[str] | None = None

    parts: list[str] = []

    note = (data.get("conversion_note") or "").strip()
    if note:
        parts.append(note)

    auto = data.get("auto_calibration") or {}
    auto_sum = (auto.get("summary") or "").strip()
    if auto_sum and not list_measures:
        parts.append(auto_sum)

    if list_measures and measures_report.get("text"):
        body = measures_report["text"].strip()
        if auto_sum:
            body = f"{auto_sum}\n\n{body}"
        draft = "\n\n".join(p for p in ([note, body] if note else [body]) if p)
        text, used = _maybe_llm_polish(draft, data)
        return text, None, used

    if det_count == 0:
        if data.get("is_demo_model"):
            draft = (
                "No pude reconocer puertas, ventanas ni muros en este plano.\n\n"
                "- El modelo demo está pensado para dibujos simples, no para láminas reales.\n"
                "- Prueba con una sola planta bien recortada (PNG/JPG nítido).\n"
                "- Si tienes plan Starter o superior, usa el modelo entrenado desde Ajustes.\n\n"
                "Sin detecciones no puedo dar un veredicto normativo confiable."
            )
        else:
            draft = (
                "No detecté elementos claros en el dibujo.\n\n"
                "- Revisa que sea una planta en planta (no corte ni 3D).\n"
                "- Sube un recorte de una sola planta, con buen contraste.\n"
                "- En Ajustes puedes bajar un poco la confianza o desactivar "
                "calibración automática.\n\n"
                "Cuando haya detecciones, te marco incidencias sobre el plano."
            )
        text, used = _maybe_llm_polish(draft, data)
        return text, steps, used

    if conversational and verdict.get("headline"):
        lead = verdict["headline"].strip()
        detail = (verdict.get("detail") or "").strip()
        parts.append(lead)
        if detail:
            parts.append(detail)
    elif errors == 0 and warnings == 0:
        parts.append(
            f"En «{intent_title}» no encontré incidencias normativas pendientes."
        )
        parts.append(_detection_line(dets, det_count))
    else:
        juris = data.get("jurisdiction")
        juris_bit = f" ({juris})" if juris else ""
        parts.append(
            f"Revisión «{intent_title}»{juris_bit}: "
            f"{errors} error{'es' if errors != 1 else ''} y "
            f"{warnings} aviso{'s' if warnings != 1 else ''}."
        )
        parts.append(_detection_line(dets, det_count))

    bullets = _issue_bullets(issues, limit=5)
    if bullets:
        parts.append("Lo principal:\n" + "\n".join(bullets))
    elif errors or warnings:
        parts.append(
            "Revisa las marcas numeradas en el plano: ahí están las incidencias detectadas."
        )

    for cf in custom[:4]:
        msg = (cf.get("message") or "").strip()
        if not msg:
            continue
        if cf.get("severity") == "ok":
            parts.append(f"- ✓ {msg}")
        else:
            parts.append(f"- {msg}")

    tips = verdict.get("suggestions") or []
    if tips:
        parts.append("Siguiente paso:\n" + "\n".join(f"- {t}" for t in tips[:3]))
    elif errors > 0:
        parts.append(
            "Siguiente paso:\n"
            "- Corrige primero lo marcado en rojo en el plano y vuelve a analizar."
        )
    elif warnings > 0:
        parts.append(
            "Siguiente paso:\n"
            "- Revisa los avisos; en algunos municipios pesan igual que un error."
        )
    else:
        parts.append(
            "Siguiente paso:\n"
            "- Confirma estructura, instalaciones y cortes en el proyecto completo "
            "(esta revisión es solo en planta)."
        )

    refs = data.get("knowledge_references") or []
    if refs and not list_measures:
        r0 = refs[0]
        title = r0.get("doc_title") or "manual"
        page = r0.get("page", "?")
        parts.append(f"Referencia útil: «{title}» (pág. {page}).")

    draft = "\n\n".join(p for p in parts if p and str(p).strip())
    text, used = _maybe_llm_polish(draft, data)
    return text, steps, used
