"""Conversión de planos (imagen, PDF, DXF, DWG) a PNG para el pipeline YOLO."""

from __future__ import annotations

import asyncio
import io
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

PREVIEW_DPI = 120
ANALYZE_DPI = 200

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}
CAD_EXTENSIONS = {".dxf", ".dwg"}
PDF_EXTENSIONS = {".pdf"}
SUPPORTED_EXTENSIONS = IMAGE_EXTENSIONS | CAD_EXTENSIONS | PDF_EXTENSIONS


class CadConversionError(Exception):
    """Error al convertir un archivo CAD a imagen."""


@dataclass
class PreparedUpload:
    original_content: bytes
    original_filename: str
    original_path: Path
    image_path: Path
    was_converted: bool
    conversion_note: str | None = None


def is_supported_filename(filename: str) -> bool:
    return Path(filename or "").suffix.lower() in SUPPORTED_EXTENSIONS


def is_cad_filename(filename: str) -> bool:
    return Path(filename or "").suffix.lower() in CAD_EXTENSIONS


def is_pdf_filename(filename: str) -> bool:
    return Path(filename or "").suffix.lower() in PDF_EXTENSIONS


def _require_pymupdf():
    try:
        import fitz

        return fitz
    except ImportError as exc:
        raise CadConversionError(
            "Para PDF instala en el proyecto:\n"
            "pip install pymupdf\n"
            "Reinicia: python app.py"
        ) from exc


def _require_ezdxf():
    try:
        import ezdxf

        return ezdxf
    except ImportError as exc:
        raise CadConversionError(
            "Faltan librerías CAD. Ejecuta en el proyecto:\n"
            'pip install "ezdwg[dxf,plot]" ezdxf matplotlib\n'
            "Luego reinicia: python app.py"
        ) from exc


def _require_ezdwg():
    try:
        import ezdwg

        return ezdwg
    except ImportError as exc:
        raise CadConversionError(
            "Para abrir .dwg sin instalar programas externos:\n"
            'pip install "ezdwg[dxf,plot]"\n'
            "Reinicia: python app.py"
        ) from exc


def _find_dwg2dxf_executable() -> Path | None:
    """LibreDWG: herramienta libre dwg2dxf (alternativa a ODA)."""
    env = os.environ.get("LIBREDWG_DWG2DXF", "").strip().strip('"')
    if env:
        p = Path(env)
        if p.is_file():
            return p
    found = shutil.which("dwg2dxf")
    if found:
        return Path(found)
    for candidate in (
        Path(r"C:\Program Files\LibreDWG\bin\dwg2dxf.exe"),
        Path(r"C:\libredwg\dwg2dxf.exe"),
    ):
        if candidate.is_file():
            return candidate
    return None


def _autocad_available() -> bool:
    if sys.platform != "win32":
        return False
    try:
        import win32com.client

        acad = win32com.client.Dispatch("AutoCAD.Application")
        _ = acad.Name
        return True
    except Exception:
        return False


def _find_oda_executable() -> Path | None:
    """Busca ODA File Converter (necesario para leer .dwg binarios)."""
    env = os.environ.get("ODA_CONVERTER_PATH", "").strip().strip('"')
    if env:
        p = Path(env)
        if p.is_file():
            return p

    for base in (
        os.environ.get("ProgramFiles", r"C:\Program Files"),
        os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
    ):
        oda_root = Path(base) / "ODA"
        if oda_root.is_dir():
            for exe in sorted(oda_root.rglob("ODAFileConverter.exe")):
                return exe

    legacy = Path(r"C:\Program Files\ODA\ODAFileConverter\ODAFileConverter.exe")
    if legacy.is_file():
        return legacy
    return None


