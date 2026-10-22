"""
Dominios de la construcción cubiertos por el validador (Chiapas, México).

Incluye lo medible en planta con YOLO (puertas, ventanas, muros, habitaciones)
y revisiones normativas que requieren cortes, memoria o proyecto completo.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ConstructionDomain:
    id: str
    title: str
    scope: str
    auto_in_planta: bool
    norm_ref: str


CONSTRUCTION_DOMAINS: list[ConstructionDomain] = [
    ConstructionDomain(
        "habitabilidad",
        "Habitabilidad y piezas",
        "Dimensiones, áreas, iluminación y ventilación de recintos",
        True,
        "tuxtla_rc Arts. 145-147 · CEV 2010",
    ),
    ConstructionDomain(
        "vanos",
        "Puertas y ventanas",
        "Anchuras, alturas, superposición y relación con muros",
        True,
        "tuxtla_rc Arts. 147, 150",
    ),
    ConstructionDomain(
        "muros",
        "Muros y cerramientos",
        "Coherencia planimétrica y apoyo de vanos",
        True,
        "Buena práctica · coherencia del plano",
    ),
    ConstructionDomain(
        "circulacion",
        "Circulación interior",
        "Pasillos, accesos entre recintos (proxy en planta)",
        True,
        "tuxtla_rc Art. 148",
    ),
    ConstructionDomain(
        "accesibilidad",
        "Accesibilidad universal",
        "Rampas, estacionamiento PCD, sanitarios accesibles",
        False,
        "tuxtla_rc Arts. 234-243 · IMSS",
    ),
    ConstructionDomain(
        "escaleras",
        "Escaleras y desniveles",
        "Huella, contrahuella y anchos",
        False,
        "tuxtla_rc Art. 150 (requiere cortes)",
    ),
    ConstructionDomain(
        "urbano",
        "Parámetros urbanos y obra",
        "Superficie construida, CUS, retiros (estimación en planta)",
        True,
        "LDU Chiapas · tuxtla_rc",
    ),
    ConstructionDomain(
        "instalaciones",
        "Instalaciones hidráulicas, sanitarias y gas",
        "Drenaje, captación, fosas, ventilación de baños",
        False,
        "NOM-006-CNA · CEV Cap. instalaciones",
    ),
    ConstructionDomain(
        "electrico",
        "Instalación eléctrica",
        "Circuitos, protecciones, alumbrado",
        False,
        "NOM-001-SEDE · CEV",
    ),
    ConstructionDomain(
        "estructura",
        "Estructura y cimentación",
        "Capacidad portante, sismo, materiales",
        False,
        "NTC · Reglamento local · Protección Civil",
    ),
    ConstructionDomain(
        "proteccion_civil",
        "Protección civil y evacuación",
        "Rutas, señalización, estabilidad en emergencia",
        False,
        "Ley Protección Civil Chiapas",
    ),
    ConstructionDomain(
        "altura_libre",
        "Alturas libres y cortes",
        "2.60 m piezas habitables, vanos en sección",
        False,
        "tuxtla_rc Art. 145 (cortes)",
    ),
]
