# API Relay Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-node, production-oriented API relay stack using New API as the employee-facing billing gateway and Sub2API as the upstream coding-plan/API-key pool.

**Architecture:** The stack runs Nginx, New API, Sub2API, Postgres, and Redis on one server. New API owns employee users, personal API tokens, balance/free quota, model allowlists, and employee-side usage logs. Sub2API owns upstream accounts, sticky routing, Redis concurrency slots, wait queues, and upstream cooldown/recovery.

**Tech Stack:** Docker Compose, Nginx, Postgres, Redis, New API, Sub2API, PowerShell runbooks, curl-based smoke tests.

---

## Scope and assumptions

- This plan creates deployable configuration and runbooks under `infra/api-relay-phase1/`.
- The first deployment uses one node and one Docker Compose project.
- Postgres and Redis are shared by New API and Sub2API, but each service uses its own database/schema namespace and Redis DB.
- The default internal hostname used in generated examples is `api-relay.internal`.
- New API and Sub2API admin UIs are exposed through localhost-bound service ports, not public Nginx subpaths. Use SSH tunnels for remote administration.
- The public Nginx virtual host exposes API relay endpoints only. Employee self-service web access is intentionally deferred because New API does not cleanly split user and admin UI surfaces at the reverse-proxy path level.
- Sub2API `AUTO_SETUP` must be allowed to write `/app/data/config.yaml` and `/app/data/.installed` on first boot. Do not bind-mount a read-only `config.yaml` over `/app/data/config.yaml` during bootstrap.
- New API source commit already analyzed: `543cc64ea3805a3f2291b86525ad83771cb61423`.
- Sub2API source commit already analyzed: `dbc8ae658cfc1c012160752582925e45115e2f3a`.
- The current workspace is not a git repository. If execution happens in a git repository later, commit after each task. In this workspace, write a SHA256 manifest after each task instead.

## File structure to create

```text
infra/api-relay-phase1/
  README.md
  docker-compose.yml
  .env.example
  postgres/
    init/
      10-create-service-databases.sh
  nginx/
    conf.d/
      api-relay.conf
    snippets/
      proxy-common.conf
  sub2api/
    config.production.yaml
  scripts/
    New-Secrets.ps1
    Build-Images.ps1
    Smoke-Test.ps1
    Backup-Postgres.ps1
    Write-Manifest.ps1
  runbooks/
    01-bootstrap.md
    02-new-api-admin-setup.md
    03-sub2api-admin-setup.md
    04-employee-onboarding.md
    05-model-and-billing-policy.md
    06-operations.md
```

Responsibilities:

- `docker-compose.yml`: one-node runtime graph.
- `.env.example`: safe, non-secret defaults plus required variable names.
- `postgres/init/10-create-service-databases.sh`: create isolated New API and Sub2API databases/users during first boot.
- `nginx/conf.d/api-relay.conf`: public reverse proxy, query-key blocking, and underscore header support.
- `sub2api/config.production.yaml`: audited production reference for operators; it is not mounted by default because Sub2API writes the live `/app/data/config.yaml` during `AUTO_SETUP`.
- `scripts/*.ps1`: repeatable local generation, image build, smoke test, backup, and manifest commands.
- `runbooks/*.md`: exact admin workflow for first boot, user/token creation, model exposure, billing, and operations.

---

## Task 1: Create secrets and inventory scaffolding

**Files:**
- Create: `infra/api-relay-phase1/.env.example`
- Create: `infra/api-relay-phase1/scripts/New-Secrets.ps1`
- Create: `infra/api-relay-phase1/scripts/Write-Manifest.ps1`

- [ ] **Step 1: Create `.env.example`**

Add this file exactly:

