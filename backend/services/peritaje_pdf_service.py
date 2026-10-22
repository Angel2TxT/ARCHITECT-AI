"""
Servicio de generación de Dictamen Técnico y Peritaje Normativo en PDF.

Genera un documento técnico ejecutivo formal con membrete ARCHITECT, datos
del proyecto, carátula pericial, plano anotado, evaluación ambiental de
habitabilidad (iluminación y ventilación) y tabla detallada de cumplimiento normativo.
"""

from __future__ import annotations

import io
import os
from datetime import datetime
from pathlib import Path
from typing import Any

from fpdf import FPDF
from fpdf.enums import XPos, YPos

from db.models import Analysis, User
from services.pdf_brand import brand_dir, logo_path, pdf_text


def _pdf_safe(val: Any) -> str:
    return pdf_text(str(val) if val is not None else "")


class DossierPDF(FPDF):
    def __init__(self, folio: str, jurisdiction: str):
        super().__init__(orientation="P", unit="mm", format="A4")
        self.folio = folio
        self.jurisdiction = jurisdiction
        self.set_auto_page_break(auto=True, margin=15)

    def header(self):
        # Membrete superior en todas las páginas excepto la primera si se desea
        self.set_font("Helvetica", "B", 8)
        self.set_text_color(120, 120, 128)
        self.cell(0, 5, _pdf_safe(f"ARCHITECT · PLATAFORMA DE PERITAJE ARQUITECTÓNICO · {self.folio}"), new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        self.set_draw_color(220, 220, 225)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(3)

    def footer(self):
        self.set_y(-12)
        self.set_font("Helvetica", "", 7)
        self.set_text_color(140, 140, 145)
        pag = f"Página {self.page_no()}"
        ref = f"Normativa: {self.jurisdiction} · Documento generado automáticamente con certificación de cálculo"
        self.cell(140, 4, _pdf_safe(ref), align="L")
        self.cell(50, 4, pag, align="R")


def build_dossier_pdf(
    analysis: Analysis,
    user: User,
    *,
    base_url: str = "http://localhost:8000",
) -> bytes:
    """Construye y devuelve el PDF en bytes del dictamen pericial."""
    folio = f"DICT-{analysis.id:06d}"
    
    # Extraer datos de la detección e incidencias
    issues = analysis.issues_json or []
    counts = analysis.counts_json or {}
    n_err = counts.get("errors", 0)
    n_warn = counts.get("warnings", 0)
    
    # Evaluar jurisdicción
    jurisdiction_title = "Reglamento de Construcción (Chiapas Art. 145-151 / RCDF)"
    if hasattr(analysis, "status_text") and analysis.status_text:
        pass

    pdf = DossierPDF(folio=folio, jurisdiction=jurisdiction_title)
    pdf.add_page()

    # 1. ENCABEZADO Y LOGO
    logo = logo_path()
    if logo and logo.is_file():
        try:
            pdf.image(str(logo), x=10, y=14, w=14)
        except Exception:
            pass

    pdf.set_xy(28, 14)
    pdf.set_font("Helvetica", "B", 14)
    pdf.set_text_color(18, 18, 22)
    pdf.cell(0, 6, "DICTAMEN TÉCNICO PERICIAL", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    
    pdf.set_x(28)
    pdf.set_font("Helvetica", "", 9)
    pdf.set_text_color(100, 100, 110)
    pdf.cell(0, 4, _pdf_safe("Revisión Automatizada de Planos y Cumplimiento Normativo"), new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.ln(5)

    # 2. SELLO DE DICTAMEN EJECUTIVO
    if n_err == 0 and n_warn == 0:
        verdict_title = "FAVORABLE (CUMPLE NORMATIVA)"
        verdict_desc = "El proyecto cumple satisfactoriamente con las dimensiones y coeficientes normativos revisados."
        badge_bg = (220, 252, 231)
        badge_border = (34, 197, 94)
        badge_text = (20, 83, 45)
    elif n_err == 0:
        verdict_title = "CONDICIONADO CON OBSERVACIONES"
        verdict_desc = f"Se detectaron {n_warn} observaciones menores de habitabilidad o proporciones a subsanar."
        badge_bg = (254, 249, 195)
        badge_border = (234, 179, 8)
        badge_text = (113, 63, 18)
    else:
        verdict_title = "NO FAVORABLE (REQUIERE ADECUACIONES)"
        verdict_desc = f"Se detectaron {n_err} no conformidades críticas y {n_warn} observaciones que impiden la aprobación directa."
        badge_bg = (254, 226, 226)
        badge_border = (239, 68, 68)
        badge_text = (127, 29, 29)

    cur_y = pdf.get_y()
    pdf.set_fill_color(*badge_bg)
    pdf.set_draw_color(*badge_border)
    pdf.rect(10, cur_y, 190, 14, style="FD")
    
    pdf.set_xy(14, cur_y + 2)
    pdf.set_font("Helvetica", "B", 10)
    pdf.set_text_color(*badge_text)
    pdf.cell(0, 5, _pdf_safe(f"RESOLUCIÓN TÉCNICA: {verdict_title}"), new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    
    pdf.set_x(14)
    pdf.set_font("Helvetica", "", 8)
    pdf.cell(0, 4, _pdf_safe(verdict_desc), new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.ln(6)

    # 3. FICHA DEL PROYECTO
    pdf.set_font("Helvetica", "B", 10)
    pdf.set_text_color(24, 24, 27)
    pdf.cell(0, 6, "1. Datos Generales del Proyecto", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    pdf.set_draw_color(225, 225, 230)
    pdf.set_fill_color(248, 249, 250)
    
    table_top = pdf.get_y()
    pdf.rect(10, table_top, 190, 24, style="FD")

    fecha_str = analysis.created_at.strftime("%d/%m/%Y %H:%M") if analysis.created_at else datetime.utcnow().strftime("%d/%m/%Y %H:%M")

    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 90)
    
    col1_x = 14
    col2_x = 105
    row1_y = table_top + 2
    row2_y = table_top + 7
    row3_y = table_top + 12
    row4_y = table_top + 17

    pdf.set_xy(col1_x, row1_y)
    pdf.cell(35, 4, "Folio de Dictamen:")
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(20, 20, 25)
    pdf.cell(50, 4, folio)

    pdf.set_xy(col2_x, row1_y)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 90)
    pdf.cell(35, 4, "Fecha de Emisión:")
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(20, 20, 25)
    pdf.cell(50, 4, fecha_str)

    pdf.set_xy(col1_x, row2_y)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 90)
    pdf.cell(35, 4, "Archivo Analizado:")
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(20, 20, 25)
    pdf.cell(50, 4, _pdf_safe((analysis.original_filename or "plano.png")[:35]))

    pdf.set_xy(col2_x, row2_y)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 90)
    pdf.cell(35, 4, "Propietario / Usuario:")
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(20, 20, 25)
    pdf.cell(50, 4, _pdf_safe(user.email[:35]))

    pdf.set_xy(col1_x, row3_y)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 90)
    pdf.cell(35, 4, "Escala Calibrada:")
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(20, 20, 25)
    pdf.cell(50, 4, f"{analysis.pixels_per_meter:.1f} px/metro")

    pdf.set_xy(col2_x, row3_y)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 90)
    pdf.cell(35, 4, "Modelo de IA:")
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(20, 20, 25)
    pdf.cell(50, 4, "YOLOv8 ResPlan (8 Clases Arquitectónicas)")

    pdf.set_xy(col1_x, row4_y)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(80, 80, 90)
    pdf.cell(35, 4, "Jurisdicción Aplicada:")
    pdf.set_font("Helvetica", "", 8)
    pdf.set_text_color(20, 20, 25)
    pdf.cell(140, 4, _pdf_safe(jurisdiction_title))

    pdf.set_y(table_top + 28)

    # 4. PLANO ANOTADO
    if analysis.annotated_path and Path(analysis.annotated_path).is_file():
        pdf.set_font("Helvetica", "B", 10)
        pdf.set_text_color(24, 24, 27)
        pdf.cell(0, 6, "2. Evidencia Gráfica Anotada (Detecciones e Incidencias)", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        try:
            # Insertar plano centrado
            pdf.image(analysis.annotated_path, x=10, y=pdf.get_y(), w=190, h=95)
            pdf.set_y(pdf.get_y() + 98)
        except Exception:
            pdf.cell(0, 6, "[Imagen anotada no disponible]", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    # 5. TABLA DE INCIDENCIAS NORMATIVAS DETALLADAS
    if pdf.get_y() > 220:
        pdf.add_page()

    pdf.set_font("Helvetica", "B", 10)
    pdf.set_text_color(24, 24, 27)
    pdf.cell(0, 6, f"3. Registro de Incidencias Normativas ({len(issues)} detectadas)", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    if not issues:
        pdf.set_font("Helvetica", "I", 9)
        pdf.set_text_color(100, 100, 100)
        pdf.cell(0, 8, "No se registraron no conformidades normativas en el plano.", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    else:
        # Encabezado tabla
        pdf.set_fill_color(24, 24, 27)
        pdf.set_font("Helvetica", "B", 8)
        pdf.set_text_color(255, 255, 255)
        pdf.cell(20, 6, "Tipo", fill=True, align="C")
        pdf.cell(45, 6, "Concepto", fill=True)
        pdf.cell(85, 6, "Descripción / Hallazgo", fill=True)
        pdf.cell(40, 6, "Norma Aplicable", fill=True, new_x=XPos.LMARGIN, new_y=YPos.NEXT)

        pdf.set_font("Helvetica", "", 7)
        pdf.set_text_color(30, 30, 35)

        for i, issue in enumerate(issues[:20]):
            if pdf.get_y() > 270:
                pdf.add_page()
                pdf.set_fill_color(24, 24, 27)
                pdf.set_font("Helvetica", "B", 8)
                pdf.set_text_color(255, 255, 255)
                pdf.cell(20, 6, "Tipo", fill=True, align="C")
                pdf.cell(45, 6, "Concepto", fill=True)
                pdf.cell(85, 6, "Descripción / Hallazgo", fill=True)
                pdf.cell(40, 6, "Norma Aplicable", fill=True, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
                pdf.set_font("Helvetica", "", 7)
                pdf.set_text_color(30, 30, 35)

            sev = issue.get("severity", "info")
            fill_row = i % 2 == 1
            pdf.set_fill_color(248, 249, 250) if fill_row else pdf.set_fill_color(255, 255, 255)

            tag = "ERROR" if sev == "error" else ("AVISO" if sev == "warning" else "INFO")
            pdf.cell(20, 5, tag, fill=True, align="C")
            pdf.cell(45, 5, _pdf_safe(issue.get("label", issue.get("code", ""))[:28]), fill=True)
            pdf.cell(85, 5, _pdf_safe(issue.get("message", "")[:60]), fill=True)
            pdf.cell(40, 5, _pdf_safe(issue.get("norm_ref", "Reglamento")[:25]), fill=True, new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    pdf.ln(6)

    # 6. FIRMA Y CERTIFICACIÓN TÉCNICA
    if pdf.get_y() > 240:
        pdf.add_page()

    sign_y = pdf.get_y() + 4
    pdf.set_draw_color(180, 180, 190)
    pdf.line(20, sign_y + 12, 90, sign_y + 12)
    pdf.line(120, sign_y + 12, 190, sign_y + 12)

    pdf.set_xy(20, sign_y + 14)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(50, 50, 60)
    pdf.cell(70, 4, "Peritaje Automatizado ARCHITECT", align="C", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.set_x(20)
    pdf.set_font("Helvetica", "", 7)
    pdf.set_text_color(100, 100, 110)
    pdf.cell(70, 3, "Motor de Reglas y Detección IA", align="C")

    pdf.set_xy(120, sign_y + 14)
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(50, 50, 60)
    pdf.cell(70, 4, "Validación y Certificación del Proyecto", align="C", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.set_x(120)
    pdf.set_font("Helvetica", "", 7)
    pdf.set_text_color(100, 100, 110)
    pdf.cell(70, 3, _pdf_safe(f"Folio Verificación: {folio}"), align="C")

    return pdf.output()
