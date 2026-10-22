# Diagnóstico rápido Plano IA
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot\..

Write-Host "`n=== Verificar Plano IA ===`n" -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
    Write-Host "[!] Falta .env — copia .env.example y ajusta DATABASE_URL" -ForegroundColor Yellow
} else {
    Write-Host "[OK] .env existe"
}

Write-Host "`nMySQL puerto 3306:"
$port = netstat -ano 2>$null | Select-String ":3306"
if ($port) { Write-Host "[OK] Algo escucha en 3306" -ForegroundColor Green }
else { Write-Host "[!] Nada en 3306 — enciende MySQL (XAMPP/WAMP/servicio)" -ForegroundColor Red }

Write-Host "`nPython / tablas:"
.\.venv\Scripts\python.exe scripts\check_status.py 2>$null
.\.venv\Scripts\python.exe -c "
from pathlib import Path
import os
from dotenv import load_dotenv
load_dotenv()
try:
    from sqlalchemy import text
    from db.database import engine
    with engine.connect() as c:
        c.execute(text('SELECT 1'))
    print('[OK] Conexion MySQL')
except Exception as e:
    print('[!] MySQL:', str(e)[:100])
" 2>&1

Write-Host "`nServidor (debe mostrar /login 200 tras reiniciar app.py):"
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:8080/login" -UseBasicParsing -TimeoutSec 3
    Write-Host "[OK] http://127.0.0.1:8080/login -> $($r.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "[!] /login no responde en 8080: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Reinicia: Ctrl+C y python app.py" -ForegroundColor Yellow
}

Write-Host "`nPasos si falla login:"
Write-Host "  1. Ctrl+C en la terminal de python app.py"
Write-Host "  2. Encender MySQL"
Write-Host "  3. CREATE DATABASE plano_ia;"
Write-Host "  4. python scripts/init_db.py"
Write-Host "  5. python app.py"
Write-Host "  6. http://127.0.0.1:8080/login"
Write-Host "  7. Admin: admin@planoia.com / admin123`n"

if (Test-Path ".env") {
  .\.venv\Scripts\python.exe -c "
import urllib.request, json
from dotenv import load_dotenv
load_dotenv()
import os
email=os.getenv('ADMIN_EMAIL','admin@planoia.com')
body=json.dumps({'email':email,'password':os.getenv('ADMIN_PASSWORD','admin123')}).encode()
req=urllib.request.Request('http://127.0.0.1:8080/api/auth/login',data=body,headers={'Content-Type':'application/json'},method='POST')
try:
  r=urllib.request.urlopen(req, timeout=5)
  print('[OK] Login API funciona con', email)
except Exception as e:
  print('[!] Login API falla:', e)
" 2>&1
}
