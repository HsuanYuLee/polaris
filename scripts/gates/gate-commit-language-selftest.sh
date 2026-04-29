#!/usr/bin/env bash
set -euo pipefail

# scripts/gates/gate-commit-language-selftest.sh — selftest for gate-commit-language.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/gate-commit-language.sh"
TMPROOT="$(mktemp -d -t commit-language-selftest-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_rc() {
  local label="$1"
  local got="$2"
  local want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

repo="$TMPROOT/repo"
mkdir -p "$repo"
cat > "$repo/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML

pr_zh="$TMPROOT/pr-zh.md"
cat > "$pr_zh" <<'EOF'
## Description

這個 PR 補上 commit message 語言 gate。
EOF

msg_file="$TMPROOT/msg.txt"
cat > "$msg_file" <<'EOF'
fix(language): wire commit message language gate
EOF

set +e
"$GATE" --repo "$repo" --message "fix(language): wire commit message language gate" >/dev/null 2>&1
rc=$?
set -e
assert_rc "無 PR 時 fallback root zh-TW 擋英文 subject" "$rc" "2"

set +e
"$GATE" --repo "$repo" --message "fix(language): 補上 commit message 語言 gate" >/dev/null 2>&1
rc=$?
set -e
assert_rc "無 PR 時中文 subject pass" "$rc" "0"

set +e
"$GATE" --repo "$repo" --pr-author-language zh-TW --message "fix(language): wire commit message language gate" >/dev/null 2>&1
rc=$?
set -e
assert_rc "中文 PR author 擋英文 subject" "$rc" "2"

set +e
"$GATE" --repo "$repo" --pr-author-language unknown --pr-description-file "$pr_zh" --message "fix(language): wire commit message language gate" >/dev/null 2>&1
rc=$?
set -e
assert_rc "未知 author fallback PR description zh-TW 擋英文 subject" "$rc" "2"

set +e
"$GATE" --repo "$repo" --pr-author-language en --message "fix(language): wire commit message language gate" >/dev/null 2>&1
rc=$?
set -e
assert_rc "英文 PR author 放行英文 subject" "$rc" "0"

set +e
"$GATE" --repo "$repo" --message "feat(scope): DP-051 調整 gate" >/dev/null 2>&1
rc=$?
set -e
assert_rc "conventional token + ticket + 中文 prose pass" "$rc" "0"

set +e
"$GATE" --repo "$repo" --command "git commit -m 'fix(language): wire commit message language gate'" >/dev/null 2>&1
rc=$?
set -e
assert_rc "command parser 擋英文 -m subject" "$rc" "2"

set +e
"$GATE" --repo "$repo" --command "git commit -F '$msg_file'" >/dev/null 2>&1
rc=$?
set -e
assert_rc "command parser 擋英文 -F file" "$rc" "2"

printf '\n=== commit-language selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
