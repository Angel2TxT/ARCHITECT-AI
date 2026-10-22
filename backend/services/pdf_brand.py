"""Marca visual compartida para PDFs (admin, reportes)."""

from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path
from typing import Any

# Paleta alineada con comprobantes / marca ARCHITECT
COLOR_BLACK = (9, 9, 11)
COLOR_WHITE = (255, 255, 255)
COLOR_MUTED = (113, 113, 122)
COLOR_MUTED_LIGHT = (161, 161, 170)
COLOR_BORDER = (228, 228, 231)
COLOR_SURFACE = (250, 250, 250)
COLOR_GREEN = (134, 239, 172)
COLOR_GREEN_DARK = (22, 101, 52)
COLOR_ROW_ALT = (245, 247, 245)
COLOR_HEADER_BG = (24, 24, 27)


def company_profile() -> dict[str, str]:
    base = (os.getenv("APP_BASE_URL") or "http://localhost:8000").rstrip("/")
    email = (os.getenv("MAIL_FROM_ADDRESS") or os.getenv("ADMIN_EMAIL") or "contacto@architect.local").strip()
    host = base.replace("https://", "").replace("http://", "").split("/")[0]
    # Evitar URLs temporales de tunel en documentos oficiales
    if "trycloudflare.com" in host or host.startswith("localhost") or host.startswith("127."):
        web_label = "Plataforma web ARCHITECT"
    else:
        web_label = host
    return {
        "name": (os.getenv("MAIL_FROM_NAME") or "ARCHITECT").strip() or "ARCHITECT",
        "legal_name": "ARCHITECT",
        "tagline": "Revisión asistida de planos arquitectónicos",
        "location": "Chiapas, México",
        "email": email,
        "web": web_label,
        "note": "Proyecto escolar · Documento administrativo interno",
        "copyright": f"© {datetime.utcnow().year} ARCHITECT. Todos los derechos reservados.",
    }


def brand_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "web" / "static" / "brand"


def logo_path() -> Path | None:
    for name in ("architect-icon.png", "architect-logo.png"):
        path = brand_dir() / name
        if path.is_file():
            return path
    return None


def pdf_text(value: Any, max_len: int | None = None) -> str:
    """Texto seguro para fuentes core de fpdf (Helvetica / latin-1)."""
    s = str(value if value is not None else "")
    replacements = {
        "\u2014": "-",
        "\u2013": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2026": "...",
        "\u2022": "-",
        "\u00a0": " ",
        "\u2248": "~",
        "\u00d7": "x",
    }
    for src, dst in replacements.items():
        s = s.replace(src, dst)
    s = s.encode("latin-1", errors="replace").decode("latin-1")
    if max_len is not None:
        s = s[:max_len]
    return s


