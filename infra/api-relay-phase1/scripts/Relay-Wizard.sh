#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
SERVER_HOST="${RELAY_SERVER_HOST:-192.168.5.121}"
SERVER_USER="${RELAY_SERVER_USER:-pyh}"
PUBLIC_BASE_URL="${RELAY_PUBLIC_BASE_URL:-http://192.168.5.121/v1}"
DEPLOY_DIR="${RELAY_DEPLOY_DIR:-/home/pyh/api-relay-phase1}"

hr() {
    printf '%s\n' "------------------------------------------------------------"
}

pause_for_operator() {
    if [[ -t 0 ]]; then
        printf '\n按 Enter 继续...'
        read -r _
    fi
}

read_required() {
    local prompt="$1"
    local secret="${2:-false}"
    local value=""

    while [[ -z "$value" ]]; do
        if [[ "$secret" == "true" ]]; then
            printf '%s' "$prompt" >&2
            if ! read -r -s value; then
                return 1
            fi
            printf '\n' >&2
        else
            printf '%s' "$prompt" >&2
            if ! read -r value; then
                return 1
            fi
        fi
        if [[ -z "$value" ]]; then
            printf '不能为空，请重新输入。\n' >&2
        fi
    done

    printf '%s' "$value"
}

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
        return
    fi

    sudo docker compose "$@"
}

print_menu() {
    cat <<EOF
==============================
API Relay Phase 1 配置向导
==============================

当前服务器: $SERVER_HOST
部署目录: $DEPLOY_DIR

请选择操作：

1) 检查基础服务状态
2) 显示后台登录方式
3) Sub2API 配置向导
4) New API 配置向导
5) 员工 Token 测试
6) 查看最近错误日志
7) 执行数据库备份
8) 生成员工客户端配置
0) 退出
EOF
}

show_admin_info() {
    cat <<EOF
New API 后台：

在你自己电脑执行：
ssh -L 3000:127.0.0.1:3000 $SERVER_USER@$SERVER_HOST

浏览器打开：
http://127.0.0.1:3000

Sub2API 后台：

在你自己电脑执行：
ssh -L 8080:127.0.0.1:8080 $SERVER_USER@$SERVER_HOST

浏览器打开：
http://127.0.0.1:8080

管理员凭据文件：
$DEPLOY_DIR/admin-credentials.txt

查看凭据：
ssh $SERVER_USER@$SERVER_HOST "cat $DEPLOY_DIR/admin-credentials.txt"

注意：
- 管理后台只通过 SSH tunnel 访问。
- 不要把管理员密码、上游 Key、员工 Token 贴进仓库或群聊。
EOF
}

check_http() {
    local name="$1"
    local url="$2"

    printf '%-18s ' "$name:"
    if curl -fsS --max-time 10 "$url" >/dev/null; then
        printf 'OK\n'
        return 0
    fi

    printf 'FAIL (%s)\n' "$url"
    return 1
}

check_status() {
    cd "$ROOT_DIR"
    hr
    printf 'Docker Compose 服务状态\n'
    hr
    compose ps

    hr
    printf 'HTTP 健康检查\n'
    hr
    local failed=0
    check_http "Nginx healthz" "http://127.0.0.1/healthz" || failed=1
    check_http "New API status" "http://127.0.0.1/api/status" || failed=1
    check_http "Sub2API health" "http://127.0.0.1:8080/health" || failed=1

    if [[ "$failed" -ne 0 ]]; then
        printf '\n有健康检查失败。建议查看菜单 6 的日志。\n'
        return 1
    fi

    printf '\n基础服务健康检查通过。\n'
}

show_sub2api_guide() {
    cat <<'EOF'
Sub2API 配置向导

第 1 步：打开后台
http://127.0.0.1:8080

第 2 步：进入 Settings / 系统设置
确认开启：
openai_advanced_scheduler_enabled = true

第 3 步：进入 Groups / 分组
创建：
名称: newapi-prod
状态: enabled

第 4 步：进入 Accounts / 账号管理
先只添加 1 个上游账号：
名称: openai-key-01 / anthropic-key-01 / gemini-key-01
分组: newapi-prod
并发: 1
状态: enabled
模型: 填真实模型名，例如 gpt-4.1-mini

第 5 步：进入 API Keys / Tokens
创建给 New API 使用的 Key：
名称: newapi-prod-key
分组: newapi-prod
状态: enabled

复制生成的 key。这个 key 只给 New API 通道使用，不给员工。
EOF
}

show_newapi_guide() {
    cat <<'EOF'
New API 配置向导

第 1 步：打开后台
http://127.0.0.1:3000

第 2 步：进入 Groups / 分组
创建：
名称: employee-prod

第 3 步：进入 Channels / 渠道
新增通道：
名称: sub2api-newapi-prod
类型: OpenAI / OpenAI Compatible / 自定义 OpenAI
Base URL: http://sub2api:8080
API Key: 粘贴 Sub2API 的 newapi-prod-key
分组: employee-prod
优先级: 10
权重: 100
模型: 填 Sub2API 上游账号支持的真实模型名

第 4 步：如有 Header Override / 自定义请求头，填写：
{
  "session_id": "{client_header:session_id}",
  "conversation_id": "{client_header:conversation_id}"
}

第 5 步：进入 Users / 用户
创建 test-user，分组 employee-prod，给少量余额。

第 6 步：进入 Tokens / 令牌
给 test-user 创建 test-user-cursor，开启模型限制，只允许测试模型。
EOF
}

