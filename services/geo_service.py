"""Geocodificación vía Nominatim (OpenStreetMap), acotada a Chiapas."""

from __future__ import annotations

from typing import Any

import httpx
from fastapi import HTTPException

# Aprox. bounding box de Chiapas (izquierda, arriba, derecha, abajo) para Nominatim.
CHIAPAS_VIEWBOX = "-94.15,17.98,-90.37,14.53"
CHIAPAS_CENTER = (16.7569, -93.1292)  # Tuxtla Gutiérrez
CHIAPAS_BOUNDS = {
    "south": 14.53,
    "north": 17.98,
    "west": -94.15,
    "east": -90.37,
}

NOMINATIM_SEARCH = "https://nominatim.openstreetmap.org/search"
NOMINATIM_REVERSE = "https://nominatim.openstreetmap.org/reverse"
USER_AGENT = "ARCHITECT-HomeProjects/1.0 (proyecto-escolar; contacto@architect.local)"


def in_chiapas(lat: float, lon: float, *, slack: float = 0.15) -> bool:
    return (
        CHIAPAS_BOUNDS["south"] - slack <= lat <= CHIAPAS_BOUNDS["north"] + slack
        and CHIAPAS_BOUNDS["west"] - slack <= lon <= CHIAPAS_BOUNDS["east"] + slack
    )


def _format_label(item: dict[str, Any]) -> str:
    addr = item.get("address") or {}
    parts: list[str] = []
    for key in (
        "neighbourhood",
        "suburb",
        "village",
        "town",
        "city",
        "municipality",
        "county",
        "state_district",
    ):
        val = (addr.get(key) or "").strip()
        if val and val not in parts:
            parts.append(val)
    state = (addr.get("state") or "").strip()
    if state and state not in parts:
        parts.append(state)
    if parts:
        return ", ".join(parts[:4])
    display = (item.get("display_name") or "").strip()
    if display:
        return display.split(",")[0].strip() + (", Chiapas" if "Chiapas" not in display else "")
    return "Ubicación en Chiapas"


def _normalize_result(item: dict[str, Any]) -> dict[str, Any] | None:
    try:
        lat = float(item["lat"])
        lon = float(item["lon"])
    except (KeyError, TypeError, ValueError):
        return None
    return {
        "label": _format_label(item),
        "display_name": item.get("display_name") or _format_label(item),
        "latitude": lat,
        "longitude": lon,
        "in_chiapas": in_chiapas(lat, lon),
    }


async def search_places(query: str, *, limit: int = 8) -> list[dict[str, Any]]:
    q = (query or "").strip()
    if len(q) < 2:
        return []
    limit = max(1, min(int(limit or 8), 12))
    params = {
        "q": q,
        "format": "json",
        "addressdetails": 1,
        "limit": limit,
        "countrycodes": "mx",
        "viewbox": CHIAPAS_VIEWBOX,
        "bounded": 1,
    }
    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            res = await client.get(
                NOMINATIM_SEARCH,
                params=params,
                headers={"User-Agent": USER_AGENT, "Accept-Language": "es"},
            )
    except httpx.HTTPError as exc:
        raise HTTPException(502, f"No se pudo consultar el mapa: {exc}") from exc
    if res.status_code >= 400:
        raise HTTPException(502, "El servicio de mapas no respondió correctamente")
    out: list[dict[str, Any]] = []
    for item in res.json() or []:
        if not isinstance(item, dict):
            continue
        row = _normalize_result(item)
        if row:
            out.append(row)
    return out


async def reverse_geocode(lat: float, lon: float) -> dict[str, Any]:
    params = {
        "lat": lat,
        "lon": lon,
        "format": "json",
        "addressdetails": 1,
        "zoom": 16,
    }
    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            res = await client.get(
                NOMINATIM_REVERSE,
                params=params,
                headers={"User-Agent": USER_AGENT, "Accept-Language": "es"},
            )
    except httpx.HTTPError as exc:
        raise HTTPException(502, f"No se pudo consultar el mapa: {exc}") from exc
    if res.status_code >= 400:
        raise HTTPException(502, "El servicio de mapas no respondió correctamente")
    data = res.json() or {}
    if not isinstance(data, dict) or "lat" not in data:
        return {
            "label": f"{lat:.5f}, {lon:.5f}",
            "display_name": f"{lat:.5f}, {lon:.5f}",
            "latitude": lat,
            "longitude": lon,
            "in_chiapas": in_chiapas(lat, lon),
        }
    row = _normalize_result(data)
    if not row:
        raise HTTPException(404, "No se encontró dirección para esas coordenadas")
    return row
