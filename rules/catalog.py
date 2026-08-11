"""Catálogo de incidencias y fuentes normativas — Chiapas, México."""

from __future__ import annotations

ISSUE_LABELS: dict[str, str] = {
    "DOOR_WIDTH_MIN": "Ancho mínimo de puerta (acceso)",
    "DOOR_HEIGHT_MIN": "Altura libre de vano / accesibilidad",
    "DOOR_OFF_WALL": "Puerta sin muro de apoyo",
    "DOOR_WINDOW_OVERLAP": "Puerta y ventana superpuestas",
    "WINDOW_WIDTH_MIN": "Ancho mínimo de ventana",
    "WINDOW_AREA_MIN": "Área mínima de ventana",
    "WINDOW_LIGHT_RATIO": "Iluminación natural insuficiente (1/8)",
    "ROOM_AREA_MIN": "Área mínima de pieza habitable",
    "ROOM_DIMENSION_MIN": "Dimensión mínima de pieza (2.70 m)",
    "ROOM_VENTILATION_OPENING": "Ventilación natural insuficiente",
    "BUILDING_INCOMPLETE": "Plano sin recintos ni cerramiento",
    "HABITABILITY_NO_WINDOWS": "Recintos sin ventanas (habitabilidad)",
    "ROOM_NO_WINDOW": "Recinto sin ventana",
    "ROOM_NO_DOOR_ACCESS": "Recinto sin acceso detectado",
    "WINDOW_PER_ROOM_LOW": "Pocas ventanas para los recintos",
    "DOOR_PER_ROOM_LOW": "Pocos accesos entre recintos",
    "DWELLING_ROOM_COUNT": "Vivienda con pocos recintos",
    "CORRIDOR_WIDTH_MIN": "Circulación estrecha",
    "BATHROOM_VENTILATION": "Sanitario sin ventilación adecuada",
    "KITCHEN_VENTILATION": "Cocina sin ventana",
    "BEDROOM_LIGHTING": "Recámara sin iluminación natural",
    "BUILT_AREA_MINOR_WORK": "Superficie construida / licencia",
    "WALL_COVERAGE_LOW": "Cerramiento / muros insuficientes",
    "CONSTRUCTION_MANUAL_REVIEW": "Revisión complementaria de proyecto",
    "MANUAL_ACCESSIBILITY": "Checklist: accesibilidad",
    "MANUAL_STAIRS": "Checklist: escaleras y desniveles",
    "MANUAL_MEP": "Checklist: instalaciones hidráulicas/sanitarias/gas",
    "MANUAL_ELECTRICAL": "Checklist: instalaciones eléctricas",
    "MANUAL_STRUCTURE": "Checklist: estructura",
    "MANUAL_CIVIL_PROTECTION": "Checklist: protección civil",
    "MANUAL_CLEAR_HEIGHT": "Checklist: alturas libres / cortes",
    "WINDOW_SIZE_UNIFORMITY": "Ventanas con tamaños no uniformes",
    "DOOR_SIZE_UNIFORMITY": "Puertas con tamaños no uniformes",
    "ROOM_OVERLAP": "Recintos superpuestos en planta",
    "LIVING_AREA_LOW": "Estancia / área social insuficiente",
}

NORM_BUNDLE_ID = "chiapas_mx"
NORM_BUNDLE_TITLE = "Chiapas, México (referencia estatal y municipal)"