```dotenv
COMPOSE_PROJECT_NAME=api-relay-phase1
TZ=Asia/Shanghai

# Host routing
PUBLIC_HTTP_PORT=80
PUBLIC_HTTPS_PORT=443
PUBLIC_SERVER_NAME=api-relay.internal
NEWAPI_ADMIN_BIND=127.0.0.1:3000
SUB2API_ADMIN_BIND=127.0.0.1:8080

# Images built from pinned source commits by scripts/Build-Images.ps1
NEW_API_IMAGE=api-relay/new-api:543cc64
SUB2API_IMAGE=api-relay/sub2api:dbc8ae

# Postgres superuser used only for container initialization
POSTGRES_ADMIN_USER=postgres
POSTGRES_ADMIN_PASSWORD=generated_by_scripts_New-Secrets_ps1

# New API database
NEWAPI_DB_NAME=newapi
NEWAPI_DB_USER=newapi
NEWAPI_DB_PASSWORD=generated_by_scripts_New-Secrets_ps1

# Sub2API database
SUB2API_DB_NAME=sub2api
SUB2API_DB_USER=sub2api
SUB2API_DB_PASSWORD=generated_by_scripts_New-Secrets_ps1

# Redis
REDIS_PASSWORD=generated_by_scripts_New-Secrets_ps1

# New API secrets
NEWAPI_SESSION_SECRET=generated_by_scripts_New-Secrets_ps1
NEWAPI_CRYPTO_SECRET=generated_by_scripts_New-Secrets_ps1

# Sub2API bootstrap admin
SUB2API_ADMIN_EMAIL=admin@api-relay.internal
SUB2API_ADMIN_PASSWORD=generated_by_scripts_New-Secrets_ps1
SUB2API_JWT_SECRET=generated_by_scripts_New-Secrets_ps1
SUB2API_TOTP_ENCRYPTION_KEY=generated_by_scripts_New-Secrets_ps1
SUB2API_DATA_DIR=/app/data

# Runtime policy
NEWAPI_MAX_REQUEST_BODY_MB=64
NEWAPI_RETRY_TIMES=1
SUB2API_RUN_MODE=standard
SUB2API_ALLOWLIST_UPSTREAM_HOSTS=api.openai.com,api.anthropic.com,generativelanguage.googleapis.com,cloudcode-pa.googleapis.com
```

- [ ] **Step 2: Create `scripts/New-Secrets.ps1`**

```powershell
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
```

- [ ] **Step 3: Create `scripts/Write-Manifest.ps1`**

```powershell
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
```

- [ ] **Step 4: Verify files exist**

Run from `infra/api-relay-phase1`:

```powershell
Test-Path .env.example
Test-Path scripts/New-Secrets.ps1
Test-Path scripts/Write-Manifest.ps1
```

Expected output:

```text
True
True
True
```

- [ ] **Step 5: Generate local manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: `manifest.sha256` is created.

---

## Task 2: Create Docker Compose runtime

**Files:**
- Create: `infra/api-relay-phase1/docker-compose.yml`
- Create: `infra/api-relay-phase1/postgres/init/10-create-service-databases.sh`
- Create: `infra/api-relay-phase1/scripts/Build-Images.ps1`

- [ ] **Step 1: Create Postgres init script**

```sh
#!/bin/sh
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<EOSQL
CREATE USER ${NEWAPI_DB_USER} WITH PASSWORD '${NEWAPI_DB_PASSWORD}';
CREATE DATABASE ${NEWAPI_DB_NAME} OWNER ${NEWAPI_DB_USER};
CREATE USER ${SUB2API_DB_USER} WITH PASSWORD '${SUB2API_DB_PASSWORD}';
CREATE DATABASE ${SUB2API_DB_NAME} OWNER ${SUB2API_DB_USER};
EOSQL
```

- [ ] **Step 2: Create Docker Compose file**

