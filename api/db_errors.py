"""Errores de base de datos con mensajes claros."""

from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy.exc import OperationalError, SQLAlchemyError


def http_db_error(exc: Exception) -> HTTPException:
    if isinstance(exc, OperationalError):
        msg = str(exc.orig) if getattr(exc, "orig", None) else str(exc)
        if "2003" in msg or "Can't connect" in msg or "deneg" in msg.lower():
            return HTTPException(
                503,
                "MySQL no está disponible. Enciende el servicio, crea la base plano_ia "
                "y ejecuta: python scripts/init_db.py",
            )
        if "1049" in msg or "Unknown database" in msg:
            return HTTPException(
                503,
                "La base plano_ia no existe. Créala en MySQL y ejecuta: python scripts/init_db.py",
            )
        if "1045" in msg or "Access denied" in msg:
            return HTTPException(
                503,
                "Credenciales MySQL incorrectas. Revisa DATABASE_URL en el archivo .env",
            )
        if "1146" in msg or "doesn't exist" in msg:
            return HTTPException(
                503,
                "Tablas no creadas. Ejecuta: python scripts/init_db.py",
            )
        return HTTPException(503, f"Error de base de datos: {msg[:200]}")
    if isinstance(exc, SQLAlchemyError):
        return HTTPException(503, f"Error de base de datos: {str(exc)[:200]}")
    return HTTPException(500, str(exc))
