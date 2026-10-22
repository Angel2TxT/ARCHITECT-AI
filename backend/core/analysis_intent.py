"""
Interpreta el mensaje del usuario para enfocar el análisis del plano.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class AnalysisIntent:
    focus: str  # full | doors | windows | rooms | walls | circulation | urban
    compare_uniformity: bool
    check_norms: bool
    title: str
    raw_prompt: str
    conversational: bool = False  # preguntas informales («¿está bien?»)
    list_measures: bool = False  # listar medidas del plano adjunto

    @property
    def is_focused(self) -> bool:
        return self.focus != "full"


FOCUS_LABELS = {
    "full": "Revisión integral",
    "doors": "Puertas y accesos",
    "windows": "Ventanas",
    "rooms": "Recintos y habitabilidad",
    "walls": "Muros y cerramientos",
    "circulation": "Circulación",
    "urban": "Superficie y urbano",
}


def _wants_all_measures(p: str) -> bool:
    return bool(
        re.search(
            r"todas?\s+las?\s+medidas|listar\s+medidas|dame\s+(las\s+)?medidas|"
            r"medidas\s+de(l|\s+ese|\s+este|\s+mi)?\s+plano|cotas\s+del\s+plano|"
            r"dimensiones\s+del\s+plano|tabla\s+de\s+medidas|cu[aá]nto\s+mide|"
            r"ancho\s+y\s+alto|qu[eé]\s+medidas\s+tiene",
            p,
        )
    )


def _is_conversational(p: str) -> bool:
    if not p:
        return False
    return bool(
        re.search(
            r"est[aá]\s+bien|est[aá]\s+correcto|est[aá]\s+ok|todo\s+bien|"
            r"va\s+bien|hay\s+(alg[uú]n\s+)?(problema|error|fallo|detalle)|"
            r"qu[eé]\s+(tal|opinas|te\s+parece|piensas)|"
            r"c[oó]mo\s+lo\s+ves|pasa\s+|cumple|aprobar|se\s+puede|"
            r"est[aá]\s+mal|algo\s+mal|algo\s+que\s+corregir|"
            r"revisar\s+si\s+est|checa\s+si|"
            r"\?\s*$",
            p,
        )
        and not re.search(
            r"mismo\s+tama[nñ]o|uniforme|0\.\d+\s*m|metros?|ancho\s+mín",
            p,
        )
    )


def _conversational_title(focus: str, p: str) -> str:
    if focus == "windows":
        return "¿Las ventanas están bien?"
    if focus == "doors":
        return "¿Las puertas están bien?"
    if focus == "rooms":
        return "¿Los recintos están bien?"
    if re.search(r"normativa|cumple|legal", p):
        return "¿Cumple la normativa?"
    return "¿El plano está bien?"


def parse_analysis_intent(prompt: str) -> AnalysisIntent:
    p = (prompt or "").strip().lower()
    conversational = _is_conversational(p)

    if not p or p in ("analiza este plano", "analiza el plano"):
        return AnalysisIntent(
            focus="full",
            compare_uniformity=False,
            check_norms=True,
            title=FOCUS_LABELS["full"],
            raw_prompt=prompt or "",
            conversational=False,
        )

    list_measures = _wants_all_measures(p)

    compare_uniformity = bool(
        re.search(
            r"mismo\s+tama[nñ]o|misma\s+medida|iguales?|uniforme|"
            r"simetr[ií]a|homog[eé]neo|del\s+mismo\s+ancho",
            p,
        )
    )
    check_norms = not list_measures and not re.search(
        r"solo\s+(tama[nñ]o|medida|uniform)|únicamente\s+medida|sin\s+normativa",
        p,
    )

    focus = "full"
    if re.search(r"ventana|vanos?\s+exterior|iluminaci[oó]n\s+natural", p):
        focus = "windows"
    elif re.search(r"puerta|acceso|vano|giro|accesibilidad", p):
        focus = "doors"
    elif re.search(
        r"habitaci[oó]n|recinto|pieza|superficie\s+habitable|rec[aá]mara|cocina|ba[nñ]o",
        p,
    ):
        focus = "rooms"
    elif re.search(r"muro|cerramiento|pared", p):
        focus = "walls"
    elif re.search(r"pasillo|circulaci[oó]n|corredor|acceso\s+entre", p):
        focus = "circulation"
    elif re.search(r"superficie\s+construida|obra\s+menor|licencia|urbano|cus", p):
        focus = "urban"
    elif re.search(r"medida|cota|dimensi[oó]n|ancho|alto|metro", p):
        if "ventana" in p:
            focus = "windows"
        elif "puerta" in p:
            focus = "doors"
        else:
            focus = "rooms"

    if compare_uniformity and focus == "full":
        if "ventana" in p:
            focus = "windows"
        elif "puerta" in p:
            focus = "doors"

    if list_measures:
        conversational = False
        title = "Medidas del plano"
    elif conversational:
        title = _conversational_title(focus, p)
    else:
        title = FOCUS_LABELS.get(focus, FOCUS_LABELS["full"])
        if compare_uniformity:
            title = f"{title} — uniformidad de tamaños"

    return AnalysisIntent(
        focus=focus,
        compare_uniformity=compare_uniformity,
        check_norms=check_norms,
        title=title,
        raw_prompt=prompt,
        conversational=conversational,
        list_measures=list_measures,
    )


# Códigos de incidencia visibles por enfoque
FOCUS_ISSUE_CODES: dict[str, set[str]] = {
    "doors": {
        "DOOR_WIDTH_MIN",
        "DOOR_HEIGHT_MIN",
        "DOOR_OFF_WALL",
        "DOOR_WINDOW_OVERLAP",
        "DOOR_PER_ROOM_LOW",
        "DOOR_SIZE_UNIFORMITY",
    },
    "windows": {
        "WINDOW_WIDTH_MIN",
        "WINDOW_AREA_MIN",
        "WINDOW_LIGHT_RATIO",
        "ROOM_VENTILATION_OPENING",
        "ROOM_NO_WINDOW",
        "WINDOW_PER_ROOM_LOW",
        "BEDROOM_LIGHTING",
        "KITCHEN_VENTILATION",
        "BATHROOM_VENTILATION",
        "WINDOW_SIZE_UNIFORMITY",
    },
    "rooms": {
        "ROOM_AREA_MIN",
        "ROOM_DIMENSION_MIN",
        "ROOM_NO_WINDOW",
        "ROOM_NO_DOOR_ACCESS",
        "DWELLING_ROOM_COUNT",
        "HABITABILITY_NO_WINDOWS",
        "BEDROOM_LIGHTING",
        "BATHROOM_VENTILATION",
        "KITCHEN_VENTILATION",
    },
    "walls": {
        "DOOR_OFF_WALL",
        "WALL_COVERAGE_LOW",
    },
    "circulation": {
        "CORRIDOR_WIDTH_MIN",
        "ROOM_NO_DOOR_ACCESS",
        "DOOR_PER_ROOM_LOW",
    },
    "urban": {
        "BUILT_AREA_MINOR_WORK",
    },
}


def filter_issues_by_focus(issues: list, intent: AnalysisIntent) -> list:
    if intent.focus == "full":
        return issues
    allowed = FOCUS_ISSUE_CODES.get(intent.focus, set())
    # Siempre mostrar revisión manual y plano incompleto
    always = {"BUILDING_INCOMPLETE", "CONSTRUCTION_MANUAL_REVIEW"}
    return [i for i in issues if i.code in allowed or i.code in always]


def filter_knowledge_terms(intent: AnalysisIntent) -> list[str]:
    base = {
        "doors": ["puerta", "acceso", "0.90", "ancho"],
        "windows": ["ventana", "iluminación", "1/8", "vanos"],
        "rooms": ["habitable", "2.70", "recinto", "superficie"],
        "walls": ["muro", "cerramiento"],
        "circulation": ["circulación", "pasillo", "1.20"],
        "urban": ["obra", "superficie", "licencia"],
    }
    return base.get(intent.focus, ["construcción", "plano"])