```yaml
services:
  nginx:
    image: nginx:1.27-alpine
    container_name: api-relay-nginx
    restart: unless-stopped
    depends_on:
      new-api:
        condition: service_healthy
      sub2api:
        condition: service_healthy
    ports:
      - "${PUBLIC_HTTP_PORT:-80}:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/snippets:/etc/nginx/snippets:ro
    networks:
      - relay-net

  new-api:
    image: ${NEW_API_IMAGE}
    container_name: api-relay-new-api
    restart: unless-stopped
    command: --log-dir /app/logs
    ports:
      - "${NEWAPI_ADMIN_BIND:-127.0.0.1:3000}:3000"
    environment:
      SQL_DSN: "postgresql://${NEWAPI_DB_USER}:${NEWAPI_DB_PASSWORD}@postgres:5432/${NEWAPI_DB_NAME}"
      REDIS_CONN_STRING: "redis://:${REDIS_PASSWORD}@redis:6379/0"
      TZ: "${TZ:-Asia/Shanghai}"
      SESSION_SECRET: "${NEWAPI_SESSION_SECRET}"
      CRYPTO_SECRET: "${NEWAPI_CRYPTO_SECRET}"
      ERROR_LOG_ENABLED: "true"
      BATCH_UPDATE_ENABLED: "true"
      MEMORY_CACHE_ENABLED: "true"
      GENERATE_DEFAULT_TOKEN: "false"
      MAX_REQUEST_BODY_MB: "${NEWAPI_MAX_REQUEST_BODY_MB:-64}"
      STREAMING_TIMEOUT: "300"
      RELAY_TIMEOUT: "0"
      GLOBAL_API_RATE_LIMIT_ENABLE: "true"
      GLOBAL_API_RATE_LIMIT: "180"
      GLOBAL_API_RATE_LIMIT_DURATION: "180"
      NODE_NAME: "new-api-single-node"
    volumes:
      - newapi_data:/data
      - newapi_logs:/app/logs
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - relay-net
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://localhost:3000/api/status | grep -q '\"success\"[[:space:]]*:[[:space:]]*true' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  sub2api:
    image: ${SUB2API_IMAGE}
    container_name: api-relay-sub2api
    restart: unless-stopped
    ports:
      - "${SUB2API_ADMIN_BIND:-127.0.0.1:8080}:8080"
    ulimits:
      nofile:
        soft: 100000
        hard: 100000
    environment:
      AUTO_SETUP: "true"
      SERVER_HOST: "0.0.0.0"
      SERVER_PORT: "8080"
      SERVER_MODE: "release"
      RUN_MODE: "${SUB2API_RUN_MODE:-standard}"
      DATABASE_HOST: "postgres"
      DATABASE_PORT: "5432"
      DATABASE_USER: "${SUB2API_DB_USER}"
      DATABASE_PASSWORD: "${SUB2API_DB_PASSWORD}"
      DATABASE_DBNAME: "${SUB2API_DB_NAME}"
      DATABASE_SSLMODE: "disable"
      DATABASE_MAX_OPEN_CONNS: "50"
      DATABASE_MAX_IDLE_CONNS: "10"
      REDIS_HOST: "redis"
      REDIS_PORT: "6379"
      REDIS_PASSWORD: "${REDIS_PASSWORD}"
      REDIS_DB: "1"
      REDIS_POOL_SIZE: "1024"
      REDIS_MIN_IDLE_CONNS: "10"
      ADMIN_EMAIL: "${SUB2API_ADMIN_EMAIL}"
      ADMIN_PASSWORD: "${SUB2API_ADMIN_PASSWORD}"
      JWT_SECRET: "${SUB2API_JWT_SECRET}"
      JWT_EXPIRE_HOUR: "24"
      TOTP_ENCRYPTION_KEY: "${SUB2API_TOTP_ENCRYPTION_KEY}"
      DATA_DIR: "${SUB2API_DATA_DIR:-/app/data}"
      TZ: "${TZ:-Asia/Shanghai}"
      SECURITY_URL_ALLOWLIST_ENABLED: "true"
      SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP: "false"
      SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS: "false"
      SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS: "${SUB2API_ALLOWLIST_UPSTREAM_HOSTS}"
      GATEWAY_LOG_UPSTREAM_ERROR_BODY: "false"
      GATEWAY_LOG_UPSTREAM_ERROR_BODY_MAX_BYTES: "0"
      SECURITY_PROXY_FALLBACK_ALLOW_DIRECT_ON_ERROR: "false"
      SECURITY_PROXY_PROBE_INSECURE_SKIP_VERIFY: "false"
    volumes:
      - sub2api_data:/app/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - relay-net
    healthcheck:
      test: ["CMD", "wget", "-q", "-T", "5", "-O", "/dev/null", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  postgres:
    image: postgres:16-alpine
    container_name: api-relay-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: "${POSTGRES_ADMIN_USER}"
      POSTGRES_PASSWORD: "${POSTGRES_ADMIN_PASSWORD}"
      POSTGRES_DB: "postgres"
      PGDATA: "/var/lib/postgresql/data"
      NEWAPI_DB_NAME: "${NEWAPI_DB_NAME}"
      NEWAPI_DB_USER: "${NEWAPI_DB_USER}"
      NEWAPI_DB_PASSWORD: "${NEWAPI_DB_PASSWORD}"
      SUB2API_DB_NAME: "${SUB2API_DB_NAME}"
      SUB2API_DB_USER: "${SUB2API_DB_USER}"
      SUB2API_DB_PASSWORD: "${SUB2API_DB_PASSWORD}"
      TZ: "${TZ:-Asia/Shanghai}"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d:ro
    networks:
      - relay-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_ADMIN_USER} -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

  redis:
    image: redis:7-alpine
    container_name: api-relay-redis
    restart: unless-stopped
    command: >
      sh -c 'redis-server
      --save 60 1
      --appendonly yes
      --appendfsync everysec
      --requirepass "$REDIS_PASSWORD"'
    environment:
      REDIS_PASSWORD: "${REDIS_PASSWORD}"
      TZ: "${TZ:-Asia/Shanghai}"
    volumes:
      - redis_data:/data
    networks:
      - relay-net
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$REDIS_PASSWORD\" ping | grep PONG"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s

networks:
  relay-net:
    driver: bridge

volumes:
  newapi_data:
  newapi_logs:
  sub2api_data:
  postgres_data:
  redis_data:
```

