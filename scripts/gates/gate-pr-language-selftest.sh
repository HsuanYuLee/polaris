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

resolver_root="$TMPROOT/router"
resolver_repo="$resolver_root/repo"
mkdir -p "$resolver_repo" "$resolver_root/acme" "$resolver_root/beta"
cat > "$resolver_root/workspace-config.yaml" <<EOF
language: zh-TW
companies:
  - name: acme
    base_dir: "$resolver_root/acme"
  - name: beta
    base_dir: "$resolver_root/beta"
EOF
cat > "$resolver_root/acme/workspace-config.yaml" <<'EOF'
projects:
  - name: repo
    delivery:
      pr_title:
        developer: "ACME/{TICKET}: {summary}"
    dev_environment:
      start_command: "true"
      ready_signal: "ready"
      base_url: "http://localhost:3000"
      health_check: "http://localhost:3000/health"
      requires: []
jira:
  projects:
    - key: ACME
github:
  org: acme-org
EOF
cat > "$resolver_root/beta/workspace-config.yaml" <<'EOF'
projects:
  - name: repo
    delivery:
      pr_title:
        developer: "BETA/{TICKET}: {summary}"
    dev_environment:
      start_command: "true"
      ready_signal: "ready"
      base_url: "http://localhost:3000"
      health_check: "http://localhost:3000/health"
      requires: []
jira:
  projects:
    - key: BETA
github:
  org: beta-org
EOF

resolver_task="$TMPROOT/T2.md"
cat > "$resolver_task" <<'EOF'
---
title: "Work Order - T2: Resolver title route (1 pt)"
description: "驗 shared resolver 能給 PR title gate 正確 company template。"
---

# T2: Resolver title route (1 pt)

> Source: SRC-000 | Task: SRC-000-T2 | JIRA: ACME-123 | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | task |
| Source ID | SRC-000 |
| Task JIRA key | ACME-123 |
| Task ID | SRC-000-T2 |
| JIRA key | ACME-123 |
| Test sub-tasks | N/A |
| AC 驗收單 | N/A |
| Base branch | main |
| Task branch | task/SRC-000-T2-resolver-title-route |
| Depends on | N/A |
EOF

set +e
POLARIS_WORKSPACE_CONFIG_ROOT="$resolver_root" \
  "$TITLE_GATE" --repo "$resolver_repo" --task-md "$resolver_task" --title "[ACME-123] Resolver title route" \
  >"$TMPROOT/title-resolver.out" 2>"$TMPROOT/title-resolver.err"
rc=$?
set -e
assert_rc "title gate uses shared resolver for company template" "$rc" "2"

if grep -q "ACME/ACME-123: Resolver title route" "$TMPROOT/title-resolver.err"; then
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  printf 'ok title gate resolver expected title\n'
else
  TOTAL=$((TOTAL + 1))
  printf 'not ok title gate resolver expected title missing\n' >&2
fi

resolver_fail_task="$TMPROOT/T3.md"
cat > "$resolver_fail_task" <<'EOF'
---
title: "Work Order - T3: Resolver fail-stop route (1 pt)"
description: "驗證 shared resolver 失敗時 title gate 不得 fallback。"
---

# T3: Resolver fail-stop route (1 pt)

> Source: SRC-000 | Task: SRC-000-T3 | JIRA: ZZZ-123 | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | task |
| Source ID | SRC-000 |
| Task JIRA key | ZZZ-123 |
| Task ID | SRC-000-T3 |
| JIRA key | ZZZ-123 |
| Test sub-tasks | N/A |
| AC 驗收單 | N/A |
| Base branch | main |
| Task branch | task/SRC-000-T3-resolver-fail-stop |
| Depends on | N/A |
EOF

set +e
POLARIS_WORKSPACE_CONFIG_ROOT="$resolver_root" \
  "$TITLE_GATE" --repo "$resolver_repo" --task-md "$resolver_fail_task" --title "[ZZZ-123] Resolver fail-stop route" \
  >"$TMPROOT/title-resolver-fail.out" 2>"$TMPROOT/title-resolver-fail.err"
rc=$?
set -e
assert_rc "title gate blocks when shared resolver cannot map ticket" "$rc" "2"

if grep -q "cannot resolve company-specific PR title template for ZZZ-123" "$TMPROOT/title-resolver-fail.err"; then
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  printf 'ok title gate resolver fail-stop message\n'
else
  TOTAL=$((TOTAL + 1))
  printf 'not ok title gate resolver fail-stop message missing\n' >&2
fi

printf '\n=== pr-language selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
