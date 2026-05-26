# CAD integrado: DWG sin .exe — usa el mismo Python que app.py (.venv si existe)
Set-Location $PSScriptRoot\..

$python = "python"
if (Test-Path ".\.venv\Scripts\python.exe") {
    $python = ".\.venv\Scripts\python.exe"
    Write-Host "Usando entorno virtual: .venv" -ForegroundColor Cyan
} else {
    Write-Host "Usando Python del sistema (sin .venv)" -ForegroundColor Yellow
}

Write-Host "Instalando planos: ezdwg, ezdxf, matplotlib, pymupdf..." -ForegroundColor Cyan
& $python -m pip install "ezdwg[dxf,plot]>=0.9.0" "ezdxf>=1.4" "matplotlib>=3.8" "pymupdf>=1.24"

Write-Host ""
Write-Host "Python:" -ForegroundColor Cyan
& $python -c "import sys; print(sys.executable)"

Write-Host ""
Write-Host "Estado CAD:" -ForegroundColor Cyan
& $python -c "from services.cad_service import cad_support_status; import json; print(json.dumps(cad_support_status(), indent=2, ensure_ascii=False))"

Write-Host ""
Write-Host "Reinicia el servidor con el MISMO entorno:" -ForegroundColor Green
if (Test-Path ".\.venv\Scripts\Activate.ps1") {
    Write-Host "  .\.venv\Scripts\Activate.ps1" -ForegroundColor White
}
Write-Host "  python app.py" -ForegroundColor White
