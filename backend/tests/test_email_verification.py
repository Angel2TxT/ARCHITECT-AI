"""Pruebas automatizadas del sistema de verificación de correo con código de 6 dígitos."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import BigInteger, create_engine
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from api.server import app
from db.database import Base, get_db
from db.models import EmailVerificationCode, Plan, User
from services.auth_service import create_access_token
from services.user_oauth_service import find_or_create_google_user


@compiles(BigInteger, "sqlite")
def _compile_big_int_sqlite(type_, compiler, **kw):
    return "INTEGER"


def _setup_test_db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    with TestingSession() as db:
        db.add(
            Plan(
                slug="free",
                name="Gratis",
                price_monthly_cents=0,
                analyses_limit_monthly=5,
            )
        )
        db.commit()
    return engine, TestingSession


class EmailVerificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.engine, cls.SessionLocal = _setup_test_db()

        def override_get_db():
            db = cls.SessionLocal()
            try:
                yield db
            finally:
                db.close()

        app.dependency_overrides[get_db] = override_get_db
        cls.client = TestClient(app)

    @classmethod
    def tearDownClass(cls) -> None:
        app.dependency_overrides.clear()
        cls.engine.dispose()

    def _register_and_capture_code(self, email: str, full_name: str = "Ana Prueba") -> tuple[dict, str]:
        sent: list[dict] = []

        def fake_send(*, to_email: str, user_name: str, code: str, expires_minutes: int = 5) -> bool:
            sent.append(
                {
                    "to_email": to_email,
                    "user_name": user_name,
                    "code": code,
                    "expires_minutes": expires_minutes,
                }
            )
            return True

        with patch("services.email_verification_service.send_verification_code_email", side_effect=fake_send):
            res = self.client.post(
                "/api/auth/register",
                json={
                    "full_name": full_name,
                    "email": email,
                    "password": "Password123!",
                },
            )
        self.assertEqual(res.status_code, 200, res.text)
        self.assertEqual(len(sent), 1)
        code = sent[0]["code"]
        self.assertRegex(code, r"^\d{6}$")
        self.assertNotIn(code, res.text)
        return res.json(), code

    def test_full_verification_flow_and_hashed_storage(self) -> None:
        email = "verif.ok@example.com"
        reg_data, code = self._register_and_capture_code(email)
        self.assertTrue(reg_data["requires_verification"])
        self.assertEqual(reg_data["access_token"], "")
        self.assertFalse(reg_data["user"]["email_verified"])

        with self.SessionLocal() as db:
            user = db.query(User).filter(User.email == email).first()
            self.assertIsNotNone(user)
            self.assertFalse(user.email_verified)
            record = (
                db.query(EmailVerificationCode)
                .filter(EmailVerificationCode.user_id == user.id)
                .first()
            )
            self.assertIsNotNone(record)
            self.assertNotEqual(record.code_hash, code)
            self.assertEqual(len(record.code_hash), 64)

            forged_token = create_access_token(user_id=user.id, email=user.email, role=user.role)

        # Unverified account cannot log in or call protected endpoints
        login_res = self.client.post(
            "/api/auth/login",
            json={"email": email, "password": "Password123!"},
        )
        self.assertEqual(login_res.status_code, 403, login_res.text)
        self.assertEqual(login_res.json()["detail"]["code"], "EMAIL_NOT_VERIFIED")

        me_res = self.client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {forged_token}"},
        )
        self.assertEqual(me_res.status_code, 403, me_res.text)
        self.assertEqual(me_res.json()["detail"]["code"], "EMAIL_NOT_VERIFIED")

        # Verify with the 6-digit code
        verify_res = self.client.post(
            "/api/auth/verify-email",
            json={"email": email, "code": code},
        )
        self.assertEqual(verify_res.status_code, 200, verify_res.text)
        verify_data = verify_res.json()
        self.assertFalse(verify_data["requires_verification"])
        self.assertTrue(verify_data["user"]["email_verified"])
        self.assertTrue(len(verify_data["access_token"]) > 10)

        # Single-use: reusing the same code must fail
        reuse_res = self.client.post(
            "/api/auth/verify-email",
            json={"email": email, "code": code},
        )
        self.assertEqual(reuse_res.status_code, 400, reuse_res.text)

    def test_max_5_attempts_per_code(self) -> None:
        email = "verif.attempts@example.com"
        _, code = self._register_and_capture_code(email)
        wrong_code = "000000" if code != "000000" else "999999"

        for _ in range(4):
            res = self.client.post(
                "/api/auth/verify-email",
                json={"email": email, "code": wrong_code},
            )
            self.assertEqual(res.status_code, 400, res.text)
            self.assertEqual(res.json()["detail"]["code"], "INVALID_CODE")

        fifth = self.client.post(
            "/api/auth/verify-email",
            json={"email": email, "code": wrong_code},
        )
        self.assertEqual(fifth.status_code, 429, fifth.text)
        self.assertEqual(fifth.json()["detail"]["code"], "MAX_ATTEMPTS_EXCEEDED")

        # Even the right code is now blocked until a new code is issued
        after = self.client.post(
            "/api/auth/verify-email",
            json={"email": email, "code": code},
        )
        self.assertEqual(after.status_code, 400, after.text)
        self.assertEqual(after.json()["detail"]["code"], "NO_ACTIVE_CODE")

    def test_expired_code_is_rejected(self) -> None:
        email = "verif.expired@example.com"
        _, code = self._register_and_capture_code(email)

        with self.SessionLocal() as db:
            user = db.query(User).filter(User.email == email).first()
            record = (
                db.query(EmailVerificationCode)
                .filter(EmailVerificationCode.user_id == user.id)
                .first()
            )
            record.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
            db.commit()

        res = self.client.post(
            "/api/auth/verify-email",
            json={"email": email, "code": code},
        )
        self.assertEqual(res.status_code, 400, res.text)
        self.assertEqual(res.json()["detail"]["code"], "CODE_EXPIRED")

    def test_resend_cooldown_and_previous_code_invalidation(self) -> None:
        email = "verif.resend@example.com"
        _, first_code = self._register_and_capture_code(email)

        # Immediate resend must be blocked by 60s cooldown
        too_soon = self.client.post(
            "/api/auth/resend-verification",
            json={"email": email},
        )
        self.assertEqual(too_soon.status_code, 429, too_soon.text)
        self.assertEqual(too_soon.json()["detail"]["code"], "RESEND_COOLDOWN")

        # Age the code record past 60s
        with self.SessionLocal() as db:
            user = db.query(User).filter(User.email == email).first()
            record = (
                db.query(EmailVerificationCode)
                .filter(EmailVerificationCode.user_id == user.id)
                .first()
            )
            record.created_at = datetime.now(timezone.utc) - timedelta(seconds=65)
            db.commit()

        resent: list[str] = []
        with patch(
            "services.email_verification_service.send_verification_code_email",
            side_effect=lambda **kw: resent.append(kw["code"]) or True,
        ):
            ok_resend = self.client.post(
                "/api/auth/resend-verification",
                json={"email": email},
            )
        self.assertEqual(ok_resend.status_code, 200, ok_resend.text)
        self.assertEqual(len(resent), 1)
        second_code = resent[0]

        # Old code must be invalidated
        old_res = self.client.post(
            "/api/auth/verify-email",
            json={"email": email, "code": first_code},
        )
        self.assertEqual(old_res.status_code, 400, old_res.text)

        # New code succeeds
        new_res = self.client.post(
            "/api/auth/verify-email",
            json={"email": email, "code": second_code},
        )
        self.assertEqual(new_res.status_code, 200, new_res.text)

    def test_update_unverified_email_flow(self) -> None:
        old_email = "verif.typo@example.com"
        new_email = "verif.fixed@example.com"
        _, old_code = self._register_and_capture_code(old_email)

        bad_pw = self.client.post(
            "/api/auth/update-unverified-email",
            json={
                "current_email": old_email,
                "new_email": new_email,
                "password": "WrongPassword123!",
            },
        )
        self.assertEqual(bad_pw.status_code, 401, bad_pw.text)

        captured: list[dict] = []
        with patch(
            "services.email_verification_service.send_verification_code_email",
            side_effect=lambda **kw: captured.append(kw) or True,
        ):
            ok_update = self.client.post(
                "/api/auth/update-unverified-email",
                json={
                    "current_email": old_email,
                    "new_email": new_email,
                },
            )
        self.assertEqual(ok_update.status_code, 200, ok_update.text)
        self.assertEqual(ok_update.json()["email"], new_email)
        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0]["to_email"], new_email)

        # Old email/code no longer works; new email + new code works
        old_try = self.client.post(
            "/api/auth/verify-email",
            json={"email": new_email, "code": old_code},
        )
        self.assertEqual(old_try.status_code, 400, old_try.text)

        new_try = self.client.post(
            "/api/auth/verify-email",
            json={"email": new_email, "code": captured[0]["code"]},
        )
        self.assertEqual(new_try.status_code, 200, new_try.text)

    def test_google_oauth_bypasses_email_verification(self) -> None:
        with self.SessionLocal() as db:
            google_user = find_or_create_google_user(
                db,
                profile={
                    "oauth_subject": "google-sub-12345",
                    "email": "google.user@example.com",
                    "full_name": "Google User",
                },
            )
            self.assertTrue(google_user.email_verified)
            token = create_access_token(
                user_id=google_user.id,
                email=google_user.email,
                role=google_user.role,
            )

        me_res = self.client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(me_res.status_code, 200, me_res.text)
        self.assertTrue(me_res.json()["user"]["email_verified"])


if __name__ == "__main__":
    unittest.main()
