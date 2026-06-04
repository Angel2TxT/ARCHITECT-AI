# Arranca ARCHITECT en modo local sin Docker.
Set-Location $PSScriptRoot

foreach ($port in 7860, 8080, 8081) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path .\.venv\Scripts\python.exe)) {
    python -m venv .venv
}

.\.venv\Scripts\pip install -r requirements.txt -q
.\.venv\Scripts\python app.py
