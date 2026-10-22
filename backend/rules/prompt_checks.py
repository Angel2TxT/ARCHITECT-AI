"""
Comprobaciones pedidas en lenguaje natural (uniformidad, comparación de tamaños).
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass

from .engine import Detection, ValidationIssue
from .norms import PlanRules


@dataclass
class CustomFinding:
    code: str
    message: str
    severity: str  # ok | info | warning | error
    detail: dict | None = None


def _widths_m(detections: list[Detection], ppm: float) -> list[float]:
    return [d.width_px / ppm for d in detections if ppm > 0]


def check_window_uniformity(
    detections: list[Detection],
    rules: PlanRules,
    *,
    tolerance_m: float = 0.12,
) -> tuple[list[ValidationIssue], CustomFinding | None]:
    ppm = rules.pixels_per_meter
    windows = [d for d in detections if d.class_name == "window"]
    issues: list[ValidationIssue] = []
    finding: CustomFinding | None = None

    if len(windows) < 2:
        finding = CustomFinding(
            code="WINDOW_COMPARE_SKIP",
            message=(
                f"Solo detecté {len(windows)} ventana(s). "
                "Necesito al menos 2 para comparar tamaños."
            ),
            severity="info",
        )
        return issues, finding

    widths = _widths_m(windows, ppm)
    med = statistics.median(widths)
    spread = max(widths) - min(widths)
    rel = spread / med if med > 0 else 0

    if spread > tolerance_m or rel > 0.18:
        issues.append(
            ValidationIssue(
                code="WINDOW_SIZE_UNIFORMITY",
                message=(
                    f"Ventanas con anchos distintos: "
                    f"mín {min(widths):.2f} m, máx {max(widths):.2f} m "
                    f"(mediana {med:.2f} m, diferencia {spread:.2f} m)"
                ),
                severity="warning",
                related_class="window",
                norm_ref="Criterio solicitado: uniformidad de vanos",
            )
        )
        finding = CustomFinding(
            code="WINDOW_SIZE_UNIFORMITY",
            message=f"No son del mismo tamaño: variación de {spread:.2f} m en ancho.",
            severity="warning",
            detail={
                "count": len(windows),
                "min_m": round(min(widths), 2),
                "max_m": round(max(widths), 2),
                "median_m": round(med, 2),
                "spread_m": round(spread, 2),
            },
        )
    else:
        finding = CustomFinding(
            code="WINDOW_SIZE_UNIFORMITY",
            message=(
                f"Las {len(windows)} ventanas detectadas tienen anchos similares "
                f"(~{med:.2f} m, variación {spread:.2f} m)."
            ),
            severity="ok",
            detail={
                "count": len(windows),
                "median_m": round(med, 2),
                "spread_m": round(spread, 2),
            },
        )
    return issues, finding


def check_door_uniformity(
    detections: list[Detection],
    rules: PlanRules,
    *,
    tolerance_m: float = 0.15,
) -> tuple[list[ValidationIssue], CustomFinding | None]:
    ppm = rules.pixels_per_meter
    doors = [d for d in detections if d.class_name == "door"]
    issues: list[ValidationIssue] = []
    finding: CustomFinding | None = None

    if len(doors) < 2:
        finding = CustomFinding(
            code="DOOR_COMPARE_SKIP",
            message=f"Solo detecté {len(doors)} puerta(s) para comparar.",
            severity="info",
        )
        return issues, finding

    widths = _widths_m(doors, ppm)
    med = statistics.median(widths)
    spread = max(widths) - min(widths)

    if spread > tolerance_m:
        issues.append(
            ValidationIssue(
                code="DOOR_SIZE_UNIFORMITY",
                message=(
                    f"Puertas con anchos distintos: "
                    f"mín {min(widths):.2f} m, máx {max(widths):.2f} m "
                    f"(diferencia {spread:.2f} m)"
                ),
                severity="warning",
                related_class="door",
                norm_ref="Criterio solicitado: uniformidad de accesos",
            )
        )
        finding = CustomFinding(
            code="DOOR_SIZE_UNIFORMITY",
            message=f"Puertas no uniformes: variación de {spread:.2f} m.",
            severity="warning",
            detail={"count": len(doors), "spread_m": round(spread, 2)},
        )
    else:
        finding = CustomFinding(
            code="DOOR_SIZE_UNIFORMITY",
            message=(
                f"Las {len(doors)} puertas tienen anchos similares "
                f"(~{med:.2f} m, variación {spread:.2f} m)."
            ),
            severity="ok",
            detail={"count": len(doors), "median_m": round(med, 2)},
        )
    return issues, finding


def run_prompt_checks(
    detections: list[Detection],
    rules: PlanRules,
    *,
    focus: str,
    compare_uniformity: bool,
) -> tuple[list[ValidationIssue], list[CustomFinding]]:
    extra_issues: list[ValidationIssue] = []
    findings: list[CustomFinding] = []

    if not compare_uniformity:
        return extra_issues, findings

    if focus in ("windows", "full"):
        wi, f = check_window_uniformity(detections, rules)
        extra_issues.extend(wi)
        if f:
            findings.append(f)
    if focus in ("doors", "full"):
        di, f = check_door_uniformity(detections, rules)
        extra_issues.extend(di)
        if f:
            findings.append(f)

    return extra_issues, findings
