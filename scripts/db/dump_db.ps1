# Genera un dump SQL de la base actual (contenedor architect-mysql).
# Uso (desde la raíz del repo): .\scripts\db\dump_db.ps1
# Por defecto aplica trim (solo plans/users/subscriptions). Usa -Full para todo.
param(
  [switch]$Full
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repoRoot

$out = Join-Path $PSScriptRoot "architect_current.sql"
$tmp = "/tmp/architect_current.sql"

Write-Host "Exportando base 'architect'..."
docker exec architect-mysql sh -c "mysqldump -uarchitect -parchitect_pass --databases architect --routines --triggers --single-transaction --default-character-set=utf8mb4 --set-gtid-purged=OFF > $tmp 2>/dev/null"
docker cp "architect-mysql:$tmp" $out
docker exec architect-mysql rm -f $tmp

if (-not $Full) {
  $py = Join-Path $repoRoot ".venv\Scripts\python.exe"
  if (-not (Test-Path $py)) { $py = "python" }
  & $py (Join-Path $PSScriptRoot "trim_dump.py")
}

$size = (Get-Item $out).Length
Write-Host "Listo: $out ($size bytes)"