def cad_support_status() -> dict:
    """Estado para /api/health y diagnóstico."""
    backends: dict[str, str | bool | None] = {
        "ezdwg": None,
        "oda": None,
        "libredwg": None,
        "autocad": False,
    }
    out = {
        "ezdxf": False,
        "matplotlib": False,
        "dxf": False,
        "dwg": False,
        "pdf": False,
        "backends": backends,
        "hint": None,
    }
    try:
        import ezdxf

        out["ezdxf"] = True
        out["dxf"] = True
        _ = ezdxf.__version__
    except ImportError:
        out["hint"] = 'pip install "ezdwg[dxf,plot]" ezdxf matplotlib'
        return out

    try:
        import matplotlib

        out["matplotlib"] = True
        _ = matplotlib.__version__
    except ImportError:
        out["hint"] = "pip install matplotlib"

    try:
        import ezdwg

        backends["ezdwg"] = getattr(ezdwg, "__version__", None) or "installed"
        out["dwg"] = True
    except ImportError:
        out["hint"] = 'pip install "ezdwg[dxf,plot]"'

    oda = _find_oda_executable()
    if oda:
        backends["oda"] = str(oda)
        out["dwg"] = True
    else:
        try:
            from ezdxf.addons import odafc

            if odafc.is_installed():
                backends["oda"] = "odafc"
                out["dwg"] = True
        except ImportError:
            pass

    libredwg = _find_dwg2dxf_executable()
    if libredwg:
        backends["libredwg"] = str(libredwg)
        out["dwg"] = True

    if _autocad_available():
        backends["autocad"] = True
        out["dwg"] = True

    if not out["dwg"]:
        out["hint"] = 'pip install "ezdwg[dxf,plot]" y reinicia app.py'

    try:
        import fitz

        backends["pymupdf"] = getattr(fitz, "__version__", None) or "installed"
        out["pdf"] = True
    except ImportError:
        if not out.get("hint"):
            out["hint"] = "pip install pymupdf"

    return out


def _load_dxf_doc(content: bytes):
    _require_ezdxf()
    import ezdxf

    with tempfile.NamedTemporaryFile(suffix=".dxf", delete=False) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)
    try:
        try:
            return ezdxf.readfile(tmp_path)
        except ezdxf.DXFStructureError:
            doc, _auditor = ezdxf.recover.readfile(tmp_path)
            return doc
    finally:
        tmp_path.unlink(missing_ok=True)


def _dxf_bytes_to_png(content: bytes, dpi: int = 200) -> bytes:
    _require_ezdxf()
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from ezdxf.addons.drawing import Frontend, RenderContext
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend

    doc = _load_dxf_doc(content)

    msp = doc.modelspace()
    if not any(True for _ in msp):
        raise CadConversionError(
            "El DXF no contiene geometría dibujable. Exporta la vista del plano desde AutoCAD."
        )

    fig = plt.figure(figsize=(14, 10), dpi=dpi)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_aspect("equal")
    ax.axis("off")
    ctx = RenderContext(doc)
    backend = MatplotlibBackend(ax)
    Frontend(ctx, backend).draw_layout(msp, finalize=True)

    buf = io.BytesIO()
    fig.savefig(
        buf,
        format="png",
        dpi=dpi,
        bbox_inches="tight",
        pad_inches=0.08,
        facecolor="white",
        edgecolor="none",
    )
    plt.close(fig)
    buf.seek(0)
    data = buf.read()
    if len(data) < 100:
        raise CadConversionError("La conversión del DXF produjo una imagen vacía.")
    return data


def _dwg_via_ezdwg(content: bytes, dpi: int = 200) -> bytes | None:
    """
    Convierte DWG → PNG integrado en Python (paquete ezdwg, sin .exe externos).
    """
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return None

    _require_ezdwg()
    import ezdwg

    dwg_path: Path | None = None
    dxf_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".dwg", delete=False) as tmp:
            tmp.write(content)
            dwg_path = Path(tmp.name)

        doc = ezdwg.read(str(dwg_path))

        # ezdwg usa show=True por defecto → plt.show(); desactivar en servidor.
        _plt_show = plt.show
        plt.show = lambda *args, **kwargs: None
        try:
            try:
                plotted = doc.plot(show=False, arc_segments=32)
                fig = plotted if plotted is not None else plt.gcf()
                buf = io.BytesIO()
                fig.savefig(
                    buf,
                    format="png",
                    dpi=dpi,
                    bbox_inches="tight",
                    pad_inches=0.08,
                    facecolor="white",
                    edgecolor="none",
                )
                plt.close(fig)
                buf.seek(0)
                data = buf.read()
                if len(data) >= 100:
                    return data
            except Exception:
                plt.close("all")

            dxf_path = dwg_path.with_suffix(".converted.dxf")
            doc.export_dxf(str(dxf_path))
            if dxf_path.is_file():
                return _dxf_bytes_to_png(dxf_path.read_bytes(), dpi=dpi)
            return None
        finally:
            plt.show = _plt_show
    except Exception:
        return None
    finally:
        if dwg_path and dwg_path.is_file():
            dwg_path.unlink(missing_ok=True)
        if dxf_path and dxf_path.is_file():
            dxf_path.unlink(missing_ok=True)


