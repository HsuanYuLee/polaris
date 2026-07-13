#!/usr/bin/env bash
# Purpose: DP-417 T8 — executable selftest for the VR/behavior verification
#   trustworthiness gate (AC8 / AC10 / AC-NEG3 / AC-NEG5 / AC-N1). Proves, via
#   run-behavior-contract.sh, that a before-after fidelity claim (applies=true,
#   mode parity/hybrid) fails closed on impersonation (hard-coded state_hash,
#   placeholder / no real render) and on confounded PASS (replaces_existing while
#   the replaced old source still exists), and PASSES only when a real render backs
#   the comparison and the test subject is isolated. AC-N1: applies=false and
#   non-fidelity modes are unaffected (no false positives).
# Inputs:  none (self-contained git fixtures under a mktemp workdir).
# Outputs: "PASS: ..." on success (exit 0); a "FAIL: ..." diagnostic + exit 1 otherwise.
# Side effects: writes /tmp/polaris-behavior-* evidence markers for fixture tickets.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/scripts/run-behavior-contract.sh"
WORKDIR="$(mktemp -d -t polaris-vrbehavior-trust.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

# Real 1x1 PNG (valid signature + IHDR/IDAT/IEND), base64-encoded.
REAL_PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pOKAAAAAElFTkSuQmCC"

write_task() {
  # write_task <file> <repo> <ticket> <mode> <baseline_ref> <replaces> <replaced_paths_yaml>
  local file="$1" repo="$2" ticket="$3" mode="$4" baseline_ref="$5" replaces="$6" replaced="$7"
  cat >"$file" <<EOF
---
title: "Work Order - ${ticket}: trust fixture (1 pt)"
description: "Trustworthiness gate fixture."
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
    assertions: []
    allowed_differences: []
    replaces_existing: ${replaces}
    replaced_paths: ${replaced}
---

# ${ticket}: trust fixture (1 pt)

> Source: DP-417 | Task: ${ticket} | JIRA: N/A | Repo: ${repo}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-417 |
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

Trust fixture。

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
  # make_repo <repo> <flow_body>
  local repo="$1" flow_body="$2"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "Polaris Selftest"
  printf '%s\n' "$flow_body" >"$repo/scripts/behavior-flow.sh"
  chmod +x "$repo/scripts/behavior-flow.sh"
  git -C "$repo" add .
  git -C "$repo" commit -qm baseline
}

expect_pass() {
  local label="$1"; shift
  if ! "$@" >"$WORKDIR/$label.out" 2>"$WORKDIR/$label.err"; then
    echo "FAIL: expected pass for $label" >&2
    cat "$WORKDIR/$label.err" >&2
    exit 1
  fi
}

expect_fail() {
  local label="$1"; shift
  if "$@" >"$WORKDIR/$label.out" 2>"$WORKDIR/$label.err"; then
    echo "FAIL: expected fail-closed for $label" >&2
    cat "$WORKDIR/$label.out" >&2
    exit 1
  fi
}

find_marker() {
  local repo="$1" ticket="$2" head="$3" m
  m="$(find /tmp -maxdepth 1 -name "polaris-behavior-${ticket}-${head}-*.json" -print -quit 2>/dev/null || true)"
  if [[ -n "$m" ]]; then printf '%s\n' "$m"; return; fi
  find "$repo/.polaris/evidence/behavior/$ticket" -maxdepth 1 -name "polaris-behavior-${ticket}-${head}-*.json" -print -quit 2>/dev/null || true
}

assert_marker_status() {
  local marker="$1" expected="$2"
  python3 - "$marker" "$expected" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("status") != sys.argv[2]:
    raise SystemExit(f"expected marker status {sys.argv[2]}, got {data.get('status')!r}")
PY
}

# Flow bodies -------------------------------------------------------------------

# Real render: writes a genuine behavior-state.json (no self-declared hash) plus a
# real PNG. Deterministic value → parity baseline==compare → real PASS.
REAL_FLOW='set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
printf "{\"value\":\"stable\"}\n" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json"
printf "%s" "'"$REAL_PNG_B64"'" | base64 --decode >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"'

# Hard-coded state_hash impersonation: self-asserts its own comparison hash.
HARDCODED_FLOW='set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
printf "{\"hash\":\"deadbeefcafefeed\",\"value\":\"whatever\"}\n" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/behavior-state.json"
printf "%s" "'"$REAL_PNG_B64"'" | base64 --decode >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"'

# Placeholder impersonation: no state file, only a text "png" stand-in.
# Deterministic stdout so parity baseline==compare (would-be PASS pre-gate).
PLACEHOLDER_FLOW='set -euo pipefail
mkdir -p "$POLARIS_BEHAVIOR_OUTPUT_DIR"
printf "png:placeholder\n" >"$POLARIS_BEHAVIOR_OUTPUT_DIR/screen.png"
echo "deterministic stdout"'

# ------------------------------------------------------------------------------
# Layer 1 (b) — AC10 positive: real render backs the comparison → PASS.
repo_real="$WORKDIR/real"
make_repo "$repo_real" "$REAL_FLOW"
task_real="$WORKDIR/real.md"
write_task "$task_real" "$(basename "$repo_real")" "DP-417-T8R" "parity" "HEAD" "false" "[]"
expect_pass "real-baseline" bash "$RUNNER" --task-md "$task_real" --mode baseline --repo "$repo_real" --ticket DP-417-T8R
expect_pass "real-compare" bash "$RUNNER" --task-md "$task_real" --mode compare --repo "$repo_real" --ticket DP-417-T8R
head_real="$(git -C "$repo_real" rev-parse HEAD)"
assert_marker_status "$(find_marker "$repo_real" DP-417-T8R "$head_real")" PASS

