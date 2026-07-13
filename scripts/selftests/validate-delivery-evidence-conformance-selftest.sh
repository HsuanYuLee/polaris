#!/usr/bin/env bash
# Purpose: DP-417 T15 selftest for scripts/validate-delivery-evidence-conformance.sh.
#   Asserts (framework-release delivery-evidence conformance gate):
#     - pre-release: head resolvable via DP-360 authority order (task.md deliverable.head_sha OR
#       --task-head-sha override) PASS; head-only block (no pr_url/pr_state) PASS (pr provenance optional);
#       override supplies head for a PR-less direct-commit task PASS; no head resolvable (neither block nor
#       matching override) => exit 2 enumerate; malformed head / CLOSED pr_state => exit 2; override keyed to
#       a different wid => fail-closed; multiple non-conformant enumerated at once.
#     - planning: non-failing front-load emit (surfaces contract even when branch derives later).
#     - framework-DP-only: source.type=jira => no-op PASS (both modes) — never applies /framework-release
#       contract to product epics.
#     - audit/confirmation task_shape excluded from required set (no false positive).
# Inputs: none (self-contained fixtures under a temp dir). Outputs: exit 0 all pass, exit 1 any fail.
set -uo pipefail

# Hermetic: fixtures are self-contained; do not inherit a live workspace root.
unset POLARIS_WORKSPACE_ROOT POLARIS_SPECS_ROOT 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$REPO_ROOT/scripts/validate-delivery-evidence-conformance.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_refinement() { # <container> <source_type> <source_id>
  mkdir -p "$1"
  printf '{"source":{"type":"%s","id":"%s"}}\n' "$2" "$3" > "$1/refinement.json"
}

mk_task() { # <container> <short_id> <work_item_id> <shape> <branch> [head_sha] [pr_url] [pr_state]
  local c="$1" sid="$2" wid="$3" shape="$4" branch="$5"
  local head="${6:-}" url="${7:-}" state="${8:-}"
  local dir="$c/tasks/$sid"
  mkdir -p "$dir"
  {
    echo "---"
    echo "title: \"$wid\""
    echo "task_shape: $shape"
    if [[ -n "$head" || -n "$url" || -n "$state" ]]; then
      echo "deliverable:"
      [[ -n "$url" ]]   && echo "  pr_url: $url"
      [[ -n "$state" ]] && echo "  pr_state: $state"
      [[ -n "$head" ]]  && echo "  head_sha: $head"
    fi
    echo "---"
    echo ""
    echo "# $wid"
    echo ""
    echo "## Operational Context"
    echo ""
    echo "| 欄位 | 值 |"
    echo "|------|-----|"
    echo "| Work item ID | $wid |"
    echo "| Task branch | $branch |"
  } > "$dir/index.md"
  printf '%s\n' "$dir/index.md"
}

RC=0
OUT=""
run_gate() { OUT="$(bash "$GATE" "$@" 2>&1)"; RC=$?; }

HEAD_OK="a1b2c3d4e5f6"

# --- 1. pre-release full-conformant framework DP => PASS ---
C1="$TMP/DP-901"; mk_refinement "$C1" dp DP-901
T1="$(mk_task "$C1" T1 DP-901-T1 implementation task/DP-901-T1-x "$HEAD_OK" https://x/pull/1 OPEN)"
run_gate --mode pre-release --task-md "$T1"
[[ $RC -eq 0 ]] && ok "pre-release full-conformant PASS" || bad "pre-release conformant expected 0 got $RC: $OUT"

# --- 2. pre-release missing delivery block => exit 2 + enumerate ---
C2="$TMP/DP-902"; mk_refinement "$C2" dp DP-902
T2="$(mk_task "$C2" T2 DP-902-T2 implementation task/DP-902-T2-x)"
run_gate --mode pre-release --task-md "$T2"
{ [[ $RC -eq 2 ]] && grep -q 'POLARIS_DELIVERY_EVIDENCE_NON_CONFORMANT' <<<"$OUT" \
  && grep -q 'DP-902-T2' <<<"$OUT" && grep -q 'deliverable.head_sha' <<<"$OUT"; } \
  && ok "pre-release missing block exit 2 + enumerate" || bad "missing-block expected exit2+enum got $RC: $OUT"

# --- 3. pre-release malformed head => exit 2 ---
C3="$TMP/DP-903"; mk_refinement "$C3" dp DP-903
T3="$(mk_task "$C3" T3 DP-903-T3 implementation task/DP-903-T3-x ZZZNOTHEX https://x/pull/3 OPEN)"
run_gate --mode pre-release --task-md "$T3"
{ [[ $RC -eq 2 ]] && grep -q 'malformed' <<<"$OUT"; } \
  && ok "pre-release malformed head exit 2" || bad "malformed-head expected exit2 got $RC: $OUT"

# --- 4. pre-release CLOSED (stale) => exit 2 ---
C4="$TMP/DP-904"; mk_refinement "$C4" dp DP-904
T4="$(mk_task "$C4" T4 DP-904-T4 implementation task/DP-904-T4-x "$HEAD_OK" https://x/pull/4 CLOSED)"
run_gate --mode pre-release --task-md "$T4"
{ [[ $RC -eq 2 ]] && grep -q 'CLOSED' <<<"$OUT"; } \
  && ok "pre-release CLOSED stale exit 2" || bad "closed-stale expected exit2 got $RC: $OUT"

# --- 5. pre-release enumerate multiple at once ---
run_gate --mode pre-release --task-md "$T2" --task-md "$T4"
{ [[ $RC -eq 2 ]] && grep -q '2 non-conformant task' <<<"$OUT"; } \
  && ok "pre-release enumerates multiple non-conformant at once" || bad "multi-enum expected '2 non-conformant' got $RC: $OUT"

