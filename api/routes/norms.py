"""Catálogo normativo Chiapas para la interfaz."""

from __future__ import annotations

from fastapi import APIRouter

from rules.catalog import (
    APPLIED_THRESHOLDS,
    ISSUE_LABELS,
    NORM_BUNDLE_ID,
    NORM_BUNDLE_TITLE,
    NORM_SOURCES,
)
from rules.construction import CONSTRUCTION_DOMAINS
from rules.norms import CHIAPAS_RULES

router = APIRouter(tags=["norms"])


@router.get("/api/norms")
def get_norms_catalog():
    """Umbrales y fuentes normativas (Chiapas, México)."""
    r = CHIAPAS_RULES
    return {
        "bundle_id": NORM_BUNDLE_ID,
        "bundle_title": NORM_BUNDLE_TITLE,
        "sources": NORM_SOURCES,
        "issue_labels": ISSUE_LABELS,
        "thresholds_applied": APPLIED_THRESHOLDS,
        "rules": {
            "door": {
                "min_width_m": r.door.min_width_m,
                "min_clear_height_m": r.door.min_clear_height_m,
            },
            "window": {
                "min_width_m": r.window.min_width_m,
                "min_area_m2": r.window.min_area_m2,
                "min_floor_area_ratio": r.window.min_floor_area_ratio,
            },
            "room": {
                "min_dimension_m": r.room.min_dimension_m,
                "min_area_m2": r.room.min_area_m2,
                "min_clear_height_m": r.room.min_clear_height_m,
            },
            "circulation": {
                "corridor_min_width_m": r.circulation.corridor_min_width_m,
                "stair_width_unifamiliar_m": r.circulation.stair_width_unifamiliar_m,
            },
            "accessibility": {
                "ramp_min_width_m": r.accessibility.ramp_min_width_m,
                "parking_pcd_min_width_m": r.accessibility.parking_pcd_min_width_m,
            },
            "urban": {
                "max_single_story_house_m2": r.urban.max_single_story_house_m2,
                "cus_small_lot_percent": r.urban.cus_small_lot_percent,
            },
        },
        "construction_domains": [
            {
                "id": d.id,
                "title": d.title,
                "scope": d.scope,
                "auto_in_planta": d.auto_in_planta,
                "norm_ref": d.norm_ref,
            }
            for d in CONSTRUCTION_DOMAINS
        ],
        "note": (
            "Validación integral de construcción: habitabilidad, vanos, muros, "
            "circulación y urbano en planta; accesibilidad, estructura, instalaciones "
            "y cortes requieren revisión de proyecto completo. "
            "Confirma con el reglamento de tu municipio."
        ),
    }