def create_branded_pdf(
    *,
    orientation: str = "P",
    document_title: str = "",
    document_subtitle: str = "",
):
    """FPDF con cabecera de marca, pie y helpers de tabla."""
    try:
        from fpdf import FPDF
    except ImportError as exc:
        raise RuntimeError("Instala fpdf2 para exportar PDF: pip install fpdf2") from exc

    company = company_profile()

    class BrandedPDF(FPDF):
        def __init__(self) -> None:
            super().__init__(orientation=orientation, unit="mm", format="A4")
            self.document_title = document_title
            self.document_subtitle = document_subtitle
            self._first_content = True
            self.set_auto_page_break(auto=True, margin=20)
            self.set_margins(14, 36, 14)

        def header(self) -> None:
            self.set_fill_color(*COLOR_BLACK)
            self.rect(0, 0, self.w, 28, "F")
            self.set_fill_color(*COLOR_GREEN)
            self.rect(0, 28, self.w, 1.8, "F")

            logo = logo_path()
            text_x = 12.0
            if logo is not None:
                try:
                    self.image(str(logo), 10, 5, h=18)
                    text_x = 32.0
                except Exception:
                    text_x = 12.0

            self.set_xy(text_x, 5)
            self.set_text_color(*COLOR_WHITE)
            self.set_font("Helvetica", "B", 13)
            self.cell(0, 6, pdf_text(company["name"]), new_x="LMARGIN", new_y="NEXT")
            self.set_x(text_x)
            self.set_font("Helvetica", "", 7)
            self.set_text_color(*COLOR_MUTED_LIGHT)
            self.cell(0, 4, pdf_text(company["tagline"]), new_x="LMARGIN", new_y="NEXT")
            self.set_x(text_x)
            self.cell(
                0,
                4,
                pdf_text(f"{company['location']}  |  {company['email']}  |  {company['web']}"),
                new_x="LMARGIN",
                new_y="NEXT",
            )

            # Meta a la derecha (solo si cabe)
            right_w = 62
            self.set_xy(self.w - right_w - 10, 7)
            self.set_font("Helvetica", "B", 7)
            self.set_text_color(*COLOR_GREEN)
            self.cell(right_w, 4, "DOCUMENTO OFICIAL", align="R", new_x="LEFT", new_y="NEXT")
            self.set_x(self.w - right_w - 10)
            self.set_font("Helvetica", "", 6)
            self.set_text_color(*COLOR_MUTED_LIGHT)
            self.cell(right_w, 3.5, pdf_text(company["note"]), align="R")

            self.set_y(34)
            self.set_text_color(*COLOR_BLACK)

        def footer(self) -> None:
            self.set_y(-16)
            self.set_draw_color(*COLOR_BORDER)
            self.set_line_width(0.3)
            self.line(14, self.get_y(), self.w - 14, self.get_y())
            self.set_y(-13)
            self.set_font("Helvetica", "", 6.5)
            self.set_text_color(*COLOR_MUTED)
            left = pdf_text(f"{company['copyright']}  ·  Uso interno administrativo")
            self.cell(self.w / 2 - 14, 5, left, align="L")
            self.cell(
                self.w / 2 - 14,
                5,
                pdf_text(f"Página {self.page_no()}/{{nb}}"),
                align="R",
            )

        def draw_document_banner(self, title: str, lines: list[str] | None = None) -> None:
            """Bloque de titulo bajo la cabecera (solo primera pagina de contenido)."""
            y0 = self.get_y()
            box_h = 18 + max(0, len(lines or []) - 1) * 4.2
            self.set_fill_color(*COLOR_SURFACE)
            self.set_draw_color(*COLOR_BORDER)
            self.set_line_width(0.4)
            self.rect(14, y0, self.w - 28, box_h, "DF")
            self.set_fill_color(*COLOR_GREEN_DARK)
            self.rect(14, y0, 2.2, box_h, "F")

            self.set_xy(20, y0 + 3.5)
            self.set_font("Helvetica", "B", 13)
            self.set_text_color(*COLOR_BLACK)
            self.cell(0, 6, pdf_text(title, 90), new_x="LMARGIN", new_y="NEXT")

            self.set_font("Helvetica", "", 8)
            self.set_text_color(*COLOR_MUTED)
            for line in lines or []:
                self.set_x(20)
                self.cell(0, 4.2, pdf_text(line, 110), new_x="LMARGIN", new_y="NEXT")

            self.set_y(y0 + box_h + 6)
            self.set_text_color(*COLOR_BLACK)
            self._first_content = False

        def section_title(self, text: str) -> None:
            self.ln(2)
            self.set_font("Helvetica", "B", 10)
            self.set_text_color(*COLOR_BLACK)
            self.cell(0, 6, pdf_text(text), new_x="LMARGIN", new_y="NEXT")
            self.set_draw_color(*COLOR_GREEN)
            self.set_line_width(0.6)
            y = self.get_y()
            self.line(14, y, 48, y)
            self.ln(3)

        def draw_kpi_grid(self, items: list[tuple[str, Any]], cols: int = 3) -> None:
            if not items:
                return
            gap = 3.5
            usable = self.w - 28
            col_w = (usable - gap * (cols - 1)) / cols
            row_h = 18
            x0 = 14.0
            y = self.get_y()
            for i, (label, value) in enumerate(items):
                col = i % cols
                if col == 0 and i > 0:
                    y += row_h + gap
                    if y + row_h > self.page_break_trigger:
                        self.add_page()
                        y = self.get_y()
                x = x0 + col * (col_w + gap)
                self.set_fill_color(*COLOR_SURFACE)
                self.set_draw_color(*COLOR_BORDER)
                self.rect(x, y, col_w, row_h, "DF")
                self.set_fill_color(*COLOR_GREEN)
                self.rect(x, y, col_w, 1.2, "F")
                self.set_xy(x + 3, y + 3.5)
                self.set_font("Helvetica", "", 6.5)
                self.set_text_color(*COLOR_MUTED)
                self.cell(col_w - 6, 3.5, pdf_text(label, 36).upper())
                self.set_xy(x + 3, y + 8.5)
                self.set_font("Helvetica", "B", 12)
                self.set_text_color(*COLOR_BLACK)
                self.cell(col_w - 6, 6, pdf_text(value, 28))
            self.set_y(y + row_h + 6)
            self.set_text_color(*COLOR_BLACK)

        def draw_table(
            self,
            headers: list[str],
            rows: list[list[Any]],
            *,
            max_rows: int = 200,
            font_size: float = 7,
        ) -> None:
            if not headers:
                return
            n = len(headers)
            usable = self.w - 28
            # Anchos proporcionales: primeras columnas un poco mas angostas para IDs
            weights = []
            for h in headers:
                hl = h.lower()
                if hl in ("id", "rol", "activo", "demo", "etapa", "msgs"):
                    weights.append(0.55)
                elif "correo" in hl or "email" in hl or "archivo" in hl or "nombre" in hl:
                    weights.append(1.35)
                else:
                    weights.append(1.0)
            total_w = sum(weights)
            widths = [usable * (w / total_w) for w in weights]

            def _header_row() -> None:
                self.set_fill_color(*COLOR_HEADER_BG)
                self.set_text_color(*COLOR_WHITE)
                self.set_font("Helvetica", "B", font_size)
                for i, h in enumerate(headers):
                    self.cell(widths[i], 7, pdf_text(h, 28), border=0, fill=True, align="C")
                self.ln()
                self.set_text_color(*COLOR_BLACK)

            _header_row()
            self.set_font("Helvetica", "", font_size)
            for idx, row in enumerate(rows[:max_rows]):
                if self.get_y() > self.page_break_trigger - 8:
                    self.add_page()
                    _header_row()
                    self.set_font("Helvetica", "", font_size)

                if idx % 2 == 0:
                    self.set_fill_color(*COLOR_WHITE)
                else:
                    self.set_fill_color(*COLOR_ROW_ALT)

                self.set_draw_color(*COLOR_BORDER)
                for i, cell in enumerate(row):
                    align = "L"
                    text = pdf_text(cell, 40)
                    if isinstance(cell, (int, float)) and not isinstance(cell, bool):
                        align = "R"
                    self.cell(widths[i], 5.5, text, border="B", fill=True, align=align)
                self.ln()

            if len(rows) > max_rows:
                self.ln(1)
                self.set_font("Helvetica", "I", 7)
                self.set_text_color(*COLOR_MUTED)
                self.cell(0, 5, pdf_text(f"Mostrando {max_rows} de {len(rows)} registros."), new_x="LMARGIN", new_y="NEXT")
                self.set_text_color(*COLOR_BLACK)

        def output_bytes(self) -> bytes:
            self.alias_nb_pages()
            out = self.output()
            if isinstance(out, bytearray):
                return bytes(out)
            if isinstance(out, bytes):
                return out
            return str(out).encode("latin-1")

    pdf = BrandedPDF()
    pdf.alias_nb_pages()
    return pdf
