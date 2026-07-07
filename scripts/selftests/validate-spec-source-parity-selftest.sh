#!/usr/bin/env bash
# scripts/selftests/validate-spec-source-parity-selftest.sh — DP-228 T5
#
# Selftest fixtures for `scripts/validate-spec-source-parity.sh`. Each case
# builds a self-contained registry + allowlist + auto-pass surface tree and
# drives the validator via env overrides so the real workspace files are not
# touched.
#
# Cases:
#   F1 parity PASS — DP/companies mirrored entries, clean auto-pass surface.
#   F2 DP-only producer entry FAIL — registry has DP glob without companies/.
#   F3 companies-only producer entry FAIL — registry has companies/ glob
#      without DP counterpart.
#   F4 registry asymmetry PASS via [registry] allowlist.
#   F5 DP-only routing prose FAIL on non-allowlisted surface.
#   F6 DP-only routing prose PASS when surface is listed under
#      [auto-pass-prose].
#   F7 Smoke — real registry under repo cwd must PASS.
#   F8 Render-body parity PASS (DP-302 AC5) — a dp render and a jira render of
#      identical content where every `design-plans/` body literal in the dp
#      render shifts to a `companies/` literal at the same structural position
#      in the jira render (field-driven, container-derived). The gate proves the
#      body cannot grow DP-only literals.
#   F9 Render-body parity FAIL (DP-302 AC5) — the dp render carries a DP-only
#      body literal (hardcoded `design-plans/` path / framework-only Verify tail)
#      that does NOT shift in the jira render of identical content, proving the
#      literal is hardcoded rather than container-driven.
#   F10 Resolver-logic parity FAIL (DP-370 T3) — aggregate validator consumes
#      lint-dp-keyed-source-symmetry.sh and fails on DP-keyed resolver logic
#      without a companies/JIRA-Epic counterpart.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-spec-source-parity.sh"

if [[ ! -x "$VALIDATOR" ]]; then
  echo "FAIL: validator not executable: $VALIDATOR" >&2
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

_assert() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [$TOTAL]: expected='$2' got='$1' — $3" >&2
  fi
}

TMP="$(mktemp -d -t spec-source-parity-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_registry() {
  local out="$1"
  shift
  # shellcheck disable=SC2016
  python3 - "$out" "$@" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
producers = []
for entry in sys.argv[2:]:
    owning, writer, globs_str = entry.split("||", 2)
    globs = [g for g in globs_str.split("\n") if g]
    producers.append({
        "owning_skill": owning,
        "writer": writer,
        "writer_scripts": ["scripts/test.sh"],
        "marker_kinds": ["test"],
        "path_globs": globs,
    })
out.write_text(json.dumps({"schema_version": 1, "producers": producers}, indent=2) + "\n")
PY
}