run_smoke_test() {
    local employee_key
    local model
    local base_url="${RELAY_SMOKE_BASE_URL:-http://127.0.0.1}"

    employee_key="$(read_required '请输入员工 New API Token: ' true)"
    model="$(read_required '请输入测试模型名，例如 gpt-4.1-mini: ' false)"

    local payload
    payload=$(cat <<EOF
{
  "model": "$model",
  "messages": [
    {"role": "user", "content": "Reply with exactly: relay-ok"}
  ],
  "stream": false
}
EOF
)

    printf '\n开始测试：%s/v1/chat/completions\n' "$base_url"
    local response
    if ! response=$(curl -sS --max-time 120 "$base_url/v1/chat/completions" \
        -H "Authorization: Bearer $employee_key" \
        -H "Content-Type: application/json" \
        -H "session_id: smoke-test-session" \
        -d "$payload"); then
        printf 'curl 调用失败。请用菜单 6 查看 new-api 与 sub2api 日志。\n'
        return 1
    fi

    if printf '%s' "$response" | grep -qi 'relay-ok'; then
        printf '业务链路测试成功：relay-ok\n'
        return 0
    fi

    printf '业务链路测试未返回 relay-ok。返回内容前 4000 字节：\n'
    printf '%s' "$response" | head -c 4000
    printf '\n\n排查顺序：Token、模型名、New API 通道、Sub2API 上游账号。\n'
    return 1
}

show_logs_menu() {
    cd "$ROOT_DIR"
    cat <<'EOF'
选择日志：
1) New API
2) Sub2API
3) Nginx
4) 全部最近 100 行
EOF
    local choice
    choice="$(read_required '请输入选项: ' false)"

    case "$choice" in
        1) compose logs --tail 200 new-api ;;
        2) compose logs --tail 200 sub2api ;;
        3) compose logs --tail 200 nginx ;;
        4) compose logs --tail 100 new-api sub2api nginx ;;
        *) printf '无效选项。\n'; return 1 ;;
    esac
}

run_backup() {
    cd "$ROOT_DIR"
    mkdir -p backups

    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local newapi_backup="backups/newapi-$timestamp.dump"
    local sub2api_backup="backups/sub2api-$timestamp.dump"

    compose exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -Fc "$NEWAPI_DB_NAME"' > "$newapi_backup"
    compose exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -Fc "$SUB2API_DB_NAME"' > "$sub2api_backup"

    printf '已写入：%s\n' "$newapi_backup"
    printf '已写入：%s\n' "$sub2api_backup"
}

render_employee_template() {
    local employee="$1"
    local model="$2"
    local token_name="$3"

    cat <<EOF
发给员工 $employee 的配置：

Provider: OpenAI Compatible
Base URL: $PUBLIC_BASE_URL
API Key: 单独发送给员工本人
Model: $model
Token name: $token_name

规则：
- 只能使用自己的 API Key。
- 不要共享 Token。
- 免费额度有限，超出后需要充值或管理员增加余额。
- Cursor / Cline / Continue 都选择 OpenAI Compatible。
EOF
}

generate_employee_template() {
    local employee
    local model
    local token_name

    employee="$(read_required '员工用户名，例如 alice: ' false)"
    model="$(read_required '模型名，例如 gpt-4.1-mini: ' false)"
    token_name="$(read_required 'Token 名称，例如 alice-cursor: ' false)"
    printf '\n'
    render_employee_template "$employee" "$model" "$token_name"
}

run_interactive() {
    while true; do
        print_menu
        local choice
        choice="$(read_required '请输入选项: ' false)"
        printf '\n'

        case "$choice" in
            1) check_status || true ;;
            2) show_admin_info ;;
            3) show_sub2api_guide ;;
            4) show_newapi_guide ;;
            5) run_smoke_test || true ;;
            6) show_logs_menu || true ;;
            7) run_backup ;;
            8) generate_employee_template ;;
            0) printf '退出。\n'; break ;;
            *) printf '无效选项，请重新输入。\n' ;;
        esac

        pause_for_operator
        printf '\n'
    done
}

usage() {
    cat <<'EOF'
Usage:
  ./scripts/Relay-Wizard.sh
  ./scripts/Relay-Wizard.sh --menu
  ./scripts/Relay-Wizard.sh --admin-info
  ./scripts/Relay-Wizard.sh --sub2api-guide
  ./scripts/Relay-Wizard.sh --newapi-guide
  ./scripts/Relay-Wizard.sh --employee-template <employee> <model> <token-name>
EOF
}

main() {
    case "${1:-}" in
        "") run_interactive ;;
        --menu) print_menu ;;
        --admin-info) show_admin_info ;;
        --sub2api-guide) show_sub2api_guide ;;
        --newapi-guide) show_newapi_guide ;;
        --employee-template)
            if [[ "$#" -ne 4 ]]; then
                usage
                return 2
            fi
            render_employee_template "$2" "$3" "$4"
            ;;
        -h|--help) usage ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
