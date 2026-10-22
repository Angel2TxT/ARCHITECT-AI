# Arranca ARCHITECT (Backend + Web) en modo local
Set-Location $PSScriptRoot

$port = 8000
$conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    Write-Host "Liberando puerto $port (PID $($c.OwningProcess))..." -ForegroundColor Yellow
    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path .\.venv\Scripts\python.exe)) {
    Write-Host "Creando entorno virtual .venv..." -ForegroundColor Cyan
    python -m venv .venv
    Write-Host "Instalando dependencias desde requirements.txt..." -ForegroundColor Cyan
    & .\.venv\Scripts\pip.exe install -r requirements.txt
}

if (-not (Test-Path .env)) {
    Write-Host "Creando archivo .env a partir de .env.example..." -ForegroundColor Yellow
    Copy-Item .env.example .env
}

if (-not (Test-Path backend\.env)) {
    Write-Host "Creando archivo backend\.env a partir de .env.example..." -ForegroundColor Yellow
    Copy-Item .env.example backend\.env
}

Write-Host "Iniciando servidor ARCHITECT en http://localhost:$port ..." -ForegroundColor Green
Set-Location "$PSScriptRoot\backend"
& "$PSScriptRoot\.venv\Scripts\python.exe" -m uvicorn api.server:app --host 0.0.0.0 --port $port --reload