- [ ] **Step 3: Create image build script**

```powershell
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
```

- [ ] **Step 4: Verify Docker Compose parses**

Run from `infra/api-relay-phase1` after generating `.env`:

```powershell
docker compose config
```

Expected: Docker Compose prints the resolved service graph and exits with code `0`.

- [ ] **Step 5: Write manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: `manifest.sha256` includes the compose, env example, scripts, and Postgres init script.

---

## Task 3: Add production Sub2API config

**Files:**
- Create: `infra/api-relay-phase1/sub2api/config.production.yaml`

This file is an audited production reference. Do not bind-mount it over `/app/data/config.yaml` during first boot, because Sub2API creates the live config and installation lock in `/app/data` when `AUTO_SETUP=true`. After first boot, use this file to compare and manually patch the live config through the Sub2API admin UI or a controlled maintenance window.

- [ ] **Step 1: Create config file**

```yaml
server:
  host: "0.0.0.0"
  port: 8080
  mode: "release"
  frontend_url: ""
  trusted_proxies: []
  max_request_body_size: 67108864
  h2c:
    enabled: true
    max_concurrent_streams: 50
    idle_timeout: 75
    max_read_frame_size: 1048576
    max_upload_buffer_per_connection: 2097152
    max_upload_buffer_per_stream: 524288

run_mode: "standard"

cors:
  allowed_origins: []
  allow_credentials: false

security:
  url_allowlist:
    enabled: true
    upstream_hosts:
      - "api.openai.com"
      - "api.anthropic.com"
      - "generativelanguage.googleapis.com"
      - "cloudcode-pa.googleapis.com"
    pricing_hosts:
      - "raw.githubusercontent.com"
    crs_hosts: []
    allow_private_hosts: false
    allow_insecure_http: false
  response_headers:
    enabled: true
    additional_allowed: []
    force_remove: []
  csp:
    enabled: true
    policy: "default-src 'self'; script-src 'self' __CSP_NONCE__ https://challenges.cloudflare.com https://static.cloudflareinsights.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' https:; frame-src https://challenges.cloudflare.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
  proxy_probe:
    insecure_skip_verify: false
  proxy_fallback:
    allow_direct_on_error: false

gateway:
  response_header_timeout: 600
  max_body_size: 67108864
  upstream_response_read_max_bytes: 8388608
  proxy_probe_response_read_max_bytes: 1048576
  gemini_debug_response_headers: false
  connection_pool_isolation: "account_proxy"
  force_codex_cli: false
  codex_image_generation_bridge_enabled: false
  openai_passthrough_allow_timeout_headers: false
  openai_ws:
    enabled: true
    oauth_enabled: true
    apikey_enabled: true
    force_http: false
    responses_websockets: false
    responses_websockets_v2: true
    mode_router_v2_enabled: false
    ingress_mode_default: ctx_pool
    max_conns_per_account: 64
    min_idle_per_account: 2
    max_idle_per_account: 8
    dynamic_max_conns_by_account_concurrency_enabled: true
    oauth_max_conns_factor: 1.0
    apikey_max_conns_factor: 1.0
    dial_timeout_seconds: 10
    read_timeout_seconds: 900
    write_timeout_seconds: 120
    fallback_cooldown_seconds: 30
    retry_total_budget_ms: 5000
    lb_top_k: 7
    sticky_session_ttl_seconds: 3600
    session_hash_read_old_fallback: true
    session_hash_dual_write_old: true
    metadata_bridge_enabled: true
    sticky_response_id_ttl_seconds: 3600
    scheduler_score_weights:
      priority: 1.0
      load: 1.0
      queue: 0.7
      error_rate: 0.8
      ttft: 0.5
  max_idle_conns: 512
  max_idle_conns_per_host: 64
  max_conns_per_host: 256
  idle_conn_timeout_seconds: 90
  max_upstream_clients: 1000
  client_idle_ttl_seconds: 900
  concurrency_slot_ttl_minutes: 30
  stream_data_interval_timeout: 180
  stream_keepalive_interval: 10
  max_line_size: 41943040
  log_upstream_error_body: false
  log_upstream_error_body_max_bytes: 0
  failover_on_400: false
  scheduling:
    sticky_session_max_waiting: 3
    sticky_session_wait_timeout: 120s
    fallback_wait_timeout: 30s
    fallback_max_waiting: 100
    load_batch_enabled: true
    slot_cleanup_interval: 30s
    db_fallback_enabled: true
    outbox_poll_interval_seconds: 1
    outbox_lag_warn_seconds: 5
    outbox_lag_rebuild_seconds: 10
    outbox_lag_rebuild_failures: 3
    outbox_backlog_rebuild_rows: 10000
    full_rebuild_interval_seconds: 300

concurrency:
  ping_interval: 10

ops:
  enabled: true

default:
  admin_email: "admin@api-relay.internal"
  admin_password: ""
  user_concurrency: 5
  user_balance: 0
  api_key_prefix: "sk-"
  rate_multiplier: 1.0

rate_limit:
  overload_cooldown_minutes: 10

billing:
  circuit_breaker:
    enabled: true
    failure_threshold: 5
    reset_timeout_seconds: 30
    half_open_requests: 3
```

