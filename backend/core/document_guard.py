"""
Verificador de documentos para ARCHITECT.
Evita analizar archivos que no sean planos arquitectónicos (ej. tareas escolares,
tablas de Word/Excel, facturas, documentos de texto, fotos personales).
"""

from __future__ import annotations
import re
from pathlib import Path
from typing import NamedTuple
import numpy as np


class DocumentCheckResult(NamedTuple):
    is_floor_plan: bool
    rejection_reason: str = ""
    detected_type: str = "plano"


# Palabras clave de documentos escolares, administrativos y de oficina
_NON_PLAN_KEYWORDS = [
    r"\br[uú]brica\b",
    r"\bcalificaci[oó]n\b",
    r"\bprofesor(a)?\b",
    r"\balumno(a)?\b",
    r"\bestudiante\b",
    r"\bmatr[ií]cula\b",
    r"\basignatura\b",
    r"\bmateria\b",
    r"\bunidad\s+\d+\b",
    r"\bactividad\s+\d+\b",
    r"\bprecondiciones\b",
    r"\brequisito(s)?\b",
    r"\bfuncionalidad\b",
    r"\bcaso\s+de\s+uso\b",
    r"\bcaso\s+de\s+prueba\b",
    r"\bmarco\s+te[oó]rico\b",
    r"\bintroducci[oó]n\b",
    r"\bconclusi[oó]n\b",
    r"\bbibliograf[ií]a\b",
    r"\bresumen\s+ejecutivo\b",
    r"\bfactura\b",
    r"\brfc\b",
    r"\bcurp\b",
]

_NON_PLAN_REGEX = re.compile("|".join(_NON_PLAN_KEYWORDS), re.IGNORECASE)


_ACADEMIC_TERMS = re.compile(
    r"\b(universidad|instituto|facultad|carrera|ingenier[ií]a|licenciatura|asignatura|materia|profesor(a)?|docente|alumno(a)?|estudiante|tecnol[oó]gic[ao]|unidad\s+de\s+aprendizaje|gesti[oó]n\s+en\s+el\s+proceso)\b",
    re.IGNORECASE,
)


def check_pdf_is_floor_plan(pdf_bytes: bytes, page_index: int = 0) -> DocumentCheckResult:
    """Inspecciona páginas clave de PDF usando PyMuPDF para verificar si es un plano o un documento escolar/texto."""
    try:
        import fitz  # PyMuPDF
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        if doc.page_count == 0:
            return DocumentCheckResult(False, "El PDF está vacío.", "vacio")

        idx = max(0, min(page_index, doc.page_count - 1))

        # Revisamos la portada (página 0), la página objetivo y una intermedia
        pages_to_check = [idx]
        if 0 not in pages_to_check:
            pages_to_check.insert(0, 0)
        if doc.page_count > 2 and 1 not in pages_to_check:
            pages_to_check.append(1)

        for p_num in pages_to_check:
            page = doc[p_num]
            text = page.get_text() or ""
            words = text.split()
            word_count = len(words)

            # 1. Chequeo de portada universitaria / institucional
            acad_matches = _ACADEMIC_TERMS.findall(text)
            if len(acad_matches) >= 2:
                terms_found = list(set(m if isinstance(m, str) else m[0] for m in acad_matches if m))[:4]
                reason = (
                    f"El archivo es un documento institucional o académico "
                    f"(detecté términos como: {', '.join(terms_found)}), "
                    f"no un plano arquitectónico en planta."
                )
                return DocumentCheckResult(False, reason, "documento_academico")

            # 2. Chequeo de palabras clave de rúbrica / casos de prueba / tablas
            matches = _NON_PLAN_REGEX.findall(text)
            if word_count > 30 and len(matches) >= 2:
                matched_terms = list(set(m if isinstance(m, str) else m[0] for m in matches if m))[:4]
                reason = (
                    f"El archivo parece ser un documento de texto o tabla de actividades "
                    f"(contiene {word_count} palabras y términos como: {', '.join(matched_terms)}), "
                    f"no un plano arquitectónico en planta."
                )
                return DocumentCheckResult(False, reason, "documento_texto")

            # 3. Si el texto es masivo (> 140 palabras en una sola página sin términos arquitectónicos)
            arch_terms = re.findall(
                r"\b(muro|planta|corte|fachada|escala|acceso|cocina|baño|dormitorio|rec[aá]mara|sala|comedor|nivel)\b",
                text,
                re.IGNORECASE,
            )
            if word_count > 120 and len(arch_terms) == 0:
                return DocumentCheckResult(
                    False,
                    f"El archivo contiene un documento de texto ({word_count} palabras en página {p_num + 1}) sin terminología arquitectónica.",
                    "documento_texto",
                )

        return DocumentCheckResult(True, "", "plano")
    except Exception:
        return DocumentCheckResult(True, "", "desconocido")


def check_image_is_floor_plan(image_bgr: np.ndarray) -> DocumentCheckResult:
    """
    Verifica mediante heurística de imagen si parece ser un plano arquitectónico
    (predominio de fondo claro con líneas vectoriales/negras) o una foto/documento saturado.
    """
    if image_bgr is None or image_bgr.size == 0:
        return DocumentCheckResult(False, "La imagen está vacía.", "vacio")

    h, w = image_bgr.shape[:2]
    if h < 100 or w < 100:
        return DocumentCheckResult(False, "La resolución es demasiado baja para ser un plano arquitectónico.", "baja_resolucion")

    # Muestreo rápido de color: los planos en planta son casi todos blancos/claros (>80% fondo)
    # con líneas oscuras (muros, ventanas).
    gray = image_bgr[:, :, 0]  # canal suficiente para planos b/n
    white_ratio = np.mean(gray > 220)

    # Si es una foto saturada (ej. foto de una persona, paisaje o foto muy oscura)
    if white_ratio < 0.35:
        # Menos del 35% de fondo blanco suele ser una fotografía normal o render 3D
        return DocumentCheckResult(
            True,  # No bloqueamos con dureza para no rechazar planos oscuros/CAD, pero etiquetamos
            "",
            "foto_o_render",
        )

    return DocumentCheckResult(True, "", "plano")
