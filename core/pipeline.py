"""
Pipeline reutilizable: detección YOLO + validación de reglas.
"""

from __future__ import annotations

import base64
from collections import Counter
from io import BytesIO
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from ultralytics import YOLO

from core.analysis_intent import (
    AnalysisIntent,
    filter_issues_by_focus,
    filter_knowledge_terms,
    parse_analysis_intent,
)
from core.auto_calibrate import AutoCalibration, calibrate_from_scout
from core.measures_report import build_measures_report
from core.verdict import build_plan_verdict
from rules import DEFAULT_RULES, ISSUE_LABELS, NORM_BUNDLE_TITLE, ValidationEngine
from rules.holistic import construction_coverage_report
from rules.remediation import enrich_issue_dict

try:
    from services.knowledge_service import find_references, references_for_issues
except ImportError:
    def references_for_issues(issues):  # type: ignore
        return []

    def find_references(codes, **kw):  # type: ignore
        return []
from rules.engine import Detection, ValidationIssue
from rules.norms import PlanRules

ROOT = Path(__file__).resolve().parents[1]

_model_cache: dict[str, YOLO] = {}


def find_default_weights() -> Path | None:
    runs = ROOT / "runs" / "detect"
    if not runs.exists():
        return None
    candidates = sorted(runs.rglob("best.pt"), key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0] if candidates else None


def _get_model(weights: str | Path) -> YOLO:
    key = str(Path(weights).resolve())
    if key not in _model_cache:
        _model_cache[key] = YOLO(key)
    return _model_cache[key]


def _load_bgr(image: str | Path | np.ndarray) -> np.ndarray:
    if isinstance(image, np.ndarray):
        if image.ndim == 2:
            return cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
        if image.shape[2] == 4:
            return cv2.cvtColor(image, cv2.COLOR_RGBA2BGR)
        return image.copy()
    path = str(image)
    bgr = cv2.imread(path)
    if bgr is None:
        raise ValueError(f"No se pudo leer la imagen: {path}")
    return bgr


