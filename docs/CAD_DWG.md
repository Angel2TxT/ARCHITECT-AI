# Planos para análisis IA: imágenes y PDF

El **análisis con IA** acepta solo:

| Formato | Notas |
|---------|--------|
| Imágenes | PNG, JPG, WEBP, BMP, TIF/TIFF |
| PDF | Se rasteriza la 1ª página con **pymupdf** |

**DXF / DWG ya no se usan en el análisis.** Exporta a PNG/JPG/PDF desde AutoCAD, o súbelos como **documentación** en Casa hogar (ahí sí están).

## Dependencia PDF

```bash
pip install pymupdf
```

Health: `/api/health` → `"cad": { "pdf": true, ... }`

## Casa hogar (documentación)

En proyectos casa hogar se permiten también: `.dxf`, `.dwg`, `.doc`, `.docx`, `.xls`, `.xlsx` (almacenamiento; sin conversión YOLO).

## Código legacy CAD

`services/cad_service.py` aún contiene helpers DXF/DWG por si se reactivan o para scripts de entrenamiento (`scripts/prepare_training_images.py`), pero `SUPPORTED_EXTENSIONS` del análisis **excluye** CAD.
