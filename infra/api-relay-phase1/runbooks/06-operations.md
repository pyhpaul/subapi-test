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
