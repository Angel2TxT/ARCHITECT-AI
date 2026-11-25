"""Pruebas de validación de entrada para registro y actualización de perfil."""

from __future__ import annotations

import unittest

from fastapi.testclient import TestClient
from sqlalchemy import BigInteger, create_engine
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from api.server import app
from db.database import Base, get_db
from db.models import Plan, User


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


class AuthValidationApiTests(unittest.TestCase):
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

    def _user_count(self) -> int:
        with self.SessionLocal() as db:
            return db.query(User).count()

    def test_valid_names_and_emails_register_successfully(self) -> None:
        valid_cases = [
            ("Juan Pérez", "prueba@gmail.com"),
            ("María José", "prueba+27@gmail.com"),
            ("Ana García-López", "ana.garcia@ejemplo.com"),
            ("Liam O'Connor", "liam_oconnor@ejemplo.com"),
        ]
        for full_name, email in valid_cases:
            with self.subTest(full_name=full_name, email=email):
                res = self.client.post(
                    "/api/auth/register",
                    json={
                        "full_name": full_name,
                        "email": email,
                        "password": "Password123!",
                    },
                )
                self.assertEqual(res.status_code, 200, res.text)
                data = res.json()
                self.assertTrue(data["requires_verification"])
                self.assertEqual(data["access_token"], "")
                self.assertFalse(data["user"]["email_verified"])
                self.assertEqual(data["user"]["full_name"], full_name.strip())
                self.assertEqual(data["user"]["email"], email.lower())

    def test_invalid_names_are_rejected_without_creating_users(self) -> None:
        invalid_names = [
            "<b>prueba</b>",
            "<div>prueba</div>",
            "<B>prueba</B>",
            "<b>prueba",
            "prueba</div>",
            "&lt;b&gt;prueba&lt;/b&gt;",
            "Juan &amp; Pérez",
            "",
            "     ",
            "A",
        ]
        before = self._user_count()
        for idx, bad_name in enumerate(invalid_names):
            with self.subTest(bad_name=bad_name):
                res = self.client.post(
                    "/api/auth/register",
                    json={
                        "full_name": bad_name,
                        "email": f"valid.name.{idx}@gmail.com",
                        "password": "Password123!",
                    },
                )
                self.assertEqual(res.status_code, 422, res.text)
                self.assertNotEqual(res.status_code, 500)
        self.assertEqual(self._user_count(), before)

    def test_invalid_emails_are_rejected_without_creating_users(self) -> None:
        invalid_emails = [
            "<b>prueba</b>27@gmail.com",
            "prueba@gmail",
            "prueba@@gmail.com",
            "",
            "   ",
            "prueba/test@gmail.com",
        ]
        before = self._user_count()
        for bad_email in invalid_emails:
            with self.subTest(bad_email=bad_email):
                res = self.client.post(
                    "/api/auth/register",
                    json={
                        "full_name": "Usuario Válido",
                        "email": bad_email,
                        "password": "Password123!",
                    },
                )
                self.assertEqual(res.status_code, 422, res.text)
                self.assertNotEqual(res.status_code, 500)
        self.assertEqual(self._user_count(), before)

    def test_profile_update_applies_same_name_validation(self) -> None:
        reg = self.client.post(
            "/api/auth/register",
            json={
                "full_name": "Carlos Méndez",
                "email": "carlos.mendez@gmail.com",
                "password": "Password123!",
            },
        )
        self.assertEqual(reg.status_code, 200, reg.text)
        with self.SessionLocal() as db:
            user = db.query(User).filter(User.email == "carlos.mendez@gmail.com").first()
            self.assertIsNotNone(user)
            user.email_verified = True
            db.commit()
        login_res = self.client.post(
            "/api/auth/login",
            json={
                "email": "carlos.mendez@gmail.com",
                "password": "Password123!",
            },
        )
        self.assertEqual(login_res.status_code, 200, login_res.text)
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        for bad_name in [
            "<b>prueba</b>",
            "<div>prueba</div>",
            "&lt;script&gt;",
            "   ",
        ]:
            res = self.client.patch(
                "/api/auth/me",
                headers=headers,
                json={"full_name": bad_name},
            )
            self.assertEqual(res.status_code, 422, res.text)
            self.assertNotEqual(res.status_code, 500)

        ok_res = self.client.patch(
            "/api/auth/me",
            headers=headers,
            json={"full_name": "  María José  "},
        )
        self.assertEqual(ok_res.status_code, 200, ok_res.text)
        self.assertEqual(ok_res.json()["user"]["full_name"], "María José")


if __name__ == "__main__":
    unittest.main()
