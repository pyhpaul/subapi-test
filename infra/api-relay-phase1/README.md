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
- Linux deployment can use `scripts/New-Secrets.py` and `scripts/Build-Images.sh`; PowerShell scripts remain available for Windows operators.

Operator shortcut:

```bash
cd /home/pyh/api-relay-phase1
chmod +x scripts/Relay-Wizard.sh
./scripts/Relay-Wizard.sh
```

See `runbooks/07-interactive-wizard.md` for the guided first-time setup flow.
