# Preguntas de construcción (sin plano)

Puedes escribir en el chat **sin adjuntar archivo**:

- «¿Cuáles son las medidas oficiales en Ocosingo?»
- «Ancho mínimo de puertas en Chiapas»
- «¿Qué dice el reglamento sobre ventilación?»

## De dónde sale la respuesta

1. **Tus PDF** en `data/knowledge/raw` (tras `ingest_knowledge_docs.py`)
2. **Umbrales** configurados en `rules/norms.py` (referencia Tuxtla / Chiapas)
3. **Internet** (opcional) — DuckDuckGo para reglamentos municipales

## Activar búsqueda web

En `.env`:

```
WEB_SEARCH_ENABLED=true
```

Requisito: `pip install duckduckgo-search`

Comprueba: `GET /api/ask/status`

## Municipios reconocidos en la pregunta

Ocosingo, Tuxtla Gutiérrez, San Cristóbal, Tapachula, Comitán, Palenque, Villaflores, Chiapas.

Si el municipio tiene reglamento propio, la respuesta web + nota te indica confirmar con el ayuntamiento.

## Analizar un plano

Adjunta el archivo y escribe la pregunta en el mismo mensaje (o después de adjuntar).
