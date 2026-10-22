"""
LLM opcional para razonar sobre el contexto RAG de ARCHITECT.

Providers: off | openai | gemini | ollama
Si falla o está en off, qa_service cae al compositor local.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

SYSTEM_PROMPT = """Eres el asistente técnico de ARCHITECT (arquitectura y construcción, enfoque Chiapas/México).

Reglas:
1. Responde SOLO a la pregunta del usuario. Nada de relleno ni listados de biblioteca.
2. Razona en silencio; en la respuesta entrega: conclusión clara + 2 a 5 puntos de apoyo.
3. Usa el contexto (manuales, umbrales, web) cuando sea pertinente. Si no alcanza, dilo y no inventes cifras ni normas.
4. Si preguntan qué puedes hacer / si respondes cualquier cosa: explica en 2–4 frases tu alcance
   (arquitectura, normativa, obra, planos adjuntos). No cites fragmentos de manuales.
5. Español claro y directo. Sin disclaimers repetidos ni “adjunta el plano” salvo que la pregunta lo pida.
6. Si el contexto trae medidas/umbrales útiles, cítalos con valor y fuente breve.
7. Formato: un párrafo corto de conclusión; luego viñetas con guion (- ) o números (1. ); sin bloques enormes.
"""

# Modelos Gemini con cuota free más usable; 2.0-flash a menudo viene con limit: 0.
_GEMINI_FALLBACKS = (
    "gemini-flash-latest",
    "gemini-flash-lite-latest",
    "gemini-3.1-flash-lite",
    "gemini-2.0-flash-lite",
)

_last_error: str | None = None


def llm_provider() -> str:
    return (os.getenv("LLM_PROVIDER") or "off").strip().lower()


def llm_configured() -> bool:
    provider = llm_provider()
    if provider in ("", "off", "none", "false", "0"):
        return False
    if provider == "ollama":
        return True
    if provider in ("openai", "gemini"):
        return bool((os.getenv("LLM_API_KEY") or "").strip())
    return False


def llm_status() -> dict[str, Any]:
    provider = llm_provider()
    out: dict[str, Any] = {
        "llm_provider": provider if llm_configured() else "off",
        "llm_configured": llm_configured(),
        "llm_model": (os.getenv("LLM_MODEL") or "").strip() or _default_model(provider),
    }
    if _last_error:
        out["llm_last_error"] = _last_error
    return out


def _default_model(provider: str) -> str:
    if provider == "openai":
        return "gpt-4o-mini"
    if provider == "gemini":
        return "gemini-flash-latest"
    if provider == "ollama":
        return "llama3.2"
    return ""


def _http_json(
    url: str,
    *,
    method: str = "POST",
    headers: dict[str, str] | None = None,
    body: dict | None = None,
    timeout: float = 60.0,
) -> dict:
    data = None
    req_headers = {"Content-Type": "application/json", **(headers or {})}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            pass
        raise urllib.error.HTTPError(
            exc.url, exc.code, f"{exc.reason}: {detail}" if detail else exc.reason,
            exc.headers, None,
        ) from None


def _call_openai(user_content: str, *, model: str, api_key: str, system_prompt: str) -> str:
    payload = {
        "model": model,
        "temperature": 0.3,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ],
    }
    data = _http_json(
        "https://api.openai.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        body=payload,
    )
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("OpenAI no devolvió choices")
    msg = (choices[0].get("message") or {}).get("content") or ""
    return str(msg).strip()


def _call_gemini(user_content: str, *, model: str, api_key: str, system_prompt: str) -> str:
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )
    payload = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": [
            {
                "role": "user",
                "parts": [{"text": user_content}],
            }
        ],
        "generationConfig": {"temperature": 0.3},
    }
    data = _http_json(url, body=payload)
    candidates = data.get("candidates") or []
    if not candidates:
        raise RuntimeError("Gemini no devolvió candidates")
    parts = ((candidates[0].get("content") or {}).get("parts")) or []
    texts = [p.get("text", "") for p in parts if isinstance(p, dict)]
    return "\n".join(t for t in texts if t).strip()


def _call_ollama(user_content: str, *, model: str, base_url: str, system_prompt: str) -> str:
    base = base_url.rstrip("/")
    payload = {
        "model": model,
        "stream": False,
        "options": {"temperature": 0.3},
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ],
    }
    data = _http_json(f"{base}/api/chat", body=payload, timeout=120.0)
    msg = (data.get("message") or {}).get("content") or data.get("response") or ""
    return str(msg).strip()


def _gemini_models_to_try(preferred: str) -> list[str]:
    ordered: list[str] = []
    for m in (preferred, *_GEMINI_FALLBACKS):
        if m and m not in ordered:
            ordered.append(m)
    return ordered


def generate_reasoned_answer(
    context_block: str,
    *,
    system_prompt: str | None = None,
    user_instruction: str | None = None,
) -> str | None:
    """
    Genera respuesta razonada. Devuelve None si el provider está off o falla.
    """
    global _last_error
    _last_error = None

    if not llm_configured():
        return None

    provider = llm_provider()
    model = (os.getenv("LLM_MODEL") or "").strip() or _default_model(provider)
    api_key = (os.getenv("LLM_API_KEY") or "").strip()
    ollama_base = (os.getenv("OLLAMA_BASE_URL") or "http://127.0.0.1:11434").strip()
    sys_prompt = (system_prompt or SYSTEM_PROMPT).strip()
    instruction = (
        user_instruction
        or "Redacta la respuesta final para el usuario."
    ).strip()

    user_content = (
        f"{context_block.strip()}\n\n{instruction}"
        if context_block.strip()
        else instruction
    )

    try:
        if provider == "openai":
            text = _call_openai(
                user_content, model=model, api_key=api_key, system_prompt=sys_prompt
            )
        elif provider == "gemini":
            text = None
            last_exc: Exception | None = None
            for candidate in _gemini_models_to_try(model):
                try:
                    text = _call_gemini(
                        user_content,
                        model=candidate,
                        api_key=api_key,
                        system_prompt=sys_prompt,
                    )
                    if text:
                        if candidate != model:
                            print(f"[llm_service] Gemini usó fallback {candidate}")
                        break
                except Exception as exc:
                    last_exc = exc
                    print(f"[llm_service] gemini/{candidate} falló: {exc}")
                    continue
            if not text:
                raise last_exc or RuntimeError("Gemini sin respuesta")
        elif provider == "ollama":
            text = _call_ollama(
                user_content,
                model=model,
                base_url=ollama_base,
                system_prompt=sys_prompt,
            )
        else:
            return None
        return text or None
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError, ValueError, KeyError, RuntimeError) as exc:
        _last_error = str(exc)[:240]
        print(f"[llm_service] {provider} falló: {exc}")
        return None
    except Exception as exc:  # pragma: no cover
        _last_error = str(exc)[:240]
        print(f"[llm_service] error inesperado: {exc}")
        return None
