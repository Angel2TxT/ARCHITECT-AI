from fastapi.testclient import TestClient

from api.server import app


def test_mobile_health_endpoint():
    client = TestClient(app)
    response = client.get("/api/mobile/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["service"] == "mobile"
    assert "/api/mobile/register" in payload["endpoints"]


def test_mobile_register_requires_valid_body():
    client = TestClient(app)
    response = client.post("/api/mobile/register", json={})

    assert response.status_code == 422
