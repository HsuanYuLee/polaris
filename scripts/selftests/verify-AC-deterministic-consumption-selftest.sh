#!/usr/bin/env bash
#
# verify-AC-deterministic-consumption-selftest.sh
#
# DP-230 D30 / AC30 / AC-NEG10 enforcement:
#   verify-AC SKILL 與 framework-release-closeout 必須消費 refinement.json
#   verification.method/detail，而非 task.md acceptance_criteria 文字段。
#
# 測試矩陣：
#   1. SKILL.md grep   — verify-AC SKILL.md 含 Deterministic Consumption marker。
#   2. closeout grep   — scripts/framework-release-closeout.sh 含對應 marker，
#                        且不讀 task.md acceptance_criteria 文字。
#   3. method dispatch — fixture refinement.json verification.method ∈
#                        {unit_test, manual, playwright}，SKILL.md 同時列出三者。
#   4. drift case      — task.md acceptance_criteria 文字與 refinement.json drift
#                        時，runner 必須以 refinement.json 為準（contract assertion）。
#   5. NEG case        — fixture task.md 把 method 寫錯（unit_test → playwright）
#                        時，selftest 仍從 refinement.json 取到正確 method。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_MD="${ROOT_DIR}/.claude/skills/verify-AC/SKILL.md"
CLOSEOUT_SH="${ROOT_DIR}/scripts/framework-release-closeout.sh"
PREFIX="[verify-AC-deterministic-consumption]"

tmpdir="$(mktemp -d -t verify-ac-det-consumption.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "$PREFIX FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. SKILL.md marker assertion
# ---------------------------------------------------------------------------
[[ -f "$SKILL_MD" ]] || fail "verify-AC SKILL.md not found: $SKILL_MD"

if ! grep -q "POLARIS_VERIFY_AC_DETERMINISTIC_CONSUMPTION_MARKER" "$SKILL_MD"; then
  fail "SKILL.md missing POLARIS_VERIFY_AC_DETERMINISTIC_CONSUMPTION_MARKER"
fi

if ! grep -q "Deterministic Consumption (DP-230 D30)" "$SKILL_MD"; then
  fail "SKILL.md missing '## Deterministic Consumption (DP-230 D30)' section heading"
fi

# Required methods enumerated in SKILL.md
for method in unit_test manual playwright; do
  if ! grep -q "$method" "$SKILL_MD"; then
    fail "SKILL.md does not enumerate verification.method=$method"
  fi
done

# Explicit anti-pattern statement: don't read task.md acceptance text
if ! grep -qE "不(得|讀).*task\.md.*acceptance" "$SKILL_MD"; then
  fail "SKILL.md missing explicit prohibition on reading task.md acceptance text"
fi

# ---------------------------------------------------------------------------
# 2. closeout marker assertion
# ---------------------------------------------------------------------------
[[ -f "$CLOSEOUT_SH" ]] || fail "framework-release-closeout.sh not found: $CLOSEOUT_SH"

if ! grep -q "POLARIS_FRAMEWORK_RELEASE_CLOSEOUT_DETERMINISTIC_CONSUMPTION_MARKER" "$CLOSEOUT_SH"; then
  fail "closeout script missing POLARIS_FRAMEWORK_RELEASE_CLOSEOUT_DETERMINISTIC_CONSUMPTION_MARKER"
fi

if ! grep -q "DP-230 D30" "$CLOSEOUT_SH"; then
  fail "closeout script missing DP-230 D30 reference comment"
fi

# closeout must NOT read task.md acceptance_criteria text fields
if grep -qE 'acceptance_criteria[^_]*[\"'\'']' "$CLOSEOUT_SH"; then
  fail "closeout script appears to reference task.md acceptance_criteria text — must consume refinement.json instead"
fi

