"""
Resumen en lenguaje natural para preguntas informales («¿está bien el plano?»).
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PlanVerdict:
    tone: str  # ok | caution | fail | unknown
    headline: str
    detail: str
    suggestions: list[str]

    def to_dict(self) -> dict:
        return {
            "tone": self.tone,
            "headline": self.headline,
            "detail": self.detail,
            "suggestions": self.suggestions,
        }


def build_plan_verdict(
    *,
    errors: int,
    warnings: int,
    detections: int,
    issues_summary: list[dict],
    custom_findings: list[dict] | None = None,
    is_demo_model: bool = False,
    informal: bool = True,
) -> PlanVerdict:
    """Veredicto comprensible para el usuario."""
    suggestions: list[str] = []

    if detections == 0:
        if is_demo_model:
            return PlanVerdict(
                tone="unknown",
                headline="No puedo decirte si está bien: no reconozco elementos en este plano.",
                detail=(
                    "El modelo actual no está entrenado para este tipo de lámina. "
                    "Hace falta un modelo entrenado con planos reales."
                ),
                suggestions=[
                    "Entrena con tus planos o usa una sola planta por imagen.",
                    "Revisa la ruta a best.pt en Ajustes.",
                ],
            )
        return PlanVerdict(
            tone="unknown",
            headline="No pude revisar el dibujo con certeza.",
            detail=(
                "No detecté puertas, ventanas ni recintos. Puede ser escala, "
                "lámina muy cargada o calidad del archivo."
            ),
            suggestions=[
                "Sube solo la planta baja (un recorte).",
                "Prueba con calibración automática activada.",
            ],
        )

    cf = custom_findings or []
    cf_warn = [c for c in cf if c.get("severity") in ("warning", "error")]
    cf_ok = [c for c in cf if c.get("severity") == "ok"]

    if errors > 0:
        tone = "fail"
        if informal:
            headline = "No, todavía no está del todo bien."
        else:
            headline = f"Hay {errors} error(es) normativos que debes corregir."
        detail = _summarize_top_issues(issues_summary, errors, warnings)
        suggestions.append("Corrige primero los errores marcados en rojo en el plano.")
    elif warnings > 0:
        tone = "caution"
        if informal:
            headline = "Más o menos: va encaminado, pero hay detalles por revisar."
        else:
            headline = f"Sin errores graves; {warnings} aviso(s) a considerar."
        detail = _summarize_top_issues(issues_summary, 0, warnings)
        suggestions.append("Revisa los avisos; algunos municipios los exigen igual.")
    else:
        tone = "ok"
        if informal:
            headline = "Sí, en líneas generales se ve bien."
        else:
            headline = "No se encontraron incidencias con las reglas configuradas."
        detail = (
            f"Detecté {detections} elementos y ninguna regla automática falló. "
            "Esto no sustituye revisión de un perito ni el reglamento de tu municipio."
        )
        suggestions.append(
            "Confirma cortes, instalaciones y estructura en proyecto completo."
        )

    if cf_warn:
        detail += " " + cf_warn[0].get("message", "")
    elif cf_ok and tone == "ok":
        detail += " " + cf_ok[0].get("message", "")

    return PlanVerdict(
        tone=tone,
        headline=headline,
        detail=detail.strip(),
        suggestions=suggestions[:3],
    )


def _summarize_top_issues(
    issues_summary: list[dict],
    errors: int,
    warnings: int,
) -> str:
    if not issues_summary:
        if errors:
            return f"Hay {errors} error(es) según la normativa aplicada."
        return f"Hay {warnings} aviso(s) que conviene revisar."

    parts: list[str] = []
    for g in issues_summary[:4]:
        label = g.get("label") or g.get("code", "")
        count = g.get("count", 1)
        parts.append(f"{label} ({count}×)")
    joined = "; ".join(parts)
    if errors and warnings:
        return f"Lo principal: {joined}. En total {errors} error(es) y {warnings} aviso(s)."
    if errors:
        return f"Lo principal: {joined}."
    return f"Detalles a revisar: {joined}."
