"""
Detector visual multimodal de planos arquitectónicos impulsado por Gemini Vision.
Reemplaza la ceguera de YOLO permitiendo:
1. Validar si la imagen es realmente un plano arquitectónico o un documento/tarea.
2. Leer textos y etiquetas reales de los espacios (Dormitorio, Cocina, Baño, etc.).
3. Identificar recintos, puertas y ventanas con coordenadas espaciales.
"""

from __future__ import annotations
import base64
import json
import os
import urllib.request
import urllib.error
from typing import NamedTuple, Any
import cv2
import numpy as np

from rules.types import Detection


class GeminiVisionResult(NamedTuple):
    success: bool
    is_floor_plan: bool
    rejection_reason: str = ""
    summary: str = ""
    detections: list[Detection] = []
    raw_response: dict | None = None
    error: str = ""


GEMINI_PLAN_PROMPT = """Eres un arquitecto inspector profesional.
Tu tarea es analizar la imagen proporcionada:

PASO 1: CLASIFICACIÓN DE DOCUMENTO
Determina si la imagen es REALMENTE un plano arquitectónico en planta (distribución de espacios, muros, puertas, ventanas).
Si la imagen es una tarea escolar, una tabla de calificaciones/actividades, un documento de texto, un currículum o una foto común:
Responde con is_floor_plan: false y una breve explicación en rejection_reason.

PASO 2: DETECCIÓN ARQUITECTÓNICA (Solo si is_floor_plan es true)
Si es un plano arquitectónico:
1. Identifica TODOS los recintos y habitaciones. Lee los letreros de texto si existen (ej. "DORMITORIO", "BAÑO", "COCINA", "SALA").
2. Proporciona su caja envolvente [ymin, xmin, ymax, xmax] normalizada en el rango 0 a 1000.
3. Identifica puertas y ventanas exteriores visibles.
4. Ignora las cotas exteriores (líneas de medidas como 5.00m, 7.00m); no las clasifiques como recintos.

Responde ÚNICAMENTE con un objeto JSON válido con la siguiente estructura:
{
  "is_floor_plan": true o false,
  "rejection_reason": "Motivo si no es un plano",
  "plan_description": "Breve descripción arquitectónica",
  "rooms": [
    {
      "name": "Dormitorio 1",
      "class_name": "room",
      "box_2d": [ymin, xmin, ymax, xmax]
    },
    {
      "name": "Baño",
      "class_name": "bathroom",
      "box_2d": [ymin, xmin, ymax, xmax]
    }
  ],
  "doors": [
    {
      "class_name": "door",
      "box_2d": [ymin, xmin, ymax, xmax]
    }
  ],
  "windows": [
    {
      "class_name": "window",
      "box_2d": [ymin, xmin, ymax, xmax]
    }
  ]
}
"""


from pathlib import Path


def _get_api_key() -> str:
    key = (
        os.environ.get("GEMINI_API_KEY")
        or os.environ.get("GOOGLE_API_KEY")
        or os.environ.get("LLM_API_KEY")
        or ""
    ).strip()
    if not key:
        try:
            from dotenv import dotenv_values
            env_file = Path(__file__).resolve().parents[1] / ".env"
            if env_file.exists():
                vals = dotenv_values(str(env_file))
                key = (vals.get("GEMINI_API_KEY") or vals.get("LLM_API_KEY") or "").strip()
        except Exception:
            pass
    return key


def is_gemini_vision_available() -> bool:
    key = _get_api_key()
    return bool(key and len(key) >= 20)