- [ ] **Step 2: Verify no unsafe URL defaults remain**

Run:

```powershell
Select-String -Path .\sub2api\config.production.yaml -Pattern "enabled: false|allow_private_hosts: true|allow_insecure_http: true"
```

Expected: no match for `allow_private_hosts: true` or `allow_insecure_http: true`. A match for unrelated `enabled: false` is acceptable only for features intentionally disabled such as `force_http`.

- [ ] **Step 3: Write manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: manifest updated.

---

## Task 4: Add Nginx reverse proxy

**Files:**
- Create: `infra/api-relay-phase1/nginx/snippets/proxy-common.conf`
- Create: `infra/api-relay-phase1/nginx/conf.d/api-relay.conf`

- [ ] **Step 1: Create common proxy snippet**

```nginx
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header Connection "";
proxy_buffering off;
proxy_request_buffering off;
proxy_read_timeout 600s;
proxy_send_timeout 600s;
client_max_body_size 64m;
```

- [ ] **Step 2: Create Nginx server config**

```nginx
underscores_in_headers on;

map $arg_key $has_query_key {
    default 1;
    "" 0;
}

map $arg_api_key $has_query_api_key {
    default 1;
    "" 0;
}

server {
    listen 80;
    server_name api-relay.internal;

    access_log /var/log/nginx/api-relay.access.log;
    error_log /var/log/nginx/api-relay.error.log warn;

    if ($has_query_key) {
        return 400 "query key is not supported; use Authorization header\n";
    }

    if ($has_query_api_key) {
        return 400 "query api_key is not supported; use Authorization header\n";
    }

    location = /healthz {
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    location = /api/status {
        include /etc/nginx/snippets/proxy-common.conf;
        proxy_pass http://new-api:3000;
    }

    location /v1/ {
        include /etc/nginx/snippets/proxy-common.conf;
        proxy_pass http://new-api:3000;
    }

    location /v1beta/ {
        include /etc/nginx/snippets/proxy-common.conf;
        proxy_pass http://new-api:3000;
    }

    location /mj/ {
        include /etc/nginx/snippets/proxy-common.conf;
        proxy_pass http://new-api:3000;
    }

    location /suno/ {
        include /etc/nginx/snippets/proxy-common.conf;
        proxy_pass http://new-api:3000;
    }

    location /kling/v1/ {
        include /etc/nginx/snippets/proxy-common.conf;
        proxy_pass http://new-api:3000;
    }

    location /jimeng/ {
        include /etc/nginx/snippets/proxy-common.conf;
        proxy_pass http://new-api:3000;
    }

    location / {
        return 404 "public relay endpoint not found\n";
        add_header Content-Type text/plain;
    }
}
```

- [ ] **Step 3: Validate Nginx config through Docker**

Run from `infra/api-relay-phase1`:

```powershell
docker run --rm -v "${PWD}\nginx\conf.d:/etc/nginx/conf.d:ro" -v "${PWD}\nginx\snippets:/etc/nginx/snippets:ro" nginx:1.27-alpine nginx -t
```

Expected output contains:

```text
syntax is ok
test is successful
```

- [ ] **Step 4: Write manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: manifest updated.

