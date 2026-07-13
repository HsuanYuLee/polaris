#!/usr/bin/env bash
set -euo pipefail

# Purpose: Assert run-behavior-contract.sh emits a canonical NOT_COVERED
#          route-back marker (evidence-level status=NOT_COVERED + exit 2) when
#          behavior_contract.applies=true but there is no executable flow to
#          run, and does NOT emit NOT_COVERED when a runnable flow_script exists
#          (no false positive). DP-417 T2 / AC2.
# Inputs:  none (builds fixture repos + task.md under a temp WORKDIR)
# Outputs: exit 0 on PASS, exit 1 on FAIL; prints PASS/FAIL diagnostics
# Side effects: temp git repos + /tmp behavior evidence (removed on EXIT)

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKDIR="$(mktemp -d -t polaris-behavior-notcovered-selftest.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

# Description: run run-behavior-contract.sh and assert its exit code equals the
#              expected value; on mismatch dump captured stdout/stderr and fail.
# Args:        $1 = label, $2 = expected exit code, $3.. = command + args
# Side effects: writes $WORKDIR/$label.{out,err}
expect_exit_code() {
  local label="$1"
  local expected="$2"
  shift 2
  local rc=0
  "$@" >"$WORKDIR/$label.out" 2>"$WORKDIR/$label.err" || rc=$?
  if [[ "$rc" -ne "$expected" ]]; then
    echo "FAIL: $label expected exit $expected, got $rc" >&2
    cat "$WORKDIR/$label.out" >&2
    cat "$WORKDIR/$label.err" >&2
    exit 1
  fi
}

# Description: write a task.md whose behavior_contract has applies=true but no
#              executable flow (fixture_policy=static_only, no flow_script) so
#              run-behavior-contract.sh reaches the no-executable-flow branch.
# Args:        $1 = file, $2 = repo basename, $3 = ticket
write_not_covered_task() {
  local file="$1"
  local repo="$2"
  local ticket="$3"

  cat >"$file" <<EOF
---
title: "Work Order - ${ticket}: not-covered fixture (1 pt)"
description: "Behavior contract applies but no executable flow."
depends_on: []
verification:
  behavior_contract:
    applies: true
    mode: pm_flow
    source_of_truth: pm_flow
    fixture_policy: static_only
    baseline_ref: none
    flow: "assertions-only"
    assertions:
      - "state matches"
    allowed_differences: []
---

# ${ticket}: not-covered fixture (1 pt)

> Source: DP-417 | Task: ${ticket} | JIRA: N/A | Repo: ${repo}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-417 |
| Task ID | ${ticket} |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/${ticket} |

## 目標

No executable flow fixture。

## Allowed Files

- scripts/behavior-flow.sh

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
EOF
}

# Description: write a task.md whose behavior_contract has applies=true AND a
#              runnable flow_script (no-false-positive control).
# Args:        $1 = file, $2 = repo basename, $3 = ticket
write_runnable_task() {
  local file="$1"
  local repo="$2"
  local ticket="$3"

  cat >"$file" <<EOF
---
title: "Work Order - ${ticket}: runnable fixture (1 pt)"
description: "Behavior contract with runnable flow."
depends_on: []
verification:
  behavior_contract:
    applies: true
    mode: parity
    source_of_truth: existing_behavior
    fixture_policy: mockoon_required
    baseline_ref: HEAD
    flow: "scripts/behavior-flow.sh"
    flow_script: "scripts/behavior-flow.sh"
    assertions:
      - "state matches"
    allowed_differences: []
---

# ${ticket}: runnable fixture (1 pt)

> Source: DP-417 | Task: ${ticket} | JIRA: N/A | Repo: ${repo}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-417 |
| Task ID | ${ticket} |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/${ticket} |

## 目標

Runnable flow fixture。

## Allowed Files

- scripts/behavior-flow.sh

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
EOF
}

# Description: init a git repo with a runnable behavior-flow.sh (for the
#              no-false-positive control) and a source file.
# Args:        $1 = repo path
make_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "Polaris Selftest"
  cat >"$repo/scripts/behavior-flow.sh" <<'EOF'
