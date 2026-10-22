"""
Pruebas unitarias para el selector y validación multi-normativa (Chiapas, CDMX, Nacional).
"""

from __future__ import annotations

import unittest

from fastapi.testclient import TestClient

from api.server import app
from rules.norms import (
    CDMX_RULES,
    CHIAPAS_RULES,
    NACIONAL_RULES,
    SUPPORTED_JURISDICTIONS,
    get_jurisdiction_rules,
)


class TestMultiJurisdiction(unittest.TestCase):
    def test_jurisdiction_constants(self):
        self.assertEqual(CHIAPAS_RULES.jurisdiction, "chiapas_mx")
        self.assertEqual(CDMX_RULES.jurisdiction, "cdmx_rcdf")
        self.assertEqual(NACIONAL_RULES.jurisdiction, "nacional_conavi")

        # Verificar diferencias normativas clave
        # Ventana Iluminación: Chiapas pide 1/8 (12.5%), CDMX pide 10%
        self.assertEqual(CHIAPAS_RULES.window.min_floor_area_ratio, 0.125)
        self.assertEqual(CDMX_RULES.window.min_floor_area_ratio, 0.10)
        self.assertEqual(NACIONAL_RULES.window.min_floor_area_ratio, 0.10)

        # Dimensión mínima de recámara: Chiapas 2.70m, CDMX 2.40m, Nacional 2.60m
        self.assertEqual(CHIAPAS_RULES.room.min_dimension_m, 2.70)
        self.assertEqual(CDMX_RULES.room.min_dimension_m, 2.40)
        self.assertEqual(NACIONAL_RULES.room.min_dimension_m, 2.60)

        # Altura libre mínima: Chiapas 2.60m (cálido), CDMX 2.30m (templado)
        self.assertEqual(CHIAPAS_RULES.room.min_clear_height_m, 2.60)
        self.assertEqual(CDMX_RULES.room.min_clear_height_m, 2.30)

    def test_get_jurisdiction_rules_resolver(self):
        r_chiapas = get_jurisdiction_rules("chiapas", pixels_per_meter=120.0)
        self.assertEqual(r_chiapas.jurisdiction, "chiapas_mx")
        self.assertEqual(r_chiapas.pixels_per_meter, 120.0)

        r_cdmx = get_jurisdiction_rules("cdmx", pixels_per_meter=85.0)
        self.assertEqual(r_cdmx.jurisdiction, "cdmx_rcdf")
        self.assertEqual(r_cdmx.pixels_per_meter, 85.0)

        r_nacional = get_jurisdiction_rules("conavi", pixels_per_meter=100.0)
        self.assertEqual(r_nacional.jurisdiction, "nacional_conavi")

        # Default fallback
        r_default = get_jurisdiction_rules(None)
        self.assertEqual(r_default.jurisdiction, "chiapas_mx")

    def test_api_norms_jurisdictions_endpoint(self):
        client = TestClient(app)
        res = client.get("/api/norms/jurisdictions")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIsInstance(data, list)
        ids = [item["id"] for item in data]
        self.assertIn("chiapas_mx", ids)
        self.assertIn("cdmx_rcdf", ids)
        self.assertIn("nacional_conavi", ids)

    def test_api_norms_with_jurisdiction_filter(self):
        client = TestClient(app)
        res_cdmx = client.get("/api/norms?jurisdiction=cdmx")
        self.assertEqual(res_cdmx.status_code, 200)
        data_cdmx = res_cdmx.json()
        self.assertEqual(data_cdmx["bundle_id"], "cdmx_rcdf")
        self.assertEqual(data_cdmx["rules"]["window"]["min_floor_area_ratio"], 0.10)
        self.assertEqual(data_cdmx["rules"]["room"]["min_dimension_m"], 2.40)

        res_chiapas = client.get("/api/norms?jurisdiction=chiapas")
        self.assertEqual(res_chiapas.status_code, 200)
        data_chiapas = res_chiapas.json()
        self.assertEqual(data_chiapas["bundle_id"], "chiapas_mx")
        self.assertEqual(data_chiapas["rules"]["window"]["min_floor_area_ratio"], 0.125)


if __name__ == "__main__":
    unittest.main()
