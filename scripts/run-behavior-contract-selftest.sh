#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="$(mktemp -d -t polaris-behavior-selftest.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

write_task() {
  local file="$1"
  local repo="$2"
  local ticket="$3"
  local mode="$4"
  local baseline_ref="$5"
  local allowed="$6"

  cat >"$file" <<EOF
---
title: "Work Order - T1: behavior fixture (1 pt)"
description: "Behavior contract fixture."
depends_on: []
verification:
  behavior_contract:
    applies: true
    mode: ${mode}
    source_of_truth: existing_behavior
    fixture_policy: mockoon_required
    baseline_ref: ${baseline_ref}
    flow: "scripts/behavior-flow.sh"
    flow_script: "scripts/behavior-flow.sh"
    assertions:
      - "state matches"
    allowed_differences: ${allowed}
---

# T1: behavior fixture (1 pt)

> Source: DP-109 | Task: ${ticket} | JIRA: N/A | Repo: ${repo}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-109 |
| Task ID | ${ticket} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/${ticket} |
| Task branch | task/${ticket} |
| Depends on | N/A |
| References to load | - behavior-contract |

## 目標

Behavior contract fixture。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| scripts/behavior-flow.sh | test | fixture only |

## Allowed Files

- scripts/behavior-flow.sh

## 估點理由

1 pt - fixture。

## 測試計畫（code-level）

- fixture。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
EOF
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "Polaris Selftest"
  cat >"$repo/scripts/behavior-flow.sh" <<'EOF'
set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
value="$(cat behavior-source.txt)"
printf '{"value":"%s"}\n' "$value" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json"
printf 'png:%s\n' "$value" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"
printf 'webm:%s\n' "$value" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/video.webm"
EOF
  chmod +x "$repo/scripts/behavior-flow.sh"
  printf 'before\n' >"$repo/behavior-source.txt"
  git -C "$repo" add .
  git -C "$repo" commit -qm "baseline"
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"$WORKDIR/$label.out" 2>"$WORKDIR/$label.err"; then
    echo "FAIL: expected failure for $label" >&2
    cat "$WORKDIR/$label.out" >&2
    cat "$WORKDIR/$label.err" >&2
    exit 1
  fi
}

expect_pass() {
  local label="$1"
  shift
  if ! "$@" >"$WORKDIR/$label.out" 2>"$WORKDIR/$label.err"; then
    echo "FAIL: expected pass for $label" >&2
    cat "$WORKDIR/$label.out" >&2
    cat "$WORKDIR/$label.err" >&2
    exit 1
  fi
}

repo_pass="$WORKDIR/pass-repo"
make_repo "$repo_pass"
task_pass="$WORKDIR/T1-pass.md"
write_task "$task_pass" "$(basename "$repo_pass")" "DP-109-T1" "parity" "HEAD" "[]"
expect_pass "baseline-pass" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_pass" --mode baseline --repo "$repo_pass" --ticket DP-109-T1
expect_pass "compare-pass" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_pass" --mode compare --repo "$repo_pass" --ticket DP-109-T1

head_pass="$(git -C "$repo_pass" rev-parse HEAD)"
printf '{"ticket":"DP-109-T1","head_sha":"%s","writer":"run-verify-command.sh","exit_code":0,"at":"2026-05-05T00:00:00Z"}\n' "$head_pass" \
  >"/tmp/polaris-verified-DP-109-T1-${head_pass}.json"
expect_pass "gate-pass" bash "$ROOT/scripts/gates/gate-evidence.sh" --repo "$repo_pass" --ticket DP-109-T1 --task-md "$task_pass"

repo_drift="$WORKDIR/drift-repo"
make_repo "$repo_drift"
printf 'after\n' >"$repo_drift/behavior-source.txt"
git -C "$repo_drift" add behavior-source.txt
git -C "$repo_drift" commit -qm "after"
task_drift="$WORKDIR/T1-drift.md"
write_task "$task_drift" "$(basename "$repo_drift")" "DP-109-T2" "parity" "HEAD~1" "[]"

expect_fail "compare-missing-baseline" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_drift" --mode compare --repo "$repo_drift" --ticket DP-109-T2
expect_pass "baseline-temp-worktree" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_drift" --mode baseline --repo "$repo_drift" --ticket DP-109-T2
expect_fail "compare-drift" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_drift" --mode compare --repo "$repo_drift" --ticket DP-109-T2

task_hybrid="$WORKDIR/T1-hybrid.md"
write_task "$task_hybrid" "$(basename "$repo_drift")" "DP-109-T3" "hybrid" "HEAD~1" '["intentional fixture delta"]'
expect_pass "hybrid-baseline" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_hybrid" --mode baseline --repo "$repo_drift" --ticket DP-109-T3
expect_pass "hybrid-compare" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_hybrid" --mode compare --repo "$repo_drift" --ticket DP-109-T3

head_hybrid="$(git -C "$repo_drift" rev-parse HEAD)"
printf '{"ticket":"DP-109-T3","head_sha":"%s","writer":"run-verify-command.sh","exit_code":0,"at":"2026-05-05T00:00:00Z"}\n' "$head_hybrid" \
  >"/tmp/polaris-verified-DP-109-T3-${head_hybrid}.json"
expect_pass "hybrid-gate-pass" bash "$ROOT/scripts/gates/gate-evidence.sh" --repo "$repo_drift" --ticket DP-109-T3 --task-md "$task_hybrid"

task_gate_block="$WORKDIR/T1-gate-block.md"
write_task "$task_gate_block" "$(basename "$repo_drift")" "DP-109-T4" "pm_flow" "none" "[]"
printf '{"ticket":"DP-109-T4","head_sha":"%s","writer":"run-verify-command.sh","exit_code":0,"at":"2026-05-05T00:00:00Z"}\n' "$head_hybrid" \
  >"/tmp/polaris-verified-DP-109-T4-${head_hybrid}.json"
expect_fail "gate-missing-behavior" bash "$ROOT/scripts/gates/gate-evidence.sh" --repo "$repo_drift" --ticket DP-109-T4 --task-md "$task_gate_block"

echo "PASS: behavior contract runner selftest"