# Referencias para la UI y documentación (no agotan el marco legal).
NORM_SOURCES: list[dict[str, str]] = [
    {
        "id": "tuxtla_rc",
        "name": "Reglamento de Construcción — Tuxtla Gutiérrez, Chiapas",
        "scope": "Municipal (referencia principal en el estado)",
        "ref": "P.O. 09-08/2017 — Arts. 145-151, 150, 234-243",
    },
    {
        "id": "cev2010",
        "name": "Código de Edificación de Vivienda (CONAVI) 2010",
        "scope": "Federal / vivienda",
        "ref": "Cap. 3-6 habitabilidad, infraestructura, tipología",
    },
    {
        "id": "ldu_chis",
        "name": "Ley de Desarrollo Urbano del Estado de Chiapas",
        "scope": "Estatal",
        "ref": "Ordenamiento, licencias, congruencia municipal",
    },
    {
        "id": "lahotdu_chis",
        "name": "Ley de Asentamientos Humanos, OT y DU — Chiapas",
        "scope": "Estatal",
        "ref": "2018 — planeación territorial y desarrollo urbano",
    },
    {
        "id": "lpc_chis",
        "name": "Ley de Protección Civil del Estado de Chiapas",
        "scope": "Estatal",
        "ref": "Seguridad estructural y evacuación",
    },
    {
        "id": "nom006_cna",
        "name": "NOM-006-CNA-1997",
        "scope": "Federal",
        "ref": "Fosas sépticas (cuando no hay drenaje municipal)",
    },
    {
        "id": "nom007_sedatu",
        "name": "PROY-NOM-007-SEDATU-2024 Habitabilidad de vivienda",
        "scope": "Federal (proyecto / consulta)",
        "ref": "Parámetros de habitabilidad e inspección",
    },
    {
        "id": "accesibilidad_imss",
        "name": "Normas de accesibilidad IMSS (citadas en reglamentos locales)",
        "scope": "Referencia técnica",
        "ref": "Rampas 1.20 m, estacionamiento PCD, sanitarios",
    },
    {
        "id": "infonavit_ref",
        "name": "Criterios INFONAVIT / vivienda social",
        "scope": "Referencia de mercado",
        "ref": "Áreas mínimas recámara, baño, cocina",
    },
]

# Tabla resumida de umbrales aplicados por el motor (medibles en planta).
APPLIED_THRESHOLDS: list[dict[str, str | float]] = [
    {
        "code": "DOOR_WIDTH_MIN",
        "value": 0.90,
        "unit": "m",
        "source": "tuxtla_rc Art. 150 (puertas a calle)",
    },
    {
        "code": "DOOR_HEIGHT_MIN",
        "value": 2.10,
        "unit": "m",
        "source": "Accesibilidad / vanos (referencia IMSS + buenas prácticas)",
    },
    {
        "code": "ROOM_DIMENSION_MIN",
        "value": 2.70,
        "unit": "m",
        "source": "tuxtla_rc Art. 145 (pieza habitable)",
    },
    {
        "code": "ROOM_AREA_MIN",
        "value": 7.29,
        "unit": "m²",
        "source": "Derivado Art. 145 (2.70 × 2.70 m)",
    },
    {
        "code": "ROOM_HEIGHT_MIN",
        "value": 2.60,
        "unit": "m",
        "source": "tuxtla_rc Art. 145 (altura libre — verificar en cortes)",
    },
    {
        "code": "WINDOW_WIDTH_MIN",
        "value": 0.60,
        "unit": "m",
        "source": "CEV / práctica habitacional",
    },
    {
        "code": "WINDOW_LIGHT_RATIO",
        "value": 0.125,
        "unit": "ratio",
        "source": "tuxtla_rc Art. 147 (1/8 superficie de piso)",
    },
    {
        "code": "CORRIDOR_WIDTH_MIN",
        "value": 1.20,
        "unit": "m",
        "source": "tuxtla_rc Art. 148 (pasillos — no auto en 2D)",
    },
    {
        "code": "STAIR_WIDTH_UNIFAM",
        "value": 0.90,
        "unit": "m",
        "source": "tuxtla_rc Art. 150 (escaleras UF)",
    },
    {
        "code": "STAIR_WIDTH_MULTI",
        "value": 1.20,
        "unit": "m",
        "source": "tuxtla_rc Art. 150 (escaleras plurifamiliar)",
    },
    {
        "code": "RAMP_WIDTH_MIN",
        "value": 1.20,
        "unit": "m",
        "source": "tuxtla_rc Art. 242 (accesibilidad)",
    },
    {
        "code": "PARKING_PCD_WIDTH",
        "value": 3.80,
        "unit": "m",
        "source": "tuxtla_rc Art. 240",
    },
    {
        "code": "BATHROOM_MIN_AREA",
        "value": 3.00,
        "unit": "m²",
        "source": "Referencia INFONAVIT / CEV",
    },
    {
        "code": "BEDROOM_MIN_AREA",
        "value": 9.00,
        "unit": "m²",
        "source": "Referencia INFONAVIT / vivienda mínima",
    },
    {
        "code": "KITCHEN_REF_AREA",
        "value": 4.00,
        "unit": "m²",
        "source": "Referencia INFONAVIT / CEV",
    },
    {
        "code": "BUILT_AREA_MINOR_WORK",
        "value": 40.0,
        "unit": "m²",
        "source": "LDU / obra menor unifamiliar (estimación planta)",
    },
]
