#!/usr/bin/env bash
# polaris-pr-create-selftest.sh — 驗證 PR wrapper 的 metadata、驗證與指派交付。
#
# 使用隔離 Git fixture，確認 writeback 只在 report 與 durable evidence 完整後標示 PASS。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/polaris-pr-create.sh"

TMPROOT="$(mktemp -d -t polaris-pr-create-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_count=0
fail_count=0

ok() {
  printf 'ok %s\n' "$1"
  pass_count=$((pass_count + 1))
}

fail() {
  printf 'not ok %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    ok "$label"
  else
    fail "$label"
    printf 'expected to contain: %s\nactual:\n%s\n' "$needle" "$haystack" >&2
  fi
}

write_task() {
  local workspace="$1"
  local task_md="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-154-pr-create-selftest/tasks/T1/index.md"
  mkdir -p "$(dirname "$task_md")"
  cat > "$task_md" <<'EOF'
---
title: "DP-154 T1: PR 交付 selftest"
description: "驗證 PR create wrapper 自動寫入 deliverable metadata 與 verify report。"
status: PLANNED
verification:
  behavior_contract:
    applies: false
    reason: "selftest static task"
depends_on: []
---

# T1: PR 交付 selftest (1 pt)

> Source: DP-154 | Task: DP-154-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-154 |
| Work item ID | DP-154-T1 |
| Task ID | DP-154-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-154-T1-pr-create-selftest |
| Task branch | task/DP-154-T1-pr-create-selftest |
| Depends on | N/A |
| References to load | - `scripts/polaris-pr-create.sh` |

## Verification Handoff

Selftest fixture。

## 目標

驗證 PR create wrapper 會自動寫入 task deliverable metadata 與 verify report。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/polaris-pr-create.sh` | 修改 | selftest fixture |

## Allowed Files

- `scripts/polaris-pr-create.sh`

## 估點理由

1 pt - selftest fixture。

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| AC1：自動寫 deliverable | `scripts/polaris-pr-create.sh` | PR wrapper | selftest |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | changed files in Allowed Files | engineering |
| test | yes | selftest PASS | engineering |
| verify | yes | deliverable and report written | engineering |
| ci-local | no | N/A fixture | planner decision |

## 測試計畫（code-level）

- 執行 PR wrapper selftest。

## Test Command

```bash
echo ok
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo ok
```
EOF
  printf '%s\n' "$task_md"
}

write_verify_evidence() {
  local repo="$1"
  local ticket="$2"
  local head_sha="$3"
  local evidence="$repo/.polaris/evidence/verify/polaris-verified-${ticket}-${head_sha}.json"
  mkdir -p "$(dirname "$evidence")"
  cat > "$evidence" <<EOF
{
  "ticket": "${ticket}",
  "head_sha": "${head_sha}",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "effective_command": "echo ok",
  "verification_mode": "primary",
  "at": "2026-05-14T00:00:00Z"
}
EOF
}

run_auto_assign_case() {
  local label="auto-assign-config-user"
  local parent="$TMPROOT/$label"
  local repo="$parent/repo"
  local mockbin="$parent/bin"
  local edit_args_file="$parent/edit-args.txt"
  local out=""
  local rc=0

  mkdir -p "$repo" "$mockbin"
cat > "$parent/workspace-config.yaml" <<'EOF'
language: zh-TW
user:
  github_username: "cfg-user"
projects:
  - name: repo
    repo: demo/example
    delivery:
      pr_review_label:
        policy: required
        labels:
          - "👀 need review"
          - ":eyes: need review"
EOF

  git init -q -b main "$repo"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.com"
  printf 'fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "base"
  git -C "$repo" checkout -q -b task/selftest

  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "pr" && "\$2" == "create" ]]; then
  printf 'https://github.com/demo/example/pull/123\n'
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "edit" ]]; then
  printf '%s\n' "\$*" >> "$edit_args_file"
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "user" ]]; then
  printf 'fallback-user\n'
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "repos/demo/example/issues/123/assignees" ]]; then
  printf '%s\n' "https://github.com/demo/example/pull/123 --add-assignee cfg-user" >> "$edit_args_file"
  printf '{"assignees":[{"login":"cfg-user"}]}\n'
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "repos/demo/example/issues/123" ]]; then
  printf '{"assignees":[{"login":"cfg-user"}]}\n'
  exit 0
fi
printf 'unexpected gh call: %s\n' "\$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  set +e
  out="$(PATH="$mockbin:$PATH" bash "$WRAPPER" --repo "$repo" --skip-gates --base main --title "fixture" --body "fixture" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    ok "$label rc"
  else
    fail "$label rc"
    printf '%s\n' "$out" >&2
  fi
  assert_contains "$label output" "$out" "PR assigned to cfg-user"
  assert_contains "$label output label" "$out" "PR labeled '👀 need review'"
  assert_contains "$label edit-args" "$(cat "$edit_args_file")" "https://github.com/demo/example/pull/123 --add-assignee cfg-user"
  assert_contains "$label edit-label" "$(cat "$edit_args_file")" "https://github.com/demo/example/pull/123 --add-label 👀 need review"
}

run_task_writeback_case() {
  local label="task-deliverable-writeback"
  local parent="$TMPROOT/$label"
  local workspace="$parent/workspace"
  local repo="$workspace/repo"
  local mockbin="$parent/bin"
  local edit_args_file="$parent/edit-args.txt"
  local task_md=""
  local head_sha=""
  local out=""
  local rc=0

  mkdir -p "$repo" "$mockbin"
  cat > "$workspace/workspace-config.yaml" <<'EOF'
language: zh-TW
user:
  github_username: "cfg-user"
projects:
  - name: repo
    repo: demo/example
EOF

  git init -q -b main "$repo"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.com"
  printf 'fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "base"
  git -C "$repo" checkout -q -b task/DP-154-T1-pr-create-selftest
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$workspace")"
  write_verify_evidence "$repo" "DP-154-T1" "$head_sha"

  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "pr" && "\$2" == "create" ]]; then
  printf 'https://github.com/demo/example/pull/154\n'
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "edit" ]]; then
  printf '%s\n' "\$*" >> "$edit_args_file"
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "user" ]]; then
  printf 'fallback-user\n'
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "repos/demo/example/issues/154/assignees" ]]; then
  printf '%s\n' "https://github.com/demo/example/pull/154 --add-assignee cfg-user" >> "$edit_args_file"
  printf '{"assignees":[{"login":"cfg-user"}]}\n'
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "repos/demo/example/issues/154" ]]; then
  printf '{"assignees":[{"login":"cfg-user"}]}\n'
  exit 0
fi
printf 'unexpected gh call: %s\n' "\$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  set +e
  out="$(POLARIS_SPECS_ROOT="$workspace/docs-manager/src/content/docs/specs" PATH="$mockbin:$PATH" bash "$WRAPPER" --repo "$repo" --skip-gates --base main --title "fixture" --body "fixture" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    ok "$label rc"
  else
    fail "$label rc"
    printf '%s\n' "$out" >&2
  fi
  assert_contains "$label output" "$out" "delivery metadata, verification, and verify report written for DP-154-T1@$head_sha"
  assert_contains "$label deliverable url" "$(cat "$task_md")" "pr_url: https://github.com/demo/example/pull/154"
  assert_contains "$label deliverable head" "$(cat "$task_md")" "head_sha: $head_sha"
  assert_contains "$label deliverable verification" "$(cat "$task_md")" "status: PASS"
  if [[ "$(grep -c '^deliverable:' "$task_md")" == "1" ]]; then
    ok "$label deliverable idempotent count"
  else
    fail "$label deliverable idempotent count"
  fi
  local report_path
  report_path="$(dirname "$task_md")/verify-report.md"
  if [[ -f "$report_path" ]]; then
    ok "$label report exists"
    assert_contains "$label report ticket" "$(cat "$report_path")" "DP-154-T1"
    assert_contains "$label report head" "$(cat "$report_path")" "$head_sha"
  else
    fail "$label report exists"
  fi
}

run_remote_assignee_empty_case() {
  local label="remote-assignee-empty-blocks"
  local parent="$TMPROOT/$label"
  local repo="$parent/repo"
  local mockbin="$parent/bin"
  local edit_args_file="$parent/edit-args.txt"
  local out=""
  local rc=0

  mkdir -p "$repo" "$mockbin"
  cat > "$parent/workspace-config.yaml" <<'EOF'
language: zh-TW
user:
  github_username: "cfg-user"
projects:
  - name: repo
    repo: demo/example
EOF

  git init -q -b main "$repo"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.com"
  printf 'fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "base"
  git -C "$repo" checkout -q -b task/selftest

  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "pr" && "\$2" == "create" ]]; then
  printf 'https://github.com/demo/example/pull/160\n'
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "edit" ]]; then
  printf '%s\n' "\$*" >> "$edit_args_file"
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "repos/demo/example/issues/160" ]]; then
  printf '{"assignees":[]}\n'
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "repos/demo/example/issues/160/assignees" ]]; then
  printf '%s\n' "https://github.com/demo/example/pull/160 --add-assignee cfg-user" >> "$edit_args_file"
  printf '{"assignees":[{"login":"cfg-user"}]}\n'
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "user" ]]; then
  printf 'fallback-user\n'
  exit 0
fi
printf 'unexpected gh call: %s\n' "\$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  set +e
  out="$(PATH="$mockbin:$PATH" bash "$WRAPPER" --repo "$repo" --skip-gates --base main --title "fixture" --body "fixture" 2>&1)"
  rc=$?
  set -e

  assert_contains "$label edit-attempted" "$(cat "$edit_args_file")" "https://github.com/demo/example/pull/160 --add-assignee cfg-user"
  if [[ "$rc" -eq 2 ]]; then
    ok "$label rc"
  else
    fail "$label rc"
    printf '%s\n' "$out" >&2
  fi
  assert_contains "$label output" "$out" "final PR assignee metadata is empty"
  assert_contains "$label remediation" "$out" "gh pr edit 160 --repo demo/example --add-assignee cfg-user"
}

run_auto_assign_case
run_task_writeback_case
run_remote_assignee_empty_case

if [[ "$fail_count" -ne 0 ]]; then
  printf '\n=== polaris-pr-create selftest: %s PASS / %s FAIL ===\n' "$pass_count" "$fail_count" >&2
  exit 1
fi

printf '\n=== polaris-pr-create selftest: %s/%s PASS ===\n' "$pass_count" "$pass_count"