write_allowlist() {
  local out="$1"
  shift
  : > "$out"
  while [[ $# -gt 0 ]]; do
    printf '%s\n' "$1" >> "$out"
    shift
  done
}

write_surface() {
  local dir="$1"
  local rel="$2"
  local body="$3"
  mkdir -p "$(dirname "$dir/$rel")"
  printf '%s\n' "$body" > "$dir/$rel"
}

run_validator_with() {
  # args: registry_path allowlist_path surfaces_value...
  local registry="$1"
  local allowlist="$2"
  shift 2
  local surfaces=""
  while [[ $# -gt 0 ]]; do
    surfaces+="$1"$'\n'
    shift
  done
  POLARIS_PRODUCER_REGISTRY="$registry" \
    POLARIS_PARITY_ALLOWLIST="$allowlist" \
    POLARIS_AUTO_PASS_SURFACES="$surfaces" \
    bash "$VALIDATOR"
}

# ---------------------------------------------------------------------------
# F1 — parity PASS with mirrored DP/companies entries and clean surfaces
# ---------------------------------------------------------------------------
F1_DIR="$TMP/f1"
mkdir -p "$F1_DIR"
write_registry "$F1_DIR/registry.json" \
  "refinement||refinement-md-writer||docs-manager/src/content/docs/specs/design-plans/DP-*/refinement.md
docs-manager/src/content/docs/specs/companies/*/*/refinement.md"
write_allowlist "$F1_DIR/allowlist.txt" \
  "[registry]" \
  "[auto-pass-prose]"
write_surface "$F1_DIR" "surface/SKILL.md" "Source-neutral routing prose."
run_validator_with "$F1_DIR/registry.json" "$F1_DIR/allowlist.txt" "$F1_DIR/surface/SKILL.md" >/dev/null 2>"$TMP/f1.err"
_assert "$?" "0" "F1: mirrored entries + clean surface should PASS"

# ---------------------------------------------------------------------------
# F2 — DP-only producer entry FAIL
# ---------------------------------------------------------------------------
F2_DIR="$TMP/f2"
mkdir -p "$F2_DIR"
write_registry "$F2_DIR/registry.json" \
  "refinement||refinement-md-writer||docs-manager/src/content/docs/specs/design-plans/DP-*/refinement.md"
write_allowlist "$F2_DIR/allowlist.txt" \
  "[registry]" \
  "[auto-pass-prose]"
write_surface "$F2_DIR" "surface/SKILL.md" "Source-neutral routing prose."
run_validator_with "$F2_DIR/registry.json" "$F2_DIR/allowlist.txt" "$F2_DIR/surface/SKILL.md" >/dev/null 2>"$TMP/f2.err"
F2_RC=$?
_assert "$F2_RC" "2" "F2: DP-only producer entry should exit 2"
if grep -q "lacks companies/ counterpart" "$TMP/f2.err"; then F2_MSG="found"; else F2_MSG="missing"; fi
_assert "$F2_MSG" "found" "F2: stderr should name the missing companies/ counterpart"

# ---------------------------------------------------------------------------
# F3 — companies-only producer entry FAIL
# ---------------------------------------------------------------------------
F3_DIR="$TMP/f3"
mkdir -p "$F3_DIR"
write_registry "$F3_DIR/registry.json" \
  "refinement||refinement-md-writer||docs-manager/src/content/docs/specs/companies/*/*/refinement.md"
write_allowlist "$F3_DIR/allowlist.txt" \
  "[registry]" \
  "[auto-pass-prose]"
write_surface "$F3_DIR" "surface/SKILL.md" "Source-neutral routing prose."
run_validator_with "$F3_DIR/registry.json" "$F3_DIR/allowlist.txt" "$F3_DIR/surface/SKILL.md" >/dev/null 2>"$TMP/f3.err"
F3_RC=$?
_assert "$F3_RC" "2" "F3: companies-only producer entry should exit 2"
if grep -q "lacks DP-\* counterpart" "$TMP/f3.err"; then F3_MSG="found"; else F3_MSG="missing"; fi
_assert "$F3_MSG" "found" "F3: stderr should name the missing DP-* counterpart"

# ---------------------------------------------------------------------------
# F4 — registry asymmetry allowed via [registry] allowlist
# ---------------------------------------------------------------------------
F4_DIR="$TMP/f4"
mkdir -p "$F4_DIR"
write_registry "$F4_DIR/registry.json" \
  "refinement||refinement-md-writer||docs-manager/src/content/docs/specs/design-plans/DP-*/refinement.md"
write_allowlist "$F4_DIR/allowlist.txt" \
  "[registry]" \
  "docs-manager/src/content/docs/specs/companies/*/*/refinement.md" \
  "[auto-pass-prose]"
write_surface "$F4_DIR" "surface/SKILL.md" "Source-neutral routing prose."
run_validator_with "$F4_DIR/registry.json" "$F4_DIR/allowlist.txt" "$F4_DIR/surface/SKILL.md" >/dev/null 2>"$TMP/f4.err"
_assert "$?" "0" "F4: registry asymmetry should PASS when listed in [registry] allowlist"

# ---------------------------------------------------------------------------
# F5 — DP-only routing prose FAIL on non-allowlisted surface
# ---------------------------------------------------------------------------
F5_DIR="$TMP/f5"
mkdir -p "$F5_DIR"
write_registry "$F5_DIR/registry.json" \
  "refinement||refinement-md-writer||docs-manager/src/content/docs/specs/design-plans/DP-*/refinement.md
docs-manager/src/content/docs/specs/companies/*/*/refinement.md"
write_allowlist "$F5_DIR/allowlist.txt" \
  "[registry]" \
  "[auto-pass-prose]"
write_surface "$F5_DIR" "surface/SKILL.md" $'Source routing notes.\nv2 只接受 DP-backed source 直到 Epic 對齊。\nEnd.'
run_validator_with "$F5_DIR/registry.json" "$F5_DIR/allowlist.txt" "$F5_DIR/surface/SKILL.md" >/dev/null 2>"$TMP/f5.err"
F5_RC=$?
_assert "$F5_RC" "2" "F5: DP-only routing prose on non-allowlisted surface should exit 2"
if grep -q "DP-only routing prose" "$TMP/f5.err"; then F5_MSG="found"; else F5_MSG="missing"; fi
_assert "$F5_MSG" "found" "F5: stderr should cite the DP-only routing prose hit"

# ---------------------------------------------------------------------------
# F6 — DP-only routing prose tolerated when surface is in [auto-pass-prose]
# ---------------------------------------------------------------------------
F6_DIR="$TMP/f6"
mkdir -p "$F6_DIR"
write_registry "$F6_DIR/registry.json" \
  "refinement||refinement-md-writer||docs-manager/src/content/docs/specs/design-plans/DP-*/refinement.md
docs-manager/src/content/docs/specs/companies/*/*/refinement.md"
write_allowlist "$F6_DIR/allowlist.txt" \
  "[registry]" \
  "[auto-pass-prose]" \
  "surface/SKILL.md:transitional:migration-task-T15"
write_surface "$F6_DIR" "surface/SKILL.md" $'Source routing notes.\nv2 只接受 DP-backed source 直到 Epic 對齊。\nEnd.'
# Validator interprets surface paths relative to cwd, so cd into F6_DIR for this case.
( cd "$F6_DIR" && POLARIS_PRODUCER_REGISTRY="$F6_DIR/registry.json" \
    POLARIS_PARITY_ALLOWLIST="$F6_DIR/allowlist.txt" \
    POLARIS_AUTO_PASS_SURFACES="surface/SKILL.md" \
    bash "$VALIDATOR" ) >/dev/null 2>"$TMP/f6.err"
_assert "$?" "0" "F6: allowlisted surface should PASS even with DP-only prose"

# ---------------------------------------------------------------------------
# F7 — smoke test against real registry
# ---------------------------------------------------------------------------
( cd "$ROOT_DIR" && bash "$VALIDATOR" ) >/dev/null 2>"$TMP/f7.err"
_assert "$?" "0" "F7: real registry under repo cwd should PASS"

# ---------------------------------------------------------------------------
# Render-body parity helpers (DP-302 AC5)
# ---------------------------------------------------------------------------
# A clean field-driven render pair: identical structure, container-derived body
# literals. The dp render carries `design-plans/` references; the jira render
# carries the matching `companies/` references at the same structural position.
# Because the dp `design-plans/` literal shifts to a `companies/` literal in the
# jira render, the gate concludes the literal is container-derived (PASS).
write_render_pair() {
  # args: dp_out jira_out dp_ref_dir jira_ref_dir [verify_tail_dp] [verify_tail_jira]
  local dp_out="$1" jira_out="$2" dp_ref="$3" jira_ref="$4"
  local verify_dp="${5:-bash scripts/selftests/sample-selftest.sh}"
  local verify_jira="${6:-bash scripts/selftests/sample-selftest.sh}"
  cat >"$dp_out" <<EOF
| References to load | - \`$dp_ref/refinement.md\`<br>- \`$dp_ref/refinement.json\` |

## Verify Command

\`\`\`bash
set -euo pipefail
$verify_dp
\`\`\`
EOF
  cat >"$jira_out" <<EOF
| References to load | - \`$jira_ref/refinement.md\`<br>- \`$jira_ref/refinement.json\` |

## Verify Command

\`\`\`bash
set -euo pipefail
$verify_jira
\`\`\`
EOF
}

run_validator_render_pair() {
  # args: dp_render jira_render
  POLARIS_PRODUCER_REGISTRY="$F1_DIR/registry.json" \
    POLARIS_PARITY_ALLOWLIST="$F1_DIR/allowlist.txt" \
    POLARIS_AUTO_PASS_SURFACES="$F1_DIR/surface/SKILL.md" \
    POLARIS_RENDER_BODY_PAIRS="$1::$2" \
    bash "$VALIDATOR"
}

# ---------------------------------------------------------------------------
# F8 — render-body parity PASS (field-driven, container-derived literals)
# ---------------------------------------------------------------------------
F8_DIR="$TMP/f8"
mkdir -p "$F8_DIR"
write_render_pair "$F8_DIR/dp.md" "$F8_DIR/jira.md" \
  "docs-manager/src/content/docs/specs/design-plans/DP-500-sample" \
  "docs-manager/src/content/docs/specs/companies/exampleco/PROJ-500"
run_validator_render_pair "$F8_DIR/dp.md" "$F8_DIR/jira.md" >/dev/null 2>"$TMP/f8.err"
_assert "$?" "0" "F8: field-driven render pair (design-plans -> companies) should PASS"

# ---------------------------------------------------------------------------
# F9 — render-body parity FAIL (hardcoded DP-only body literal)
# ---------------------------------------------------------------------------
# The dp render carries a `design-plans/` Verify-tail literal that the jira
# render reproduces UNCHANGED (still `design-plans/`), proving the literal is
# hardcoded rather than container-derived.
F9_DIR="$TMP/f9"
mkdir -p "$F9_DIR"
write_render_pair "$F9_DIR/dp.md" "$F9_DIR/jira.md" \
  "docs-manager/src/content/docs/specs/design-plans/DP-500-sample" \
  "docs-manager/src/content/docs/specs/companies/exampleco/PROJ-500" \
  "bash scripts/x.sh docs-manager/src/content/docs/specs/design-plans/DP-500-sample" \
  "bash scripts/x.sh docs-manager/src/content/docs/specs/design-plans/DP-500-sample"
run_validator_render_pair "$F9_DIR/dp.md" "$F9_DIR/jira.md" >/dev/null 2>"$TMP/f9.err"
F9_RC=$?
_assert "$F9_RC" "2" "F9: hardcoded DP-only body literal in render should exit 2"
if grep -q "DP-only body literal" "$TMP/f9.err"; then F9_MSG="found"; else F9_MSG="missing"; fi
_assert "$F9_MSG" "found" "F9: stderr should cite the DP-only body literal"

# ---------------------------------------------------------------------------
# F10 — resolver-logic parity FAIL (DP-370 T3 aggregate face)
# ---------------------------------------------------------------------------
F10_DIR="$TMP/f10"
mkdir -p "$F10_DIR"
cat >"$F10_DIR/asymmetric.sh" <<'EOF'
resolve_by_dp() {
  find docs-manager/src/content/docs/specs/design-plans -name 'DP-*'
}
EOF
POLARIS_PRODUCER_REGISTRY="$F1_DIR/registry.json" \
  POLARIS_PARITY_ALLOWLIST="$F1_DIR/allowlist.txt" \
  POLARIS_AUTO_PASS_SURFACES="$F1_DIR/surface/SKILL.md" \
  POLARIS_DP_KEYED_SOURCE_SURFACES="$F10_DIR/asymmetric.sh" \
  bash "$VALIDATOR" >/dev/null 2>"$TMP/f10.err"
F10_RC=$?
_assert "$F10_RC" "2" "F10: aggregate validator should consume resolver-logic lint and exit 2"
if grep -q "POLARIS_DP_KEYED_SOURCE_ASYMMETRY" "$TMP/f10.err"; then F10_MSG="found"; else F10_MSG="missing"; fi
_assert "$F10_MSG" "found" "F10: stderr should include resolver-logic asymmetry marker"

echo ""
echo "validate-spec-source-parity selftest: $PASS/$TOTAL passed, $FAIL failed"
if [[ "$FAIL" -ne 0 ]]; then
  echo "--- captured stderr ---"
  for f in "$TMP"/*.err; do
    [[ -s "$f" ]] || continue
    echo "## $(basename "$f")"
    cat "$f"
  done
  exit 1
fi
echo "PASS"
exit 0