def _draw_clean_overlay(
    image_bgr: np.ndarray,
    issues: list[ValidationIssue],
    *,
    max_boxes: int = 28,
) -> np.ndarray:
    """Plano limpio: solo errores numerados (sin todas las cajas YOLO)."""
    out = image_bgr.copy()
    h, w = out.shape[:2]
    errors = [i for i in issues if i.severity == "error" and i.bbox_xyxy]

    def area(issue: ValidationIssue) -> float:
        x1, y1, x2, y2 = issue.bbox_xyxy  # type: ignore[misc]
        return (x2 - x1) * (y2 - y1)

    errors.sort(key=area, reverse=True)
    drawn = errors[:max_boxes]

    for idx, issue in enumerate(drawn, start=1):
        x1, y1, x2, y2 = [int(v) for v in issue.bbox_xyxy]  # type: ignore[arg-type]
        color = (0, 0, 220)
        cv2.rectangle(out, (x1, y1), (x2, y2), color, 2)
        tag = str(idx)
        (tw, th), _ = cv2.getTextSize(tag, cv2.FONT_HERSHEY_SIMPLEX, 0.45, 1)
        ly = max(y1 - 6, th + 4)
        cv2.rectangle(out, (x1, ly - th - 4), (x1 + tw + 6, ly + 2), color, -1)
        cv2.putText(
            out, tag, (x1 + 3, ly),
            cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA,
        )

    err_n = sum(1 for i in issues if i.severity == "error")
    warn_n = sum(1 for i in issues if i.severity == "warning")
    info_n = sum(1 for i in issues if i.severity == "info")
    shown = len(drawn)
    if err_n > shown:
        note = f"Errores: {err_n} (marcados {shown})  |  Avisos: {warn_n}"
    else:
        note = f"Errores: {err_n}  |  Avisos: {warn_n}"
    if info_n:
        note += f"  |  Revisión: {info_n}"

    pad = 8
    (tw, th), _ = cv2.getTextSize(note, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
    bar_h = th + pad * 2
    cv2.rectangle(out, (0, h - bar_h), (w, h), (255, 255, 255), -1)
    cv2.putText(
        out, note, (pad, h - pad),
        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (30, 30, 30), 1, cv2.LINE_AA,
    )
    return out


def _serialize_issue(issue) -> dict:
    return enrich_issue_dict(
        {
            "code": issue.code,
            "label": ISSUE_LABELS.get(issue.code, issue.code),
            "message": issue.message,
            "severity": issue.severity,
            "class": issue.related_class,
            "norm_ref": issue.norm_ref,
        }
    )


def summarize_issues(issues: list[ValidationIssue]) -> list[dict]:
    groups: dict[str, dict] = {}
    for issue in issues:
        g = groups.get(issue.code)
        if not g:
            g = {
                "code": issue.code,
                "label": ISSUE_LABELS.get(issue.code, issue.code.replace("_", " ").title()),
                "severity": issue.severity,
                "count": 0,
                "sample_message": issue.message,
                "related_class": issue.related_class,
                "norm_ref": issue.norm_ref,
            }
            groups[issue.code] = g
        g["count"] += 1

    sev_order = {"error": 0, "warning": 1, "info": 2}

    ordered = sorted(
        groups.values(),
        key=lambda x: (sev_order.get(x["severity"], 9), -x["count"], x["code"]),
    )
    return ordered


def summarize_detections(detections: list[Detection]) -> list[dict]:
    counts = Counter(d.class_name for d in detections)
    labels = {
        "door": "Puertas",
        "window": "Ventanas",
        "wall": "Muros",
        "room": "Habitaciones",
    }
    return [
        {
            "class": cls,
            "label": labels.get(cls, cls),
            "count": n,
        }
        for cls, n in counts.most_common()
    ]


def _scale_hint(
    issues: list[ValidationIssue],
    pixels_per_meter: float,
    *,
    auto_calibrated: bool = False,
) -> str | None:
    if auto_calibrated:
        return None
    door_codes = {"DOOR_WIDTH_MIN", "DOOR_HEIGHT_MIN"}
    door_issues = [i for i in issues if i.code in door_codes]
    if len(door_issues) < 8:
        return None
    if pixels_per_meter <= 40:
        return None
    return (
        "Hay muchas incidencias de puertas con medidas en metros muy bajas. "
        "Activa calibración automática o baja «Píxeles por metro» (p. ej. 30–60)."
    )


def _detection_matches_focus(det: Detection, intent: AnalysisIntent) -> bool:
    if intent.focus == "full":
        return True
    focus_class = {
        "doors": "door",
        "windows": "window",
        "rooms": "room",
        "walls": "wall",
    }.get(intent.focus)
    if focus_class:
        return det.class_name == focus_class
    if intent.focus == "circulation":
        return det.class_name in ("room", "door")
    return True


def _scout_detect(
    model: YOLO, image, names: dict, conf: float = 0.12
) -> list[Detection]:
    results = _run_predict(model, image, conf)
    return _extract_detections(results, names)


def _is_demo_model(weights: str | Path) -> bool:
    return "demo_planos" in str(weights).replace("\\", "/").lower()


def _detections_to_storage(detections: list[Detection]) -> list[dict]:
    from services.feedback_service import detection_to_dict

    return [detection_to_dict(d, i) for i, d in enumerate(detections)]


def revalidate_analysis(
    image: str | Path,
    detections_payload: list[dict],
    *,
    pixels_per_meter: float,
    user_prompt: str = "",
    weights: str | Path | None = None,
) -> dict:
    """
    Reaplica reglas normativas sobre detecciones ya corregidas (sin volver a ejecutar YOLO).
    """
    from rules.prompt_checks import run_prompt_checks
    from services.feedback_service import dict_to_detection, normalize_stored_detections

    intent = parse_analysis_intent(user_prompt or "Revisión con tus correcciones")
    stored = normalize_stored_detections(detections_payload)
    detections = [dict_to_detection(d) for d in stored]

    rules = PlanRules(
        pixels_per_meter=pixels_per_meter,
        door=DEFAULT_RULES.door,
        window=DEFAULT_RULES.window,
        room=DEFAULT_RULES.room,
    )
    engine = ValidationEngine(rules=rules)
    issues = engine.validate(detections)
    extra_issues, custom_findings = run_prompt_checks(
        detections,
        rules,
        focus=intent.focus,
        compare_uniformity=intent.compare_uniformity,
    )
    all_issues = issues + extra_issues
    display_issues = filter_issues_by_focus(all_issues, intent)

    base_bgr = _load_bgr(image)
    bgr = _draw_clean_overlay(base_bgr, display_issues)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    buf = BytesIO()
    Image.fromarray(rgb).save(buf, format="JPEG", quality=88)
    image_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

    errors = [i for i in display_issues if i.severity == "error"]
    warnings = [i for i in display_issues if i.severity == "warning"]
    infos = [i for i in display_issues if i.severity == "info"]
    n_err, n_warn, n_info = len(errors), len(warnings), len(infos)
    status = (
        f"Detecciones (corregidas): {len(detections)} · "
        f"Errores: {n_err} · Avisos: {n_warn} · Revisión: {n_info} · "
        f"Escala: {pixels_per_meter:.0f} px/m"
    )

    issues_summary = summarize_issues(display_issues)
    detections_summary = summarize_detections(
        [d for d in detections if _detection_matches_focus(d, intent)]
    )
    construction_coverage = None
    if intent.focus == "full" and not intent.list_measures:
        construction_coverage = construction_coverage_report(display_issues)

    knowledge_refs = references_for_issues(display_issues)
    hint = _scale_hint(display_issues, pixels_per_meter, auto_calibrated=False)
    verdict = build_plan_verdict(
        errors=n_err,
        warnings=n_warn,
        detections=len(detections),
        issues_summary=issues_summary,
        custom_findings=[
            {"severity": cf.severity, "message": cf.message} for cf in custom_findings
        ],
        is_demo_model=_is_demo_model(weights) if weights else False,
        informal=False,
    )

    return {
        "status": status,
        "is_demo_model": _is_demo_model(weights) if weights else False,
        "image_base64": image_b64,
        "scale_hint": hint,
        "auto_calibration": None,
        "pixels_per_meter_used": round(pixels_per_meter, 1),
        "confidence_used": 0.0,
        "detections": _detections_to_storage(detections),
        "detections_summary": detections_summary,
        "jurisdiction": NORM_BUNDLE_TITLE,
        "verdict": verdict.to_dict(),
        "analysis_intent": {
            "focus": intent.focus,
            "title": "Revisión con tus correcciones",
            "compare_uniformity": intent.compare_uniformity,
            "conversational": False,
            "list_measures": False,
            "prompt": intent.raw_prompt,
        },
        "measures_report": None,
        "custom_findings": [
            {
                "code": f.code,
                "message": f.message,
                "severity": f.severity,
                "detail": f.detail,
            }
            for f in custom_findings
        ],
        "issues": [_serialize_issue(i) for i in display_issues],
        "issues_summary": issues_summary,
        "construction_coverage": construction_coverage,
        "knowledge_references": knowledge_refs,
        "counts": {
            "detections": len(detections),
            "errors": n_err,
            "warnings": n_warn,
            "info": n_info,
        },
        "corrections_applied": True,
    }


def _run_predict(model: YOLO, image, conf: float):
    return model.predict(source=image, conf=conf, imgsz=640, verbose=False)


def _extract_detections(results, names: dict) -> list[Detection]:
    detections: list[Detection] = []
    for r in results:
        if r.boxes is None:
            continue
        for box in r.boxes:
            cls_id = int(box.cls[0])
            detections.append(
                Detection(
                    class_name=names[cls_id],
                    bbox_xyxy=tuple(box.xyxy[0].tolist()),
                    confidence=float(box.conf[0]),
                )
            )
    return detections


def analyze_plano(
    image: str | Path | np.ndarray,
    weights: str | Path,
    pixels_per_meter: float = 100.0,
    conf: float = 0.05,
    *,
    auto_calibrate: bool = True,
    manual_ppm: float | None = None,
    manual_conf: float | None = None,
) -> tuple[np.ndarray, list[Detection], list[ValidationIssue], str, AutoCalibration | None]:
    """
    Devuelve: imagen RGB, detecciones, incidencias, status, calibración (si auto).
    """
    model = _get_model(weights)
    names = model.names
    base_bgr = _load_bgr(image)
    h, w = base_bgr.shape[:2]

    calibration: AutoCalibration | None = None
    used_conf = conf
    used_ppm = pixels_per_meter

    if auto_calibrate:
        scout = _scout_detect(model, image, names, conf=0.12)
        calibration = calibrate_from_scout(
            scout,
            w,
            h,
            is_demo=_is_demo_model(weights),
            manual_ppm=manual_ppm if manual_ppm and manual_ppm > 0 else None,
            manual_conf=manual_conf if manual_conf and manual_conf > 0 else None,
        )
        used_ppm = calibration.pixels_per_meter
        used_conf = calibration.confidence

    results = _run_predict(model, image, used_conf)
    detections = _extract_detections(results, names)

    if not detections and used_conf > 0.03:
        for retry_conf in (0.10, 0.06, 0.03):
            if retry_conf >= used_conf:
                continue
            results = _run_predict(model, image, retry_conf)
            detections = _extract_detections(results, names)
            used_conf = retry_conf
            if detections:
                if calibration:
                    calibration.confidence = retry_conf
                    calibration.conf_note = "reintento por pocas detecciones"
                break

    rules = PlanRules(
        pixels_per_meter=used_ppm,
        door=DEFAULT_RULES.door,
        window=DEFAULT_RULES.window,
        room=DEFAULT_RULES.room,
    )
    engine = ValidationEngine(rules=rules)
    issues = engine.validate(detections)

    bgr = _draw_clean_overlay(base_bgr, issues)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

    auto_tag = " (automática)" if calibration else ""
    n_err = sum(1 for i in issues if i.severity == "error")
    n_warn = sum(1 for i in issues if i.severity == "warning")
    n_info = sum(1 for i in issues if i.severity == "info")
    status = (
        f"Detecciones: {len(detections)} · "
        f"Errores: {n_err} · Avisos: {n_warn} · Revisión: {n_info} · "
        f"Escala: {used_ppm:.0f} px/m · Confianza: {used_conf:.2f}{auto_tag}"
    )
    return rgb, detections, issues, status, calibration


def format_detections_table(detections: list[Detection]) -> str:
    if not detections:
        return "_Sin detecciones. ¿Cargaste el modelo entrenado (`best.pt`)?_"

    lines = [
        "| Elemento | Confianza | Ancho px | Alto px |",
        "|----------|-----------|----------|---------|",
    ]
    for d in sorted(detections, key=lambda x: -x.confidence):
        lines.append(
            f"| {d.class_name} | {d.confidence:.0%} | "
            f"{d.width_px:.0f} | {d.height_px:.0f} |"
        )
    return "\n".join(lines)


def format_issues_table(issues: list[ValidationIssue]) -> str:
    if not issues:
        return "_✅ No se encontraron incidencias con las reglas actuales._"

    lines = [
        "| Tipo | Regla | Cantidad | Ejemplo |",
        "|------|-------|----------|---------|",
    ]
    for g in summarize_issues(issues):
        tipo = "🔴 Error" if g["severity"] == "error" else "🟠 Aviso"
        lines.append(
            f"| {tipo} | {g['label']} | {g['count']}× | {g['sample_message']} |"
        )
    return "\n".join(lines)


def analyze_plano_json(
    image: str | Path | np.ndarray,
    weights: str | Path,
    pixels_per_meter: float = 0.0,
    conf: float = 0.0,
    *,
    auto_calibrate: bool = True,
    user_prompt: str = "",
) -> dict:
    """Respuesta estructurada para la API / interfaz chat."""
    from rules.prompt_checks import run_prompt_checks

    intent = parse_analysis_intent(user_prompt)
    manual_ppm = pixels_per_meter if pixels_per_meter > 0 else None
    manual_conf = conf if conf > 0 else None
    use_auto = auto_calibrate and not (manual_ppm and manual_conf)

    rgb, detections, issues, status, calibration = analyze_plano(
        image,
        weights,
        pixels_per_meter=manual_ppm or 100.0,
        conf=manual_conf or 0.18,
        auto_calibrate=use_auto,
        manual_ppm=manual_ppm,
        manual_conf=manual_conf,
    )
    used_ppm = calibration.pixels_per_meter if calibration else (manual_ppm or 100.0)
    used_conf = calibration.confidence if calibration else (manual_conf or 0.18)

    rules = PlanRules(
        pixels_per_meter=used_ppm,
        door=DEFAULT_RULES.door,
        window=DEFAULT_RULES.window,
        room=DEFAULT_RULES.room,
    )
    extra_issues, custom_findings = run_prompt_checks(
        detections,
        rules,
        focus=intent.focus,
        compare_uniformity=intent.compare_uniformity,
    )
    all_issues = issues + extra_issues
    display_issues = filter_issues_by_focus(all_issues, intent)

    base_bgr = _load_bgr(image)
    bgr = _draw_clean_overlay(base_bgr, display_issues)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

    buf = BytesIO()
    Image.fromarray(rgb).save(buf, format="JPEG", quality=88)
    image_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

    errors = [i for i in display_issues if i.severity == "error"]
    warnings = [i for i in display_issues if i.severity == "warning"]
    infos = [i for i in display_issues if i.severity == "info"]
    issues_summary = summarize_issues(display_issues)
    detections_summary = summarize_detections(
        [d for d in detections if _detection_matches_focus(d, intent)]
    )
    # Solo en revisión integral; en consultas focalizadas (medidas, puertas, etc.) no saturar la UI
    construction_coverage = None
    if intent.focus == "full" and not intent.list_measures:
        construction_coverage = construction_coverage_report(display_issues)
    measures_report = None
    if intent.list_measures:
        knowledge_refs = []
        measures_report = build_measures_report(
            detections,
            used_ppm,
            auto_calibrated=bool(calibration),
        )
    elif intent.is_focused:
        codes = list({i.code for i in display_issues})
        extra_terms = filter_knowledge_terms(intent)
        knowledge_refs = find_references(
            codes,
            max_refs=4,
            extra_terms=extra_terms,
        )
    else:
        knowledge_refs = references_for_issues(display_issues)
    hint = _scale_hint(display_issues, used_ppm, auto_calibrated=bool(calibration))

    verdict = build_plan_verdict(
        errors=len(errors),
        warnings=len(warnings),
        detections=len(detections),
        issues_summary=issues_summary,
        custom_findings=[
            {"severity": cf.severity, "message": cf.message} for cf in custom_findings
        ],
        is_demo_model=_is_demo_model(weights),
        informal=intent.conversational and not intent.list_measures,
    )

    auto_block = None
    if calibration:
        auto_block = {
            "pixels_per_meter": round(calibration.pixels_per_meter, 1),
            "confidence": round(calibration.confidence, 3),
            "ppm_note": calibration.ppm_note,
            "conf_note": calibration.conf_note,
            "summary": calibration.summary,
        }

    return {
        "status": status,
        "is_demo_model": _is_demo_model(weights),
        "image_base64": image_b64,
        "scale_hint": hint,
        "auto_calibration": auto_block,
        "pixels_per_meter_used": round(used_ppm, 1),
        "confidence_used": round(used_conf, 3),
        "detections": _detections_to_storage(detections),
        "detections_summary": detections_summary,
        "jurisdiction": NORM_BUNDLE_TITLE,
        "verdict": verdict.to_dict(),
        "analysis_intent": {
            "focus": intent.focus,
            "title": intent.title,
            "compare_uniformity": intent.compare_uniformity,
            "conversational": intent.conversational,
            "list_measures": intent.list_measures,
            "prompt": intent.raw_prompt,
        },
        "measures_report": measures_report,
        "custom_findings": [
            {
                "code": f.code,
                "message": f.message,
                "severity": f.severity,
                "detail": f.detail,
            }
            for f in custom_findings
        ],
        "issues": [_serialize_issue(i) for i in display_issues],
        "issues_summary": issues_summary,
        "construction_coverage": construction_coverage,
        "knowledge_references": knowledge_refs,
        "counts": {
            "detections": len(detections),
            "errors": len(errors),
            "warnings": len(warnings),
            "info": len(infos),
        },
        "markdown": {
            "detections": format_detections_table(detections),
            "issues": format_issues_table(issues),
        },
    }