# Layer 1 (a) — AC-NEG3 impersonation: hard-coded state_hash → fail-closed, no PASS.
repo_hc="$WORKDIR/hardcoded"
make_repo "$repo_hc" "$HARDCODED_FLOW"
task_hc="$WORKDIR/hardcoded.md"
write_task "$task_hc" "$(basename "$repo_hc")" "DP-417-T8H" "parity" "HEAD" "false" "[]"
expect_pass "hc-baseline" bash "$RUNNER" --task-md "$task_hc" --mode baseline --repo "$repo_hc" --ticket DP-417-T8H
expect_fail "hc-compare" bash "$RUNNER" --task-md "$task_hc" --mode compare --repo "$repo_hc" --ticket DP-417-T8H
head_hc="$(git -C "$repo_hc" rev-parse HEAD)"
assert_marker_status "$(find_marker "$repo_hc" DP-417-T8H "$head_hc")" FAIL

# Layer 1 (a2) — AC-NEG3 impersonation: placeholder / no real render → fail-closed.
repo_ph="$WORKDIR/placeholder"
make_repo "$repo_ph" "$PLACEHOLDER_FLOW"
task_ph="$WORKDIR/placeholder.md"
write_task "$task_ph" "$(basename "$repo_ph")" "DP-417-T8P" "parity" "HEAD" "false" "[]"
expect_pass "ph-baseline" bash "$RUNNER" --task-md "$task_ph" --mode baseline --repo "$repo_ph" --ticket DP-417-T8P
expect_fail "ph-compare" bash "$RUNNER" --task-md "$task_ph" --mode compare --repo "$repo_ph" --ticket DP-417-T8P
head_ph="$(git -C "$repo_ph" rev-parse HEAD)"
assert_marker_status "$(find_marker "$repo_ph" DP-417-T8P "$head_ph")" FAIL

# Layer 2 (c) — AC-NEG5 confounded: replaces_existing + old source still present.
repo_conf="$WORKDIR/confounded"
make_repo "$repo_conf" "$REAL_FLOW"
printf 'legacy widget\n' >"$repo_conf/old-widget.js"
git -C "$repo_conf" add old-widget.js
git -C "$repo_conf" commit -qm "old source still present"
task_conf="$WORKDIR/confounded.md"
write_task "$task_conf" "$(basename "$repo_conf")" "DP-417-T8C" "parity" "HEAD" "true" '["old-widget.js"]'
expect_pass "conf-baseline" bash "$RUNNER" --task-md "$task_conf" --mode baseline --repo "$repo_conf" --ticket DP-417-T8C
expect_fail "conf-compare" bash "$RUNNER" --task-md "$task_conf" --mode compare --repo "$repo_conf" --ticket DP-417-T8C
head_conf="$(git -C "$repo_conf" rev-parse HEAD)"
assert_marker_status "$(find_marker "$repo_conf" DP-417-T8C "$head_conf")" FAIL

# Layer 2 (d) — AC10: old source isolated → PASS.
repo_iso="$WORKDIR/isolated"
make_repo "$repo_iso" "$REAL_FLOW"
task_iso="$WORKDIR/isolated.md"
write_task "$task_iso" "$(basename "$repo_iso")" "DP-417-T8I" "parity" "HEAD" "true" '["old-widget.js"]'
expect_pass "iso-baseline" bash "$RUNNER" --task-md "$task_iso" --mode baseline --repo "$repo_iso" --ticket DP-417-T8I
expect_pass "iso-compare" bash "$RUNNER" --task-md "$task_iso" --mode compare --repo "$repo_iso" --ticket DP-417-T8I
head_iso="$(git -C "$repo_iso" rev-parse HEAD)"
assert_marker_status "$(find_marker "$repo_iso" DP-417-T8I "$head_iso")" PASS

# AC-N1 no-false-positive (e1) — applies=false is unaffected (no evidence required).
repo_na="$WORKDIR/applies-false"
make_repo "$repo_na" "$PLACEHOLDER_FLOW"
task_na="$WORKDIR/applies-false.md"
cat >"$task_na" <<'EOF'
---
title: "Work Order - DP-417-T8N: applies false (1 pt)"
description: "applies=false fixture."
depends_on: []
verification:
  behavior_contract:
    applies: false
    reason: "static framework docs; no user-visible runtime behavior."
---

# DP-417-T8N: applies false (1 pt)

> Source: DP-417 | Task: DP-417-T8N | JIRA: N/A | Repo: applies-false
EOF
expect_pass "applies-false-noop" bash "$RUNNER" --task-md "$task_na" --mode compare --repo "$repo_na" --ticket DP-417-T8N

# AC-N1 no-false-positive (e2) — non-fidelity mode (pm_flow) placeholder is unaffected.
repo_pm="$WORKDIR/pm-flow"
make_repo "$repo_pm" "$PLACEHOLDER_FLOW"
task_pm="$WORKDIR/pm-flow.md"
write_task "$task_pm" "$(basename "$repo_pm")" "DP-417-T8M" "pm_flow" "none" "false" "[]"
expect_pass "pm-flow-compare" bash "$RUNNER" --task-md "$task_pm" --mode compare --repo "$repo_pm" --ticket DP-417-T8M
head_pm="$(git -C "$repo_pm" rev-parse HEAD)"
assert_marker_status "$(find_marker "$repo_pm" DP-417-T8M "$head_pm")" PASS

echo "PASS: vr/behavior verification trustworthiness gate selftest"
