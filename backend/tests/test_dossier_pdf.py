"""
Pruebas unitarias para el servicio y endpoint de generación de Dictamen Técnico Oficial en PDF.
"""

from __future__ import annotations

import unittest
from datetime import datetime

from db.models import Analysis, User
from services.peritaje_pdf_service import build_dossier_pdf


class TestDossierPDF(unittest.TestCase):
    def setUp(self):
        self.mock_user = User(
            id=1,
            email="arquitecto@ejemplo.com",
            role="user",
        )

    def test_build_dossier_pdf_favorable(self):
        analysis = Analysis(
            id=101,
            user_id=1,
            original_filename="casa_habitacion.png",
            pixels_per_meter=100.0,
            counts_json={"errors": 0, "warnings": 0, "info": 0},
            issues_json=[],
            created_at=datetime.utcnow(),
        )

        pdf_bytes = build_dossier_pdf(analysis, self.mock_user)
        self.assertIsInstance(pdf_bytes, (bytes, bytearray))
        self.assertTrue(len(pdf_bytes) > 500)
        self.assertTrue(pdf_bytes.startswith(b"%PDF"))

    def test_build_dossier_pdf_with_issues_and_unfavorable_verdict(self):
        issues = [
            {
                "code": "WINDOW_LIGHT_RATIO",
                "label": "Iluminación insuficiente",
                "message": "Iluminación 6.2% del piso (mín. 12.5% — Art. 147)",
                "severity": "warning",
                "norm_ref": "Art. 147 Tuxtla",
            },
            {
                "code": "ROOM_NO_WINDOW",
                "label": "Recinto sin ventana",
                "message": "Recámara principal sin vano exterior detectado",
                "severity": "error",
                "norm_ref": "Art. 147 Tuxtla",
            },
        ]
        analysis = Analysis(
            id=102,
            user_id=1,
            original_filename="departamento_tipo_a.pdf",
            pixels_per_meter=125.0,
            counts_json={"errors": 1, "warnings": 1, "info": 0},
            issues_json=issues,
            created_at=datetime.utcnow(),
        )

        pdf_bytes = build_dossier_pdf(analysis, self.mock_user)
        self.assertIsInstance(pdf_bytes, (bytes, bytearray))
        self.assertTrue(len(pdf_bytes) > 1000)
        self.assertTrue(pdf_bytes.startswith(b"%PDF"))


if __name__ == "__main__":
    unittest.main()
