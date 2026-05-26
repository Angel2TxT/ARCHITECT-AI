"""
Interfaz estilo ChatGPT — NO es Gradio.

Uso:
  python app.py
"""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import webbrowser

import uvicorn

PORT = int(os.environ.get("PLANO_IA_PORT", "8080"))


def _free_port(port: int) -> None:
    if sys.platform != "win32":
        return
    try:
        out = subprocess.check_output(
            ["netstat", "-ano"],
            text=True,
            errors="ignore",
        )
        pids = set()
        for line in out.splitlines():
            if f":{port}" in line and "LISTENING" in line:
                parts = line.split()
                if parts:
                    pids.add(parts[-1])
        for pid in pids:
            subprocess.run(
                ["taskkill", "/F", "/PID", pid],
                capture_output=True,
            )
    except Exception:
        pass


def _port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


if __name__ == "__main__":
    # Cierra Gradio viejo que suele quedarse en 7860
    for old in (7860, PORT):
        _free_port(old)

    if not _port_free(PORT):
        PORT = 8081
        _free_port(PORT)

    url = f"http://127.0.0.1:{PORT}"
    print()
    print("  ========================================")
    print("  PLANO IA — interfaz tipo ChatGPT")
    print(f"  App:    {url}")
    print(f"  Login:  {url}/login")
    print("  Admin:  admin@planoia.com / admin123")
    print("  (Si /login da 404: Ctrl+C y vuelve a ejecutar python app.py)")
    print("  ========================================")
    print()

    webbrowser.open(url)
    uvicorn.run(
        "api.server:app",
        host="127.0.0.1",
        port=PORT,
        reload=True,
    )