---

## Task 5: Add bootstrap and admin runbooks

**Files:**
- Create: `infra/api-relay-phase1/README.md`
- Create: `infra/api-relay-phase1/runbooks/01-bootstrap.md`
- Create: `infra/api-relay-phase1/runbooks/02-new-api-admin-setup.md`
- Create: `infra/api-relay-phase1/runbooks/03-sub2api-admin-setup.md`

- [ ] **Step 1: Create README**

```markdown
# API Relay Phase 1

This directory contains the single-node deployment bundle for the company API relay service.

Runtime path:

```text
employee client -> Nginx -> New API -> Sub2API -> upstream coding plan/API key pool
```

Primary rules:

- New API is the employee-facing billing and token gateway.
- Sub2API is the upstream account/API-key scheduler.
- Prompt and completion bodies are not intentionally logged in phase 1.
- Query API keys are rejected at Nginx.
- Employee billing is based on New API usage.
- The public endpoint exposes API paths only; employee self-service web UI is deferred until it can be isolated from admin surfaces.
```

- [ ] **Step 2: Create bootstrap runbook**

```markdown
# Bootstrap Runbook

Run all commands from `infra/api-relay-phase1`.

## 1. Generate secrets

```powershell
.\scripts\New-Secrets.ps1
```

Expected:

- `.env` exists.
- `.env` is not committed or shared.

## 2. Build pinned images

```powershell
.\scripts\Build-Images.ps1
```

Expected:

- `api-relay/new-api:543cc64` exists locally.
- `api-relay/sub2api:dbc8ae` exists locally.

## 3. Validate compose

```powershell
docker compose config
```

Expected: command exits with code `0`.

## 4. Start stack

```powershell
docker compose up -d
```

## 5. Check health

```powershell
docker compose ps
```

Expected:

- `api-relay-nginx` is running.
- `api-relay-new-api` is healthy.
- `api-relay-sub2api` is healthy.
- `api-relay-postgres` is healthy.
- `api-relay-redis` is healthy.
```

- [ ] **Step 3: Create New API admin setup runbook**

```markdown
# New API Admin Setup

## 1. Open admin UI

Local server access:

```text
http://127.0.0.1:3000/
```

Remote administration uses SSH tunneling:

```powershell
ssh -L 3000:127.0.0.1:3000 relay-admin@server
```

Expected: the UI is reachable only through the localhost-bound Compose port or the SSH tunnel. Do not expose this UI through the public Nginx virtual host.

## 2. First admin

Complete New API first-run admin setup in the UI.

## 3. Operation settings

Set:

- Failure retry count: `1`
- Automatic disable channel: enabled
- Automatic disable status codes: `401`
- Automatic retry status codes: keep default unless production errors show retry amplification
- Error log: enabled for metadata; do not enable prompt/completion body logging

## 4. Add Sub2API as upstream channel

Create one OpenAI-compatible custom channel:

- Base URL: `http://sub2api:8080`
- API key: a Sub2API API key created in Sub2API
- Models: first production model allowlist
- Groups: employee production group
- Priority: `10`
- Weight: `100`
- Header Override:

```json
{
  "session_id": "{client_header:session_id}",
  "conversation_id": "{client_header:conversation_id}"
}
```

## 5. Employee user pattern

For each employee:

- Create one user.
- Add monthly free quota or balance.
- Create one or more tokens.
- Enable model limits on tokens.
- Keep token names traceable, such as `alice-main`, `alice-cursor`, `alice-cli`.
```

- [ ] **Step 4: Create Sub2API admin setup runbook**

```markdown
# Sub2API Admin Setup

## 1. Open admin UI

Local server access:

```text
http://127.0.0.1:8080/
```

Remote administration uses SSH tunneling:

```powershell
ssh -L 8080:127.0.0.1:8080 relay-admin@server
```

Expected: the UI is reachable only through the localhost-bound Compose port or the SSH tunnel. Do not expose this UI through the public Nginx virtual host.

## 2. Login

Use:

- Email from `.env`: `SUB2API_ADMIN_EMAIL`
- Password from `.env`: `SUB2API_ADMIN_PASSWORD`

## 3. Enable OpenAI advanced scheduler

In system settings, enable:

```text
openai_advanced_scheduler_enabled = true
```

## 4. Create group for New API

Create a group dedicated to New API upstream traffic, for example:

```text
newapi-prod
```

## 5. Add upstream coding-plan/API-key accounts

For each upstream account:

