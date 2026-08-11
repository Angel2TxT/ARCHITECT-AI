"""
API Plano IA — FastAPI + MySQL + auth + suscripciones.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from contextlib import asynccontextmanager

from fastapi import FastAPI  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.responses import FileResponse  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402
from sqlalchemy import text  # noqa: E402
from starlette.middleware.base import BaseHTTPMiddleware  # noqa: E402
from starlette.requests import Request  # noqa: E402

from api.routes import (  # noqa: E402
    admin,
    analyses,
    analyze,
    ask,
    auth,
    billing,
    chats,
    feedback,
    guest,
    home_projects,
    knowledge,
    mobile,
    mobile_home_projects,
    norms,
    support,
)
from core.pipeline import find_default_weights  # noqa: E402
from db.database import engine  # noqa: E402
from db.migrations import apply_pending_migrations  # noqa: E402
from services.cad_service import cad_support_status  # noqa: E402
from services.email_service import mail_config_status  # noqa: E402
from services.knowledge_service import knowledge_stats  # noqa: E402

WEB_DIR = ROOT / "web"
STATIC_DIR = WEB_DIR / "static"
FRONTEND_DIST = ROOT / "frontend" / "dist"
AVATAR_DIR = ROOT / "data" / "avatars"


@asynccontextmanager
async def lifespan(_app: FastAPI):
    try:
        apply_pending_migrations()
    except Exception as exc:
        print(f"[ARCHITECT] Migraciones omitidas al arranque: {exc}")
    yield


app = FastAPI(title="ARCHITECT", version="2.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class NoCacheHTML(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        if (
            request.url.path
            in (
                "/",
                "/app",
                "/login",
                "/welcome",
                "/privacidad",
                "/privacy",
                "/terminos",
                "/terms",
                "/checkout",
                "/checkout/success",
                "/index.html",
                "/legacy-app",
            )
            or request.url.path.startswith("/static/")
            or request.url.path.startswith("/app/")
        ):
            response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
        return response


app.add_middleware(NoCacheHTML)

app.include_router(guest.router)
app.include_router(auth.router)
app.include_router(chats.router)
app.include_router(billing.router)
app.include_router(admin.router)
app.include_router(support.router)
app.include_router(analyze.router)
app.include_router(feedback.router)
app.include_router(analyses.router)
app.include_router(ask.router)
app.include_router(knowledge.router)
app.include_router(mobile.router)
app.include_router(mobile_home_projects.router)
app.include_router(norms.router)
app.include_router(home_projects.router)


def _all_weights() -> list[Path]:
    runs = ROOT / "runs" / "detect"
    if not runs.exists():
        return []
    return sorted(runs.rglob("best.pt"), key=lambda p: p.stat().st_mtime, reverse=True)


def _db_ok() -> tuple[bool, str | None]:
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True, None
    except Exception as exc:
        return False, str(exc)


@app.get("/api/health")
def health():
    """Estado de MySQL, CAD, manuales y modelo."""
    db_ok, db_err = _db_ok()
    cad = cad_support_status()
    k = knowledge_stats()
    weights = find_default_weights()

    hints: list[str] = []
    if not db_ok:
        hints.append(
            "MySQL no conectado: revisa .env, enciende el servicio y ejecuta "
            "python scripts/init_db.py"
        )
    if not weights or not weights.is_file():
        hints.append("Modelo best.pt no encontrado; entrena o configura la ruta en Ajustes.")
    if not cad.get("pdf"):
        hints.append("Para PDF en análisis: pip install pymupdf")
    if k.get("pages", 0) == 0:
        hints.append(
            "Sin manuales indexados; opcional: python scripts/ingest_knowledge_docs.py"
        )
    mail = mail_config_status()
    if not mail.get("configured"):
        hints.append(
            "Correo Brevo no configurado: completa MAIL_* en .env para tickets y recuperación de contraseña. "
            "Ver docs/MAIL_BREVO_SETUP.md"
        )

    return {
        "ok": db_ok,
        "database": db_ok,
        "database_error": db_err,
        "cad": cad,
        "knowledge": k,
        "model_weights": str(weights) if weights else None,
        "model_ready": bool(weights and weights.is_file()),
        "mail": mail,
        "hints": hints,
    }


@app.get("/api/config")
def get_config():
    """Config pública del modelo (sin auth)."""
    candidates = _all_weights()
    weights = candidates[0] if candidates else None
    default = (
        str(weights)
        if weights
        else str(ROOT / "runs/detect/demo_planos/weights/best.pt")
    )
    wpath = Path(default)
    if not wpath.is_absolute():
        wpath = ROOT / wpath
    demo_ready = (ROOT / "runs/detect/demo_planos/weights/best.pt").is_file()
    return {
        "weights": str(wpath),
        "weights_exists": wpath.is_file(),
        "demo_ready": demo_ready,
        "default_ppm": 100,
        "default_conf": 0.05,
        "auto_calibrate_default": True,
        "auth_required": True,
        "database_url_set": bool(os.getenv("DATABASE_URL")),
    }


def _react_index() -> Path | None:
    index_file = FRONTEND_DIST / "index.html"
    return index_file if index_file.is_file() else None


def _frontend_page(fallback: Path):
    react = _react_index()
    return FileResponse(react or fallback, headers={"Cache-Control": "no-store"})


def _legacy_page(path: Path):
    """HTML estático en web/ (no el index del build React)."""
    return FileResponse(path, headers={"Cache-Control": "no-store"})


@app.get("/")
def index():
    return _legacy_page(WEB_DIR / "welcome.html")


@app.get("/app")
def app_page():
    return _frontend_page(WEB_DIR / "index.html")


@app.get("/app/admin")
def admin_app_page():
    return _legacy_page(WEB_DIR / "admin.html")


@app.get("/app/{spa_path:path}")
def app_spa_routes(spa_path: str):
    """Rutas del React SPA: /app/projects, etc."""
    return _frontend_page(WEB_DIR / "index.html")


@app.get("/login")
def login_page():
    return _legacy_page(WEB_DIR / "login.html")


@app.get("/privacidad")
@app.get("/privacy")
def privacy_page():
    return _legacy_page(WEB_DIR / "privacy.html")


@app.get("/terminos")
@app.get("/terms")
def terms_page():
    return _legacy_page(WEB_DIR / "terms.html")


@app.get("/welcome")
def welcome_page():
    return _legacy_page(WEB_DIR / "welcome.html")


@app.get("/checkout")
def checkout_page():
    return _legacy_page(WEB_DIR / "checkout.html")


@app.get("/checkout/success")
def checkout_success_page():
    return _legacy_page(WEB_DIR / "checkout-success.html")


@app.get("/legacy-app")
def legacy_app_page():
    return FileResponse(WEB_DIR / "index.html", headers={"Cache-Control": "no-store"})


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
AVATAR_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/media/avatars", StaticFiles(directory=AVATAR_DIR), name="avatars")
if (FRONTEND_DIST / "assets").is_dir():
    app.mount("/assets", StaticFiles(directory=FRONTEND_DIST / "assets"), name="assets")
