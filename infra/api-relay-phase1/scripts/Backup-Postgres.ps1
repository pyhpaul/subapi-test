param(
    [string]$OutputDir = ".\backups"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$newApiBackup = Join-Path $OutputDir "newapi-$timestamp.dump"
$sub2apiBackup = Join-Path $OutputDir "sub2api-$timestamp.dump"

docker compose exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -Fc "$NEWAPI_DB_NAME"' > $newApiBackup
docker compose exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -Fc "$SUB2API_DB_NAME"' > $sub2apiBackup

Write-Host "Wrote $newApiBackup"
Write-Host "Wrote $sub2apiBackup"
