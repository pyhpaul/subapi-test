# Interactive Wizard

`scripts/Relay-Wizard.sh` is the recommended operator entrypoint after the base stack is deployed.

It is intentionally conservative:

- It guides UI operations for Sub2API and New API.
- It automates health checks, smoke tests, logs, backups, and employee client templates.
- It does not write upstream accounts, API keys, New API users, or channel records directly into application databases.
- It does not store employee tokens or upstream keys.

## Run on the server

```bash
ssh pyh@192.168.5.121
cd /home/pyh/api-relay-phase1
chmod +x scripts/Relay-Wizard.sh
./scripts/Relay-Wizard.sh
```

## Recommended first-time flow

Run these menu items in order:

```text
1) 检查基础服务状态
2) 显示后台登录方式
3) Sub2API 配置向导
4) New API 配置向导
5) 员工 Token 测试
7) 执行数据库备份
8) 生成员工客户端配置
```

## Non-interactive helpers

Print the menu:

```bash
./scripts/Relay-Wizard.sh --menu
```

Print admin tunnel instructions:

```bash
./scripts/Relay-Wizard.sh --admin-info
```

Print Sub2API UI setup guide:

```bash
./scripts/Relay-Wizard.sh --sub2api-guide
```

Print New API UI setup guide:

```bash
./scripts/Relay-Wizard.sh --newapi-guide
```

Generate employee client text:

```bash
./scripts/Relay-Wizard.sh --employee-template alice gpt-4.1-mini alice-cursor
```

## Environment overrides

Defaults match the current phase 1 deployment:

```bash
RELAY_SERVER_HOST=192.168.5.121
RELAY_SERVER_USER=pyh
RELAY_PUBLIC_BASE_URL=http://192.168.5.121/v1
RELAY_DEPLOY_DIR=/home/pyh/api-relay-phase1
RELAY_SMOKE_BASE_URL=http://127.0.0.1
```

Override only if the deployment address changes:

```bash
RELAY_PUBLIC_BASE_URL=http://api-relay.internal/v1 ./scripts/Relay-Wizard.sh
```

## Smoke test

Menu item 5 asks for:

```text
员工 New API Token
真实模型名
```

The token is read silently and is not printed back. The test calls:

```text
POST http://127.0.0.1/v1/chat/completions
```

Expected model response:

```text
relay-ok
```

If the test fails, use menu item 6 and inspect logs in this order:

```text
New API
Sub2API
Nginx
```
