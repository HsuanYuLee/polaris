#!/usr/bin/env bash
# validate-task-md-allowed-files-create-smoke-selftest.sh — DP-226 T3 contract.
#
# Verifies verify_command_static_smoke honours create lifecycle:
#   AC3       Verify Command references a script under scripts/selftests/foo.sh
#             which does NOT exist yet, AND `## 改動範圍` lists that path with
#             action=create, AND `## Allowed Files` covers that path → smoke
#             PASS (no missing-script error).
#   AC-NEG3a  Same Verify Command but `## 改動範圍` action is `modify` (not
#             create) → smoke FAILS with missing-script error (EC5).
#   AC-NEG3b  Same Verify Command + action=create but path NOT in
#             `## Allowed Files` → smoke FAILS (EC8).
#
# All fixtures are minimal task.md bodies that satisfy the
# verify_command_static_smoke entry point. We invoke the python function via
# the bash validator's path with --scan-less invocation:
#   bash scripts/validate-task-md.sh <file>
# Exit codes from the validator:
#   0 schema pass
#   1 schema violations (any error captured by smoke or other checks)
#
# The selftest pinpoints the missing-script error in the validator's stderr.

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"
WORKDIR="$(mktemp -d -t dp226-t3.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$VALIDATOR" ]]; then
  echo "FAIL: validator not executable: $VALIDATOR" >&2
  exit 1
fi

# Reusable canonical fixture — use the DP-226 T3 task.md itself (it references
# scripts/selftests/validate-task-md-allowed-files-create-smoke-selftest.sh
# which IS in its action=create + Allowed Files set, so verify-command smoke
# must not report missing-script for the referenced selftest script). After
# this PR lands, the script exists on disk; we still test the missing-script
# path by using a synthetic fixture pointing at a non-existent script.

# Build fixture A — AC3 happy path.
fixture_a="$WORKDIR/T-create-happy/index.md"
mkdir -p "$(dirname "$fixture_a")"
cat >"$fixture_a" <<'MD'
---
title: "DP-999-T9: fixture create-lifecycle happy path (1 pt)"
description: "Fixture for DP-226 T3 selftest — create lifecycle happy path."
status: PLANNED
depends_on: []
verification:
  behavior_contract:
    applies: false
    reason: "fixture for selftest"
jira_transition_log: []
---

# T9: fixture create-lifecycle happy path (1 pt)

> Source: DP-999 | Task: DP-999-T9 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T9 |
| JIRA key | N/A |
| Test sub-tasks | N/A |
| AC 驗收單 | N/A |
| Base branch | main |
| Branch chain | main -> task/DP-999-T9 |
| Task branch | task/DP-999-T9 |
| Depends on | N/A |
| References to load | - none |

## Verification Handoff

N/A.

## 目標

fixture for selftest.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/selftests/__dp226_t3_nonexistent_create__.sh` | create | new selftest |

## Allowed Files

- `scripts/selftests/__dp226_t3_nonexistent_create__.sh`

## 估點理由

1 pt — fixture for selftest.

## 測試計畫（code-level）

- 跑 selftest → PASS。

## Test Command

```bash
bash scripts/selftests/__dp226_t3_nonexistent_create__.sh
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| fixture | n/a | n/a | n/a |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | changed files in Allowed Files | breakdown |
| test | yes | Test Command passes | engineering |
| verify | yes | Verify Command passes | engineering |
| ci-local | no | N/A | framework workspace |

## Verify Command

```bash
bash scripts/selftests/__dp226_t3_nonexistent_create__.sh
```

預期輸出：`PASS`
MD

# Build fixture B — same Verify Command but action=modify instead of create.
fixture_b="$WORKDIR/T-modify-fails/index.md"
mkdir -p "$(dirname "$fixture_b")"
cp "$fixture_a" "$fixture_b"
python3 - "$fixture_b" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
t = t.replace("| create | new selftest", "| modify | edit selftest")
open(p, "w").write(t)
PY

# Build fixture C — action=create but path NOT in Allowed Files.
fixture_c="$WORKDIR/T-create-not-allowed/index.md"
mkdir -p "$(dirname "$fixture_c")"
cp "$fixture_a" "$fixture_c"
python3 - "$fixture_c" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
# Replace the Allowed Files bullet with a different path so the intersection
# becomes empty.
t = t.replace(
    "- `scripts/selftests/__dp226_t3_nonexistent_create__.sh`",
    "- `scripts/selftests/some-other-allowed.sh`",
)
open(p, "w").write(t)
PY

# Helper: run validator and inspect stderr for missing-script error.
contains_missing_script() {
  local out_file="$1"
  grep -q 'Verify Command references missing repo-local script' "$out_file"
}

# Case AC3: validator should NOT report missing-script for the create-set
# script. Other validator errors (frontmatter, etc.) may still surface for the
# synthetic fixture, but they do not affect the create-smoke contract under
# test. So we check that THE SPECIFIC missing-script line is absent.
set +e
"$VALIDATOR" "$fixture_a" >"$WORKDIR/ac3.stdout" 2>"$WORKDIR/ac3.stderr"
set -e
if grep -q '__dp226_t3_nonexistent_create__' "$WORKDIR/ac3.stderr" "$WORKDIR/ac3.stdout"; then
  if grep -q 'Verify Command references missing repo-local script: scripts/selftests/__dp226_t3_nonexistent_create__.sh' \
      "$WORKDIR/ac3.stderr" "$WORKDIR/ac3.stdout"; then
    echo "FAIL (AC3): validator reported missing-script even though path is in create_set" >&2
    cat "$WORKDIR/ac3.stderr" "$WORKDIR/ac3.stdout" >&2
    exit 1
  fi
fi

# Case AC-NEG3a: action=modify, script does not exist → missing-script error.
set +e
"$VALIDATOR" "$fixture_b" >"$WORKDIR/neg3a.stdout" 2>"$WORKDIR/neg3a.stderr"
set -e
if ! grep -q 'Verify Command references missing repo-local script: scripts/selftests/__dp226_t3_nonexistent_create__.sh' \
    "$WORKDIR/neg3a.stderr" "$WORKDIR/neg3a.stdout"; then
  echo "FAIL (AC-NEG3a): expected missing-script error for action=modify but it was not reported" >&2
  cat "$WORKDIR/neg3a.stderr" "$WORKDIR/neg3a.stdout" >&2
  exit 1
fi

# Case AC-NEG3b: action=create but path not in Allowed Files → missing-script.
set +e
"$VALIDATOR" "$fixture_c" >"$WORKDIR/neg3b.stdout" 2>"$WORKDIR/neg3b.stderr"
set -e
if ! grep -q 'Verify Command references missing repo-local script: scripts/selftests/__dp226_t3_nonexistent_create__.sh' \
    "$WORKDIR/neg3b.stderr" "$WORKDIR/neg3b.stdout"; then
  echo "FAIL (AC-NEG3b): expected missing-script error when path is in action=create but not in Allowed Files" >&2
  cat "$WORKDIR/neg3b.stderr" "$WORKDIR/neg3b.stdout" >&2
  exit 1
fi

echo "PASS"
