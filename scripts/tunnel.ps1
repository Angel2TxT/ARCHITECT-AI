# Expone ARCHITECT (puerto 8000) en internet sin desplegar a produccion.
# Uso: .\scripts\tunnel.ps1
# Al arrancar, copia la URL https://....trycloudflare.com y actualiza APP_BASE_URL en .env
# Luego: docker compose up -d --force-recreate backend

$ErrorActionPreference = "Stop"
Write-Host "Iniciando tunel hacia http://127.0.0.1:8000 ..."
Write-Host "Mantén esta ventana abierta. Al cerrarla, el enlace deja de funcionar."
Write-Host ""
npx --yes cloudflared tunnel --url http://127.0.0.1:8000
