#!/usr/bin/env bash
# Purpose: DP-419 T2 hermetic selftest for scripts/detect-self-referential-delivery.sh —
#          assert the D1 deterministic self-referential-DP classifier: a DP whose
#          planned-task Allowed Files intersect the delivery-gate script set
#          (manifest kind=gate|hook scripts + the 3 delivery lane entrypoints +
#          the scripts/lib/*.sh they source) is classified self_referential=true
#          with the matched members enumerated, while non-delivery-gate changes
#          are self_referential=false (AC-NEG3), and missing input fails closed.
# Inputs:  none (builds a synthetic repo-root fixture under mktemp with a fixture
#          manifest.json, fixture gate/support/lib scripts, and fixture lane
#          entrypoints; drives the real classifier with --repo-root / --manifest
#          overrides so the assertions do not depend on the live workspace corpus).
# Outputs: stdout PASS/FAIL lines; exit 0 all-pass, exit 1 any failure.
# Side effects: tmpdir only (removed on EXIT). No live workspace mutation.
#
# Coverage map:
#   AC1 gate-body   — Allowed Files include a manifest kind=gate script => true,
#                     matched contains that gate.
#   AC1 lane        — Allowed Files include a delivery lane entrypoint => true.
#   AC1 lib-layer   — Allowed Files include a scripts/lib/*.sh sourced by a
#                     gate/lane script => true, matched contains that lib.
#   AC-NEG3         — Allowed Files only reference/docs/non-gate (kind=support)
#                     scripts => false, matched empty.
#   missing-input   — no Allowed Files provided => exit 2 + POLARIS_* marker.
#   mixed           — one gate + one unrelated => true, matched only the gate.
#   abs-path        — absolute path under repo-root normalizes and matches.
#   stdin           — --stdin newline-separated input path matches.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFIER="${SCRIPT_DIR}/detect-self-referential-delivery.sh"

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:jq (selftest requires jq; run 'mise install')" >&2
  exit 2
fi

FIXTURE="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

# --- build hermetic repo-root fixture ---------------------------------------
mkdir -p "${FIXTURE}/scripts/lib" \
         "${FIXTURE}/scripts/selftests" \
         "${FIXTURE}/.claude/hooks" \
         "${FIXTURE}/.claude/skills/references" \
         "${FIXTURE}/docs-manager/src/content/docs"

# Fixture manifest: one delivery gate (kind=gate) + one non-gate helper
# (kind=support). Only the gate must enter the delivery-gate script set.
cat >"${FIXTURE}/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/fixture-gate.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "framework_pr_gate",
      "selftest": "N/A",
      "lifecycle": "hot_path",
      "relocation": "stay",
      "selftest_reason": "fixture"
    },
    {
      "path": "scripts/fixture-support.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "lifecycle": "support_path",
      "relocation": "stay",
      "selftest_reason": "fixture"
    }
  ]
}
JSON

# Fixture gate sources a lib -> multi-layer self-reference target.
cat >"${FIXTURE}/scripts/fixture-gate.sh" <<'SH'
#!/usr/bin/env bash
# Purpose: fixture delivery gate that sources a shared lib.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/fixture-helper.sh
. "${SCRIPT_DIR}/lib/fixture-helper.sh"
SH

# Fixture lib sourced by the gate (self-reference at the lib layer).
cat >"${FIXTURE}/scripts/lib/fixture-helper.sh" <<'SH'
#!/usr/bin/env bash
# Purpose: fixture shared helper sourced by fixture-gate.sh.
fixture_helper_noop() { :; }
SH

# Non-gate helper (kind=support): must NOT be in the delivery-gate set.
cat >"${FIXTURE}/scripts/fixture-support.sh" <<'SH'
#!/usr/bin/env bash
# Purpose: fixture support script, not a delivery gate.
set -euo pipefail
echo support
SH

# Fixture delivery lane entrypoints (resolved relative to --repo-root).
cat >"${FIXTURE}/.claude/hooks/pre-push-quality-gate.sh" <<'SH'
#!/usr/bin/env bash
# Purpose: fixture pre-push lane entrypoint.
set -euo pipefail
echo pre-push
SH
cat >"${FIXTURE}/scripts/check-framework-pr-gate.sh" <<'SH'
#!/usr/bin/env bash
# Purpose: fixture PR gate lane entrypoint.
set -euo pipefail
echo pr-gate
SH
cat >"${FIXTURE}/scripts/framework-release-pr-lane.sh" <<'SH'
#!/usr/bin/env bash
# Purpose: fixture release lane entrypoint.
set -euo pipefail
echo release-lane
SH

