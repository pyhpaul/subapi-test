param(
    [string]$Root = ".",
    [string]$OutputPath = "manifest.sha256"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$files = Get-ChildItem -LiteralPath $Root -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '\\\.env$' -and
        $_.FullName -notmatch '\\manifest\.sha256$'
    } |
    Sort-Object FullName

$lines = foreach ($file in $files) {
    $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
    $relative = Resolve-Path -LiteralPath $file.FullName -Relative
    "$($hash.Hash.ToLowerInvariant())  $relative"
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
Write-Host "Wrote $OutputPath"