- Assign it to `newapi-prod`.
- Configure supported models.
- Set conservative concurrency first.
- Keep auto pause/recovery settings enabled where available.
- Record account owner/source outside the application in the operations register.

## 6. Create Sub2API API key for New API

Create one API key for New API's upstream channel:

- Group: `newapi-prod`
- Status: enabled
- Expiry: long enough for production rotation window
- IP allowlist: Docker network or internal gateway address when practical
```

- [ ] **Step 5: Write manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: manifest updated.

---

## Task 6: Add employee, model, and billing runbooks

**Files:**
- Create: `infra/api-relay-phase1/runbooks/04-employee-onboarding.md`
- Create: `infra/api-relay-phase1/runbooks/05-model-and-billing-policy.md`

- [ ] **Step 1: Create employee onboarding runbook**

```markdown
# Employee Onboarding

## Employee record

For each employee, record:

```text
employee_name
department
new_api_username
token_names
monthly_free_quota
enabled_models
created_at
created_by
```

Do not record API token values in this file.

## Token naming

Use one or more:

```text
employee-main
employee-cursor
employee-cli
employee-test
```

## Employee message

Send the employee:

```text
Base URL: http://api-relay.internal/v1
API Key: issued separately
Supported mode: OpenAI-compatible API
Rule: use only your own key; do not share it or paste it into untrusted websites.
Rule: free quota is limited; usage above the free quota requires balance.
Rule: non-standard clients are best-effort support only.
Balance and usage visibility: request a report from the administrator during phase 1.
```

## L1 client templates

### OpenAI SDK compatible

```text
base_url = http://api-relay.internal/v1
api_key = employee token
model = real model name from allowed list
```

### Cursor / Cline / Continue

```text
Provider = OpenAI compatible
Base URL = http://api-relay.internal/v1
API Key = employee token
Model = real model name from allowed list
```

### Coding CLI with session header support

If the client supports custom headers, add:

```text
session_id = stable per project/session
```

If custom headers are not supported, rely on prompt/body fallback.
```

- [ ] **Step 2: Create model and billing policy runbook**

```markdown
# Model and Billing Policy

## Model exposure

Employees see real model names. Model access is still controlled by New API model limits.

## Initial model tiers

Use three tiers:

```text
basic
premium
experimental
```

## Basic tier

Purpose:

- daily coding
- low-cost chat
- normal development

Policy:

- available to all active employees
- can consume monthly free quota

## Premium tier

Purpose:

- high-quality coding
- long-context work
- expensive reasoning

Policy:

- enabled per employee or department
- requires balance after free quota
- alert on daily spend spikes

## Experimental tier

Purpose:

- new models
- unstable providers
- temporary tests

Policy:

- low daily quota
- removable without notice
- not used for production automation

## Manual balance flow

```text
employee requests balance
admin records internal payment or approval
admin adjusts New API user balance
admin records amount, operator, timestamp, and reason
admin sends updated balance confirmation to employee
```

## Cost control

Minimum controls:

- every employee has a separate New API user
- every token belongs to one employee
- token model limits are enabled
- balance exhaustion blocks usage
- daily user spend is reviewed during the first 7 days
- employee usage/balance reports are handled by admin until self-service portal is isolated
```

- [ ] **Step 3: Write manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: manifest updated.

---

## Task 7: Add smoke tests, backup script, and operations runbook

**Files:**
- Create: `infra/api-relay-phase1/scripts/Smoke-Test.ps1`
- Create: `infra/api-relay-phase1/scripts/Backup-Postgres.ps1`
- Create: `infra/api-relay-phase1/runbooks/06-operations.md`

- [ ] **Step 1: Create smoke test script**

```powershell
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
```

- [ ] **Step 2: Create Postgres backup script**

```powershell
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
```

- [ ] **Step 3: Create operations runbook**

```markdown
# Operations Runbook

## Daily checks during first 7 days

Check:

- New API successful requests
- New API failed requests
- top users by cost
- top models by cost
- Sub2API 401/403/429/529 counts
- Sub2API account cooldown count
- Sub2API queue/wait symptoms
- Redis and Postgres container health

## Stop one employee token

In New API:

```text
Tokens -> find token -> disable
```

Expected: requests with that token fail immediately or after auth cache expiration.

## Stop one employee user

In New API:

```text
Users -> find user -> disable
```

Expected: all tokens belonging to the user become unusable.

## Backup

Run:

```powershell
.\scripts\Backup-Postgres.ps1
```

