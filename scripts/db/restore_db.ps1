# Restaura scripts/db/architect.sql en el MySQL de Docker.
# ATENCIÓN: sobrescribe la base 'architect'.
# Uso (desde la raíz del repo): .\scripts\db\restore_db.ps1
$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repoRoot

$sql = Join-Path $PSScriptRoot "architect.sql"
if (-not (Test-Path $sql)) {
  throw "No existe $sql — genera uno con .\scripts\db\dump_db.ps1"
}

Write-Host "Restaurando $sql en architect-mysql..."
docker cp $sql "architect-mysql:/tmp/architect_restore.sql"
docker exec -i architect-mysql mysql -uarchitect -parchitect_pass --default-character-set=utf8mb4 -e "SOURCE /tmp/architect_restore.sql"
docker exec architect-mysql rm -f /tmp/architect_restore.sql
Write-Host "Restauración completa."
