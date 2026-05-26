# ARCHITECT AI (Plano IA)

Interfaz estilo ChatGPT para **revisar planos** (imagen/PDF/DXF/DWG), **detectar elementos** (YOLO) y **validar reglas** (normativa configurable). Incluye modo invitado, login/registro, historial y un flujo de **correcciones** para que el sistema aprenda con tus notas.

## Arquitectura

```
Plano (imagen / PDF / CAD)
      ↓
  YOLOv8  →  puertas, ventanas, muros, habitaciones
      ↓
  Motor de reglas  →  errores / avisos (normativa que tú defines)
      ↓
Correcciones del usuario → se guardan para re-entrenar
```

**YOLO solo detecta objetos.** No entiende el código de edificación: eso va en `rules/`.

## Requisitos

- **Windows 10/11** (probado) o Linux/macOS
- **Python 3.10+**
- **MySQL 8** (recomendado para cuentas/historial). Sin MySQL la UI puede mostrar avisos y algunas funciones no guardan datos.
- GPU NVIDIA (opcional, recomendado para entrenamiento) o CPU (más lento)
- Espacio libre:
  - Solo usar la app (sin entrenar): 1–3 GB
  - Entrenar con dataset: 20+ GB

> Para usar DWG/PDF puede requerirse instalar dependencias extra (ver sección CAD).

## Instalación

```powershell
cd c:\UNI\plano-validador
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Configuración (.env)

1) Crea tu archivo `.env` a partir del ejemplo:

```powershell
copy .env.example .env
```

2) Edita `DATABASE_URL` (MySQL). Ejemplo:

```text
DATABASE_URL=mysql+pymysql://root:TU_PASSWORD@localhost:3306/plano_ia?charset=utf8mb4
```

3) Crea/migra tablas y datos iniciales:

```powershell
python scripts/init_db.py
```

> Esto crea planes, usuario admin, y agrega columnas nuevas si faltan (migración ligera).

## Arrancar la app (Interfaz estilo ChatGPT)

```powershell
.\iniciar.ps1
# o:
python app.py
```

Abre:
- App: **http://127.0.0.1:8080**
- Login: **http://127.0.0.1:8080/login**

> Si ves la pantalla vieja con “Analizar plano” y sliders, es **Gradio en caché/puerto 7860**. Cierra esa pestaña y usa **8080**.

- Botón **+** para adjuntar el plano
- Chips rápidos: *Analizar plano*, *Revisar puertas*, *Revisar medidas*
- **Ajustes**: ruta del modelo, escala (px/m), confianza

## Ejecutarlo en otra PC (u otro monitor)

En otra computadora:

1) Clona el repo y entra a la carpeta.
2) Instala dependencias (`pip install -r requirements.txt`).
3) Configura `.env` y corre `python scripts/init_db.py`.
4) Ejecuta `python app.py`.

Para abrirlo desde **otra PC/tu celular** en la misma red:

- En `app.py` cambia `host="127.0.0.1"` por `host="0.0.0.0"`.
- Usa la IP de tu PC: `http://TU_IP:8080`.

> Nota: abre el puerto 8080 en el firewall si lo necesitas.

## CAD (PDF / DXF / DWG)

- **PDF**: se rasteriza la primera página.
- **DXF/DWG**: se convierte a PNG para el pipeline.

Si DWG/PDF falla, instala extras:

```powershell
pip install pymupdf
pip install "ezdwg[dxf,plot]" ezdxf matplotlib
```

Guía: `docs/CAD_DWG.md`

## Correcciones (para que “aprenda”)

Cuando el modelo se equivoca (ej. **ventana donde hay muro**), puedes corregir:

- **En el panel del análisis**: botones “No es correcto”, “Es muro/puerta/ventana/recinto”.
- **En el chat**: escribe algo como: `esa ventana no es ventana, ahí hay muro`.

Las correcciones:
- Se guardan en MySQL en `analyses.corrections_json`.
- Se exportan a `data/training/feedback/*.jsonl` para re-entrenamiento.

Para aplicar correcciones en un análisis existente, asegúrate de que la DB ya fue migrada:

```powershell
python scripts/init_db.py
```

## Pasos

### 1. Descargar CubiCasa5K (~5 GB)

```powershell
python scripts/download_dataset.py --force
```