Expected:

- `backups/newapi-*.dump`
- `backups/sub2api-*.dump`

## Restart stack

```powershell
docker compose restart
docker compose ps
```

Expected:

- all containers return to running or healthy

## View logs

```powershell
docker compose logs --tail 200 new-api
docker compose logs --tail 200 sub2api
docker compose logs --tail 200 nginx
```

## Rollback

If a config change breaks routing:

```powershell
docker compose down
Copy-Item -Recurse -Force .\backups\last-known-good\* .
docker compose config
docker compose up -d
```

Expected: `docker compose config` exits with code `0`, then services return to running or healthy. If a git repository is available, review the exact diff first and revert only the bad files after operator approval.
```

- [ ] **Step 4: Validate PowerShell syntax**

Run:

```powershell
powershell -NoProfile -Command { [scriptblock]::Create((Get-Content .\scripts\Smoke-Test.ps1 -Raw)) | Out-Null }
powershell -NoProfile -Command { [scriptblock]::Create((Get-Content .\scripts\Backup-Postgres.ps1 -Raw)) | Out-Null }
```

Expected: both commands exit with code `0`.

- [ ] **Step 5: Write manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: manifest updated.

---

## Task 8: First boot verification

**Files:**
- Modify: `infra/api-relay-phase1/runbooks/01-bootstrap.md`

- [ ] **Step 1: Build images**

Run:

```powershell
cd infra\api-relay-phase1
.\scripts\Build-Images.ps1
```

Expected:

```text
Built api-relay/new-api:543cc64
Built api-relay/sub2api:dbc8ae
```

- [ ] **Step 2: Start stack**

Run:

```powershell
docker compose up -d
docker compose ps
```

Expected: all services are running; New API and Sub2API become healthy after startup.

- [ ] **Step 3: Verify HTTP routing**

Run:

```powershell
Invoke-WebRequest -Uri http://api-relay.internal/healthz -UseBasicParsing
```

Expected status code: `200`.

- [ ] **Step 4: Verify query key rejection**

Run:

```powershell
try {
    Invoke-WebRequest -Uri "http://api-relay.internal/v1/models?key=abc" -UseBasicParsing
} catch {
    $_.Exception.Response.StatusCode.value__
}
```

Expected output:

```text
400
```

- [ ] **Step 5: Complete admin setup manually**

Follow:

- `runbooks/02-new-api-admin-setup.md`
- `runbooks/03-sub2api-admin-setup.md`

Expected:

- New API has one employee test user.
- New API has one employee test token.
- Sub2API has at least one upstream account.
- New API has one Sub2API upstream channel.

- [ ] **Step 6: Run smoke test**

Run:

```powershell
.\scripts\Smoke-Test.ps1 -BaseUrl "http://api-relay.internal" -ApiKey "employee-test-token-value" -Model "first-enabled-real-model"
```

Expected:

```text
Smoke test passed
```

- [ ] **Step 7: Record first boot status**

Append this section to `runbooks/01-bootstrap.md`:

```markdown
## First boot record

Date: 2026-05-10

Verified:

- Docker Compose config rendered.
- Containers started.
- Nginx health endpoint returned 200.
- Query API key was rejected.
- New API admin setup completed.
- Sub2API admin setup completed.
- Smoke test returned expected content.
```

- [ ] **Step 8: Write manifest**

Run:

```powershell
.\scripts\Write-Manifest.ps1 -Root . -OutputPath manifest.sha256
```

Expected: manifest updated.

---

## Self-review checklist

- Spec coverage:
  - Single-node Nginx/New API/Sub2API/Postgres/Redis stack: Tasks 2, 4, 8.
  - Employee users, personal tokens, balance/free quota: Tasks 5, 6.
  - Real model names with allowlists: Tasks 5, 6.
  - Mixed client support: Task 6.
  - Sticky headers: Tasks 4, 5.
  - Conservative retries: Task 5.
  - No prompt/completion logging by default: Tasks 5, 6.
  - Security baseline: Tasks 2, 3, 4.
  - Observability and operations: Task 7.
- Placeholder scan:
  - Environment values are generated by script, not left as manual blanks in runtime `.env`.
  - The smoke test command uses explicit argument names and requires real token/model values created during admin setup.
- Type/name consistency:
  - Compose service names match Nginx upstreams: `new-api`, `sub2api`.
  - Redis DB split is explicit: New API DB 0, Sub2API DB 1.
  - Postgres DB/user names match `.env.example` variables.
