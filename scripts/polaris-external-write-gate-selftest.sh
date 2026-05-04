#!/usr/bin/env bash
# Selftest for polaris-external-write-gate.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/polaris-external-write-gate.sh"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

pass_body="$tmp/jira-comment.md"
cat > "$pass_body" <<'EOF'
這是一段要送到 JIRA comment 的中文內容。
EOF

bash "$GATE" --surface jira-comment --body-file "$pass_body" --workspace-root "$ROOT" >/dev/null

if bash "$GATE" --surface jira-comment --body-file "$tmp/missing.md" --workspace-root "$ROOT" >/dev/null 2>&1; then
  echo "FAIL: missing body file should fail" >&2
  exit 1
fi

if bash "$GATE" --surface unknown --body-file "$pass_body" --workspace-root "$ROOT" >/dev/null 2>&1; then
  echo "FAIL: unknown surface should fail" >&2
  exit 1
fi

starlight_body="$tmp/spec.md"
cat > "$starlight_body" <<'EOF'
---
title: "測試文件"
description: "這是 selftest 使用的 Starlight markdown。"
---

## 內容

這是一段符合語言政策的內容。
EOF

bash "$GATE" --surface artifact --body-file "$starlight_body" --workspace-root "$ROOT" --starlight >/dev/null

echo "PASS: polaris external write gate selftest"
