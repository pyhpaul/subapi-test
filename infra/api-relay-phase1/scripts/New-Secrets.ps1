param(
    [string]$ExamplePath = ".env.example",
    [string]$OutputPath = ".env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-HexSecret {
    param([int]$Bytes = 32)
    $buffer = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
    return ($buffer | ForEach-Object { $_.ToString("x2") }) -join ""
}

function New-Password {
    return New-HexSecret -Bytes 24
}

if (-not (Test-Path -LiteralPath $ExamplePath)) {
    throw "Example env file not found: $ExamplePath"
}

if (Test-Path -LiteralPath $OutputPath) {
    throw "Refusing to overwrite existing env file: $OutputPath"
}

$content = Get-Content -LiteralPath $ExamplePath -Raw
$replacements = @{
    "POSTGRES_ADMIN_PASSWORD=generated_by_scripts_New-Secrets_ps1" = "POSTGRES_ADMIN_PASSWORD=$(New-Password)"
    "NEWAPI_DB_PASSWORD=generated_by_scripts_New-Secrets_ps1" = "NEWAPI_DB_PASSWORD=$(New-Password)"
    "SUB2API_DB_PASSWORD=generated_by_scripts_New-Secrets_ps1" = "SUB2API_DB_PASSWORD=$(New-Password)"
    "REDIS_PASSWORD=generated_by_scripts_New-Secrets_ps1" = "REDIS_PASSWORD=$(New-Password)"
    "NEWAPI_SESSION_SECRET=generated_by_scripts_New-Secrets_ps1" = "NEWAPI_SESSION_SECRET=$(New-HexSecret -Bytes 32)"
    "NEWAPI_CRYPTO_SECRET=generated_by_scripts_New-Secrets_ps1" = "NEWAPI_CRYPTO_SECRET=$(New-HexSecret -Bytes 32)"
    "SUB2API_ADMIN_PASSWORD=generated_by_scripts_New-Secrets_ps1" = "SUB2API_ADMIN_PASSWORD=$(New-Password)"
    "SUB2API_JWT_SECRET=generated_by_scripts_New-Secrets_ps1" = "SUB2API_JWT_SECRET=$(New-HexSecret -Bytes 32)"
    "SUB2API_TOTP_ENCRYPTION_KEY=generated_by_scripts_New-Secrets_ps1" = "SUB2API_TOTP_ENCRYPTION_KEY=$(New-HexSecret -Bytes 32)"
}

foreach ($key in $replacements.Keys) {
    $content = $content.Replace($key, $replacements[$key])
}

Set-Content -LiteralPath $OutputPath -Value $content -NoNewline -Encoding UTF8
Write-Host "Wrote $OutputPath"
Write-Host "Store this file securely. It contains production secrets."