# Non-delivery-gate surfaces (AC-NEG3 negatives).
printf '# fixture reference\n' >"${FIXTURE}/.claude/skills/references/foo.md"
printf '# fixture doc\n' >"${FIXTURE}/docs-manager/src/content/docs/foo.md"

run() {
  # run --repo-root <fixture> <args...>; echoes stdout, sets RC.
  set +e
  OUT="$("$CLASSIFIER" --repo-root "$FIXTURE" --manifest "${FIXTURE}/scripts/manifest.json" "$@" 2>ERR_TMP)"
  RC=$?
  ERR="$(cat ERR_TMP 2>/dev/null || true)"
  rm -f ERR_TMP
  set -e
}

is_self_ref() { jq -r '.self_referential' <<<"$OUT"; }
matched_has() { jq -e --arg p "$1" '.matched | index($p)' <<<"$OUT" >/dev/null 2>&1; }
matched_len() { jq -r '.matched | length' <<<"$OUT"; }

# --- AC1 gate-body ----------------------------------------------------------
run --allowed-file scripts/fixture-gate.sh
if [[ "$RC" -eq 0 && "$(is_self_ref)" == "true" ]] && matched_has scripts/fixture-gate.sh; then
  pass "AC1 gate-body: gate script in Allowed Files => self_referential + matched"
else
  fail "AC1 gate-body: expected true+matched (rc=$RC out=$OUT)"
fi

# --- AC1 lane entrypoint -----------------------------------------------------
run --allowed-file .claude/hooks/pre-push-quality-gate.sh
if [[ "$RC" -eq 0 && "$(is_self_ref)" == "true" ]] && matched_has .claude/hooks/pre-push-quality-gate.sh; then
  pass "AC1 lane: delivery lane entrypoint in Allowed Files => self_referential"
else
  fail "AC1 lane: expected true+matched (rc=$RC out=$OUT)"
fi

# --- AC1 lib-layer -----------------------------------------------------------
run --allowed-file scripts/lib/fixture-helper.sh
if [[ "$RC" -eq 0 && "$(is_self_ref)" == "true" ]] && matched_has scripts/lib/fixture-helper.sh; then
  pass "AC1 lib-layer: sourced lib in Allowed Files => self_referential"
else
  fail "AC1 lib-layer: expected true+matched lib (rc=$RC out=$OUT)"
fi

# --- AC-NEG3 non-delivery-gate ----------------------------------------------
run --allowed-file .claude/skills/references/foo.md \
    --allowed-file scripts/fixture-support.sh \
    --allowed-file docs-manager/src/content/docs/foo.md
if [[ "$RC" -eq 0 && "$(is_self_ref)" == "false" && "$(matched_len)" == "0" ]]; then
  pass "AC-NEG3: reference/docs/non-gate support => self_referential=false, matched empty"
else
  fail "AC-NEG3: expected false+empty (rc=$RC out=$OUT)"
fi

# --- missing input fail-closed ----------------------------------------------
run
if [[ "$RC" -eq 2 ]] && printf '%s' "$ERR" | grep -q 'POLARIS_'; then
  pass "missing-input: no Allowed Files => exit 2 + POLARIS_* marker"
else
  fail "missing-input: expected exit 2 + POLARIS marker (rc=$RC err=$ERR)"
fi

# --- mixed: gate + unrelated => true, matched only the gate -----------------
run --allowed-file scripts/fixture-gate.sh --allowed-file .claude/skills/references/foo.md
if [[ "$RC" -eq 0 && "$(is_self_ref)" == "true" && "$(matched_len)" == "1" ]] && matched_has scripts/fixture-gate.sh; then
  pass "mixed: gate + unrelated => true, matched only the gate"
else
  fail "mixed: expected true + single gate match (rc=$RC out=$OUT)"
fi

# --- absolute path normalization --------------------------------------------
run --allowed-file "${FIXTURE}/scripts/fixture-gate.sh"
if [[ "$RC" -eq 0 && "$(is_self_ref)" == "true" ]] && matched_has scripts/fixture-gate.sh; then
  pass "abs-path: absolute Allowed File under repo-root normalizes and matches"
else
  fail "abs-path: expected true+matched (rc=$RC out=$OUT)"
fi

# --- stdin input ------------------------------------------------------------
set +e
OUT="$(printf 'scripts/fixture-gate.sh\n' | "$CLASSIFIER" --repo-root "$FIXTURE" --manifest "${FIXTURE}/scripts/manifest.json" --stdin 2>/dev/null)"
RC=$?
set -e
if [[ "$RC" -eq 0 && "$(jq -r '.self_referential' <<<"$OUT")" == "true" ]]; then
  pass "stdin: --stdin newline-separated Allowed File matches"
else
  fail "stdin: expected true (rc=$RC out=$OUT)"
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "${FAILS} FAIL(s)"
exit 1
