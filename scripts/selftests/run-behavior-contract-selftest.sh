#!/usr/bin/env bash
# Purpose: Selftest for scripts/run-behavior-contract.sh — exercises baseline /
#   compare / drift / hybrid / health / assertion-coverage / NOT_COVERED route-back
#   and the gate-evidence integration (behavioral task missing behavior evidence).
# Inputs:  none (self-contained git fixtures under a mktemp workdir).
# Outputs: "PASS: ..." on success (exit 0); "FAIL: ..." diagnostic + exit 1 otherwise.
# Side effects: writes /tmp/polaris-behavior-* and /tmp/polaris-verified-* markers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_VERIFY="$ROOT/scripts/run-verify-command.sh"
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
      - "optional carousel click covered"
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

write_product_task() {
  local file="$1"
  local repo="$2"
  local task_id="$3"
  local jira_key="$4"
  local mode="$5"
  local baseline_ref="$6"
  local allowed="$7"

  cat >"$file" <<EOF
---
title: "Work Order - ${task_id}: behavior fixture (1 pt)"
description: "Behavior contract product fixture."
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
      - "optional carousel click covered"
    allowed_differences: ${allowed}
---

# ${task_id}: behavior fixture (1 pt)

> Epic: DEMO-478 | JIRA: ${jira_key} | Repo: ${repo}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Task ID | ${task_id} |
| Task JIRA key | ${jira_key} |
| Parent Epic | DEMO-478 |
| JIRA key | ${jira_key} |
| Test sub-tasks | N/A |
| AC 驗收單 | N/A |
| Base branch | main |
| Branch chain | main -> task/${jira_key}-${task_id} |
| Task branch | task/${jira_key}-${task_id} |
| Depends on | N/A |
| References to load | - behavior-contract |

## 目標

Behavior contract product fixture。

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
  printf '.polaris/\n' >>"$repo/.git/info/exclude"
  cat >"$repo/scripts/behavior-flow.sh" <<'EOF'
set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
value="$(cat behavior-source.txt)"
printf '{"value":"%s","assertion_results":[{"assertion":"state matches","status":"PASS","source":"behavior-state.json"}]}\n' "$value" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json"
printf 'png:%s\n' "$value" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"
printf 'webm:%s\n' "$value" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/video.webm"
EOF
  chmod +x "$repo/scripts/behavior-flow.sh"
  printf 'before\n' >"$repo/behavior-source.txt"
  git -C "$repo" add .
  git -C "$repo" commit -qm "baseline"
}

