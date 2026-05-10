param(
    [string]$BaseUrl = "http://api-relay.internal",
    [string]$ApiKey,
    [string]$Model
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "ApiKey is required"
}
if ([string]::IsNullOrWhiteSpace($Model)) {
    throw "Model is required"
}

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type" = "application/json"
    "session_id" = "smoke-test-session"
}

$body = @{
    model = $Model
    messages = @(
        @{
            role = "user"
            content = "Reply with exactly: relay-ok"
        }
    )
    stream = $false
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/v1/chat/completions" `
    -Headers $headers `
    -Body $body `
    -TimeoutSec 120

$text = $response.choices[0].message.content
if ($text -notmatch "relay-ok") {
    throw "Unexpected response content: $text"
}

Write-Host "Smoke test passed"
