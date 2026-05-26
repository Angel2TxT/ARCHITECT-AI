"""
Motor de validación: YOLO detecta objetos, este módulo aplica normativa de Chiapas.

Las medidas en planta dependen de pixels_per_meter (escala del dibujo).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .holistic import HolisticConstructionValidator
from .norms import CHIAPAS_RULES, PlanRules
from .types import Detection, ValidationIssue


@dataclass
class ValidationEngine:
    rules: PlanRules = field(default_factory=lambda: CHIAPAS_RULES)

    def _px_to_m(self, px: float) -> float:
        ppm = self.rules.pixels_per_meter
        if ppm <= 0:
            raise ValueError("pixels_per_meter debe ser > 0")
        return px / ppm

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

        issues.extend(self._check_doors(doors))
        issues.extend(self._check_windows(windows, rooms))
        issues.extend(self._check_rooms(rooms))
        issues.extend(self._check_door_not_on_wall(doors, walls))
        issues.extend(self._check_overlaps(doors, windows))

        holistic = HolisticConstructionValidator(rules=self.rules)
        issues.extend(holistic.validate(detections))

        return issues

    def _check_doors(self, doors: list[Detection]) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        dr = self.rules.door
        for door in doors:
            w_m, h_m, _ = self._dims_m(door)
            if w_m < dr.min_width_m:
                issues.append(
                    ValidationIssue(
                        code="DOOR_WIDTH_MIN",
                        message=(
                            f"Puerta estrecha: {w_m:.2f} m "
                            f"(mín. {dr.min_width_m:.2f} m — Tuxtla Gtz. Art. 150)"
                        ),
                        severity="error",
                        related_class="door",
                        bbox_xyxy=door.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 150",
                    )
                )
            if h_m < dr.min_clear_height_m:
                issues.append(
                    ValidationIssue(
                        code="DOOR_HEIGHT_MIN",
                        message=(
                            f"Vano bajo en planta/corte: {h_m:.2f} m "
                            f"(ref. {dr.min_clear_height_m:.2f} m accesibilidad)"
                        ),
                        severity="warning",
                        related_class="door",
                        bbox_xyxy=door.bbox_xyxy,
                        norm_ref="Accesibilidad / IMSS",
                    )
                )
        return issues

    def _check_windows(
        self, windows: list[Detection], rooms: list[Detection]
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        wr = self.rules.window
        for win in windows:
            w_m, _, area_m2 = self._dims_m(win)
            if w_m < wr.min_width_m:
                issues.append(
                    ValidationIssue(
                        code="WINDOW_WIDTH_MIN",
                        message=(
                            f"Ventana estrecha: {w_m:.2f} m "
                            f"(mín. {wr.min_width_m:.2f} m)"
                        ),
                        severity="warning",
                        related_class="window",
                        bbox_xyxy=win.bbox_xyxy,
                        norm_ref="CEV 2010 / habitabilidad",
                    )
                )
            if area_m2 < wr.min_area_m2:
                issues.append(
                    ValidationIssue(
                        code="WINDOW_AREA_MIN",
                        message=f"Ventana pequeña: {area_m2:.2f} m²",
                        severity="warning",
                        related_class="window",
                        bbox_xyxy=win.bbox_xyxy,
                        norm_ref="CEV 2010",
                    )
                )

        for win, room in self._pair_windows_rooms(windows, rooms):
            _, _, win_area = self._dims_m(win)
            _, _, room_area = self._dims_m(room)
            if room_area <= 0:
                continue
            ratio = win_area / room_area
            if ratio < wr.min_floor_area_ratio:
                issues.append(
                    ValidationIssue(
                        code="WINDOW_LIGHT_RATIO",
                        message=(
                            f"Iluminación ~{ratio * 100:.1f}% del piso "
                            f"(mín. {wr.min_floor_area_ratio * 100:.1f}% — Art. 147 Tuxtla)"
                        ),
                        severity="warning",
                        related_class="window",
                        bbox_xyxy=win.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 147",
                    )
                )
            if ratio < wr.min_ventilation_area_ratio:
                issues.append(
                    ValidationIssue(
                        code="ROOM_VENTILATION_OPENING",
                        message=(
                            f"Apertura de ventilación ~{ratio * 100:.1f}% "
                            f"(ref. 1/20 del piso — Art. 147)"
                        ),
                        severity="warning",
                        related_class="window",
                        bbox_xyxy=win.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 147",
                    )
                )
        return issues

    def _check_rooms(self, rooms: list[Detection]) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        rr = self.rules.room
        for room in rooms:
            w_m, h_m, area_m2 = self._dims_m(room)
            min_side = min(w_m, h_m)
            if min_side < rr.min_dimension_m:
                issues.append(
                    ValidationIssue(
                        code="ROOM_DIMENSION_MIN",
                        message=(
                            f"Pieza habitable estrecha: {min_side:.2f} m "
                            f"(mín. {rr.min_dimension_m:.2f} m — Art. 145 Tuxtla)"
                        ),
                        severity="error",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 145",
                    )
                )
            if area_m2 < rr.min_area_m2:
                issues.append(
                    ValidationIssue(
                        code="ROOM_AREA_MIN",
                        message=(
                            f"Superficie {area_m2:.1f} m² "
                            f"(mín. ref. {rr.min_area_m2:.2f} m² pieza habitable)"
                        ),
                        severity="error",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref="tuxtla_rc Art. 145",
                    )
                )
            if area_m2 < rr.bedroom_ref_area_m2 and area_m2 >= rr.min_area_m2:
                issues.append(
                    ValidationIssue(
                        code="ROOM_AREA_MIN",
                        message=(
                            f"Posible recámara pequeña: {area_m2:.1f} m² "
                            f"(ref. INFONAVIT {rr.bedroom_ref_area_m2:.0f} m²)"
                        ),
                        severity="warning",
                        related_class="room",
                        bbox_xyxy=room.bbox_xyxy,
                        norm_ref="INFONAVIT / CEV",
                    )
                )
        return issues

    @staticmethod
    def _pair_windows_rooms(
        windows: list[Detection], rooms: list[Detection]
    ) -> list[tuple[Detection, Detection]]:
        pairs: list[tuple[Detection, Detection]] = []
        for win in windows:
            w = win.to_shapely()
            best_room: Detection | None = None
            best_inter = 0.0
            for room in rooms:
                inter = w.intersection(room.to_shapely()).area
                if inter > best_inter:
                    best_inter = inter
                    best_room = room
            if best_room is not None and best_inter > 0:
                pairs.append((win, best_room))
        return pairs

    def _check_door_not_on_wall(
        self, doors: list[Detection], walls: list[Detection]
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        if not walls:
            return issues

        wall_geoms = [w.to_shapely() for w in walls]
        for door in doors:
            d = door.to_shapely()
            touches = any(d.intersects(w) or d.touches(w) for w in wall_geoms)
            if not touches:
                issues.append(
                    ValidationIssue(
                        code="DOOR_OFF_WALL",
                        message="Puerta no alineada con muro detectado",
                        severity="error",
                        related_class="door",
                        bbox_xyxy=door.bbox_xyxy,
                        norm_ref="Buena práctica / coherencia planimétrica",
                    )
                )
        return issues

    def _check_overlaps(
        self, doors: list[Detection], windows: list[Detection]
    ) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        for door in doors:
            d = door.to_shapely()
            for win in windows:
                w = win.to_shapely()
                if d.intersection(w).area > 0.5 * min(d.area, w.area):
                    issues.append(
                        ValidationIssue(
                            code="DOOR_WINDOW_OVERLAP",
                            message="Puerta y ventana se superponen",
                            severity="error",
                            related_class="door",
                            bbox_xyxy=door.bbox_xyxy,
                            norm_ref="Coherencia de vanos",
                        )
                    )
        return issues
