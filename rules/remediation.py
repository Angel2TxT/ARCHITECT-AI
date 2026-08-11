"""Guías de corrección por código de incidencia (planta 2D)."""

from __future__ import annotations

# summary: una línea; steps: acciones concretas para el equipo
ISSUE_REMEDIATION: dict[str, dict[str, object]] = {
    "DOOR_WIDTH_MIN": {
        "summary": "Ensancha el vano de acceso al mínimo normativo.",
        "steps": [
            "Mide el claro libre de la puerta en planta (sin marco).",
            "Ajusta a ≥ 0.90 m en accesos principales (referencia Tuxtla).",
            "Si es puerta interior estrecha, documenta justificación o cámbiala.",
        ],
    },
    "DOOR_HEIGHT_MIN": {
        "summary": "Verifica altura libre del vano en corte (no solo en planta).",
        "steps": [
            "Revisa el corte o detalle de puerta: ≥ 2.10 m de claro.",
            "Coordina con carpintería y acabados de piso/cielo.",
        ],
    },
    "DOOR_OFF_WALL": {
        "summary": "Coloca la puerta sobre un muro o tabique claro.",
        "steps": [
            "Alinea el símbolo de puerta con el muro detectado.",
            "Evita puertas flotando en el centro del recinto.",
        ],
    },
    "DOOR_WINDOW_OVERLAP": {
        "summary": "Separa puerta y ventana; no deben ocupar el mismo vano.",
        "steps": [
            "Revisa superposición de símbolos en el CAD/dibujo.",
            "Deja claro libre independiente para cada vano.",
        ],
    },
    "WINDOW_WIDTH_MIN": {
        "summary": "Aumenta el ancho de la ventana.",
        "steps": [
            "Verifica ancho libre ≥ 0.60 m (referencia local).",
            "Si es vano de servicio, documenta tipo y justificación.",
        ],
    },
    "WINDOW_AREA_MIN": {
        "summary": "Aumenta el área del vano de ventana.",
        "steps": [
            "Calcula área del vano en planta/elevación.",
            "Amplía hasta cumplir el mínimo de área de ventana.",
        ],
    },
    "WINDOW_LIGHT_RATIO": {
        "summary": "Mejora la iluminación natural del recinto (≈ 1/8 del piso).",
        "steps": [
            "Suma área de ventanas del local / área del piso.",
            "Añade o agranda ventanas hacia exterior o patio.",
        ],
    },
    "ROOM_AREA_MIN": {
        "summary": "Amplía el área del local habitable.",
        "steps": [
            "Recalcula área neta del recinto.",
            "Redistribuye muros o fusiona espacios hasta el mínimo.",
        ],
    },
    "ROOM_DIMENSION_MIN": {
        "summary": "Corrige la dimensión menor del local (≥ 2.70 m habitable).",
        "steps": [
            "Identifica el lado corto del rectángulo del local.",
            "Mueve muros o cambia tipología del espacio.",
        ],
    },
    "ROOM_VENTILATION_OPENING": {
        "summary": "Garantiza ventilación natural suficiente.",
        "steps": [
            "Asegura vano operable hacia exterior o ducto válido.",
            "Revisa ratio de ventilación respecto al área del piso.",
        ],
    },
    "BUILDING_INCOMPLETE": {
        "summary": "Mejora la legibilidad de la planta para detectar cerramiento.",
        "steps": [
            "Exporta una sola planta, nítida, con muros contrastados.",
            "Evita cortes, 3D o láminas con muchas capas.",
            "Recorta márgenes y cartelas grandes.",
        ],
    },
    "HABITABILITY_NO_WINDOWS": {
        "summary": "Incorpora ventanas a los locales habitables.",
        "steps": [
            "Dibuja vanos hacia fachada o patio en cada pieza habitable.",
            "Vuelve a revisar con IA tras actualizar el plano.",
        ],
    },
    "ROOM_NO_WINDOW": {
        "summary": "Agrega ventana (o ventilación válida) a este recinto.",
        "steps": [
            "Ubica el local marcado en el overlay.",
            "Abre vano al exterior o patio de luces.",
        ],
    },
    "ROOM_NO_DOOR_ACCESS": {
        "summary": "Da acceso con puerta a este recinto.",
        "steps": [
            "Conecta el local al pasillo o a un local adyacente.",
            "Dibuja el símbolo de puerta en el muro correspondiente.",
        ],
    },
    "WINDOW_PER_ROOM_LOW": {
        "summary": "Equilibra ventanas respecto al número de recintos.",
        "steps": [
            "Revisa pieza por pieza qué falta de iluminación.",
            "Prioriza estancia, recámaras y cocina.",
        ],
    },
    "DOOR_PER_ROOM_LOW": {
        "summary": "Completa la circulación entre locales.",
        "steps": [
            "Verifica que cada local tenga acceso lógico.",
            "Añade puertas faltantes en muros divisorios.",
        ],
    },
    "DWELLING_ROOM_COUNT": {
        "summary": "Completa el programa mínimo de vivienda.",
        "steps": [
            "Incluye al menos estancia, cocina y sanitario (ref. CEV/INFONAVIT).",
            "Actualiza el cuadro de espacios y la planta.",
        ],
    },
    "CORRIDOR_WIDTH_MIN": {
        "summary": "Ensancha pasillos o circulaciones.",
        "steps": [
            "Mide el ancho libre del pasillo.",
            "Ajusta a ≥ 1.20 m (referencia Art. 148 Tuxtla) si aplica.",
        ],
    },
    "BATHROOM_VENTILATION": {
        "summary": "Ventila el sanitario (ventana o ducto).",
        "steps": [
            "Confirma si el local es baño por área/programa.",
            "Añade ventana exterior o extracto/ducto según norma.",
        ],
    },
    "KITCHEN_VENTILATION": {
        "summary": "Ventila la cocina con vano al exterior.",
        "steps": [
            "Asegura ventana o salida de humos válida.",
            "Coordina con instalaciones de gas/humos.",
        ],
    },
    "BEDROOM_LIGHTING": {
        "summary": "Ilumina la recámara con vano natural.",
        "steps": [
            "Abre ventana a fachada o patio.",
            "Verifica área mínima de recámara en el programa.",
        ],
    },
    "BUILT_AREA_MINOR_WORK": {
        "summary": "Revisa licencia y alcance del proyecto por superficie.",
        "steps": [
            "Confirma m² construidos con el cuadro de áreas.",
            "Si supera obra menor, prepara proyecto/licencia ampliada.",
        ],
    },
    "WALL_COVERAGE_LOW": {
        "summary": "Completa o aclara muros en el dibujo.",
        "steps": [
            "Dibuja cerramientos con trazo continuo y contraste.",
            "Evita solo hatch sin línea de muro.",
        ],
    },
    "CONSTRUCTION_MANUAL_REVIEW": {
        "summary": "Complementa con cortes, estructura e instalaciones.",
        "steps": [
            "Añade cortes con altura libre ≥ 2.60 m.",
            "Incluye memoria estructural e instalaciones en el expediente.",
            "Revisa accesibilidad y protección civil aparte de la planta.",
        ],
    },
    "MANUAL_ACCESSIBILITY": {
        "summary": "Revisa accesibilidad (rampas, PCD, sanitarios).",
        "steps": [
            "Verifica anchos de circulación y cambios de nivel.",
            "Incluye sanitario accesible si aplica al programa.",
            "Documenta rampas/estaciones PCD fuera de esta planta si hace falta.",
        ],
    },
    "MANUAL_STAIRS": {
        "summary": "Dimensiona escaleras en corte y planta.",
        "steps": [
            "Define huella, contrahuella y ancho en corte.",
            "Marca desniveles y barandales en el ejecutivo.",
        ],
    },
    "MANUAL_MEP": {
        "summary": "Coordina instalaciones hidráulicas, sanitarias y gas.",
        "steps": [
            "Agrega esquemas o planos de instalaciones al expediente.",
            "Verifica ventilación de baños y criterios NOM aplicables.",
        ],
    },
    "MANUAL_ELECTRICAL": {
        "summary": "Completa el proyecto eléctrico.",
        "steps": [
            "Incluye diagrama unifilar / contactos según etapa.",
            "Coordina con locales húmedos y circulaciones.",
        ],
    },
    "MANUAL_STRUCTURE": {
        "summary": "Documenta criterio estructural.",
        "steps": [
            "Adjunta memoria o croquis estructural.",
            "Marca ejes/columnas en planta si ya existen.",
        ],
    },
    "MANUAL_CIVIL_PROTECTION": {
        "summary": "Revisa rutas de evacuación y protección civil.",
        "steps": [
            "Identifica salidas y recorridos de evacuación.",
            "Incluye notas de seguridad según alcance del proyecto.",
        ],
    },
    "MANUAL_CLEAR_HEIGHT": {
        "summary": "Confirma alturas libres en cortes.",
        "steps": [
            "Dibuja corte por locales habitables (≥ 2.60 m de referencia).",
            "Verifica vanos y cielos en sección, no solo en planta.",
        ],
    },
    "WINDOW_SIZE_UNIFORMITY": {
        "summary": "Homogeneiza tamaños de ventanas si el diseño lo pide.",
        "steps": [
            "Revisa familias de vanos en fachada.",
            "Unifica módulos salvo justificación de diseño.",
        ],
    },
    "DOOR_SIZE_UNIFORMITY": {
        "summary": "Homogeneiza anchos de puertas por tipo de uso.",
        "steps": [
            "Separa accesos principales vs interiores.",
            "Aplica un módulo por tipo de puerta.",
        ],
    },
    "ROOM_OVERLAP": {
        "summary": "Corrige recintos superpuestos en el dibujo.",
        "steps": [
            "Revisa hatches o bloques duplicados de locales.",
            "Deja un polígono claro por recinto.",
        ],
    },
    "LIVING_AREA_LOW": {
        "summary": "Amplía la estancia / área social principal.",
        "steps": [
            "Identifica el local de mayor área (posible estancia).",
            "Ajusta al mínimo de referencia de estar / vivienda.",
        ],
    },
}


def remediation_for(code: str | None) -> dict[str, object]:
    key = str(code or "").strip()
    data = ISSUE_REMEDIATION.get(key)
    if not data:
        return {
            "summary": "Revisa el hallazgo en el plano y corrige según la norma citada.",
            "steps": [
                "Localiza el elemento en el overlay o en el archivo del apartado.",
                "Ajusta el dibujo o el entregable y vuelve a revisar con IA.",
                "Si no aplica, descarta el hallazgo con un motivo claro.",
            ],
        }
    return {
        "summary": str(data.get("summary") or ""),
        "steps": list(data.get("steps") or []),
    }


def enrich_issue_dict(issue: dict) -> dict:
    """Añade fix / fix_steps a un issue ya serializado."""
    rem = remediation_for(issue.get("code"))
    out = dict(issue)
    out["fix"] = rem["summary"]
    out["fix_steps"] = rem["steps"]
    return out
