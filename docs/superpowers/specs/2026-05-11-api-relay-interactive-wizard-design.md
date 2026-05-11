# API Relay Interactive Wizard Design

**Goal:** Add a low-risk interactive terminal wizard that guides an operator through API Relay phase 1 setup after the base Docker stack is already deployed.

**Architecture:** The wizard is a Bash script that runs from `/home/pyh/api-relay-phase1` or `infra/api-relay-phase1`, prints exact UI instructions for Sub2API/New API, and automates only safe local checks: health checks, smoke test, logs, backups, and employee client templates. It does not write directly into New API or Sub2API databases and does not store upstream API keys or employee tokens.

**Scope:**
- Add `infra/api-relay-phase1/scripts/Relay-Wizard.sh`.
- Add `infra/api-relay-phase1/runbooks/07-interactive-wizard.md`.
- Add tests that verify the script exposes the expected menu, safe command behavior, and generated instructions.

**Operator flow:**
1. Run `./scripts/Relay-Wizard.sh`.
2. Use menu option 1 to check container and HTTP health.
3. Use option 2 to display SSH tunnel and credential-file instructions.
4. Use option 3 to follow Sub2API UI setup.
5. Use option 4 to follow New API UI setup.
6. Use option 5 to run a real employee-token smoke test.
7. Use option 6 to view recent logs.
8. Use option 7 to create Postgres backups.
9. Use option 8 to generate employee client configuration text.

**Safety rules:**
- Never echo secret values entered by the operator.
- Never require tokens as command-line arguments.
- Refuse query-string API key patterns in examples.
- Keep management UI access instructions on SSH tunnels only.
- Use `sudo docker compose` when plain `docker compose` is unavailable.

**Testing strategy:**
- Static tests inspect the script for the expected menu items and guarded secret handling.
- Non-interactive command tests call safe helper modes such as `--menu`, `--admin-info`, and `--employee-template`.
- Shell syntax is validated with `bash -n`.

**Out of scope:**
- Automatic backend API calls to create New API users/channels.
- Automatic Sub2API account creation.
- Web-based admin wizard.
- Storing upstream API keys, employee API tokens, or generated credentials.
