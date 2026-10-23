"""Pruebas de la API de FastAPI para editar el nombre del proyecto casa hogar."""

import unittest
from fastapi.testclient import TestClient

from api.server import app
from db.models import User
from api.deps import get_current_user


class HomeProjectRenameApiTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_routes_registered_in_fastapi(self):
        paths = app.openapi()["paths"]
        self.assertIn("/api/home-projects/{project_id}/rename", paths)
        self.assertIn("/api/mobile/home-projects/{project_id}/rename", paths)

    def test_rename_requires_auth(self):
        res = self.client.patch("/api/home-projects/test-proj-123/rename", json={"name": "Nuevo Nombre"})
        self.assertIn(res.status_code, [401, 403])

        res_mobile = self.client.patch("/api/mobile/home-projects/test-proj-123/rename", json={"name": "Nuevo Nombre"})
        self.assertIn(res_mobile.status_code, [401, 403])

    def test_rename_validates_min_length(self):
        # Override user auth para probar validación del schema
        mock_user = User(id=1, email="test@example.com", role="user")
        app.dependency_overrides[get_current_user] = lambda: mock_user
        try:
            res = self.client.patch("/api/home-projects/test-proj-123/rename", json={"name": "a"})
            self.assertEqual(res.status_code, 422)  # Pydantic validation error (min_length=2)

            res_empty = self.client.patch("/api/home-projects/test-proj-123/rename", json={})
            self.assertEqual(res_empty.status_code, 422)
        finally:
            app.dependency_overrides.pop(get_current_user, None)


if __name__ == "__main__":
    unittest.main()
