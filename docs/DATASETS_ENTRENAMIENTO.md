# Datasets abiertos para entrenar YOLO (planos reales)

No scrapees planos de arquitectos ni PDFs con copyright. Usa datasets con licencia explícita.

## ResPlan (recomendado) — CC BY 4.0

- ~17 000 plantas residenciales vectoriales (puertas, ventanas, muros, baño, cocina, escalera, parking…)
- Origen: geometrías derivadas de listados públicos (sin imágenes ni datos personales)
- Repo: https://github.com/m-agour/ResPlan  
- Zip: https://github.com/m-agour/ResPlan/releases/download/1.0.0/ResPlan.zip

```powershell
# Ya descargado en data/raw/resplan/ResPlan.pkl
python scripts/resplan_to_yolo.py --max-samples 3500 --imgsz 1024
python scripts/train.py --data config/data_resplan.yaml --model yolov8s.pt --epochs 60 --imgsz 640 --batch 4 --device cpu --name plano_resplan_s
```

Pesos: `runs/detect/plano_resplan_s/weights/best.pt` → Ajustes en la app.

Clases: `door`, `window`, `wall`, `room`, `stair`, `bathroom`, `kitchen`, `parking`.

## CubiCasa5K — investigación

- 5000 plantas anotadas (Finlandia / marketing inmobiliario)
- Ya convertido parcialmente en `datasets/cubicasa_yolo`
- Conversión: `scripts/cubicasa_to_yolo.py --input data/raw/cubicasa5k`

## Conocimiento normativo (no es YOLO)

Manuales y reglamentos → `docs/CONOCIMIENTO_DOCUMENTOS.md` (`ingest_knowledge_docs.py`).
Mejora citas y checklists; **no** sustituye etiquetas de detección.

## Planos mexicanos propios

Siguen siendo el mejor fine-tune local: etiquetar `data/training/to_label/` → mezclar con ResPlan.
