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
    assert "/api/mobile/device-token" in payload["endpoints"]
    assert "fcm_configured" in payload


def test_mobile_register_requires_valid_body():
    client = TestClient(app)
    response = client.post("/api/mobile/register", json={})

    assert response.status_code == 422


def test_safe_form_helpers_prevent_form_object_attribute_error():
    from fastapi import Form
    from api.routes.analyze import _safe_str, _safe_float, _safe_int

    form_default_str = Form("")
    form_default_val = Form("test_val")
    form_default_float = Form(0.0)
    form_default_int = Form(123)

    assert _safe_str(form_default_str).strip() == ""
    assert _safe_str(form_default_val).strip() == "test_val"
    assert _safe_float(form_default_float) == 0.0
    assert _safe_int(form_default_int) == 123

