#!/usr/bin/env python3
"""Validación E2E del flujo de billing (demo) contra la API en ejecución."""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request

BASE = "http://localhost:8000"
EMAIL = f"billing-test-{int(time.time())}@architect.local"
PASSWORD = "billing-test-12345"


def req(method: str, path: str, body: dict | None = None, token: str | None = None) -> tuple[int, dict]:
    url = f"{BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode()
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"detail": raw}
        return exc.code, payload


def main() -> int:
    print(f"=== Validación billing en {BASE} ===\n")
    ok = True

    status, health = req("GET", "/api/health")
    if status != 200 or not health.get("ok"):
        print(f"FAIL health: {status} {health}")
        return 1
    print("OK  /api/health")

    status, config = req("GET", "/api/billing/config")
    print(f"OK  /api/billing/config -> mode={config.get('mode')}")
    if config.get("mode") not in ("demo", "stripe"):
        print(f"WARN modo inesperado: {config}")
        ok = False

    status, reg = req(
        "POST",
        "/api/auth/register",
        {"email": EMAIL, "password": PASSWORD, "full_name": "Billing Test"},
    )
    if status != 200:
        print(f"FAIL register: {status} {reg}")
        return 1
    token = reg["access_token"]
    print(f"OK  login ({EMAIL}) plan={reg.get('subscription', {}).get('plan', {}).get('slug')}")

    status, blocked = req("POST", "/api/billing/change-plan", {"plan_slug": "pro"}, token)
    if status != 402:
        print(f"FAIL change-plan pro sin checkout debería ser 402, got {status}: {blocked}")
        ok = False
    else:
        detail = blocked.get("detail", {})
        code = detail.get("code") if isinstance(detail, dict) else None
        print(f"OK  change-plan pro bloqueado (402, code={code})")

    status, checkout = req(
        "POST",
        "/api/billing/checkout",
        {"plan_slug": "pro", "return_url": "/legacy-app"},
        token,
    )
    if status != 200:
        print(f"FAIL checkout: {status} {checkout}")
        return 1
    print(f"OK  checkout pro -> status={checkout.get('status')} mode={checkout.get('mode')}")
    if checkout.get("status") != "checkout_required":
        print(f"FAIL se esperaba checkout_required: {checkout}")
        ok = False

    checkout_url = checkout.get("checkout_url", "")
    session_token = checkout.get("session_token", "")
    if config.get("mode") == "demo":
        if "token=" not in checkout_url or not (
            checkout_url.startswith("/") or checkout_url.startswith("http")
        ):
            print(f"FAIL checkout_url demo inválida: {checkout_url}")
            ok = False
        else:
            print(f"OK  checkout_url demo presente")

        status, complete = req(
            "POST",
            "/api/billing/checkout/complete",
            {"session_token": session_token},
            token,
        )
        if status != 200 or complete.get("status") != "completed":
            print(f"FAIL complete demo: {status} {complete}")
            ok = False
        else:
            plan = complete.get("subscription", {}).get("plan", {}).get("slug")
            print(f"OK  checkout/complete -> plan activo: {plan}")

        status, again = req("POST", "/api/billing/change-plan", {"plan_slug": "pro"}, token)
        if status != 402:
            print(f"FAIL change-plan pro después de pagar debería seguir bloqueado (402), got {status}")
            ok = False
        else:
            print("OK  change-plan pro sigue bloqueado tras activación demo")

        status, down = req("POST", "/api/billing/change-plan", {"plan_slug": "free"}, token)
        if status != 400:
            print(f"FAIL bajar a free debería bloquearse (400), got {status}: {down}")
            ok = False
        else:
            code = (down.get("detail") or {}).get("code") if isinstance(down.get("detail"), dict) else None
            print(f"OK  bajar a free bloqueado (code={code})")

        status, down_co = req(
            "POST",
            "/api/billing/checkout",
            {"plan_slug": "starter", "return_url": "/legacy-app"},
            token,
        )
        if status != 400:
            print(f"FAIL starter desde pro debería ser downgrade 400, got {status}: {down_co}")
            ok = False
        else:
            print("OK  downgrade a starter bloqueado desde checkout")

    elif config.get("mode") == "stripe":
        if not checkout_url.startswith("https://checkout.stripe.com"):
            print(f"WARN checkout_url Stripe: {checkout_url[:80]}...")
        else:
            print("OK  checkout_url Stripe presente")
        print("INFO modo stripe: completa el pago manualmente con tarjeta 4242…")

    print()
    if ok:
        print("=== TODAS LAS PRUEBAS PASARON ===")
        return 0
    print("=== ALGUNAS PRUEBAS FALLARON ===")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