def analyze_floorplan_with_gemini_vision(
    image_bgr: np.ndarray,
    *,
    api_key: str | None = None,
    model: str = "gemini-3.5-flash",
) -> GeminiVisionResult:
    """
    Envía la imagen del plano a Gemini Vision para inspección semántica y detección espacial.
    """
    key = (api_key or _get_api_key()).strip()
    if not key or len(key) < 20:
        return GeminiVisionResult(
            success=False,
            is_floor_plan=True,
            error="No se encontró API Key válida de Gemini.",
        )

    # Convertir imagen BGR a JPEG Base64
    success, buffer = cv2.imencode(".jpg", image_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not success:
        return GeminiVisionResult(
            success=False,
            is_floor_plan=True,
            error="No se pudo codificar la imagen en JPEG.",
        )

    b64_image = base64.b64encode(buffer).decode("utf-8")
    img_h, img_w = image_bgr.shape[:2]

    models_to_try = [model, "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.6-flash"]
    seen_models: list[str] = []
    for m in models_to_try:
        if m and m not in seen_models:
            seen_models.append(m)

    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": GEMINI_PLAN_PROMPT},
                    {
                        "inlineData": {
                            "mimeType": "image/jpeg",
                            "data": b64_image,
                        }
                    },
                ],
            }
        ],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
        },
    }

    last_err = ""
    data = None
    for target_model in seen_models:
        url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"{target_model}:generateContent?key={key}"
        )
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=40.0) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            if data and data.get("candidates"):
                break
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            last_err = f"Error Gemini {target_model} ({exc.code}): {err_body[:200]}"
            if exc.code in (401, 403):
                # Error de autenticación, no seguir reintentando modelos
                return GeminiVisionResult(
                    success=False,
                    is_floor_plan=True,
                    error=last_err,
                )
            continue
        except Exception as exc:
            last_err = f"Fallo de conexión con Gemini ({target_model}): {exc}"
            continue

    if not data or not data.get("candidates"):
        return GeminiVisionResult(
            success=False,
            is_floor_plan=True,
            error=last_err or "Gemini no devolvió candidatos de respuesta.",
        )

    candidates = data.get("candidates") or []
    parts = ((candidates[0].get("content") or {}).get("parts")) or []
    text_resp = "".join(p.get("text", "") for p in parts if isinstance(p, dict)).strip()

    try:
        parsed = json.loads(text_resp)
    except Exception as exc:
        return GeminiVisionResult(
            success=False,
            is_floor_plan=True,
            error=f"No se pudo parsear el JSON de Gemini: {exc}",
        )

    # Verificar si es un plano
    is_floor = bool(parsed.get("is_floor_plan", True))
    rejection = str(parsed.get("rejection_reason") or "").strip()
    if not is_floor:
        return GeminiVisionResult(
            success=True,
            is_floor_plan=False,
            rejection_reason=rejection or "El archivo no contiene un plano arquitectónico en planta.",
            raw_response=parsed,
        )

    # Mapear recintos, puertas y ventanas a Detection objects
    detections: list[Detection] = []

    def _add_boxes(items: list[dict], default_cls: str):
        for it in items or []:
            box = it.get("box_2d") or it.get("bbox") or []
            if len(box) != 4:
                continue
            ymin, xmin, ymax, xmax = box
            # Convertir de escala normalizada 0..1000 a píxeles
            px_x1 = float(xmin * img_w / 1000.0)
            px_y1 = float(ymin * img_h / 1000.0)
            px_x2 = float(xmax * img_w / 1000.0)
            px_y2 = float(ymax * img_h / 1000.0)

            cls_name = it.get("class_name") or default_cls
            det = Detection(
                class_name=cls_name,
                bbox_xyxy=(px_x1, px_y1, px_x2, px_y2),
                confidence=0.95,
            )
            detections.append(det)

    _add_boxes(parsed.get("rooms", []), "room")
    _add_boxes(parsed.get("doors", []), "door")
    _add_boxes(parsed.get("windows", []), "window")

    summary_text = str(parsed.get("plan_description") or "Plano analizado mediante Gemini Vision.")
    return GeminiVisionResult(
        success=True,
        is_floor_plan=True,
        summary=summary_text,
        detections=detections,
        raw_response=parsed,
    )
