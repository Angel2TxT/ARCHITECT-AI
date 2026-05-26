# Cómo aportar tus planos para entrenar la IA

> Si tus PDF traen **explicaciones, diagramas y ejemplos** (no solo plantas), lee primero  
> **[CONOCIMIENTO_DOCUMENTOS.md](CONOCIMIENTO_DOCUMENTOS.md)** (`ingest_knowledge_docs.py`).

La IA **no aprende solo con PDFs sueltos**: necesita **imágenes + etiquetas** (cajas alrededor de cada puerta, ventana, muro, recinto). Tus documentos de construcción y arquitectura son la materia prima; el paso clave es **etiquetarlos** (una vez) y luego **reentrenar YOLO**.

## Por qué hoy marca cosas que no son

En láminas como la tuya suele pasar esto:

1. **Varias vistas en una sola imagen** (plantas + cortes + fachadas + croquis). YOLO fue entrenado con **una planta por imagen**; confunde símbolos, mobiliario y líneas de cotas con puertas/muros.
2. **Confianza muy baja** (p. ej. 0.18): el modelo “adivina” para no quedarse en cero detecciones → falsos positivos.
3. **Estilo distinto** al dataset CubiCasa5K (líneas, grosores, convenciones mexicanas).
4. Solo **4 clases** (`door`, `window`, `wall`, `room`). Escaleras, rampas, sanitarios, etc. aún no existen en el modelo.

Mejorar detección = **más planos como los tuyos, bien etiquetados**, y analizar **una planta recortada** cuando sea posible.

---

## Qué puedes entregar (formatos)

| Formato | Uso |
|---------|-----|
| PDF | Se convierte a PNG (página 1 o todas las páginas) |
| PNG / JPG | Directo |
| DXF / DWG | Se rasteriza a PNG (requiere `ezdwg` / CAD instalado) |

**No subas** planos con datos personales sensibles si van a un servidor compartido; para entrenamiento local basta copiarlos a la carpeta del proyecto.

---

## Dónde poner los archivos en el proyecto

Copia tus documentos aquí (puedes crear subcarpetas por proyecto o municipio):

```
plano-validador/
  data/training/
    raw/              ← TUS PDF, PNG, DWG, DXF (sin tocar)
    to_label/images/  ← PNG listos para etiquetar (generados por script)
    labeled/          ← Después de etiquetar (train/val)
      images/train/
      images/val/
      labels/train/
      labels/val/
```

Comando para generar imágenes desde `raw/`:

```powershell
cd c:\UNI\plano-validador
.\.venv\Scripts\Activate.ps1
python scripts/prepare_training_images.py --input data/training/raw
```

---

## Paso 1: Preparar imágenes (automático)

El script `prepare_training_images.py`:

- Convierte PDF (cada página), DWG/DXF e imágenes a PNG en `data/training/to_label/images/`.
- Opcional: recorta láminas grandes en tiles (`--tiles`) para acercarte a “una planta por imagen”.

```powershell
python scripts/prepare_training_images.py --input data/training/raw --dpi 200
python scripts/prepare_training_images.py --input data/training/raw --tiles --tile-size 1280
```

---

## Paso 2: Etiquetar (manual, imprescindible)

Herramientas recomendadas (gratis o con plan free):

| Herramienta | Ventaja |
|-------------|---------|
| [Roboflow](https://roboflow.com) | Export directo a YOLOv8, colaborativo |
| [CVAT](https://www.cvat.ai) | Bueno para equipos |
| [Label Studio](https://labelstud.io) | Local / self-hosted |

**Clases a dibujar** (mismo orden que `config/data.yaml`):

| ID | Clase | Qué dibujar |
|----|-------|-------------|
| 0 | door | Vano de puerta en planta (rectángulo en el hueco) |
| 1 | window | Ventana en planta |
| 2 | wall | Tramos de muro (rectángulos sobre líneas gruesas) |
| 3 | room | Contorno de cada recinto habitable |

**Consejos para láminas complejas:**

- Etiqueta **solo la planta baja** (recorta o usa una página PDF = una planta).
- No etiquetes cotas, mobiliario, escaleras en fachada ni leyendas del cajetín.
- Mínimo recomendado: **50–100 imágenes** etiquetadas para notar mejora; **200+** para producción estable.

Exporta en formato **YOLOv8** (un `.txt` por imagen con líneas `clase cx cy w h` normalizadas 0–1).

Copia el export a:

```
data/training/labeled/images/train/
data/training/labeled/labels/train/
data/training/labeled/images/val/
data/training/labeled/labels/val/
```

(80 % train / 20 % val es habitual.)

---

## Paso 3: Unir con CubiCasa (opcional) y entrenar

Si ya tienes `datasets/cubicasa_yolo`, puedes **mezclar** tus imágenes etiquetadas en las mismas carpetas `images/train` y `labels/train`, o crear un `config/data_custom.yaml` que apunte solo a `data/training/labeled`.

Entrenar:

```powershell
python scripts/train.py --data config/data.yaml --epochs 80 --device cpu --batch 4 --name plano_elementos_mx
```

Pesos nuevos: `runs/detect/plano_elementos_mx/weights/best.pt`

En la app → **Ajustes** → ruta del modelo: esa `best.pt` → recargar y probar.

---

## Paso 4: Planos que ya subes por la web

Cada análisis guarda el original en:

`data/uploads/<usuario_id>/<analysis_id>/source.pdf` (o `.png`, `.dwg`)

Puedes copiar esos archivos a `data/training/raw/` **solo si tienes derecho** a usarlos para entrenamiento (tuyos o con permiso del cliente).

---

## Checklist rápido

- [ ] Copiar PDF/planos a `data/training/raw/`
- [ ] `python scripts/prepare_training_images.py --input data/training/raw`
- [ ] Etiquetar en Roboflow/CVAT (clases door, window, wall, room)
- [ ] Export YOLO → `data/training/labeled/`
- [ ] `python scripts/train.py --epochs 80 --device cpu`
- [ ] Apuntar Ajustes a `runs/detect/.../weights/best.pt`
- [ ] Subir **una planta por archivo** (o recortar) para validar en producción

---

## Siguiente fase (más clases)

Cuando domines las 4 clases, amplía `config/data.yaml` con, por ejemplo:

`stair`, `ramp`, `bathroom`, `kitchen`, `column`

y vuelve a etiquetar esas clases en tus planos mexicanos. El motor normativo en `rules/` ya contempla circulación, accesibilidad y urbano; el cuello de botella es **que YOLO las detecte**.

---

## Si quieres que el equipo revise tus documentos

1. Coloca una muestra (5–20 planos representativos) en `data/training/raw/`.
2. Indica municipio / tipo (vivienda, comercial, lámina completa vs planta sola).
3. Opcional: comparte export Roboflow ya etiquetado (zip YOLO).

No hace falta “entrenar al chat”: el flujo es **archivos en disco → etiquetas → `train.py` → `best.pt`**.
