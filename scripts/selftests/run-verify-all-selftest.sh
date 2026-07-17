#!/usr/bin/env bash
# Selftest for task-declared, single-layer verify orchestration.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT_DIR/scripts/run-verify-all.sh"
tmp="$(mktemp -d -t polaris-verify-all.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
printf '.polaris/\n' >"$repo/.gitignore"
git -C "$repo" -c user.name=test -c user.email=test@example.com add .gitignore
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q -m init
head_sha="$(git -C "$repo" rev-parse HEAD)"
ticket="DP-422-T6"
task="$tmp/task.md"
export POLARIS_EVIDENCE_ROOT="$tmp/evidence"

write_task() {
  local verify_command="$1"
  cat >"$task" <<EOF
---
title: "Work Order - DP-422-T6: verify all selftest (1 pt)"
description: "Fixture task for run-verify-all selftest."
status: PLANNED
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "selftest"
---

# T6: verify all selftest (1 pt)

> Source: DP-422 | Task: DP-422-T6 | JIRA: N/A | Repo: fixture

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-422 |
| Work item ID | DP-422-T6 |
| Task ID | DP-422-T6 |
| Task JIRA key | DP-422-T6 |
| JIRA key | N/A |
| Test sub-tasks | N/A - self-contained |
| AC 驗收單 | N/A - self-contained |
| Base branch | main |
| Task branch | task/DP-422-T6-selftest |
| Depends on | N/A |
| References to load | N/A |

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`.gitignore\` | modify | selftest |

## 估點理由

1 pt — deterministic fixture。

## Test Environment

- **Level**: build
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Test Command

\`\`\`bash
true
\`\`\`

## Verify Command

\`\`\`bash
$verify_command
\`\`\`

## Allowed Files

- \`.gitignore\`
EOF
}

fail() { echo "run-verify-all-selftest: FAIL: $*" >&2; exit 1; }

write_task "printf 'http://127.0.0.1/selftest\\n'"
output="$($RUNNER --task-md "$task" --repo "$repo" --ticket "$ticket")"
[[ "$output" == *"visual regression not declared; layer skipped"* ]] || fail "missing undeclared VR skip"
[[ "$output" == *"behavior_contract.applies is not true; layer skipped"* ]] || fail "missing applies=false behavior skip"
[[ "$output" == *"PASS: run-verify-all"* ]] || fail "orchestration did not pass"
verify_path="$POLARIS_EVIDENCE_ROOT/verify/polaris-verified-${ticket}-${head_sha}.json"
[[ -f "$verify_path" ]] || fail "head-bound verify marker missing"
[[ ! -d "$POLARIS_EVIDENCE_ROOT/vr" ]] || fail "undeclared VR wrote a marker"
[[ ! -d "$POLARIS_EVIDENCE_ROOT/behavior" ]] || fail "applies=false behavior wrote a marker"

# Malformed optional declarations are not equivalent to absent declarations.
# Canonical task validation must stop before the primary runner writes a marker.
write_task "printf 'must-not-run\\n'"
python3 - "$task" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "verification:\n  behavior_contract:",
    "verification:\n  visual_regression:\n    pages:\n      - /missing-expected\n  behavior_contract:",
)
open(path, "w", encoding="utf-8").write(text)
PY
rm -f "$verify_path" "/tmp/polaris-verified-${ticket}-${head_sha}.json"
if "$RUNNER" --task-md "$task" --repo "$repo" --ticket "$ticket" >/dev/null 2>&1; then
  fail "malformed VR declaration passed"
fi
[[ ! -f "$verify_path" ]] || fail "malformed VR reached primary runner"

write_task "printf 'must-not-run\\n'"
python3 - "$task" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read().replace("    applies: false", "    applies: maybe")
open(path, "w", encoding="utf-8").write(text)
PY
if "$RUNNER" --task-md "$task" --repo "$repo" --ticket "$ticket" >/dev/null 2>&1; then
  fail "malformed behavior declaration passed"
fi
[[ ! -f "$verify_path" ]] || fail "malformed behavior reached primary runner"

# A declared VR layer must dispatch the existing runner and fail closed on its
# own runtime contract; the BLOCKED_ENV marker proves dispatch occurred.
write_task "printf 'http://127.0.0.1/selftest\\n'"
python3 - "$task" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "verification:\n  behavior_contract:",
    "verification:\n  visual_regression:\n    expected: none_allowed\n    pages: [\"/selftest\"]\n  behavior_contract:",
)
text = text.replace("- **Level**: build", "- **Level**: runtime")
text = text.replace("- **Runtime verify target**: N/A", "- **Runtime verify target**: http://127.0.0.1/selftest")
text = text.replace("- **Env bootstrap command**: N/A", "- **Env bootstrap command**: true")
open(path, "w", encoding="utf-8").write(text)
PY
vr_out="$tmp/vr.out"
vr_err="$tmp/vr.err"
if "$RUNNER" --task-md "$task" --repo "$repo" --ticket "$ticket" >"$vr_out" 2>"$vr_err"; then
  fail "declared VR unexpectedly passed build-level contract"
fi
vr_path="$POLARIS_EVIDENCE_ROOT/vr/polaris-vr-${ticket}-${head_sha}.json"
if [[ ! -f "$vr_path" ]]; then
  sed -n '1,160p' "$vr_err" >&2
  fail "declared VR was not dispatched"
fi
python3 - "$vr_path" <<'PY'
import json
import sys

assert json.load(open(sys.argv[1], encoding="utf-8"))["status"] == "BLOCKED_ENV"
PY

# behavior_contract.applies=true must dispatch the existing behavior runner.
# No executable flow is intentionally declared, so its canonical NOT_COVERED
# marker and non-zero exit prove fail-closed dispatch without reimplementing it.
write_task "printf 'single-layer-pass\\n'"
python3 - "$task" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "    applies: false\n    reason: \"selftest\"",
    "    applies: true\n    mode: pm_flow\n    source_of_truth: spec\n    fixture_policy: live_allowed\n    baseline_ref: none\n    flow: selftest flow\n    assertions:\n      - selftest assertion\n    allowed_differences: []",
)
open(path, "w", encoding="utf-8").write(text)
PY
behavior_out="$tmp/behavior.out"
behavior_err="$tmp/behavior.err"
if "$RUNNER" --task-md "$task" --repo "$repo" --ticket "$ticket" >"$behavior_out" 2>"$behavior_err"; then
  fail "applies=true behavior without executable flow passed"
fi
behavior_marker="$(find "$repo/.polaris/evidence/behavior" -type f -name "polaris-behavior-${ticket}-${head_sha}-*.json" -print -quit 2>/dev/null || true)"
if [[ -z "$behavior_marker" ]]; then
  sed -n '1,160p' "$behavior_err" >&2
  fail "applies=true behavior was not dispatched"
fi

write_task "bash scripts/run-verify-all.sh --task-md '$task'"
if "$RUNNER" --task-md "$task" --repo "$repo" --ticket "$ticket" >/dev/null 2>&1; then
  fail "recursive verify command passed"
fi

echo "run-verify-all-selftest: PASS"
