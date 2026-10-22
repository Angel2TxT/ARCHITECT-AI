"""Pruebas unitarias para soporte de polígonos y segmentación en Detection."""

import pytest
from shapely.geometry import Polygon

from core.tiled_infer import _boxes_to_detections
from rules.types import Detection
from services.feedback_service import detection_to_dict, dict_to_detection


def test_detection_bbox_fallback():
    # Sin polígono, área y perímetro corresponden al bounding box
    det = Detection(class_name="room", bbox_xyxy=(0.0, 0.0, 100.0, 50.0))
    assert det.width_px == 100.0
    assert det.height_px == 50.0
    assert det.area_px == 5000.0
    assert det.perimeter_px == 300.0
    geom = det.to_shapely()
    assert geom.geom_type == "Polygon"
    assert geom.area == 5000.0


def test_detection_l_shaped_polygon():
    # Habitación en L: bounding box 100x100 (área 10,000), pero la L tiene área 7,500
    # Polígono L: (0,0) -> (100,0) -> (100,50) -> (50,50) -> (50,100) -> (0,100)
    l_poly = [(0.0, 0.0), (100.0, 0.0), (100.0, 50.0), (50.0, 50.0), (50.0, 100.0), (0.0, 100.0)]
    det = Detection(
        class_name="room",
        bbox_xyxy=(0.0, 0.0, 100.0, 100.0),
        polygon=l_poly,
    )
    # El bounding box daría 10,000 px²
    assert det.width_px * det.height_px == 10000.0
    # El área del polígono real debe ser 7,500 px²
    assert det.area_px == 7500.0
    # Perímetro real: 100 + 50 + 50 + 50 + 50 + 100 = 400
    assert det.perimeter_px == 400.0


def test_feedback_polygon_roundtrip():
    poly = [(10.5, 20.2), (50.8, 20.2), (50.8, 80.4), (10.5, 80.4)]
    det = Detection(
        class_name="bathroom",
        bbox_xyxy=(10.5, 20.2, 50.8, 80.4),
        confidence=0.92,
        polygon=poly,
    )
    data = detection_to_dict(det, idx=3)
    assert data["idx"] == 3
    assert data["class"] == "bathroom"
    assert "polygon" in data
    assert len(data["polygon"]) == 4

    restored = dict_to_detection(data)
    assert restored.class_name == "bathroom"
    assert restored.confidence == 0.92
    assert restored.polygon is not None
    assert len(restored.polygon) == 4
    assert round(restored.area_px, 1) == round(det.area_px, 1)


class DummyBox:
    def __init__(self, cls_id: int, xyxy: list[float], conf: float):
        self.cls = [cls_id]
        import numpy as np
        self.xyxy = np.array([xyxy])
        self.conf = [conf]


class DummyMasks:
    def __init__(self, polygons):
        self.xy = polygons


class DummyResult:
    def __init__(self, boxes, masks=None):
        self.boxes = boxes
        self.masks = masks


def test_boxes_to_detections_with_masks():
    boxes = [DummyBox(0, [10.0, 20.0, 30.0, 40.0], 0.95)]
    masks = DummyMasks([[(10.0, 20.0), (30.0, 20.0), (30.0, 40.0), (10.0, 40.0)]])
    res = DummyResult(boxes, masks)
    names = {0: "door"}

    dets = _boxes_to_detections([res], names)
    assert len(dets) == 1
    assert dets[0].class_name == "door"
    assert dets[0].polygon is not None
    assert len(dets[0].polygon) == 4
