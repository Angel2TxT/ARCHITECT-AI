"""
Pruebas unitarias para el servicio de OCR y calibración de cotas métricas.
"""

from __future__ import annotations

import unittest
import numpy as np
import cv2

from core.auto_calibrate import calibrate_from_scout
from core.ocr_dimension_service import (
    _COTA_REGEX,
    _find_cota_line_near_text,
    calibrate_scale_from_ocr,
)
from rules.types import Detection


class TestOcrDimensions(unittest.TestCase):
    def test_cota_regex_patterns(self):
        # Casos válidos
        valid_cases = ["3.50m", "2.80", "12.50 m", "0.90mts", "4.25 metros", "Cota: 3.20"]
        for s in valid_cases:
            match = _COTA_REGEX.search(s)
            self.assertIsNotNone(match, f"Fallo al reconocer cota en: {s}")
            val = float(match.group(1))
            self.assertTrue(0.40 <= val <= 45.0)

        # Casos no correspondientes a cotas
        invalid_cases = ["Art. 147", "Nivel 3", "2026", ""]
        for s in invalid_cases:
            match = _COTA_REGEX.search(s)
            if match:
                val = float(match.group(1))
                self.assertFalse(val > 45.0)

    def test_find_cota_line_near_text_synthetic(self):
        # Crear imagen sintética blanca de 600x400
        canvas = np.full((400, 600), 255, dtype=np.uint8)

        # Dibujar una línea de cota horizontal de 300 px de longitud (de x=150 a x=450 en y=200)
        cv2.line(canvas, (150, 200), (450, 200), (0,), 2)
        # Ticks / testigos de cota
        cv2.line(canvas, (150, 190), (150, 210), (0,), 2)
        cv2.line(canvas, (450, 190), (450, 210), (0,), 2)

        # El texto de la cota está situado justo encima de la línea (centrado en x=300, y=185)
        # Bbox del texto: x1=280, y1=170, x2=320, y2=195
        text_bbox = (280.0, 170.0, 320.0, 195.0)

        detected_len = _find_cota_line_near_text(canvas, text_bbox, margin=50)
        self.assertIsNotNone(detected_len)
        # La línea dibujada tiene 300 px
        self.assertAlmostEqual(detected_len, 300.0, delta=25.0)

    def test_calibrate_from_scout_with_ocr_priority(self):
        # Si OCR detecta 120.0 px/m, calibrate_from_scout debe priorizarlo
        scout = [Detection(class_name="door", bbox_xyxy=(10.0, 10.0, 100.0, 30.0))]
        calib = calibrate_from_scout(
            scout,
            image_width_px=1000,
            image_height_px=800,
            ocr_ppm=120.0,
            ocr_note="Cota exacta 3.00m (360px)",
        )

        self.assertAlmostEqual(calib.pixels_per_meter, 120.0, places=1)
        self.assertIn("Cota exacta", calib.ppm_note)


if __name__ == "__main__":
    unittest.main()
