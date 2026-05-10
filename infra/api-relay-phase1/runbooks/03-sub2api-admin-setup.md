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
