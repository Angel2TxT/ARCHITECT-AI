"""
Cálculo automatizado de Iluminación y Ventilación Natural por Recinto.

Aplica la relación geométrica entre vanos de ventanas detectados y los
recintos correspondientes, evaluando los coeficientes normativos exigidos
por el Reglamento de Construcción (Chiapas Art. 147, CDMX Art. 83 y CEV).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

from shapely.geometry import box

from .norms import CHIAPAS_RULES, PlanRules
from .types import Detection, ValidationIssue


@dataclass
class RoomHabitabilityMetric:
    """Métricas de habitabilidad física y ambiental para un recinto."""

    room_index: int
    room_type: str
    bbox_xyxy: tuple[float, float, float, float]
    room_area_m2: float
    window_count: int
    total_window_area_m2: float
    effective_ventilation_area_m2: float
    lighting_ratio: float
    ventilation_ratio: float
    min_lighting_ratio: float
    min_ventilation_ratio: float
    lighting_status: str  # "compliant" | "deficit" | "missing_window"
    ventilation_status: str  # "compliant" | "deficit" | "missing_window"
    status: str  # "compliant" | "warning" | "error"
    lighting_deficit_m2: float
    ventilation_deficit_m2: float
    recommendation: str

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["bbox_xyxy"] = [round(float(v), 2) for v in self.bbox_xyxy]
        d["room_area_m2"] = round(self.room_area_m2, 2)
        d["total_window_area_m2"] = round(self.total_window_area_m2, 2)
        d["effective_ventilation_area_m2"] = round(self.effective_ventilation_area_m2, 2)
        d["lighting_ratio_percent"] = round(self.lighting_ratio * 100, 1)
        d["ventilation_ratio_percent"] = round(self.ventilation_ratio * 100, 1)
        d["min_lighting_ratio_percent"] = round(self.min_lighting_ratio * 100, 1)
        d["min_ventilation_ratio_percent"] = round(self.min_ventilation_ratio * 100, 1)
        d["lighting_deficit_m2"] = round(self.lighting_deficit_m2, 2)
        d["ventilation_deficit_m2"] = round(self.ventilation_deficit_m2, 2)
        return d


@dataclass
class EnvironmentalReport:
    """Reporte agregado de desempeño ambiental y normativo de la planta."""

    total_rooms_evaluated: int = 0
    compliant_rooms_count: int = 0
    rooms_with_lighting_deficit: int = 0
    rooms_with_ventilation_deficit: int = 0
    rooms_without_windows: int = 0
    overall_compliance_percent: float = 0.0
    overall_status: str = "compliant"  # "compliant" | "warning" | "non_compliant"
    jurisdiction_ref: str = "Reglamento de Construcción (Chiapas Art. 147 / CDMX Art. 83)"
    room_metrics: list[RoomHabitabilityMetric] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "total_rooms_evaluated": self.total_rooms_evaluated,
            "compliant_rooms_count": self.compliant_rooms_count,
            "rooms_with_lighting_deficit": self.rooms_with_lighting_deficit,
            "rooms_with_ventilation_deficit": self.rooms_with_ventilation_deficit,
            "rooms_without_windows": self.rooms_without_windows,
            "overall_compliance_percent": round(self.overall_compliance_percent, 1),
            "overall_status": self.overall_status,
            "jurisdiction_ref": self.jurisdiction_ref,
            "rooms": [m.to_dict() for m in self.room_metrics],
        }


def _px_to_m(px: float, ppm: float) -> float:
    return px / max(ppm, 1e-4)


def _dims_m(det: Detection, ppm: float) -> tuple[float, float, float]:
    w_m = _px_to_m(det.width_px, ppm)
    h_m = _px_to_m(det.height_px, ppm)
    return w_m, h_m, w_m * h_m


def evaluate_environmental_habitability(
    detections: list[Detection],
    rules: PlanRules | None = None,
) -> tuple[EnvironmentalReport, list[ValidationIssue]]:
    """
    Evalúa la relación de iluminación y ventilación natural para todos los recintos
    detectados frente a las ventanas asociadas.
    """
    if rules is None:
        rules = CHIAPAS_RULES

    ppm = rules.pixels_per_meter
    wr = rules.window

    # Filtrar recintos evaluables (habitación general, baños y cocinas tipadas)
    evaluable_room_classes = {"room", "bathroom", "kitchen"}
    rooms = [d for d in detections if d.class_name in evaluable_room_classes]
    windows = [d for d in detections if d.class_name == "window"]

    issues: list[ValidationIssue] = []
    room_metrics: list[RoomHabitabilityMetric] = []

    # Buffer en píxeles equivalente a ~0.35 metros de grosor de muro para capturar
    # vanos adyacentes al perímetro del recinto
    wall_buffer_px = max(ppm * 0.35, 12.0)

    # Coeficientes requeridos por norma
    req_light_ratio = getattr(wr, "min_floor_area_ratio", 0.125)  # 1/8 = 12.5%
    req_vent_ratio = getattr(wr, "min_ventilation_area_ratio", 0.05)  # 1/20 = 5%

    for idx, room in enumerate(rooms, start=1):
        _, _, room_area_m2 = _dims_m(room, ppm)
        if room_area_m2 < 1.0:
            continue

        r_geom = room.to_shapely()
        buffered_r = r_geom.buffer(wall_buffer_px)

        # Encontrar todas las ventanas que intersectan o colindan con el recinto
        associated_windows = [w for w in windows if buffered_r.intersects(w.to_shapely())]
        win_count = len(associated_windows)

        # Sumatoria de área de vanos asociados
        total_win_area = sum(_dims_m(w, ppm)[2] for w in associated_windows)

        # La apertura útil para ventilación en ventanas típicas (corredizas/proyección)
        # se calcula al 50% de la superficie total del vano
        effective_vent_area = total_win_area * 0.50

        light_ratio = total_win_area / room_area_m2 if room_area_m2 > 0 else 0.0
        vent_ratio = effective_vent_area / room_area_m2 if room_area_m2 > 0 else 0.0

        light_status = "compliant"
        vent_status = "compliant"
        status = "compliant"
        recs: list[str] = []

        light_deficit = max(0.0, (room_area_m2 * req_light_ratio) - total_win_area)
        vent_deficit = max(0.0, (room_area_m2 * req_vent_ratio) - effective_vent_area)

        is_bathroom = room.class_name == "bathroom" or (
            room.class_name == "room" and 1.8 <= room_area_m2 <= 4.8
        )
        is_kitchen = room.class_name == "kitchen"

        norm_article = "Art. 147 Tuxtla / Art. 83 RCDF"

        if win_count == 0:
            light_status = "missing_window"
            vent_status = "missing_window"
            status = "error" if not is_bathroom else "warning"

            code = "ROOM_NO_WINDOW"
            if is_bathroom:
                code = "BATHROOM_VENTILATION"
                msg = (
                    f"Sanitario (~{room_area_m2:.1f} m²) sin ventana de ventilación. "
                    "Requiere vano mín. de 1/10 o extracción mecánica conforme a norma."
                )
            elif is_kitchen:
                code = "KITCHEN_VENTILATION"
                msg = (
                    f"Cocina (~{room_area_m2:.1f} m²) sin ventana exterior detectada. "
                    "Requiere ventilación natural directa para evacuación de humos."
                )
            else:
                msg = (
                    f"Recinto habitable (~{room_area_m2:.1f} m²) sin ventana detectada. "
                    f"Normativa ({norm_article}) exige iluminación y ventilación natural directa."
                )

            recs.append(
                f"Proyectar vano de ventana de al menos {(room_area_m2 * req_light_ratio):.2f} m² hacia fachada o patio de iluminación."
            )

            issues.append(
                ValidationIssue(
                    code=code,
                    message=msg,
                    severity="error" if not is_bathroom else "warning",
                    related_class=room.class_name,
                    bbox_xyxy=room.bbox_xyxy,
                    norm_ref=norm_article,
                )
            )
        else:
            # Evaluar iluminación
            if light_ratio < req_light_ratio:
                light_status = "deficit"
                status = "warning"
                recs.append(
                    f"Aumentar vano de ventana en +{light_deficit:.2f} m² para alcanzar el {req_light_ratio*100:.1f}% requerido."
                )
                issues.append(
                    ValidationIssue(
                        code="WINDOW_LIGHT_RATIO",
                        message=(
                            f"Iluminación insuficiente en recinto (~{room_area_m2:.1f} m²): "
                            f"{light_ratio * 100:.1f}% del piso (mín. {req_light_ratio * 100:.1f}% — {norm_article}). "
                            f"Déficit: {light_deficit:.2f} m²."
                        ),
                        severity="warning",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref=norm_article,
                    )
                )

            # Evaluar ventilación
            if vent_ratio < req_vent_ratio:
                vent_status = "deficit"
                if status == "compliant":
                    status = "warning"
                recs.append(
                    f"Superficie de apertura de ventilación deficiente en {vent_deficit:.2f} m²."
                )
                issues.append(
                    ValidationIssue(
                        code="ROOM_VENTILATION_OPENING",
                        message=(
                            f"Ventilación natural insuficiente en recinto (~{room_area_m2:.1f} m²): "
                            f"apertura útil {vent_ratio * 100:.1f}% (mín. {req_vent_ratio * 100:.1f}% — {norm_article})."
                        ),
                        severity="warning",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref=norm_article,
                    )
                )

        if not recs:
            recs.append("Cumple satisfactoriamente con los ratios de habitabilidad natural.")

        metric = RoomHabitabilityMetric(
            room_index=idx,
            room_type=room.class_name,
            bbox_xyxy=room.bbox_xyxy,
            room_area_m2=room_area_m2,
            window_count=win_count,
            total_window_area_m2=total_win_area,
            effective_ventilation_area_m2=effective_vent_area,
            lighting_ratio=light_ratio,
            ventilation_ratio=vent_ratio,
            min_lighting_ratio=req_light_ratio,
            min_ventilation_ratio=req_vent_ratio,
            lighting_status=light_status,
            ventilation_status=vent_status,
            status=status,
            lighting_deficit_m2=light_deficit,
            ventilation_deficit_m2=vent_deficit,
            recommendation=" ".join(recs),
        )
        room_metrics.append(metric)

    total_eval = len(room_metrics)
    comp_count = sum(1 for m in room_metrics if m.status == "compliant")
    light_def_count = sum(1 for m in room_metrics if m.lighting_status != "compliant")
    vent_def_count = sum(1 for m in room_metrics if m.ventilation_status != "compliant")
    no_win_count = sum(1 for m in room_metrics if m.window_count == 0)

    comp_pct = (comp_count / total_eval * 100.0) if total_eval > 0 else 100.0

    if comp_pct >= 90.0:
        overall_status = "compliant"
    elif comp_pct >= 60.0:
        overall_status = "warning"
    else:
        overall_status = "non_compliant"

    report = EnvironmentalReport(
        total_rooms_evaluated=total_eval,
        compliant_rooms_count=comp_count,
        rooms_with_lighting_deficit=light_def_count,
        rooms_with_ventilation_deficit=vent_def_count,
        rooms_without_windows=no_win_count,
        overall_compliance_percent=comp_pct,
        overall_status=overall_status,
        room_metrics=room_metrics,
    )

    return report, issues