Fuente oficial: [Zenodo – CubiCasa5K](https://zenodo.org/record/2613548)

> El zip debe pesar **~5100 MB**. Si pesa ~60 MB, es solo el código de GitHub (sin planos).

### 2. Convertir a formato YOLO

```powershell
# Prueba rápida con 200 muestras (usa data/raw/dataset, NO cubicasa5k)
python scripts/cubicasa_to_yolo.py --input data/raw/dataset --max-samples 200

# Dataset completo (tarda más)
python scripts/cubicasa_to_yolo.py --input data/raw/dataset
```

Opcional: splits oficiales del repo:

```powershell
python scripts/cubicasa_to_yolo.py ^
  --input data/raw/cubicasa5k ^
  --splits-dir data/raw/splits_repo/CubiCasa5k-master
```

### 3. Entrenar YOLOv8

```powershell
# GPU
python scripts/train.py --epochs 100 --device 0

# Solo CPU (laptop)
python scripts/train.py --epochs 50 --device cpu --batch 4
```

Equivalente CLI:

```powershell
yolo detect train data=config/data.yaml model=yolov8n.pt epochs=100 imgsz=640
```

Pesos generados: `runs/detect/plano_elementos/weights/best.pt`

### 4. Probar detección

```powershell
python scripts/infer.py --image mi_plano.png --weights runs/detect/plano_elementos/weights/best.pt
```

### 5. Validar con reglas civiles

Calibra **píxeles por metro** (`--ppm`) según la escala del plano (cotas o escala gráfica):

```powershell
python scripts/validate_plano.py ^
  --image mi_plano.png ^
  --weights runs/detect/plano_elementos/weights/best.pt ^
  --ppm 120
```

Edita umbrales en `rules/norms.py` (puertas ≥ 0.80 m, etc.) según tu normativa local.

## Google Colab

1. Sube esta carpeta o clónala.
2. `!pip install ultralytics opencv-python shapely pyyaml tqdm lxml`
3. Monta Drive y descarga/extrae CubiCasa ahí.
4. Ejecuta los mismos scripts con `--device 0`.

## Clases detectadas

| ID | Clase   | Origen CubiCasa      |
|----|---------|----------------------|
| 0  | door    | Icono Door           |
| 1  | window  | Icono Window         |
| 2  | wall    | Wall                 |
| 3  | room    | Kitchen, Bedroom, …  |

## Lo más difícil (realista)

| Tarea | Dificultad |
|-------|------------|
| Entrenar YOLOv8 | Media |
| Convertir CubiCasa → YOLO | Alta (SVG, escala F1_scaled) |
| Calibrar escala (m/píxel) | Alta |
| Codificar normativa real | Muy alta (varía por país/proyecto) |

## Entrenar con tus propios planos (México / láminas reales)

Tus PDF y DWG **no entrenan solos**: hace falta etiquetar puertas, ventanas, muros y recintos, luego `train.py`.

1. Copia planos a `data/training/raw/`
2. `python scripts/prepare_training_images.py --input data/training/raw`
3. Etiqueta en [Roboflow](https://roboflow.com) o CVAT → export YOLO
4. `python scripts/train.py --epochs 80 --device cpu`

Guía completa: **[docs/ENTRENAMIENTO_PLANOS.md](docs/ENTRENAMIENTO_PLANOS.md)**

## Manuales con texto e imágenes explicativas

Si tus PDF ya traen **qué hacer** y **diagramas de referencia** (no solo plantas):

```powershell
# Copiar PDF a data/knowledge/raw/
python scripts/ingest_knowledge_docs.py
```

El análisis citará fragmentos del manual. Guía: **[docs/CONOCIMIENTO_DOCUMENTOS.md](docs/CONOCIMIENTO_DOCUMENTOS.md)**

## Próximos pasos sugeridos

1. **Segmentación** (YOLO-seg o modelo CubiCasa original) para medidas más precisas que un bbox.
2. **OCR** de cotas en el plano para inferir escala automáticamente.
3. **API** (FastAPI) que reciba imagen y devuelva JSON de errores.
4. **App Flutter** que consuma esa API (encaja con tu stack UNI).

## Estructura del proyecto

```
plano-validador/
├── config/          data.yaml, mapeo de clases
├── scripts/         descarga, conversión, train, infer, validar
├── rules/           motor de normas (tú lo amplías)
├── datasets/        salida YOLO (generada)
└── runs/            modelos entrenados (generado)
```
