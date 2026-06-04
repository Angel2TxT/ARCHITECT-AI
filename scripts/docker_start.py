"""Start helper for Docker: wait for MySQL, initialize DB, then run FastAPI."""

from __future__ import annotations

import os
import subprocess
import sys
import time

from sqlalchemy import create_engine, text


def wait_for_database() -> None:
    url = os.getenv("DATABASE_URL")
    if not url:
        return

    last_error: Exception | None = None
    for _ in range(45):
        try:
            engine = create_engine(url)
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            engine.dispose()
            return
        except Exception as exc:  # pragma: no cover - startup resilience
            last_error = exc
            time.sleep(2)

    raise RuntimeError(f"MySQL no estuvo listo a tiempo: {last_error}")


def main() -> int:
    wait_for_database()
    subprocess.check_call([sys.executable, "scripts/init_db.py"])
    return subprocess.call(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "api.server:app",
            "--host",
            "0.0.0.0",
            "--port",
            "8000",
            "--reload",
        ]
    )


if __name__ == "__main__":
    raise SystemExit(main())
