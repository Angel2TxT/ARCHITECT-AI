"""
Análisis geométrico ligero de DXF para complementar YOLO.

No sustituye al detector: aporta escala aproximada, capas útiles y avisos
cuando el dibujo vectorial sugiere problemas que el raster no ve bien.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from rules.types import ValidationIssue


@dataclass
class DxfGeometryReport:
    entity_count: int = 0
    layer_counts: dict[str, int] = field(default_factory=dict)
    extent_width: float | None = None
    extent_height: float | None = None
    units_hint: str | None = None
    suggested_ppm: float | None = None
    structure_layers: list[str] = field(default_factory=list)
    opening_layers: list[str] = field(default_factory=list)
    issues: list[ValidationIssue] = field(default_factory=list)
    note: str | None = None

    def to_dict(self) -> dict:
        return {
            "entity_count": self.entity_count,
            "layer_counts": dict(sorted(self.layer_counts.items(), key=lambda x: -x[1])[:24]),
            "extent_width": self.extent_width,
            "extent_height": self.extent_height,
            "units_hint": self.units_hint,
            "suggested_ppm": self.suggested_ppm,
            "structure_layers": self.structure_layers,
            "opening_layers": self.opening_layers,
            "note": self.note,
            "issue_codes": [i.code for i in self.issues],
        }


_STRUCTURE_KEYS = (
    "muro",
    "wall",
    "mur",
    "pared",
    "estructura",
    "struct",
    "column",
    "columna",
    "eje",
    "axis",
    "ciment",
    "foundation",
)
_OPENING_KEYS = (
    "puerta",
    "door",
    "ventana",
    "window",
    "vano",
    "opening",
    "hueco",
)
_FURNITURE_KEYS = ("mobili", "furn", "equip", "bloq", "block")


def _layer_matches(name: str, keys: tuple[str, ...]) -> bool:
    low = (name or "").lower()
    return any(k in low for k in keys)


def analyze_dxf_bytes(
    content: bytes,
    *,
    raster_width_px: int | None = None,
    raster_height_px: int | None = None,
) -> DxfGeometryReport:
    """Lee DXF en memoria y genera reporte + issues informativos."""
    report = DxfGeometryReport()
    try:
        import ezdxf
    except ImportError:
        report.note = "ezdxf no instalado; omitiendo geometría CAD."
        return report

    import tempfile

    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".dxf", delete=False) as tmp:
            tmp.write(content)
            tmp_path = Path(tmp.name)
        try:
            doc = ezdxf.readfile(tmp_path)
        except Exception:
            doc, _ = ezdxf.recover.readfile(tmp_path)
    except Exception as exc:
        report.note = f"No se pudo leer DXF: {exc}"
        return report
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)

    msp = doc.modelspace()
    layer_counts: dict[str, int] = {}
    entity_count = 0
    for ent in msp:
        entity_count += 1
        layer = getattr(ent.dxf, "layer", "0") or "0"
        layer_counts[layer] = layer_counts.get(layer, 0) + 1

    report.entity_count = entity_count
    report.layer_counts = layer_counts

    if entity_count == 0:
        report.issues.append(
            ValidationIssue(
                code="CAD_EMPTY_GEOMETRY",
                message=(
                    "El archivo CAD no tiene geometría en modelspace. "
                    "Exporta el layout del plano o verifica que no esté vacío."
                ),
                severity="error",
                related_class=None,
                norm_ref="Integridad CAD",
            )
        )
        return report

    try:
        ext = ezdxf.bbox.extents(msp)
        if ext.has_data:
            report.extent_width = float(ext.size.x)
            report.extent_height = float(ext.size.y)
    except Exception:
        pass

    report.structure_layers = sorted(
        n for n in layer_counts if _layer_matches(n, _STRUCTURE_KEYS)
    )
    report.opening_layers = sorted(
        n for n in layer_counts if _layer_matches(n, _OPENING_KEYS)
    )

    # Heurística de unidades por tamaño del dibujo
    w = report.extent_width or 0.0
    h = report.extent_height or 0.0
    diag = (w * w + h * h) ** 0.5
    if diag > 0:
        if 5 <= max(w, h) <= 120:
            report.units_hint = "metros"
        elif 500 <= max(w, h) <= 12000:
            report.units_hint = "milímetros"
        elif 15 <= max(w, h) <= 400:
            report.units_hint = "posible_pies_o_metros"
        else:
            report.units_hint = "desconocidas"

    if (
        raster_width_px
        and raster_height_px
        and report.extent_width
        and report.extent_height
        and report.extent_width > 0
        and report.extent_height > 0
    ):
        unit_w = report.extent_width
        if report.units_hint == "milímetros":
            unit_w_m = unit_w / 1000.0
        elif report.units_hint == "metros":
            unit_w_m = unit_w
        else:
            unit_w_m = None
        if unit_w_m and 3 <= unit_w_m <= 80:
            report.suggested_ppm = float(raster_width_px) / unit_w_m

    if not report.structure_layers:
        report.issues.append(
            ValidationIssue(
                code="CAD_NO_STRUCTURE_LAYER",
                message=(
                    "No se detectaron capas con nombres típicos de muros/estructura "
                    f"({entity_count} entidades en {len(layer_counts)} capas). "
                    "La revisión raster puede ser menos precisa; revisa capas en AutoCAD."
                ),
                severity="info",
                related_class="wall",
                norm_ref="Capas CAD",
            )
        )
    else:
        report.issues.append(
            ValidationIssue(
                code="CAD_STRUCTURE_LAYERS_OK",
                message=(
                    "Capas de estructura/muros detectadas en CAD: "
                    + ", ".join(report.structure_layers[:8])
                    + ("…" if len(report.structure_layers) > 8 else "")
                ),
                severity="info",
                related_class="wall",
                norm_ref="Capas CAD",
            )
        )

    if report.opening_layers:
        report.issues.append(
            ValidationIssue(
                code="CAD_OPENING_LAYERS",
                message=(
                    "Capas de vanos/puertas/ventanas en CAD: "
                    + ", ".join(report.opening_layers[:8])
                ),
                severity="info",
                related_class="door",
                norm_ref="Capas CAD",
            )
        )

    furniture = [n for n in layer_counts if _layer_matches(n, _FURNITURE_KEYS)]
    if furniture and entity_count > 200:
        report.issues.append(
            ValidationIssue(
                code="CAD_FURNITURE_HEAVY",
                message=(
                    "El dibujo incluye muchas entidades de mobiliario/bloques. "
                    "Pueden generar falsos positivos en detección; conviene un PDF/PNG "
                    "solo de muros y vanos para revisión crítica."
                ),
                severity="warning",
                related_class=None,
                norm_ref="Calidad de lámina",
            )
        )

    report.note = (
        f"CAD: {entity_count} entidades, {len(layer_counts)} capas"
        + (f", extents ~{w:.1f}×{h:.1f}" if w and h else "")
        + (f", unidades {report.units_hint}" if report.units_hint else "")
    )
    return report


def analyze_dxf_file(
    path: str | Path,
    *,
    raster_width_px: int | None = None,
    raster_height_px: int | None = None,
) -> DxfGeometryReport:
    return analyze_dxf_bytes(
        Path(path).read_bytes(),
        raster_width_px=raster_width_px,
        raster_height_px=raster_height_px,
    )
