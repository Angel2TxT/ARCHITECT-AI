"""Pruebas unitarias para exportación de planos a formato CAD DXF."""

import ezdxf
import pytest

from rules.types import Detection
from services.cad_export_service import export_detections_to_dxf


def test_export_detections_to_dxf():
    detections = [
        Detection(
            class_name="wall",
            bbox_xyxy=(100.0, 100.0, 500.0, 120.0),
            polygon=[(100.0, 100.0), (500.0, 100.0), (500.0, 120.0), (100.0, 120.0)],
        ),
        Detection(class_name="door", bbox_xyxy=(250.0, 100.0, 340.0, 120.0)),
        Detection(class_name="window", bbox_xyxy=(380.0, 100.0, 480.0, 120.0)),
        Detection(class_name="room", bbox_xyxy=(100.0, 120.0, 500.0, 400.0)),
        Detection(class_name="stair", bbox_xyxy=(110.0, 130.0, 200.0, 300.0)),
    ]

    dxf_bytes = export_detections_to_dxf(detections, pixels_per_meter=100.0, project_title="Casa Habitación Test")
    assert isinstance(dxf_bytes, bytes)
    assert len(dxf_bytes) > 500

    # Leer el DXF con ezdxf para verificar capas y entidades
    import io
    doc = ezdxf.read(io.StringIO(dxf_bytes.decode("utf-8")))
    layer_names = [l.dxf.name for l in doc.layers]
    assert "MUROS" in layer_names
    assert "PUERTAS" in layer_names
    assert "VENTANAS" in layer_names
    assert "RECINTOS" in layer_names
    assert "ESCALERAS" in layer_names

    msp = doc.modelspace()
    entities = list(msp)
    assert len(entities) > 5