set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
printf '{"value":"x","assertion_results":[{"assertion":"state matches","status":"PASS","source":"behavior-state.json"}]}\n' >"$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json"
printf 'png\n' >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"
printf 'webm\n' >"$POLARIS_BEHAVIOR_OUTPUT_DIR/video.webm"
EOF
  chmod +x "$repo/scripts/behavior-flow.sh"
  printf 'seed\n' >"$repo/behavior-source.txt"
  git -C "$repo" add .
  git -C "$repo" commit -qm "baseline"
}

# Description: init a bare git repo (no runnable flow) for the NOT_COVERED case.
# Args:        $1 = repo path
make_bare_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "Polaris Selftest"
  printf 'seed\n' >"$repo/seed.txt"
  git -C "$repo" add .
  git -C "$repo" commit -qm "baseline"
}

# Description: locate the behavior evidence marker for a ticket + head sha.
# Args:        $1 = repo, $2 = ticket, $3 = head sha
find_behavior_evidence() {
  local repo="$1"
  local ticket="$2"
  local head_sha="$3"
  local evidence=""
  evidence="$(find /tmp -maxdepth 1 -name "polaris-behavior-${ticket}-${head_sha}-*.json" -print -quit 2>/dev/null || true)"
  if [[ -n "$evidence" ]]; then
    printf '%s\n' "$evidence"
    return
  fi
  find "$repo/.polaris/evidence/behavior/$ticket" -maxdepth 1 -name "polaris-behavior-${ticket}-${head_sha}-*.json" -print -quit 2>/dev/null || true
}

# --- Case 1: applies=true, no executable flow → NOT_COVERED route-back --------
repo_nc="$WORKDIR/not-covered-repo"
make_bare_repo "$repo_nc"
task_nc="$WORKDIR/T-not-covered.md"
write_not_covered_task "$task_nc" "$(basename "$repo_nc")" "DP-417-T2NC"
expect_exit_code "not-covered-routeback" 2 \
  bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_nc" --mode compare --repo "$repo_nc" --ticket DP-417-T2NC

head_nc="$(git -C "$repo_nc" rev-parse HEAD)"
nc_evidence="$(find_behavior_evidence "$repo_nc" "DP-417-T2NC" "$head_nc")"
if [[ -z "$nc_evidence" ]]; then
  echo "FAIL: expected NOT_COVERED behavior evidence marker" >&2
  exit 1
fi
python3 - "$nc_evidence" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "NOT_COVERED", data["status"]
assert data["writer"] == "run-behavior-contract.sh", data["writer"]
assert data["comparison"]["status"] == "NOT_COVERED", data["comparison"]
# No silent assertions_only pass: no behavior-state.json should have been written.
assert data["state_file"] == "N/A", data["state_file"]
PY
# The former silent "assertions_only:true" state file must NOT be emitted.
if find "$repo_nc/.polaris/evidence/behavior/DP-417-T2NC" -name "behavior-state.json" 2>/dev/null | grep -q .; then
  if grep -rq "assertions_only" "$repo_nc/.polaris/evidence/behavior/DP-417-T2NC" 2>/dev/null; then
    echo "FAIL: NOT_COVERED case must not emit silent assertions_only state" >&2
    exit 1
  fi
fi

# --- Case 2: applies=true WITH runnable flow → normal PASS, no NOT_COVERED -----
repo_ok="$WORKDIR/runnable-repo"
make_repo "$repo_ok"
task_ok="$WORKDIR/T-runnable.md"
write_runnable_task "$task_ok" "$(basename "$repo_ok")" "DP-417-T2OK"
expect_exit_code "runnable-baseline" 0 \
  bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_ok" --mode baseline --repo "$repo_ok" --ticket DP-417-T2OK
expect_exit_code "runnable-compare" 0 \
  bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_ok" --mode compare --repo "$repo_ok" --ticket DP-417-T2OK

head_ok="$(git -C "$repo_ok" rev-parse HEAD)"
ok_evidence="$(find_behavior_evidence "$repo_ok" "DP-417-T2OK" "$head_ok")"
if [[ -z "$ok_evidence" ]]; then
  echo "FAIL: expected runnable behavior evidence marker" >&2
  exit 1
fi
python3 - "$ok_evidence" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "PASS", data["status"]
assert data["status"] != "NOT_COVERED"
assert data["comparison"]["status"] != "NOT_COVERED", data["comparison"]
PY

echo "PASS: behavior contract NOT_COVERED route-back selftest"
