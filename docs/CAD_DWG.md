# Planos para análisis IA: imágenes, PDF y CAD

El **análisis con IA** acepta:

| Formato | Notas |
|---------|--------|
| Imágenes | PNG, JPG, WEBP, BMP, TIF/TIFF |
| PDF | Rasteriza la página con **más contenido dibujado** (pymupdf), DPI adaptativo |
| DXF | Raster + análisis de capas/geometría (`ezdxf`) |
| DWG | Convierte con **ezdwg** → ODA / LibreDWG / AutoCAD → DXF/PNG |

## Dependencias

```bash
pip install pymupdf
pip install "ezdwg[dxf,plot]" ezdxf matplotlib   # CAD opcional pero recomendado
```

Health: `/api/health` → `"cad": { "pdf": true, "dxf": true, "dwg": true, ... }`

## Pipeline mejorado

1. Conversión a PNG (y DXF intermedio si aplica)
2. Inferencia YOLO por **tiles** en planos grandes + NMS
3. `imgsz` adaptativo (640 / 960 / 1280)
4. Avisos de capas CAD + calibración de escala asistida por extents DXF
5. Reglas tipadas listas para clases ampliadas tras reentrenar

## Casa hogar

En documentación de proyectos también: `.doc`, `.docx`, `.xls`, `.xlsx` (almacenamiento).

## Código

- `services/cad_service.py` — conversión
- `services/dxf_geometry.py` — capas / escala CAD
- `core/tiled_infer.py` — tiles + NMS
- `core/pipeline.py` — orquestación
