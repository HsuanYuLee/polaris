#!/usr/bin/env bash
set -euo pipefail

# scripts/gates/gate-pr-language-selftest.sh — selftest for gate-pr-language.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/gate-pr-language.sh"
TITLE_GATE="$SCRIPT_DIR/gate-pr-title.sh"
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

task_md="$TMPROOT/T1.md"
cat > "$task_md" <<'EOF'
---
title: "Work Order - T1: English title conflict (1 pt)"
description: "此工單描述 title conflict。"
---

# T1: English title conflict (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Task branch | task/DP-999-T1-title-conflict |
| Depends on | N/A |
EOF

set +e
"$TITLE_GATE" --repo "$repo" --task-md "$task_md" --title "[DP-999-T1] English title conflict" >"$TMPROOT/title-conflict.out" 2>"$TMPROOT/title-conflict.err"
rc=$?
set -e
assert_rc "title gate blocks expected title language conflict" "$rc" "2"

if grep -q "incompatible with workspace language policy" "$TMPROOT/title-conflict.err"; then
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  printf 'ok title gate conflict message\n'
else
  TOTAL=$((TOTAL + 1))
  printf 'not ok title gate conflict message missing\n' >&2
fi

printf '\n=== pr-language selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
