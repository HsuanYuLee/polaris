#!/usr/bin/env bash
# Purpose: DP-296 T5 / AC4 (fix-forward of DP-294 T7) — assert
#          validate-refinement-lock-preflight.sh carries each canonical task's real
#          title (tasks[].title) into the synthesized placeholder summary line, so
#          the EXISTING validate-task-md.sh summary-language guard fires per task in
#          the REAL policy path (reuse, no second classifier). An English-only title
#          under the zh-TW workspace policy fail-stops (exit 2 +
#          POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED); an all-zh-TW title PASSes.
#          Fixtures use the canonical tasks[] shape the production preflight reads
#          (planned_tasks[] was removed in DP-296 T3); a hand-detached planned_tasks[]
#          fixture would yield zero rows and silently mask the guard (AC-NEG2).
# Inputs:  none (hermetic tmp refinement.json fixtures).
# Outputs: PASS/FAIL lines; exit 0 (all pass) / 1 (any fail).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFLIGHT="$ROOT/scripts/validate-refinement-lock-preflight.sh"
BREAKDOWN_READY="$ROOT/scripts/validate-breakdown-ready.sh"
[[ -x "$PREFLIGHT" ]] || { echo "FAIL: missing/not executable: $PREFLIGHT" >&2; exit 1; }

TMP="$(mktemp -d -t lock-preflight-title-lang-XXXX)"
trap 'rm -rf "$TMP"' EXIT

# Mini-workspace under zh-TW policy: the preflight walks up from the refinement.json
# directory to source the live language, so the fixtures must sit under this config.
printf 'language: zh-TW\n' >"$TMP/workspace-config.yaml"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

# DP-296 T5 / AC4 / AC-NEG2: fixtures use the canonical tasks[] shape (id /
# task_shape / tracked_deliverable_hint / title are first-class tasks[] fields),
# matching the production preflight reader. Hand-detached planned_tasks[] fixtures
# would silently yield zero rows under the canonical-only reader, masking the
# language guard — so the real-callsite shape is mandatory here.

# --- Case 1: English-only title under zh-TW policy -> exit 2 fail-stop ----------
cat >"$TMP/english.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-294" },
  "acceptance_criteria": [ { "id": "AC1", "text": "title language guard fixture" } ],
  "tasks": [
    { "id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "tracked",
      "title": "Add deterministic gate coverage for the evidence classifier helper",
      "scope": "新增 title language guard 的 full-derive fixture。",
      "modules": ["scripts/title-language-fixture.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS",
        "behavior_contract": { "applies": false, "reason": "framework selftest；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static" },
        "verify_command": "echo PASS",
        "references": []
      } }
  ]
}
JSON
set +e
out_en="$(bash "$PREFLIGHT" "$TMP/english.json" 2>&1)"; rc_en=$?
set -e
[[ "$rc_en" -eq 2 ]] && ok || bad "English-only title should fail-stop with exit 2 (got $rc_en)"
printf '%s' "$out_en" | grep -q 'POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED' \
  && ok || bad "English-only title failure should emit POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED"

# --- Case 2: all zh-TW title -> PASS ------------------------------------------
cat >"$TMP/zhtw.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-294" },
  "acceptance_criteria": [ { "id": "AC1", "text": "title language guard fixture" } ],
  "tasks": [
    { "id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "tracked",
      "title": "新增 evidence classifier 的確定性 gate 覆蓋與驗證",
      "scope": "新增 title language guard 的 full-derive fixture。",
      "modules": ["scripts/title-language-fixture.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS",
        "behavior_contract": { "applies": false, "reason": "framework selftest；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static" },
        "verify_command": "echo PASS",
        "references": []
      } }
  ]
}
JSON
set +e
out_zh="$(bash "$PREFLIGHT" "$TMP/zhtw.json" 2>&1)"; rc_zh=$?
set -e
[[ "$rc_zh" -eq 0 ]] && ok || bad "all-zh-TW title should PASS exit 0 (got $rc_zh): $out_zh"

# --- Case 3: incomplete task body fail-louds under full-derive -----------------
cat >"$TMP/notitle.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-294" },
  "tasks": [
    { "id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
set +e
out_nt="$(bash "$PREFLIGHT" "$TMP/notitle.json" 2>&1)"; rc_nt=$?
set -e
[[ "$rc_nt" -eq 2 ]] && ok || bad "title-less planned task should fail-stop exit 2 under full-derive (got $rc_nt): $out_nt"
printf '%s' "$out_nt" | grep -q 'POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED' \
  && ok || bad "title-less task failure should emit POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED"

# --- Case 4: reuse, no second classifier --------------------------------------
# The preflight must NOT carry its own language/CJK classifier; the language
# verdict comes from validate-task-md.sh via validate-breakdown-ready.sh.
if grep -qE 'u3400|u4e00|u9fff|uf900' "$PREFLIGHT"; then
  bad "preflight must not embed a second CJK/language classifier regex"
else
  ok
fi
if grep -q 'English prose' "$PREFLIGHT"; then
  bad "preflight must not duplicate the validate-task-md language message (no second classifier)"
else
  ok
fi
grep -q 'validate-breakdown-ready.sh' "$PREFLIGHT" \
  && ok || bad "preflight should delegate to validate-breakdown-ready.sh (reuse chain)"
grep -q 'validate-task-md' "$BREAKDOWN_READY" \
  && ok || bad "validate-breakdown-ready.sh should run validate-task-md.sh (summary-language source)"

echo "[validate-refinement-lock-preflight-title-language-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
