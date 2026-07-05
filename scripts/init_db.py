"""
Crea base de datos, tablas MySQL y datos iniciales (planes + admin).

Uso:
  python scripts/init_db.py
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")

from sqlalchemy import create_engine, text

from db.database import Base, engine, session_scope
from db.migrations import apply_pending_migrations
from db.seed import run_seed


def _db_name_from_url(url: str) -> str:
    path = urlparse(url).path.strip("/")
    return path.split("?")[0] or "plano_ia"


def _server_url(url: str, db_name: str) -> str:
    """URL sin nombre de base (para CREATE DATABASE)."""
    p = urlparse(url)
    base = f"{p.scheme}://"
    if p.username:
        base += p.username
        if p.password:
            base += f":{p.password}"
        base += "@"
    base += p.hostname or "localhost"
    if p.port:
        base += f":{p.port}"
    qs = f"?{p.query}" if p.query else ""
    return f"{base}{qs}"


def ensure_database():
    url = os.getenv(
        "DATABASE_URL",
        "mysql+pymysql://root:@localhost:3306/plano_ia?charset=utf8mb4",
    )
    db_name = _db_name_from_url(url)
    if not re.match(r"^[a-zA-Z0-9_]+$", db_name):
        raise ValueError(f"Nombre de base inválido: {db_name}")

    server_url = _server_url(url, db_name)
    print(f"Creando base de datos '{db_name}' si no existe...")
    srv = create_engine(server_url, isolation_level="AUTOCOMMIT")
    with srv.connect() as conn:
        conn.execute(
            text(
                f"CREATE DATABASE IF NOT EXISTS `{db_name}` "
                "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
        )
    srv.dispose()
    print(f"  Base '{db_name}' OK")


def main():
    ensure_database()
    print("Creando tablas...")
    Base.metadata.create_all(bind=engine)
    apply_pending_migrations()
    with session_scope() as db:
        run_seed(db)
    print("OK — tablas, planes y admin listos.")
    print("Admin:", os.getenv("ADMIN_EMAIL", "admin@plano-ia.local"))
    print("Password:", os.getenv("ADMIN_PASSWORD", "admin123"))


if __name__ == "__main__":
    main()
