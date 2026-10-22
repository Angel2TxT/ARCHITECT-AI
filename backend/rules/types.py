"""Tipos compartidos del motor de validación."""

from __future__ import annotations

from dataclasses import dataclass

from shapely.geometry import box

from .catalog import ISSUE_LABELS


@dataclass
class Detection:
    class_name: str
    bbox_xyxy: tuple[float, float, float, float]
    confidence: float = 1.0
    polygon: list[tuple[float, float]] | None = None

    @property
    def width_px(self) -> float:
        return self.bbox_xyxy[2] - self.bbox_xyxy[0]

    @property
    def height_px(self) -> float:
        return self.bbox_xyxy[3] - self.bbox_xyxy[1]

    @property
    def area_px(self) -> float:
        if self.polygon and len(self.polygon) >= 3:
            try:
                poly = self.to_shapely()
                if not poly.is_empty and poly.area > 0:
                    return float(poly.area)
            except Exception:
                pass
        return self.width_px * self.height_px

    @property
    def perimeter_px(self) -> float:
        try:
            return float(self.to_shapely().length)
        except Exception:
            return 2 * (self.width_px + self.height_px)

    def to_shapely(self):
        if self.polygon and len(self.polygon) >= 3:
            try:
                from shapely.geometry import Polygon
                p = Polygon(self.polygon)
                if not p.is_valid:
                    p = p.buffer(0)
                if not p.is_empty:
                    return p
            except Exception:
                pass
        return box(*self.bbox_xyxy)


@dataclass
class ValidationIssue:
    code: str
    message: str
    severity: str  # error | warning | info
    related_class: str | None = None
    bbox_xyxy: tuple[float, float, float, float] | None = None
    norm_ref: str | None = None

    @property
    def label(self) -> str:
        return ISSUE_LABELS.get(self.code, self.code)
