import os
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "Relay-Wizard.sh"


def find_bash() -> str | None:
    candidate = shutil.which("bash")
    if candidate:
        return candidate

    for path in [
        Path(r"C:\Program Files\Git\bin\bash.exe"),
        Path(r"C:\Program Files\Git\usr\bin\bash.exe"),
        Path(r"C:\msys64\usr\bin\bash.exe"),
    ]:
        if path.exists():
            return str(path)

    return None


class RelayWizardTests(unittest.TestCase):
    def read_script(self) -> str:
        self.assertTrue(SCRIPT.exists(), f"{SCRIPT} does not exist")
        return SCRIPT.read_text(encoding="utf-8")

    def run_script(self, *args: str) -> subprocess.CompletedProcess[str]:
        bash = find_bash()
        self.assertIsNotNone(bash, "bash is required to execute Relay-Wizard.sh")
        return subprocess.run(
            [bash, str(SCRIPT), *args],
            cwd=ROOT,
            check=False,
            text=True,
            encoding="utf-8",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**os.environ, "NO_COLOR": "1"},
        )

    def test_script_has_valid_bash_syntax(self):
        bash = find_bash()
        if bash is None:
            self.skipTest("bash is not available on this workstation")
        result = subprocess.run(
            [bash, "-n", str(SCRIPT)],
            text=True,
            encoding="utf-8",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_menu_lists_required_operator_steps(self):
        if find_bash() is not None:
            result = self.run_script("--menu")
            self.assertEqual(result.returncode, 0, result.stderr)
            output = result.stdout
        else:
            output = self.read_script()
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
            self.assertIn(item, output)

    def test_admin_info_uses_ssh_tunnels_and_localhost_admin_ports(self):
        if find_bash() is not None:
            result = self.run_script("--admin-info")
            self.assertEqual(result.returncode, 0, result.stderr)
            output = result.stdout
        else:
            output = self.read_script()
            self.assertIn('SERVER_HOST="${RELAY_SERVER_HOST:-192.168.5.121}"', output)
            self.assertIn('SERVER_USER="${RELAY_SERVER_USER:-pyh}"', output)
            self.assertIn('DEPLOY_DIR="${RELAY_DEPLOY_DIR:-/home/pyh/api-relay-phase1}"', output)
            self.assertIn('ssh -L 3000:127.0.0.1:3000 $SERVER_USER@$SERVER_HOST', output)
            self.assertIn('ssh -L 8080:127.0.0.1:8080 $SERVER_USER@$SERVER_HOST', output)
            return
        self.assertIn("ssh -L 3000:127.0.0.1:3000 pyh@192.168.5.121", output)
        self.assertIn("ssh -L 8080:127.0.0.1:8080 pyh@192.168.5.121", output)
        self.assertIn("/home/pyh/api-relay-phase1/admin-credentials.txt", output)

    def test_employee_template_uses_public_v1_endpoint_and_real_model(self):
        if find_bash() is not None:
            result = self.run_script("--employee-template", "alice", "gpt-4.1-mini", "alice-cursor")
            self.assertEqual(result.returncode, 0, result.stderr)
            output = result.stdout
        else:
            output = self.read_script()
            self.assertIn("render_employee_template", output)
            self.assertIn("http://192.168.5.121/v1", output)
            self.assertIn("Token name:", output)
            self.assertIn("Model:", output)
            return
        self.assertIn("Base URL: http://192.168.5.121/v1", output)
        self.assertIn("Model: gpt-4.1-mini", output)
        self.assertIn("Token name: alice-cursor", output)
        self.assertNotIn("?key=", output)
        self.assertNotIn("?api_key=", output)

    def test_interactive_exit_option_exits_cleanly(self):
        bash = find_bash()
        if bash is None:
            self.skipTest("bash is not available on this workstation")

        result = subprocess.run(
            [bash, "-lc", "printf '0\\n' | ./scripts/Relay-Wizard.sh"],
            cwd=ROOT,
            check=False,
            text=True,
            encoding="utf-8",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("退出。", result.stdout)


if __name__ == "__main__":
    unittest.main()
