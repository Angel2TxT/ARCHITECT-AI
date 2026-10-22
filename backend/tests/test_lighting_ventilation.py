"""
Pruebas unitarias para el cálculo automático de iluminación y ventilación natural.
"""

from __future__ import annotations

import unittest

from rules.engine import ValidationEngine
from rules.environmental import evaluate_environmental_habitability
from rules.norms import CHIAPAS_RULES, PlanRules
from rules.types import Detection


class TestLightingAndVentilation(unittest.TestCase):
    def setUp(self):
        # 100 px = 1 m
        self.rules = PlanRules(pixels_per_meter=100.0)

    def test_compliant_room_with_adequate_window(self):
        # Recinto de 4m x 3m = 12 m2 (400px x 300px)
        room = Detection(class_name="room", bbox_xyxy=(100.0, 100.0, 500.0, 400.0))
        # Ventana de 1.6m x 1.2m = 1.92 m2 (160px x 120px), colocada en el borde superior del cuarto
        # Ratio iluminación: 1.92 / 12 = 16.0% (mínimo 12.5%) -> Cumple
        # Ratio ventilación: 1.92 * 0.50 / 12 = 8.0% (mínimo 5.0%) -> Cumple
        window = Detection(class_name="window", bbox_xyxy=(200.0, 90.0, 360.0, 210.0))

        report, issues = evaluate_environmental_habitability([room, window], self.rules)

        self.assertEqual(report.total_rooms_evaluated, 1)
        self.assertEqual(report.compliant_rooms_count, 1)
        self.assertEqual(report.overall_status, "compliant")
        self.assertEqual(len(issues), 0)

        metric = report.room_metrics[0]
        self.assertAlmostEqual(metric.room_area_m2, 12.0, places=1)
        self.assertAlmostEqual(metric.total_window_area_m2, 1.92, places=2)
        self.assertEqual(metric.lighting_status, "compliant")
        self.assertEqual(metric.ventilation_status, "compliant")

    def test_room_with_insufficient_lighting_and_ventilation(self):
        # Recinto de 4m x 4m = 16 m2
        room = Detection(class_name="room", bbox_xyxy=(0.0, 0.0, 400.0, 400.0))
        # Ventana muy pequeña: 0.8m x 0.8m = 0.64 m2
        # Ratio iluminación: 0.64 / 16 = 4% (mínimo 12.5%) -> Déficit de iluminación
        # Ratio ventilación: 0.32 / 16 = 2% (mínimo 5.0%) -> Déficit de ventilación
        window = Detection(class_name="window", bbox_xyxy=(50.0, 0.0, 130.0, 80.0))

        report, issues = evaluate_environmental_habitability([room, window], self.rules)

        self.assertEqual(report.total_rooms_evaluated, 1)
        self.assertEqual(report.rooms_with_lighting_deficit, 1)
        self.assertEqual(report.rooms_with_ventilation_deficit, 1)

        metric = report.room_metrics[0]
        self.assertEqual(metric.lighting_status, "deficit")
        self.assertEqual(metric.ventilation_status, "deficit")
        self.assertGreater(metric.lighting_deficit_m2, 0)
        self.assertGreater(metric.ventilation_deficit_m2, 0)

        # Debe generar incidencias para advertir en el reporte normativo
        codes = [i.code for i in issues]
        self.assertIn("WINDOW_LIGHT_RATIO", codes)
        self.assertIn("ROOM_VENTILATION_OPENING", codes)

    def test_room_without_windows_flags_missing_window(self):
        # Recinto de 3.5m x 3.5m = 12.25 m2 sin ninguna ventana
        room = Detection(class_name="room", bbox_xyxy=(100.0, 100.0, 450.0, 450.0))

        report, issues = evaluate_environmental_habitability([room], self.rules)

        self.assertEqual(report.rooms_without_windows, 1)
        metric = report.room_metrics[0]
        self.assertEqual(metric.window_count, 0)
        self.assertEqual(metric.lighting_status, "missing_window")

        codes = [i.code for i in issues]
        self.assertIn("ROOM_NO_WINDOW", codes)

    def test_multiple_windows_aggregate_correctly(self):
        # Recinto de 4m x 4m = 16 m2
        room = Detection(class_name="room", bbox_xyxy=(0.0, 0.0, 400.0, 400.0))
        # Dos ventanas de 1.1m x 1.0m = 1.1 m2 cada una -> Total 2.2 m2
        # Ratio iluminación: 2.2 / 16 = 13.75% (cumple > 12.5%)
        # Ratio ventilación: 1.1 / 16 = 6.875% (cumple > 5.0%)
        win1 = Detection(class_name="window", bbox_xyxy=(50.0, 0.0, 160.0, 100.0))
        win2 = Detection(class_name="window", bbox_xyxy=(200.0, 0.0, 310.0, 100.0))

        report, issues = evaluate_environmental_habitability([room, win1, win2], self.rules)

        metric = report.room_metrics[0]
        self.assertEqual(metric.window_count, 2)
        self.assertAlmostEqual(metric.total_window_area_m2, 2.20, places=1)
        self.assertEqual(metric.lighting_status, "compliant")
        self.assertEqual(metric.ventilation_status, "compliant")
        self.assertEqual(report.compliant_rooms_count, 1)

    def test_validation_engine_integration(self):
        # Verificar que ValidationEngine expone validate_with_report
        engine = ValidationEngine(rules=self.rules)
        room = Detection(class_name="room", bbox_xyxy=(100.0, 100.0, 500.0, 400.0))
        win = Detection(class_name="window", bbox_xyxy=(200.0, 90.0, 360.0, 210.0))
        door = Detection(class_name="door", bbox_xyxy=(100.0, 200.0, 195.0, 215.0))
        wall = Detection(class_name="wall", bbox_xyxy=(100.0, 100.0, 500.0, 115.0))

        issues, env_report = engine.validate_with_report([room, win, door, wall])

        self.assertIsNotNone(env_report)
        self.assertIsInstance(env_report.to_dict(), dict)
        self.assertEqual(env_report.total_rooms_evaluated, 1)


if __name__ == "__main__":
    unittest.main()
