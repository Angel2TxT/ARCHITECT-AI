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

    @property
    def width_px(self) -> float:
        return self.bbox_xyxy[2] - self.bbox_xyxy[0]

    @property
    def height_px(self) -> float:
        return self.bbox_xyxy[3] - self.bbox_xyxy[1]

    @property
    def area_px(self) -> float:
        return self.width_px * self.height_px

    def to_shapely(self):
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