def _dwg_via_oda(content: bytes) -> bytes | None:
    import tempfile

    try:
        from ezdxf.addons import odafc

        if odafc.is_installed():
            with tempfile.TemporaryDirectory() as tmp:
                tmp_path = Path(tmp)
                dwg_path = tmp_path / "plano.dwg"
                dwg_path.write_bytes(content)
                odafc.convert(dwg_path, tmp_path, version="R2018")
                dxf_files = sorted(tmp_path.glob("*.dxf"))
                if dxf_files:
                    return dxf_files[0].read_bytes()
    except Exception:
        pass

    exe = _find_oda_executable()
    if not exe:
        return None

    with tempfile.TemporaryDirectory() as inp, tempfile.TemporaryDirectory() as outp:
        in_dir = Path(inp)
        out_dir = Path(outp)
        (in_dir / "plano.dwg").write_bytes(content)
        cmd = [str(exe), str(in_dir), str(out_dir), "ACAD2018", "DXF", "0", "1"]
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=180, check=False
        )
        if proc.returncode != 0:
            return None
        dxf_files = sorted(out_dir.glob("*.dxf"))
        return dxf_files[0].read_bytes() if dxf_files else None


def _dwg_via_libredwg(content: bytes) -> bytes | None:
    exe = _find_dwg2dxf_executable()
    if not exe:
        return None

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        dwg_path = tmp_path / "plano.dwg"
        dxf_path = tmp_path / "plano.dxf"
        dwg_path.write_bytes(content)
        proc = subprocess.run(
            [str(exe), "-o", str(dxf_path), str(dwg_path)],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        if proc.returncode != 0 or not dxf_path.is_file():
            return None
        return dxf_path.read_bytes()


def _dwg_via_autocad(content: bytes) -> bytes | None:
    if not _autocad_available():
        return None

    import win32com.client

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        dwg_path = tmp_path / "plano.dwg"
        dxf_path = tmp_path / "plano.dxf"
        dwg_path.write_bytes(content)

        acad = win32com.client.Dispatch("AutoCAD.Application")
        acad.Visible = False
        doc = None
        try:
            doc = acad.Documents.Open(str(dwg_path.resolve()))
            # 12 = DXF; si falla, AutoCAD usa la extensión .dxf del destino
            try:
                doc.SaveAs(str(dxf_path.resolve()), 12)
            except Exception:
                doc.SaveAs(str(dxf_path.resolve()))
            if not dxf_path.is_file():
                return None
            return dxf_path.read_bytes()
        finally:
            if doc is not None:
                doc.Close(False)


def _dwg_to_dxf_bytes_legacy(content: bytes) -> bytes | None:
    """Respaldo opcional con herramientas externas (solo si ezdwg falla)."""
    for converter in (_dwg_via_oda, _dwg_via_libredwg, _dwg_via_autocad):
        try:
            result = converter(content)
            if result:
                return result
        except Exception:
            continue
    return None


def _dwg_bytes_to_png(content: bytes, dpi: int = 200) -> bytes:
    _require_ezdxf()

    png = _dwg_via_ezdwg(content, dpi=dpi)
    if png:
        return png

    dxf_bytes = _dwg_to_dxf_bytes_legacy(content)
    if dxf_bytes:
        return _dxf_bytes_to_png(dxf_bytes, dpi=dpi)

    raise CadConversionError(
        "No se pudo leer este .dwg.\n\n"
        "1) Instala el conversor integrado (sin .exe):\n"
        '   pip install "ezdwg[dxf,plot]" ezdxf matplotlib\n'
        "   Reinicia: python app.py\n\n"
        "2) Si sigue fallando, el DWG puede ser muy nuevo o dañado:\n"
        "   en AutoCAD → Guardar como → DXF o PNG y súbelo aquí."
    )


def pdf_bytes_to_png(
    content: bytes, dpi: int = 200, page_index: int = 0
) -> tuple[bytes, str | None]:
    """Renderiza una página del PDF a PNG (por defecto la primera)."""
    fitz = _require_pymupdf()
    doc = fitz.open(stream=content, filetype="pdf")
    try:
        if doc.page_count == 0:
            raise CadConversionError("El PDF no tiene páginas.")
        idx = max(0, min(page_index, doc.page_count - 1))
        page = doc[idx]
        zoom = dpi / 72.0
        matrix = fitz.Matrix(zoom, zoom)
        pix = page.get_pixmap(matrix=matrix, alpha=False)
        png = pix.tobytes("png")
        if len(png) < 100:
            raise CadConversionError("La página del PDF está vacía o no se pudo rasterizar.")
        note = None
        if doc.page_count > 1:
            note = (
                f"PDF con {doc.page_count} páginas: se analizó la página {idx + 1}. "
                "Si el plano está en otra hoja, exporta esa página como imagen."
            )
        return png, note
    finally:
        doc.close()


def cad_bytes_to_png(content: bytes, filename: str, dpi: int = 200) -> bytes:
    ext = Path(filename or "").suffix.lower()
    if ext == ".dxf":
        return _dxf_bytes_to_png(content, dpi=dpi)
    if ext == ".dwg":
        return _dwg_bytes_to_png(content, dpi=dpi)
    raise CadConversionError(f"Formato CAD no soportado: {ext}")


def plano_bytes_to_png(
    content: bytes, filename: str, dpi: int = 200
) -> tuple[bytes, str | None]:
    """Convierte PDF o CAD a PNG. Devuelve (png_bytes, nota_opcional)."""
    ext = Path(filename or "").suffix.lower()
    if ext in PDF_EXTENSIONS:
        return pdf_bytes_to_png(content, dpi=dpi)
    if ext in CAD_EXTENSIONS:
        return cad_bytes_to_png(content, filename, dpi=dpi), None
    raise CadConversionError(f"Formato no convertible: {ext}")


def prepare_upload(
    content: bytes,
    filename: str,
    work_dir: Path,
) -> PreparedUpload:
    """
    Guarda el original en work_dir y devuelve la ruta de imagen lista para YOLO.
    """
    work_dir.mkdir(parents=True, exist_ok=True)
    safe_name = Path(filename or "plano.png").name
    ext = Path(safe_name).suffix.lower() or ".png"

    if ext not in SUPPORTED_EXTENSIONS:
        raise CadConversionError(
            f"Formato «{ext}» no soportado. Usa PNG, JPG, PDF, DXF o DWG."
        )

    original_path = work_dir / f"source{ext}"
    original_path.write_bytes(content)

    if ext in IMAGE_EXTENSIONS:
        return PreparedUpload(
            original_content=content,
            original_filename=safe_name,
            original_path=original_path,
            image_path=original_path,
            was_converted=False,
        )

    try:
        png_bytes, extra_note = plano_bytes_to_png(content, safe_name)
    except CadConversionError:
        raise
    except Exception as exc:
        raise CadConversionError(
            f"No se pudo convertir «{safe_name}»: {exc}"
        ) from exc

    raster_path = work_dir / "converted.png"
    raster_path.write_bytes(png_bytes)
    labels = {".dxf": "DXF", ".dwg": "DWG", ".pdf": "PDF"}
    label = labels.get(ext, ext.upper().lstrip("."))
    note = extra_note or f"Plano convertido desde {label} para el análisis."
    return PreparedUpload(
        original_content=content,
        original_filename=safe_name,
        original_path=original_path,
        image_path=raster_path,
        was_converted=True,
        conversion_note=note,
    )


async def cad_bytes_to_png_async(
    content: bytes, filename: str, dpi: int = ANALYZE_DPI
) -> bytes:
    """Ejecuta la conversión CAD en un hilo para no bloquear el servidor web."""
    return await asyncio.to_thread(cad_bytes_to_png, content, filename, dpi)


async def prepare_upload_async(
    content: bytes, filename: str, work_dir: Path
) -> PreparedUpload:
    return await asyncio.to_thread(prepare_upload, content, filename, work_dir)


async def pdf_bytes_to_png_async(
    content: bytes, dpi: int = ANALYZE_DPI, page_index: int = 0
) -> tuple[bytes, str | None]:
    return await asyncio.to_thread(pdf_bytes_to_png, content, dpi, page_index)
