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
