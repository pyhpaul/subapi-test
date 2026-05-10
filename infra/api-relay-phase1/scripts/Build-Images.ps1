param(
    [string]$NewApiSource = "..\..\.research\new-api",
    [string]$Sub2ApiSource = "..\..\.research\sub2api",
    [string]$NewApiImage = "api-relay/new-api:543cc64",
    [string]$Sub2ApiImage = "api-relay/sub2api:dbc8ae",
    [string]$WorkDir = ".\.build-context"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-GitCommit {
    param(
        [string]$Path,
        [string]$Expected
    )
    $actual = (git -C $Path rev-parse HEAD).Trim()
    if ($actual -ne $Expected) {
        throw "Unexpected commit in $Path. Expected $Expected, got $actual"
    }
}

Assert-GitCommit -Path $NewApiSource -Expected "543cc64ea3805a3f2291b86525ad83771cb61423"
Assert-GitCommit -Path $Sub2ApiSource -Expected "dbc8ae658cfc1c012160752582925e45115e2f3a"

function Copy-BuildContext {
    param(
        [string]$Source,
        [string]$Target
    )
    if (Test-Path -LiteralPath $Target) {
        Remove-Item -LiteralPath $Target -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Target -Recurse -Force
}

function Add-NewApiDockerignoreFix {
    param([string]$Context)
    Add-Content -LiteralPath (Join-Path $Context ".dockerignore") -Value @"

# Build fix: Dockerfile copies these markdown license files.
!LICENSE
!NOTICE
!THIRD-PARTY-LICENSES.md
"@
}

function Add-Sub2ApiPnpmFix {
    param([string]$Context)
    $dockerfile = Join-Path $Context "Dockerfile"
    $content = Get-Content -LiteralPath $dockerfile -Raw
    $content = $content.Replace(
        "RUN corepack enable && corepack prepare pnpm@latest --activate",
        "RUN corepack enable && corepack prepare pnpm@9.15.9 --activate"
    )
    Set-Content -LiteralPath $dockerfile -Value $content -NoNewline -Encoding UTF8
}

$newApiContext = Join-Path $WorkDir "new-api"
$sub2ApiContext = Join-Path $WorkDir "sub2api"
Copy-BuildContext -Source $NewApiSource -Target $newApiContext
Copy-BuildContext -Source $Sub2ApiSource -Target $sub2ApiContext
Add-NewApiDockerignoreFix -Context $newApiContext
Add-Sub2ApiPnpmFix -Context $sub2ApiContext

docker build -t $NewApiImage $newApiContext
docker build -t $Sub2ApiImage $sub2ApiContext

Write-Host "Built $NewApiImage"
Write-Host "Built $Sub2ApiImage"
