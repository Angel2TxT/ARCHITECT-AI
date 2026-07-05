# Preguntas de construcción (sin plano)

Puedes escribir en el chat **sin adjuntar archivo**:

- «¿Cuáles son las medidas oficiales en Ocosingo?»
- «Ancho mínimo de puertas en Chiapas»
- «¿Qué materiales convienen para losa en clima húmedo?»
- «¿Qué trámites pide el ayuntamiento para ampliación?»

## IA ARCHITECT (sin costo, sin APIs externas)

ARCHITECT responde con **su propia biblioteca**:

1. **Tus PDF** en `data/knowledge/raw` (tras `ingest_knowledge_docs.py`)
2. **Umbrales normativos** en `rules/norms.py` (referencia Tuxtla / Chiapas)
3. **Internet** (opcional) — DuckDuckGo para reglamentos municipales

No se usa OpenAI ni servicios de pago. La respuesta se redacta a partir de lo indexado.

Comprueba estado: `GET /api/ask/status` → `architect_ai_enabled: true` y `document_catalog`.

### Biblioteca actual (447 páginas)

| Documento | Contenido |
|-----------|-----------|
| **Manual+Casa+1_LR** | Vivienda progresiva, etapas, criterios de diseño (texto + planos) |
| **las-medidas-de-una-casa** | Tablas gráficas de medidas por espacio (diagramas) |
| **Neufert - parte 1** | Referencia antropométrica (diagramas/tablás) |

La IA enlaza sinónimos (cocina, recámara, Neufert, escalera…) con el documento correcto.

## Activar búsqueda web

En `.env`:

```
WEB_SEARCH_ENABLED=true
```

## Ampliar lo que «sabe» ARCHITECT

1. Coloca PDF (reglamentos, manuales) en `data/knowledge/raw`
2. Ejecuta: `python scripts/ingest_knowledge_docs.py`
3. Vuelve a preguntar en el chat

## Municipios reconocidos

Ocosingo, Tuxtla Gutiérrez, San Cristóbal, Tapachula, Comitán, Palenque, Villaflores, Chiapas.

## Analizar un plano

Adjunta el archivo y escribe la pregunta en el mismo mensaje.
