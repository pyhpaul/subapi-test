param(
    [string]$NewApiSource = "..\..\.research\new-api",
    [string]$Sub2ApiSource = "..\..\.research\sub2api",
    [string]$NewApiImage = "api-relay/new-api:543cc64",
    [string]$Sub2ApiImage = "api-relay/sub2api:dbc8ae"
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

docker build -t $NewApiImage $NewApiSource
docker build -t $Sub2ApiImage $Sub2ApiSource

Write-Host "Built $NewApiImage"
Write-Host "Built $Sub2ApiImage"
