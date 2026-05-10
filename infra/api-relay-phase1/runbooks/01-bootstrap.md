# Bootstrap Runbook

Run all commands from `infra/api-relay-phase1`.

## 1. Generate secrets

```powershell
.\scripts\New-Secrets.ps1
```

Linux:

```bash
python3 scripts/New-Secrets.py
chmod 600 .env
```

Expected:

- `.env` exists.
- `.env` is not committed or shared.

## 2. Build pinned images

```powershell
.\scripts\Build-Images.ps1
```

Linux:

```bash
NEW_API_SOURCE=/home/pyh/api-relay-sources/new-api \
SUB2API_SOURCE=/home/pyh/api-relay-sources/sub2api \
bash scripts/Build-Images.sh
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
