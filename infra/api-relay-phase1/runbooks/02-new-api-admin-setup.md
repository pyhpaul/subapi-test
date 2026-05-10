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
