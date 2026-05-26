# Documentos con explicaciones e imágenes (conocimiento)

Tus PDF de construcción y arquitectura **no son solo planos para medir**: traen **qué hacer**, **por qué** y **diagramas de referencia**. El validador puede usar ese material de **tres formas distintas**.

## Las 3 formas de usar tus documentos

| Tipo de contenido en el PDF | Para qué sirve | Cómo lo usa el proyecto |
|-----------------------------|----------------|-------------------------|
| **Texto normativo** (artículos, mínimos, procedimientos) | Entender reglas | Se indexa y **se cita en el análisis** (`rules/norms.py` + base de conocimiento) |
| **Imágenes explicativas** (leyendas, símbolos, “cómo se revisa”) | Saber qué buscar en un plano | Referencia visual; opcional entrenamiento si etiquetas los símbolos |
| **Planos de ejemplo** dentro del manual | Enseñar a la IA dónde están puertas/muros | Exportar PNG → etiquetar → **entrenar YOLO** (`docs/ENTRENAMIENTO_PLANOS.md`) |

**Importante:** YOLO no “lee” el PDF entero como un humano. Hay que **extraer** páginas e imágenes y conectar cada uso (citas, entrenamiento, reglas).

---

## Paso 1: Copiar tus manuales aquí

```
data/knowledge/raw/
  Reglamento_Construccion.pdf
  Manual_revision_planos.pdf
  Guia_simbologia.pdf
  ...
```

---

## Paso 2: Procesar (texto + imagen por página)

```powershell
cd c:\UNI\plano-validador
.\.venv\Scripts\Activate.ps1
python scripts/ingest_knowledge_docs.py
```

Genera:

```
data/knowledge/processed/<id_documento>/
  manifest.json      ← índice (tipo de cada página)
  pages/
    001.png          ← imagen de la página (diagramas incluidos)
    001.txt          ← texto extraído
    002.png
    002.txt
    ...
```

El `manifest.json` clasifica cada página:

| page_type | Significado |
|-----------|-------------|
| `regulation_text` | Artículos y requisitos → citas en el chat |
| `diagram` | Leyenda, símbolos, esquemas |
| `example_plan` | Plano de ejemplo en el manual |
| `mixed` | Texto + figuras |

---

## Paso 3: Qué hacer con las imágenes extraídas

1. Abre `pages/*.png` en el explorador de archivos.
2. **Diagramas / leyendas** → úsalos para verificar que `rules/norms.py` tenga los mismos criterios.
3. **Planos de ejemplo** con puertas y recintos claros → cópialos a `data/training/to_label/images/` y etiqueta para YOLO.
4. **Fotos o renders** que no son planta → no sirven para YOLO; sí para documentación.

---

## Paso 4: Reiniciar la app

Tras ingestar, reinicia `python app.py`. En el análisis, si hay manuales indexados, la respuesta puede incluir **Referencias del documento** (fragmentos del texto que coinciden con las incidencias).

Comprueba estado:

`GET /api/knowledge` → número de documentos y páginas indexadas.

---

## Relación con la normativa Chiapas

- `rules/norms.py` = umbrales **fijos** que valida el motor (0.90 m puertas, etc.).
- `data/knowledge/processed/` = **tus PDF** con la explicación extendida y contexto local.
- Ambos se complementan: el motor mide; los manuales **explican** en el chat.

---

## Si el PDF es escaneado (solo imagen, sin texto seleccionable)

El `.txt` saldrá casi vacío. Opciones:

1. Usar PDF con texto (exportar desde CAD).
2. Añadir después OCR (futuro: Tesseract / servicio cloud).
3. Mientras tanto: usar las **PNG** de cada página como referencia visual y para etiquetar.

---

## Resumen

| Tu material | Acción |
|-----------|--------|
| PDF con reglas y explicaciones | `ingest_knowledge_docs.py` → citas en análisis |
| Imágenes “así se hace” / leyenda | Revisar PNG + ajustar `norms.py` |
| Planos ejemplo en el manual | `prepare_training_images.py` + etiquetar + `train.py` |
| Láminas reales de obra | `data/training/raw/` + entrenamiento |

No hace falta “entrenar al chat” con el PDF completo: hay que **clasificar cada página** según para qué sirve (norma, leyenda o plano).
