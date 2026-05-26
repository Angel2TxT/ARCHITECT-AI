"""
Validación integral de construcción a partir de todas las detecciones del plano.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from shapely.geometry import box
from shapely.ops import unary_union

from .construction import CONSTRUCTION_DOMAINS
from .types import Detection, ValidationIssue
from .norms import CHIAPAS_RULES, PlanRules


@dataclass
class HolisticConstructionValidator:
    rules: PlanRules = field(default_factory=lambda: CHIAPAS_RULES)

    def _px_to_m(self, px: float) -> float:
        return px / self.rules.pixels_per_meter

    def _dims_m(self, det: Detection) -> tuple[float, float, float]:
        w_m = self._px_to_m(det.width_px)
        h_m = self._px_to_m(det.height_px)
        return w_m, h_m, w_m * h_m

    def _min_side_m(self, det: Detection) -> float:
        w_m, h_m, _ = self._dims_m(det)
        return min(w_m, h_m)

    def validate(self, detections: list[Detection]) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        doors = [d for d in detections if d.class_name == "door"]
        windows = [d for d in detections if d.class_name == "window"]
        rooms = [d for d in detections if d.class_name == "room"]
        walls = [d for d in detections if d.class_name == "wall"]

        issues.extend(self._check_building_completeness(rooms, walls, windows))
        issues.extend(self._check_habitability_package(rooms, windows, doors))
        issues.extend(self._check_room_access_and_ventilation(rooms, windows, doors))
        issues.extend(self._check_circulation_proxies(rooms))
        issues.extend(self._check_special_spaces(rooms, windows))
        issues.extend(self._check_urban_built_area(rooms))
        issues.extend(self._check_wall_presence(rooms, walls))
        issues.extend(self._check_manual_construction_domains(detections))
        return issues

    def _check_building_completeness(
        self,
        rooms: list[Detection],
        walls: list[Detection],
        windows: list[Detection],
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        if not rooms and not walls:
            issues.append(
                ValidationIssue(
                    code="BUILDING_INCOMPLETE",
                    message=(
                        "No se identificó cerramiento ni recintos en planta. "
                        "Revisa escala, calidad del dibujo o el modelo entrenado."
                    ),
                    severity="error",
                    related_class=None,
                    norm_ref="Integridad del proyecto",
                )
            )
        elif rooms and not windows:
            issues.append(
                ValidationIssue(
                    code="HABITABILITY_NO_WINDOWS",
                    message=(
                        "Hay recintos pero ninguna ventana detectada. "
                        "Art. 147 Tuxtla: iluminación y ventilación natural obligatorias."
                    ),
                    severity="error",
                    related_class="room",
                    norm_ref="tuxtla_rc Art. 147",
                )
            )
        return issues

    def _check_habitability_package(
        self,
        rooms: list[Detection],
        windows: list[Detection],
        doors: list[Detection],
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        n_rooms = len(rooms)
        if n_rooms == 0:
            return issues

        if n_rooms < 2:
            issues.append(
                ValidationIssue(
                    code="DWELLING_ROOM_COUNT",
                    message=(
                        f"Solo {n_rooms} recinto(s) habitacional(es) detectado(s). "
                        "Vivienda mínima suele requerir estancia, cocina y sanitario (CEV/INFONAVIT)."
                    ),
                    severity="warning",
                    related_class="room",
                    norm_ref="CEV 2010 · INFONAVIT",
                )
            )

        if n_rooms >= 2 and len(windows) / n_rooms < 0.35:
            issues.append(
                ValidationIssue(
                    code="WINDOW_PER_ROOM_LOW",
                    message=(
                        f"Ventanas/recintos bajo ({len(windows)}/{n_rooms}). "
                        "Revisa iluminación y ventilación en todas las piezas."
                    ),
                    severity="warning",
                    related_class="window",
                    norm_ref="tuxtla_rc Art. 147",
                )
            )

        if n_rooms >= 3 and len(doors) / n_rooms < 0.45:
            issues.append(
                ValidationIssue(
                    code="DOOR_PER_ROOM_LOW",
                    message=(
                        f"Pocos vanos de acceso ({len(doors)} puertas / {n_rooms} recintos). "
                        "Verifica circulación y accesos entre espacios."
                    ),
                    severity="warning",
                    related_class="door",
                    norm_ref="tuxtla_rc Art. 148",
                )
            )
        return issues

    def _check_room_access_and_ventilation(
        self,
        rooms: list[Detection],
        windows: list[Detection],
        doors: list[Detection],
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        for room in rooms:
            r = room.to_shapely().buffer(2)
            has_window = any(r.intersects(w.to_shapely()) for w in windows)
            has_door = any(r.intersects(d.to_shapely()) for d in doors)
            _, _, area_m2 = self._dims_m(room)

            if not has_window and area_m2 >= self.rules.room.min_area_m2 * 0.85:
                issues.append(
                    ValidationIssue(
                        code="ROOM_NO_WINDOW",
                        message=(
                            f"Recinto ~{area_m2:.1f} m² sin ventana detectada. "
                            "Iluminación/ventilación natural requerida."
                        ),
                        severity="warning",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 147",
                    )
                )
            if not has_door and area_m2 >= 3.0:
                issues.append(
                    ValidationIssue(
                        code="ROOM_NO_DOOR_ACCESS",
                        message=(
                            f"Recinto ~{area_m2:.1f} m² sin puerta de acceso detectada. "
                            "Revisa circulación y vanos."
                        ),
                        severity="warning",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 148",
                    )
                )
        return issues

    def _check_circulation_proxies(self, rooms: list[Detection]) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        corr_min = self.rules.circulation.corridor_min_width_m
        for room in rooms:
            w_m, h_m, area_m2 = self._dims_m(room)
            if area_m2 < 1.5:
                continue
            long_side = max(w_m, h_m)
            short_side = min(w_m, h_m)
            if long_side / max(short_side, 0.05) >= 3.2 and short_side < corr_min:
                issues.append(
                    ValidationIssue(
                        code="CORRIDOR_WIDTH_MIN",
                        message=(
                            f"Pasillo o circulación estrecha: {short_side:.2f} m "
                            f"(mín. {corr_min:.2f} m — Art. 148 Tuxtla)"
                        ),
                        severity="warning",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 148",
                    )
                )
        return issues

    def _check_special_spaces(
        self,
        rooms: list[Detection],
        windows: list[Detection],
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        rr = self.rules.room
        wr = self.rules.window

        for room in rooms:
            _, _, area_m2 = self._dims_m(room)
            r = room.to_shapely()
            win_in_room = [w for w in windows if r.intersects(w.to_shapely())]
            win_area = sum(self._dims_m(w)[2] for w in win_in_room)

            if rr.bathroom_ref_area_m2 * 0.75 <= area_m2 <= rr.bathroom_ref_area_m2 * 1.6:
                if not win_in_room or win_area < wr.min_area_m2:
                    issues.append(
                        ValidationIssue(
                            code="BATHROOM_VENTILATION",
                            message=(
                                f"Posible sanitario ~{area_m2:.1f} m² sin ventana adecuada "
                                f"(ref. {wr.min_area_m2:.2f} m² vano)."
                            ),
                            severity="warning",
                            related_class="room",
                            bbox_xyxy=room.bbox_xyxy,
                            norm_ref="CEV · ventilación sanitarios",
                        )
                    )
            if rr.kitchen_ref_area_m2 * 0.8 <= area_m2 <= rr.living_ref_area_m2 * 0.7:
                if not win_in_room:
                    issues.append(
                        ValidationIssue(
                            code="KITCHEN_VENTILATION",
                            message=(
                                f"Posible cocina ~{area_m2:.1f} m² sin ventana detectada. "
                                "Ventilación natural recomendada."
                            ),
                            severity="warning",
                            related_class="room",
                            bbox_xyxy=room.bbox_xyxy,
                            norm_ref="CEV 2010 · cocina",
                        )
                    )
            if area_m2 < rr.bedroom_ref_area_m2 and area_m2 >= rr.min_area_m2 * 1.1:
                if not win_in_room:
                    issues.append(
                        ValidationIssue(
                            code="BEDROOM_LIGHTING",
                            message=(
                                f"Posible recámara ~{area_m2:.1f} m² sin ventana. "
                                f"Referencia {rr.bedroom_ref_area_m2:.0f} m² y vano exterior."
                            ),
                            severity="warning",
                            related_class="room",
                            bbox_xyxy=room.bbox_xyxy,
                            norm_ref="INFONAVIT · Art. 147",
                        )
                    )
        return issues

    def _check_urban_built_area(self, rooms: list[Detection]) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        if not rooms:
            return issues

        geoms = [r.to_shapely() for r in rooms]
        try:
            built = unary_union(geoms)
            built_m2 = built.area / (self.rules.pixels_per_meter**2)
        except Exception:
            built_m2 = sum(self._dims_m(r)[2] for r in rooms) * 0.85

        urban = self.rules.urban
        if built_m2 > urban.max_single_story_house_m2:
            issues.append(
                ValidationIssue(
                    code="BUILT_AREA_MINOR_WORK",
                    message=(
                        f"Superficie construida estimada ~{built_m2:.0f} m² "
                        f"(obra menor unifamiliar ref. {urban.max_single_story_house_m2:.0f} m²). "
                        "Puede requerir proyecto y licencia ampliada."
                    ),
                    severity="warning",
                    related_class="room",
                    norm_ref="LDU Chiapas · tuxtla_rc",
                )
            )
        return issues

    def _check_wall_presence(
        self,
        rooms: list[Detection],
        walls: list[Detection],
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        if len(rooms) >= 2 and len(walls) < max(2, len(rooms) * 0.4):
            issues.append(
                ValidationIssue(
                    code="WALL_COVERAGE_LOW",
                    message=(
                        f"Pocos muros detectados ({len(walls)}) para {len(rooms)} recintos. "
                        "Revisa cerramientos y estructura en el plano."
                    ),
                    severity="warning",
                    related_class="wall",
                    norm_ref="Integridad · estructura/cerramiento",
                )
            )
        return issues

    def _check_manual_construction_domains(
        self, detections: list[Detection]
    ) -> list[ValidationIssue]:
        """Recordatorios normativos que no se pueden medir solo con las 4 clases YOLO."""
        if not detections:
            return []

        manual = [d for d in CONSTRUCTION_DOMAINS if not d.auto_in_planta]
        if not manual:
            return []

        titles = ", ".join(d.title for d in manual[:6])
        extra = len(manual) - 6
        suffix = f" y {extra} más" if extra > 0 else ""

        return [
            ValidationIssue(
                code="CONSTRUCTION_MANUAL_REVIEW",
                message=(
                    "Revisión complementaria obligatoria en proyecto completo: "
                    f"{titles}{suffix}. "
                    "Incluye cortes (altura 2.60 m), estructura, instalaciones, "
                    "accesibilidad, escaleras y protección civil."
                ),
                severity="info",
                related_class=None,
                norm_ref="Marco integral Chiapas",
            )
        ]


def construction_coverage_report(
    issues: list[ValidationIssue],
) -> list[dict]:
    """Estado por dominio de construcción para la API/UI."""
    codes_by_domain: dict[str, set[str]] = {
        "habitabilidad": {
            "ROOM_AREA_MIN",
            "ROOM_DIMENSION_MIN",
            "ROOM_VENTILATION_OPENING",
            "WINDOW_LIGHT_RATIO",
            "HABITABILITY_NO_WINDOWS",
            "DWELLING_ROOM_COUNT",
            "ROOM_NO_WINDOW",
            "BEDROOM_LIGHTING",
            "BATHROOM_VENTILATION",
            "KITCHEN_VENTILATION",
        },
        "vanos": {
            "DOOR_WIDTH_MIN",
            "DOOR_HEIGHT_MIN",
            "DOOR_OFF_WALL",
            "DOOR_WINDOW_OVERLAP",
            "WINDOW_WIDTH_MIN",
            "WINDOW_AREA_MIN",
            "WINDOW_PER_ROOM_LOW",
            "DOOR_PER_ROOM_LOW",
        },
        "muros": {"DOOR_OFF_WALL", "WALL_COVERAGE_LOW"},
        "circulacion": {
            "CORRIDOR_WIDTH_MIN",
            "ROOM_NO_DOOR_ACCESS",
            "DOOR_PER_ROOM_LOW",
        },
        "urbano": {"BUILT_AREA_MINOR_WORK"},
    }

    issue_codes = {i.code for i in issues}
    report: list[dict] = []

    for domain in CONSTRUCTION_DOMAINS:
        linked = codes_by_domain.get(domain.id, set())
        hits = issue_codes & linked if linked else set()
        if domain.auto_in_planta:
            if hits:
                status = "incidencias"
            else:
                status = "revisado"
        else:
            status = "manual"

        report.append(
            {
                "id": domain.id,
                "title": domain.title,
                "scope": domain.scope,
                "auto_in_planta": domain.auto_in_planta,
                "norm_ref": domain.norm_ref,
                "status": status,
                "issue_codes": sorted(hits),
            }
        )
    return report
