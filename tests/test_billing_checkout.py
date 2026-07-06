"""Pruebas de checkout demo y restricción de cambio de plan."""

from __future__ import annotations

import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
from jose import jwt

from services.auth_service import ALGORITHM, SECRET_KEY
from services.billing_checkout_service import (
    CHECKOUT_TOKEN_TYPE,
    complete_demo_checkout,
    create_checkout_token,
    decode_checkout_token,
    start_checkout,
)
from services.subscription_service import change_plan, is_paid_plan


class PaidPlanHelpersTests(unittest.TestCase):
    def test_is_paid_plan(self):
        self.assertFalse(is_paid_plan(SimpleNamespace(price_monthly_cents=0)))
        self.assertTrue(is_paid_plan(SimpleNamespace(price_monthly_cents=9900)))


class CheckoutTokenTests(unittest.TestCase):
    def test_create_and_decode_checkout_token(self):
        token = create_checkout_token(
            user_id=42,
            plan_slug="pro",
            return_url="/legacy-app",
        )
        payload = decode_checkout_token(token)
        self.assertEqual(payload["typ"], CHECKOUT_TOKEN_TYPE)
        self.assertEqual(payload["uid"], 42)
        self.assertEqual(payload["plan"], "pro")
        self.assertEqual(payload["return_url"], "/legacy-app")

    def test_invalid_token_raises(self):
        with self.assertRaises(HTTPException):
            decode_checkout_token("not-a-valid-token")


class ChangePlanGuardTests(unittest.TestCase):
    def test_paid_plan_requires_checkout(self):
        db = MagicMock()
        plan = SimpleNamespace(
            id=2,
            slug="pro",
            name="Pro",
            price_monthly_cents=29900,
            is_public=True,
        )
        free = SimpleNamespace(id=1, slug="free", price_monthly_cents=0)
        sub = SimpleNamespace(
            plan_id=1,
            plan=free,
            status=SimpleNamespace(value="active"),
            stripe_customer_id=None,
            stripe_subscription_id=None,
            current_period_start=datetime.now(timezone.utc),
            current_period_end=datetime.now(timezone.utc),
        )
        user = SimpleNamespace(id=7, role="user", email="u@test.com")

        db.query.return_value.filter.return_value.first.side_effect = [plan, sub]

        with patch("services.subscription_service.ensure_subscription", return_value=sub):
            with self.assertRaises(HTTPException) as ctx:
                change_plan(db, user, "pro", bypass_checkout=False)
        self.assertEqual(ctx.exception.status_code, 402)
        detail = ctx.exception.detail
        self.assertEqual(detail["code"], "checkout_required")


class StartCheckoutTests(unittest.TestCase):
    def test_free_plan_completes_without_checkout_url(self):
        db = MagicMock()
        free = SimpleNamespace(
            id=1,
            slug="free",
            name="Gratis",
            price_monthly_cents=0,
            is_public=True,
        )
        pro = SimpleNamespace(id=2, slug="pro")
        sub = SimpleNamespace(plan=pro, plan_id=2)
        user = SimpleNamespace(id=3, role="user", email="free@test.com")

        db.query.return_value.filter.return_value.first.return_value = free

        with patch("services.billing_checkout_service.ensure_subscription", return_value=sub):
            with patch("services.billing_checkout_service.change_plan") as mock_change:
                mock_change.return_value = {"plan": {"slug": "free"}}
                result = start_checkout(db, user, "free")
        self.assertEqual(result["status"], "completed")
        mock_change.assert_called_once()

    def test_paid_plan_returns_demo_checkout_url(self):
        db = MagicMock()
        pro = SimpleNamespace(
            id=2,
            slug="pro",
            name="Pro",
            description="",
            price_monthly_cents=29900,
            is_public=True,
        )
        free = SimpleNamespace(id=1, slug="free")
        sub = SimpleNamespace(plan=free, plan_id=1)
        user = SimpleNamespace(id=5, role="user", email="paid@test.com")

        db.query.return_value.filter.return_value.first.return_value = pro

        with patch("services.billing_checkout_service.ensure_subscription", return_value=sub):
            with patch("services.billing_checkout_service.billing_mode", return_value="demo"):
                result = start_checkout(db, user, "pro", return_url="/legacy-app")

        self.assertEqual(result["status"], "checkout_required")
        self.assertEqual(result["mode"], "demo")
        self.assertIn("checkout_url", result)
        self.assertTrue(result["checkout_url"].startswith("/checkout?token="))
        self.assertIn("session_token", result)


class CompleteDemoCheckoutTests(unittest.TestCase):
    def test_complete_checkout_rejects_other_user(self):
        db = MagicMock()
        token = create_checkout_token(user_id=1, plan_slug="starter", return_url="/legacy-app")
        user = SimpleNamespace(id=99, role="user", email="other@test.com")

        with self.assertRaises(HTTPException) as ctx:
            complete_demo_checkout(db, user, token)
        self.assertEqual(ctx.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
