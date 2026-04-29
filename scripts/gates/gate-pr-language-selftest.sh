#!/usr/bin/env bash
set -euo pipefail

# scripts/gates/gate-pr-language-selftest.sh — selftest for gate-pr-language.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/gate-pr-language.sh"
TMPROOT="$(mktemp -d -t pr-language-selftest-XXXXXX)"
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

zh_body="$TMPROOT/zh.md"
cat > "$zh_body" <<'EOF'
## Description

這個 PR 補上 GitHub PR 文案送出前的語言 gate。

## Changed

- 新增共用 gate。
EOF

template_body="$TMPROOT/template-zh.md"
cat > "$template_body" <<'EOF'
## Description

這段說明是繁體中文。

## QA notes

無。
EOF

en_body="$TMPROOT/en.md"
cat > "$en_body" <<'EOF'
## Description

This pull request wires the GitHub pull request language gate before metadata is sent to GitHub.
EOF

set +e
"$GATE" --repo "$repo" --title "fix(language): 補上 PR 語言 gate" --body-file "$zh_body" >/dev/null 2>&1
rc=$?
set -e
assert_rc "中文 title/body passes" "$rc" "0"

set +e
"$GATE" --repo "$repo" --title "fix(language): 補上 PR 語言 gate" --body-file "$template_body" >/dev/null 2>&1
rc=$?
set -e
assert_rc "英文 template heading + 中文 prose passes" "$rc" "0"

set +e
"$GATE" --repo "$repo" --title "fix(language): 補上 PR 語言 gate" --body-file "$en_body" >/dev/null 2>&1
rc=$?
set -e
assert_rc "英文 body blocks" "$rc" "2"

set +e
"$GATE" --repo "$repo" --title "fix(language): wire pull request language gate" --body-file "$zh_body" >/dev/null 2>&1
rc=$?
set -e
assert_rc "英文 title blocks" "$rc" "2"

set +e
"$GATE" --repo "$repo" --command "gh pr edit 12 --title 'fix(language): wire pull request language gate' --body-file '$zh_body'" >/dev/null 2>&1
rc=$?
set -e
assert_rc "gh pr edit command title blocks" "$rc" "2"

set +e
"$GATE" --repo "$repo" --command "gh pr comment 12 --body-file '$en_body'" >/dev/null 2>&1
rc=$?
set -e
assert_rc "gh pr comment command body blocks" "$rc" "2"

printf '\n=== pr-language selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
