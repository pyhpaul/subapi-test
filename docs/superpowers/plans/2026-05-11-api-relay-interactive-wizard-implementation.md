# API Relay Interactive Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Bash-based interactive wizard for guiding API Relay phase 1 business setup and verification.

**Architecture:** A single shell script contains a thin interactive menu and focused helper functions for status checks, printed setup guides, smoke testing, logs, backups, and employee template generation. Python unittest coverage validates safe non-interactive output and shell syntax.

**Tech Stack:** Bash, Docker Compose, curl, Python unittest.

---

### Task 1: Add failing tests for wizard behavior

**Files:**
- Create: `infra/api-relay-phase1/tests/test_relay_wizard.py`

- [ ] **Step 1: Add tests**

```python
import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "Relay-Wizard.sh"


class RelayWizardTests(unittest.TestCase):
    def run_script(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            cwd=ROOT,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**os.environ, "NO_COLOR": "1"},
        )

    def test_script_has_valid_bash_syntax(self):
        result = subprocess.run(["bash", "-n", str(SCRIPT)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_menu_lists_required_operator_steps(self):
        result = self.run_script("--menu")
        self.assertEqual(result.returncode, 0, result.stderr)
        for item in [
            "检查基础服务状态",
            "显示后台登录方式",
            "Sub2API 配置向导",
            "New API 配置向导",
            "员工 Token 测试",
            "查看最近错误日志",
            "执行数据库备份",
            "生成员工客户端配置",
        ]:
            self.assertIn(item, result.stdout)

    def test_admin_info_uses_ssh_tunnels_and_localhost_admin_ports(self):
        result = self.run_script("--admin-info")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ssh -L 3000:127.0.0.1:3000 pyh@192.168.5.121", result.stdout)
        self.assertIn("ssh -L 8080:127.0.0.1:8080 pyh@192.168.5.121", result.stdout)
        self.assertIn("/home/pyh/api-relay-phase1/admin-credentials.txt", result.stdout)

    def test_employee_template_uses_public_v1_endpoint_and_real_model(self):
        result = self.run_script("--employee-template", "alice", "gpt-4.1-mini", "alice-cursor")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Base URL: http://192.168.5.121/v1", result.stdout)
        self.assertIn("Model: gpt-4.1-mini", result.stdout)
        self.assertIn("Token name: alice-cursor", result.stdout)
        self.assertNotIn("?key=", result.stdout)
        self.assertNotIn("?api_key=", result.stdout)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m unittest infra/api-relay-phase1/tests/test_relay_wizard.py -v`

Expected: FAIL because `scripts/Relay-Wizard.sh` does not exist yet.

### Task 2: Implement the wizard script

**Files:**
- Create: `infra/api-relay-phase1/scripts/Relay-Wizard.sh`

- [ ] **Step 1: Add Bash script**
- [ ] **Step 2: Run tests and verify GREEN**

Run: `python -m unittest infra/api-relay-phase1/tests/test_relay_wizard.py -v`

Expected: all tests pass.

### Task 3: Add runbook and final verification

**Files:**
- Create: `infra/api-relay-phase1/runbooks/07-interactive-wizard.md`
- Modify: `infra/api-relay-phase1/README.md`

- [ ] **Step 1: Document how to run the wizard locally and on the server**
- [ ] **Step 2: Validate syntax and tests**

Run:

```powershell
python -m unittest infra/api-relay-phase1/tests/test_relay_wizard.py -v
bash -n infra/api-relay-phase1/scripts/Relay-Wizard.sh
git diff --check
```

Expected: all commands exit 0.
