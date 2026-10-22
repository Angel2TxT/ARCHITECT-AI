"""
Pruebas unitarias para el pre-procesador y aislador de láminas arquitectónicas.
"""

from __future__ import annotations

import unittest
import numpy as np
import cv2

from core.sheet_splitter import detect_sheet_layout, extract_isolated_plan


class TestSheetSplitter(unittest.TestCase):
    def test_compact_isolated_plan_no_split(self):
        # Imagen de 800x600 (inferior a 1000px)
        compact = np.full((600, 800, 3), 255, dtype=np.uint8)
        regions = detect_sheet_layout(compact)
        self.assertFalse(regions.is_split)
        self.assertEqual(regions.main_plan_bbox, (0, 0, 800, 600))

        cropped, offset, _ = extract_isolated_plan(compact)
        self.assertEqual(offset, (0, 0))
        self.assertEqual(cropped.shape, compact.shape)

    def test_large_sheet_with_title_block_in_corner(self):
        # Lámina grande de 2000x1500 px
        sheet = np.full((1500, 2000, 3), 255, dtype=np.uint8)

        # Dibujar cajetín denso en la esquina inferior derecha (x >= 1450, y >= 1150)
        # Llenar con cuadrículas y patrones de texto simulados
        for y in range(1160, 1490, 15):
            cv2.line(sheet, (1450, y), (1980, y), (0, 0, 0), 1)
        for x in range(1450, 1980, 40):
            cv2.line(sheet, (x, 1160), (x, 1490), (0, 0, 0), 1)

        regions = detect_sheet_layout(sheet)
        self.assertTrue(regions.is_split)
        self.assertIsNotNone(regions.title_block_bbox)

        cropped, (off_x, off_y), _ = extract_isolated_plan(sheet)
        self.assertTrue(cropped.shape[0] < sheet.shape[0] or cropped.shape[1] < sheet.shape[1])
        self.assertEqual((off_x, off_y), (regions.main_plan_bbox[0], regions.main_plan_bbox[1]))


if __name__ == "__main__":
    unittest.main()