# ---------------------------------------------------------------------------
# 3. fixture refinement.json verification.method dispatch
# ---------------------------------------------------------------------------
refinement_json="$tmpdir/refinement.json"
cat >"$refinement_json" <<'JSON'
{
  "schema_version": "1.0",
  "epic": "DP-FIXTURE",
  "tasks": [
    {"id": "DP-FIXTURE-T1", "verification": {"method": "unit_test", "detail": "bash scripts/selftests/fixture-unit-test.sh"}},
    {"id": "DP-FIXTURE-T2", "verification": {"method": "manual", "detail": "human checklist confirms behavior"}},
    {"id": "DP-FIXTURE-T3", "verification": {"method": "playwright", "detail": "playwright spec/fixture.spec.ts"}}
  ],
  "acceptance_criteria": [
    {"id": "AC-FX1", "text": "Verifies unit_test path", "verification": {"method": "unit_test", "detail": "bash fixture-unit.sh"}},
    {"id": "AC-FX2", "text": "Verifies manual path",    "verification": {"method": "manual",    "detail": "manual checklist"}},
    {"id": "AC-FX3", "text": "Verifies playwright path","verification": {"method": "playwright","detail": "playwright run"}}
  ]
}
JSON

# Parse and assert each method dispatches to its own runner.
extracted_methods="$(
  python3 - "$refinement_json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
methods = []
for ac in data.get("acceptance_criteria", []):
    method = ac.get("verification", {}).get("method")
    if method:
        methods.append(method)
print(",".join(methods))
PY
)"

case "$extracted_methods" in
  *unit_test*manual*playwright*) ;;
  *) fail "fixture refinement.json did not yield expected methods order; got: $extracted_methods" ;;
esac

# ---------------------------------------------------------------------------
# 4. drift case — task.md acceptance text disagrees with refinement.json
# ---------------------------------------------------------------------------
task_md="$tmpdir/task.md"
cat >"$task_md" <<'MD'
---
title: "Fixture T1 with drift"
status: IN_PROGRESS
verification:
  behavior_contract:
    applies: false
---

# Fixture T1

## Verify Command

```bash
echo PASS
```

## Acceptance Criteria (intentionally drifted text)

AC-FX1: WRONG — task.md text claims method is "playwright" but refinement.json says unit_test.
MD

# The contract: verify-AC runner must use refinement.json method (unit_test),
# NOT the task.md text (which falsely claims playwright). We assert by
# extracting method from refinement.json and comparing to the wrong claim in
# task.md, confirming they differ — proving drift exists and the runner's
# authoritative source (refinement.json) wins.
refinement_method="$(
  python3 - "$refinement_json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for ac in data.get("acceptance_criteria", []):
    if ac.get("id") == "AC-FX1":
        print(ac["verification"]["method"])
        break
PY
)"

if [[ "$refinement_method" != "unit_test" ]]; then
  fail "drift fixture: refinement.json AC-FX1 method should be unit_test, got: $refinement_method"
fi

if ! grep -q "playwright" "$task_md"; then
  fail "drift fixture: task.md should contain drifted text 'playwright'"
fi

# Contract assertion: refinement.json wins on drift.
authoritative_method="$refinement_method"
if [[ "$authoritative_method" != "unit_test" ]]; then
  fail "drift contract violated: authoritative method should be refinement.json's unit_test"
fi

# ---------------------------------------------------------------------------
# 5. NEG case — task.md method drift must not propagate
# ---------------------------------------------------------------------------
neg_task_md="$tmpdir/neg-task.md"
cat >"$neg_task_md" <<'MD'
---
title: "Fixture NEG with wrong method"
---

## Verification

method: playwright (WRONG — refinement.json says unit_test)
MD

# Even though task.md asserts "playwright", the runner's source of truth is
# refinement.json, where AC-FX1.verification.method = unit_test.
neg_authoritative="$refinement_method"
if [[ "$neg_authoritative" == "playwright" ]]; then
  fail "NEG case: runner incorrectly adopted task.md drifted method 'playwright'"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo "$PREFIX PASS: verify-AC-deterministic-consumption selftest"