# --- 6. jira source no-op (pre-release), even with missing block ---
C6="$TMP/EXCO-EPIC1"; mk_refinement "$C6" jira EXCO-901
J1="$(mk_task "$C6" T1 EXCO-901-T1 implementation task/EXCO-901-T1-x)"
run_gate --mode pre-release --task-md "$J1"
{ [[ $RC -eq 0 ]] && grep -q 'no-op PASS' <<<"$OUT"; } \
  && ok "jira source pre-release no-op PASS" || bad "jira pre-release expected no-op 0 got $RC: $OUT"

# --- 7. jira source no-op (planning) ---
run_gate --mode planning --tasks-dir "$C6/tasks"
[[ $RC -eq 0 ]] && ok "jira source planning no-op PASS" || bad "jira planning expected 0 got $RC: $OUT"

# --- 8. planning branch-bearing required tasks => PASS ---
C8="$TMP/DP-908"; mk_refinement "$C8" dp DP-908
mk_task "$C8" T1 DP-908-T1 implementation task/DP-908-T1-x >/dev/null
mk_task "$C8" T2 DP-908-T2 implementation task/DP-908-T2-y >/dev/null
run_gate --mode planning --tasks-dir "$C8/tasks"
{ [[ $RC -eq 0 ]] && grep -q 'PASS (2 required task' <<<"$OUT"; } \
  && ok "planning branch-bearing PASS" || bad "planning conformant expected 0/2 got $RC: $OUT"

# --- 9. planning surfaces contract non-failing even when a branch derives later (no false-fail) ---
C9="$TMP/DP-909"; mk_refinement "$C9" dp DP-909
mk_task "$C9" T1 DP-909-T1 implementation task/DP-909-T1-x >/dev/null
mk_task "$C9" T2 DP-909-T2 implementation N/A >/dev/null
run_gate --mode planning --tasks-dir "$C9/tasks"
{ [[ $RC -eq 0 ]] && grep -q 'will require' <<<"$OUT" && grep -q 'DP-909-T2' <<<"$OUT" && grep -q '<derived at breakdown>' <<<"$OUT"; } \
  && ok "planning surfaces contract non-failing (branch derived later)" || bad "planning surfacing expected 0+emit got $RC: $OUT"

# --- 10. audit task_shape excluded from required set (no false positive) ---
C10="$TMP/DP-910"; mk_refinement "$C10" dp DP-910
mk_task "$C10" T1 DP-910-T1 audit N/A >/dev/null
run_gate --mode pre-release --task-md "$C10/tasks/T1/index.md"
{ [[ $RC -eq 0 ]] && grep -q '0 required task' <<<"$OUT"; } \
  && ok "audit shape excluded (0 required)" || bad "audit-excluded expected 0/0 got $RC: $OUT"

# --- 11. planning with refinement.json but no tasks dir yet (pre-breakdown LOCK) => no-op PASS ---
C11="$TMP/DP-911"; mk_refinement "$C11" dp DP-911
run_gate --mode planning --source-refinement-json "$C11/refinement.json"
{ [[ $RC -eq 0 ]] && grep -q 'nothing to check' <<<"$OUT"; } \
  && ok "planning no tasks dir yet => no-op PASS (pre-breakdown)" || bad "no-tasks-dir expected 0/no-op got $RC: $OUT"

# --- 12. pre-release: NO delivery block but --task-head-sha override supplies head (direct-commit-to-feat) => PASS ---
C12="$TMP/DP-912"; mk_refinement "$C12" dp DP-912
T12="$(mk_task "$C12" T1 DP-912-T1 implementation task/DP-912-T1-x)"  # no head/url/state block
run_gate --mode pre-release --task-md "$T12" --task-head-sha "DP-912-T1=$HEAD_OK"
{ [[ $RC -eq 0 ]] && grep -q '1 required task' <<<"$OUT"; } \
  && ok "pre-release override head (no block) => PASS (DP-360 authority order #1)" || bad "override-head expected 0/1 got $RC: $OUT"

# --- 13. pre-release: block records head_sha only (no pr_url/pr_state) => PASS (pr provenance optional) ---
C13="$TMP/DP-913"; mk_refinement "$C13" dp DP-913
T13="$(mk_task "$C13" T1 DP-913-T1 implementation task/DP-913-T1-x "$HEAD_OK")"  # head only
run_gate --mode pre-release --task-md "$T13"
{ [[ $RC -eq 0 ]] && grep -q '1 required task' <<<"$OUT"; } \
  && ok "pre-release head-only block (no PR) => PASS (pr_url/pr_state optional)" || bad "head-only expected 0/1 got $RC: $OUT"

# --- 14. pre-release: no block + override keyed to a DIFFERENT wid (no match) => fail-closed enumerate ---
C14="$TMP/DP-914"; mk_refinement "$C14" dp DP-914
T14="$(mk_task "$C14" T1 DP-914-T1 implementation task/DP-914-T1-x)"  # no block
run_gate --mode pre-release --task-md "$T14" --task-head-sha "DP-914-T2=$HEAD_OK"
{ [[ $RC -eq 2 ]] && grep -q 'no delivered head resolvable' <<<"$OUT" && grep -q 'DP-914-T1' <<<"$OUT"; } \
  && ok "pre-release override for wrong wid => fail-closed (map keying honored)" || bad "wrong-key-override expected exit2 got $RC: $OUT"

echo ""
echo "validate-delivery-evidence-conformance-selftest: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
