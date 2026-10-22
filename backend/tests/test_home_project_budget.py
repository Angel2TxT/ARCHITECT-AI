"""Pruebas unitarias para gestión de presupuesto y costos por etapas en HomeProjects."""

import pytest
from unittest.mock import MagicMock

from services.home_project_service import get_project_budget, update_project_budget


class DummyUser:
    def __init__(self, id=1, email="arquitecto@ejemplo.com", role="user"):
        self.id = id
        self.email = email
        self.role = role


class DummyProject:
    def __init__(self, id="proj-123", name="Residencia Los Pinos"):
        self.id = id
        self.name = name
        self.metadata_json = {}


def test_get_project_budget_defaults(monkeypatch):
    user = DummyUser()
    project = DummyProject()

    def mock_require_access(db, u, pid):
        return project, "owner"

    monkeypatch.setattr(
        "services.home_project_service._require_project_access",
        mock_require_access,
    )

    budget = get_project_budget(MagicMock(), user, "proj-123")
    assert budget["project_id"] == "proj-123"
    assert budget["currency"] == "MXN"
    assert budget["total_estimated"] == 0.0
    assert budget["total_spent"] == 0.0
    assert len(budget["stages"]) == 9


def test_update_project_budget(monkeypatch):
    user = DummyUser()
    project = DummyProject()

    def mock_require_access(db, u, pid):
        return project, "owner"

    monkeypatch.setattr(
        "services.home_project_service._require_project_access",
        mock_require_access,
    )
    monkeypatch.setattr("services.home_project_service._log_event", lambda *args, **kwargs: None)

    payload = {
        "currency": "MXN",
        "total_estimated": 350000.0,
        "stages": [
            {"stage_number": 1, "name": "Cimentación", "allocated": 80000.0, "spent": 75000.0, "notes": "Zapatas listas"},
            {"stage_number": 2, "name": "Muros y Estructura", "allocated": 120000.0, "spent": 60000.0, "notes": "En proceso"},
        ],
    }

    db = MagicMock()
    res = update_project_budget(db, user, "proj-123", payload)
    assert res["total_estimated"] == 350000.0
    assert res["total_allocated"] == 200000.0
    assert res["total_spent"] == 135000.0
    assert res["remaining_balance"] == 215000.0
    assert res["percent_spent"] == round((135000 / 350000) * 100, 1)

    # Buscar la etapa 1
    s1 = next(s for s in res["stages"] if s["stage_number"] == 1)
    assert s1["allocated"] == 80000.0
    assert s1["spent"] == 75000.0
    assert s1["variance"] == 5000.0
    assert s1["percent_spent"] == round((75000 / 80000) * 100, 1)
    assert s1["notes"] == "Zapatas listas"