make_health_repo() {
  local repo="$1"
  local body_has_text="$2"
  local has_nuxt_root="$3"
  local status_code="${4:-200}"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "Polaris Selftest"
  printf '.polaris/\n' >>"$repo/.git/info/exclude"
  cat >"$repo/scripts/behavior-flow.sh" <<EOF
set -euo pipefail
mkdir -p "\$POLARIS_BEHAVIOR_OUTPUT_DIR"
cat >"\$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json" <<'JSON'
{
  "comparableState": {
    "actions": ["page-load"],
    "flow": "health-fixture",
    "interactionResult": {"optionalClickAttempted": false},
    "relevantConsoleErrors": [],
    "stateScope": "runtime_health",
    "targets": [
      {
        "health": {
          "bodyHasText": ${body_has_text},
          "bodyTextBucket": "empty",
          "hasNuxtRoot": ${has_nuxt_root}
        },
        "selectorPresence": {},
        "status": ${status_code},
        "targetPath": "/fixture"
      }
    ],
    "viewport": "desktop"
  },
  "diagnostics": {},
  "mode": "baseline",
  "stateScope": "runtime_health"
}
JSON
printf 'health fixture\n' >"\$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"
EOF
  chmod +x "$repo/scripts/behavior-flow.sh"
  printf 'fixture\n' >"$repo/behavior-source.txt"
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

write_verify_evidence() {
  local task_md="$1"
  local repo="$2"
  local ticket="$3"

  if ! bash "$RUN_VERIFY" --task-md "$task_md" --repo "$repo" --ticket "$ticket" >/dev/null 2>&1; then
    echo "FAIL: run-verify-command could not mint current identity evidence for $ticket" >&2
    exit 1
  fi
}

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

repo_pass="$WORKDIR/pass-repo"
make_repo "$repo_pass"
task_pass="$WORKDIR/T1-pass.md"
write_task "$task_pass" "$(basename "$repo_pass")" "DP-109-T1" "parity" "HEAD" "[]"
expect_pass "baseline-pass" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_pass" --mode baseline --repo "$repo_pass" --ticket DP-109-T1
expect_pass "compare-pass" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_pass" --mode compare --repo "$repo_pass" --ticket DP-109-T1

head_pass="$(git -C "$repo_pass" rev-parse HEAD)"
pass_behavior_evidence="$(find_behavior_evidence "$repo_pass" "DP-109-T1" "$head_pass")"
python3 - "$pass_behavior_evidence" <<'PY'
import hashlib, json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
results = {item["assertion"]: item["status"] for item in data["assertion_results"]}
assert results["state matches"] == "PASS"
assert results["optional carousel click covered"] == "NOT_COVERED"
assert data["assertion_summary"]["PASS"] == 1
assert data["assertion_summary"]["NOT_COVERED"] == 1
for key, hash_key in (("stdout_file", "stdout_hash"), ("stderr_file", "stderr_hash")):
    path = data[key]
    assert path and path != "N/A", f"{key} missing"
    with open(path, "rb") as handle:
        assert hashlib.sha256(handle.read()).hexdigest() == data[hash_key], f"{hash_key} mismatch"
PY
write_verify_evidence "$task_pass" "$repo_pass" "DP-109-T1"
expect_pass "gate-pass" bash "$ROOT/scripts/gates/gate-evidence.sh" --repo "$repo_pass" --ticket DP-109-T1 --task-md "$task_pass"

report_dir="$WORKDIR/report"
mkdir -p "$report_dir"
expect_pass "write-report-assertion-coverage" bash "$ROOT/scripts/write-task-verify-report.sh" \
  --repo "$repo_pass" \
  --ticket DP-109-T1 \
  --task-md "$task_pass" \
  --head-sha "$head_pass" \
  --status PASS \
  --output "$report_dir/verify-report.md"
grep -q "optional carousel click covered" "$report_dir/verify-report.md"
grep -q "NOT_COVERED" "$report_dir/verify-report.md"
expect_pass "write-report-language-gate" bash "$ROOT/scripts/validate-language-policy.sh" --blocking --mode artifact --workspace-root "$ROOT" "$report_dir/verify-report.md"

repo_manual="$WORKDIR/manual-repo"
make_repo "$repo_manual"
cat >"$repo_manual/scripts/behavior-flow.sh" <<'EOF'
set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
cat >"$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json" <<'JSON'
{
  "value": "manual",
  "assertion_results": [
    {"assertion": "state matches", "status": "PASS", "source": "behavior-state.json"},
    {"assertion": "optional carousel click covered", "status": "MANUAL_REQUIRED", "source": "manual qa handoff", "note": "Carousel click requires human device verification."}
  ]
}
JSON
printf 'manual png\n' >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"
EOF
git -C "$repo_manual" add scripts/behavior-flow.sh
git -C "$repo_manual" commit -qm "manual assertion"
task_manual="$WORKDIR/T1-manual.md"
write_task "$task_manual" "$(basename "$repo_manual")" "DP-109-T8" "pm_flow" "none" "[]"
expect_pass "manual-required-compare" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_manual" --mode compare --repo "$repo_manual" --ticket DP-109-T8
head_manual="$(git -C "$repo_manual" rev-parse HEAD)"
write_verify_evidence "$task_manual" "$repo_manual" "DP-109-T8"
expect_pass "manual-required-gate-pass" bash "$ROOT/scripts/gates/gate-evidence.sh" --repo "$repo_manual" --ticket DP-109-T8 --task-md "$task_manual"
manual_report_dir="$WORKDIR/manual-report"
mkdir -p "$manual_report_dir"
expect_pass "manual-required-report" bash "$ROOT/scripts/write-task-verify-report.sh" \
  --repo "$repo_manual" \
  --ticket DP-109-T8 \
  --task-md "$task_manual" \
  --head-sha "$head_manual" \
  --status PASS \
  --output "$manual_report_dir/verify-report.md"
grep -q "MANUAL_REQUIRED" "$manual_report_dir/verify-report.md"
expect_pass "manual-required-report-language-gate" bash "$ROOT/scripts/validate-language-policy.sh" --blocking --mode artifact --workspace-root "$ROOT" "$manual_report_dir/verify-report.md"

repo_invalid="$WORKDIR/invalid-assertion-repo"
make_repo "$repo_invalid"
cat >"$repo_invalid/scripts/behavior-flow.sh" <<'EOF'
set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
cat >"$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json" <<'JSON'
{
  "value": "invalid",
  "assertion_results": [
    {"assertion": "state matches", "status": "MAYBE", "source": "behavior-state.json"},
    {"assertion": "optional carousel click covered", "status": "PASS", "source": "behavior-state.json"}
  ]
}
JSON
printf 'invalid png\n' >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"
EOF
git -C "$repo_invalid" add scripts/behavior-flow.sh
git -C "$repo_invalid" commit -qm "invalid assertion"
task_invalid="$WORKDIR/T1-invalid-assertion.md"
write_task "$task_invalid" "$(basename "$repo_invalid")" "DP-109-T9" "pm_flow" "none" "[]"
expect_fail "invalid-assertion-status" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_invalid" --mode compare --repo "$repo_invalid" --ticket DP-109-T9

repo_stale="$WORKDIR/stale-artifact-repo"
make_repo "$repo_stale"
task_stale="$WORKDIR/T1-stale-artifact.md"
write_task "$task_stale" "$(basename "$repo_stale")" "DP-109-T10" "pm_flow" "none" "[]"
expect_pass "stale-artifact-seed" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_stale" --mode compare --repo "$repo_stale" --ticket DP-109-T10
cat >"$repo_stale/scripts/behavior-flow.sh" <<'EOF'
set -euo pipefail
echo "new stdout before failure"
echo "new stderr failure" >&2
exit 1
EOF
expect_fail "stale-artifact-not-reused" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_stale" --mode compare --repo "$repo_stale" --ticket DP-109-T10
head_stale="$(git -C "$repo_stale" rev-parse HEAD)"
stale_evidence="$(find_behavior_evidence "$repo_stale" "DP-109-T10" "$head_stale")"
python3 - "$stale_evidence" <<'PY'
import hashlib, json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "FAIL"
assert data["exit_code"] == 1
assert data["state_file"] == "N/A", data["state_file"]
results = {item["assertion"]: item["status"] for item in data["assertion_results"]}
assert results["state matches"] == "NOT_COVERED"
assert results["optional carousel click covered"] == "NOT_COVERED"
assert data["assertion_summary"]["PASS"] == 0
assert data["assertion_summary"]["NOT_COVERED"] == 2
for key, hash_key, expected in (
    ("stdout_file", "stdout_hash", "new stdout before failure"),
    ("stderr_file", "stderr_hash", "new stderr failure"),
):
    path = data[key]
    assert path and path != "N/A", f"{key} missing"
    with open(path, "rb") as handle:
        payload = handle.read()
    assert expected.encode() in payload, payload
    assert hashlib.sha256(payload).hexdigest() == data[hash_key], f"{hash_key} mismatch"
PY

repo_identity="$WORKDIR/identity-repo"
make_repo "$repo_identity"
task_identity="$WORKDIR/T8e-identity.md"
write_product_task "$task_identity" "$(basename "$repo_identity")" "T8e" "DEMO-4114" "parity" "HEAD" "[]"
expect_pass "jira-key-default-baseline" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_identity" --mode baseline --repo "$repo_identity"
head_identity="$(git -C "$repo_identity" rev-parse HEAD)"
jira_key_evidence="$(find_behavior_evidence "$repo_identity" "DEMO-4114" "$head_identity")"
if [[ -z "$jira_key_evidence" ]]; then
  echo "FAIL: expected Task JIRA key behavior evidence namespace" >&2
  exit 1
fi

expect_pass "task-id-fallback-baseline" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_pass" --mode baseline --repo "$repo_pass"
task_id_evidence="$(find_behavior_evidence "$repo_pass" "DP-109-T1" "$head_pass")"
if [[ -z "$task_id_evidence" ]]; then
  echo "FAIL: expected task id behavior evidence namespace fallback" >&2
  exit 1
fi

expect_pass "ticket-override-baseline" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_pass" --mode baseline --repo "$repo_pass" --ticket OVERRIDE-TICKET
override_evidence="$(find_behavior_evidence "$repo_pass" "OVERRIDE-TICKET" "$head_pass")"
if [[ -z "$override_evidence" ]]; then
  echo "FAIL: expected explicit --ticket behavior evidence namespace" >&2
  exit 1
fi

repo_unhealthy="$WORKDIR/unhealthy-repo"
make_health_repo "$repo_unhealthy" "false" "false"
task_unhealthy="$WORKDIR/T1-unhealthy.md"
write_task "$task_unhealthy" "$(basename "$repo_unhealthy")" "DP-109-T6" "parity" "HEAD" "[]"
expect_fail "baseline-unhealthy-runtime" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_unhealthy" --mode baseline --repo "$repo_unhealthy" --ticket DP-109-T6
head_unhealthy="$(git -C "$repo_unhealthy" rev-parse HEAD)"
unhealthy_evidence="$(find_behavior_evidence "$repo_unhealthy" "DP-109-T6" "$head_unhealthy")"
python3 - "$unhealthy_evidence" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "FAIL"
assert data["comparison"]["kind"] == "runtime_health"
assert "target[0].health.bodyHasText=false" in data["health_failures"]
assert "target[0].health.hasNuxtRoot=false" in data["health_failures"]
PY

task_unhealthy_compare="$WORKDIR/T1-unhealthy-compare.md"
write_task "$task_unhealthy_compare" "$(basename "$repo_unhealthy")" "DP-109-T7" "pm_flow" "none" "[]"
expect_fail "compare-unhealthy-runtime" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_unhealthy_compare" --mode compare --repo "$repo_unhealthy" --ticket DP-109-T7
unhealthy_compare_evidence="$(find_behavior_evidence "$repo_unhealthy" "DP-109-T7" "$head_unhealthy")"
python3 - "$unhealthy_compare_evidence" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "FAIL"
assert data["comparison"]["kind"] == "runtime_health"
assert "target[0].health.bodyHasText=false" in data["health_failures"]
assert "target[0].health.hasNuxtRoot=false" in data["health_failures"]
PY

repo_drift="$WORKDIR/drift-repo"
make_repo "$repo_drift"
printf 'after\n' >"$repo_drift/behavior-source.txt"
# DP-417 T8 reconcile: the gate-missing-behavior case must exercise a *behavioral*
# task that lacks its behavior evidence marker. Post-DP-294, a text-only HEAD delta
# is legitimately classified metadata_only and exempt from head_sha-bound evidence,
# so a .txt-only fixture would never reach the missing-evidence block. Include a
# real behavioral (.sh) delta in the HEAD commit so the classifier requires evidence.
printf '#!/usr/bin/env bash\necho after\n' >"$repo_drift/behavior-delta-after.sh"
git -C "$repo_drift" add behavior-source.txt behavior-delta-after.sh
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
write_verify_evidence "$task_hybrid" "$repo_drift" "DP-109-T3"
expect_pass "hybrid-gate-pass" bash "$ROOT/scripts/gates/gate-evidence.sh" --repo "$repo_drift" --ticket DP-109-T3 --task-md "$task_hybrid"

task_gate_block="$WORKDIR/T1-gate-block.md"
write_task "$task_gate_block" "$(basename "$repo_drift")" "DP-109-T4" "pm_flow" "none" "[]"
write_verify_evidence "$task_gate_block" "$repo_drift" "DP-109-T4"
expect_fail "gate-missing-behavior" bash "$ROOT/scripts/gates/gate-evidence.sh" --repo "$repo_drift" --ticket DP-109-T4 --task-md "$task_gate_block"

task_missing_flow_script="$WORKDIR/T1-missing-flow-script.md"
write_task "$task_missing_flow_script" "$(basename "$repo_drift")" "DP-109-T5" "parity" "HEAD~1" "[]"
sed -i.bak '/flow_script:/d' "$task_missing_flow_script"
rm -f "$task_missing_flow_script.bak"
expect_fail "mockoon-missing-flow-script" bash "$ROOT/scripts/run-behavior-contract.sh" --task-md "$task_missing_flow_script" --mode baseline --repo "$repo_drift" --ticket DP-109-T5

echo "PASS: behavior contract runner selftest"
