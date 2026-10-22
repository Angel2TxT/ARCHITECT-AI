"""
Normativa de referencia para validación de planos — Chiapas, México.

Los valores medibles en planta provienen principalmente del Reglamento de
Construcción de Tuxtla Gutiérrez (referencia habitual en el estado), el Código
de Edificación de Vivienda (CONAVI 2010) y criterios federales de habitabilidad.

IMPORTANTE: Calibra pixels_per_meter por plano. Los municipios de Chiapas
pueden tener reglamentos propios (San Cristóbal, Tapachula, etc.) que modifiquen
cifras; este paquete usa la referencia estatal/municipal más documentada.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .catalog import NORM_BUNDLE_ID, NORM_BUNDLE_TITLE


@dataclass(frozen=True)
class DoorRules:
    """Puertas y vanos — Reglamento Tuxtla Gtz. Art. 150 y accesibilidad."""

    min_width_m: float = 0.90
    min_clear_height_m: float = 2.10
    main_access_min_width_m: float = 0.90
    accessible_module_width_m: float = 0.90
    accessible_module_height_m: float = 2.20


@dataclass(frozen=True)
class WindowRules:
    """Ventanas e iluminación — Art. 147 Tuxtla (1/8) y CEV."""

    min_width_m: float = 0.60
    min_area_m2: float = 0.35
    min_floor_area_ratio: float = 0.125
    min_ventilation_area_ratio: float = 0.04


@dataclass(frozen=True)
class RoomRules:
    """Piezas habitables — Art. 145-146 Tuxtla Gutiérrez."""

    min_dimension_m: float = 2.70
    min_area_m2: float = 7.29
    min_clear_height_m: float = 2.60
    bedroom_ref_area_m2: float = 9.00
    bathroom_ref_area_m2: float = 3.00
    kitchen_ref_area_m2: float = 4.00
    living_ref_area_m2: float = 12.00


@dataclass(frozen=True)
class CirculationRules:
    """Circulaciones — Arts. 148, 150 Tuxtla (referencia; escaleras no en YOLO)."""

    corridor_min_width_m: float = 1.20
    stair_width_unifamiliar_m: float = 0.90
    stair_width_multifamiliar_m: float = 1.20
    stair_tread_min_cm: float = 28.0
    stair_riser_min_cm: float = 15.0
    stair_riser_max_cm: float = 18.0


@dataclass(frozen=True)
class AccessibilityRules:
    """Accesibilidad — Arts. 234-243 Tuxtla / IMSS."""

    ramp_min_width_m: float = 1.20
    ramp_max_slope_percent: float = 8.0
    parking_pcd_min_width_m: float = 3.80
    parking_pcd_min_percent: float = 5.0
    accessible_toilet_module_m: tuple[float, float] = (1.60, 2.00)


@dataclass(frozen=True)
class UrbanRules:
    """Parámetros urbanos de referencia (información / futuras extensiones)."""

    max_single_story_house_m2: float = 40.0
    cus_small_lot_percent: float = 15.0
    cus_large_lot_percent: float = 20.0
    lot_small_threshold_m2: float = 300.0
    facade_ventilation_setback_m: float = 1.70
    water_supply_l_per_inhabitant_day: float = 150.0


@dataclass(frozen=True)
class PlanRules:
    pixels_per_meter: float = 100.0
    jurisdiction: str = NORM_BUNDLE_ID
    jurisdiction_title: str = NORM_BUNDLE_TITLE
    door: DoorRules = field(default_factory=DoorRules)
    window: WindowRules = field(default_factory=WindowRules)
    room: RoomRules = field(default_factory=RoomRules)
    circulation: CirculationRules = field(default_factory=CirculationRules)
    accessibility: AccessibilityRules = field(default_factory=AccessibilityRules)
    urban: UrbanRules = field(default_factory=UrbanRules)


CHIAPAS_RULES = PlanRules(
    jurisdiction="chiapas_mx",
    jurisdiction_title="Chiapas, México (Reglamento Estatal / Tuxtla Gutiérrez)",
    door=DoorRules(min_width_m=0.90, min_clear_height_m=2.10),
    window=WindowRules(min_width_m=0.60, min_area_m2=0.35, min_floor_area_ratio=0.125, min_ventilation_area_ratio=0.04),
    room=RoomRules(min_dimension_m=2.70, min_area_m2=7.29, min_clear_height_m=2.60),
    circulation=CirculationRules(corridor_min_width_m=1.20, stair_width_unifamiliar_m=0.90),
)

CDMX_RULES = PlanRules(
    jurisdiction="cdmx_rcdf",
    jurisdiction_title="Ciudad de México (RCDF y Normas Técnicas Complementarias)",
    door=DoorRules(min_width_m=0.90, min_clear_height_m=2.10),
    window=WindowRules(min_width_m=0.60, min_area_m2=0.30, min_floor_area_ratio=0.10, min_ventilation_area_ratio=0.05),
    room=RoomRules(min_dimension_m=2.40, min_area_m2=7.00, min_clear_height_m=2.30, bedroom_ref_area_m2=7.50),
    circulation=CirculationRules(corridor_min_width_m=0.90, stair_width_unifamiliar_m=0.90),
    urban=UrbanRules(cus_small_lot_percent=20.0, facade_ventilation_setback_m=2.00),
)

NACIONAL_RULES = PlanRules(
    jurisdiction="nacional_conavi",
    jurisdiction_title="Nacional México (Código de Edificación de Vivienda CONAVI / INFONAVIT)",
    door=DoorRules(min_width_m=0.90, min_clear_height_m=2.10),
    window=WindowRules(min_width_m=0.60, min_area_m2=0.30, min_floor_area_ratio=0.10, min_ventilation_area_ratio=0.05),
    room=RoomRules(min_dimension_m=2.60, min_area_m2=7.00, min_clear_height_m=2.40, bedroom_ref_area_m2=8.00),
    circulation=CirculationRules(corridor_min_width_m=1.00, stair_width_unifamiliar_m=0.90),
)

DEFAULT_RULES = CHIAPAS_RULES

SUPPORTED_JURISDICTIONS: dict[str, PlanRules] = {
    "chiapas_mx": CHIAPAS_RULES,
    "cdmx_rcdf": CDMX_RULES,
    "nacional_conavi": NACIONAL_RULES,
}


def get_jurisdiction_rules(
    jurisdiction: str | None = None,
    pixels_per_meter: float = 100.0,
) -> PlanRules:
    """Obtiene las reglas configuradas para una jurisdicción dada."""
    if not jurisdiction:
        base = DEFAULT_RULES
    else:
        norm_key = jurisdiction.strip().lower()
        if norm_key in ("cdmx", "cdmx_rcdf", "mexico_df", "df"):
            base = CDMX_RULES
        elif norm_key in ("nacional", "nacional_conavi", "conavi", "infonavit", "federal", "nom"):
            base = NACIONAL_RULES
        else:
            base = CHIAPAS_RULES

    # Clonar con la escala de píxeles por metro deseada
    return PlanRules(
        pixels_per_meter=pixels_per_meter,
        jurisdiction=base.jurisdiction,
        jurisdiction_title=base.jurisdiction_title,
        door=base.door,
        window=base.window,
        room=base.room,
        circulation=base.circulation,
        accessibility=base.accessibility,
        urban=base.urban,
    )

