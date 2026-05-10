#!/usr/bin/env bash
set -euo pipefail

NEW_API_SOURCE="${NEW_API_SOURCE:-../../.research/new-api}"
SUB2API_SOURCE="${SUB2API_SOURCE:-../../.research/sub2api}"
NEW_API_IMAGE="${NEW_API_IMAGE:-api-relay/new-api:543cc64}"
SUB2API_IMAGE="${SUB2API_IMAGE:-api-relay/sub2api:dbc8ae}"
WORK_DIR="${WORK_DIR:-./.build-context}"

assert_git_commit() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(git -C "$path" rev-parse HEAD)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected commit in $path. Expected $expected, got $actual" >&2
    exit 1
  fi
}

prepare_context() {
  local source="$1"
  local target="$2"
  rm -rf "$target"
  mkdir -p "$(dirname "$target")"
  cp -a "$source" "$target"
}

patch_new_api_context() {
  local context="$1"
  cat >> "$context/.dockerignore" <<'EOF'

# Build fix: Dockerfile copies these markdown license files.
!LICENSE
!NOTICE
!THIRD-PARTY-LICENSES.md
EOF
}

patch_sub2api_context() {
  local context="$1"
  python3 - "$context/Dockerfile" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
content = path.read_text()
content = content.replace(
    "RUN corepack enable && corepack prepare pnpm@latest --activate",
    "RUN corepack enable && corepack prepare pnpm@9.15.9 --activate",
)
path.write_text(content)
PY
}

assert_git_commit "$NEW_API_SOURCE" "543cc64ea3805a3f2291b86525ad83771cb61423"
assert_git_commit "$SUB2API_SOURCE" "dbc8ae658cfc1c012160752582925e45115e2f3a"

prepare_context "$NEW_API_SOURCE" "$WORK_DIR/new-api"
prepare_context "$SUB2API_SOURCE" "$WORK_DIR/sub2api"
patch_new_api_context "$WORK_DIR/new-api"
patch_sub2api_context "$WORK_DIR/sub2api"

docker build -t "$NEW_API_IMAGE" "$WORK_DIR/new-api"
docker build -t "$SUB2API_IMAGE" "$WORK_DIR/sub2api"

echo "Built $NEW_API_IMAGE"
echo "Built $SUB2API_IMAGE"
