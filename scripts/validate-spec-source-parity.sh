#!/usr/bin/env bash
# scripts/validate-spec-source-parity.sh — DP-228 T5
#
# Framework PR gate validator that enforces DP / company-Epic source parity:
#
#   1. Producer registry parity (AC2, AC-NF1):
#      For every path_glob entry in `scripts/lib/evidence-producers.json` that
#      targets the design-plans/DP-* spec namespace, there must be a matching
#      companies/*/*/{KEY} glob entry on the same producer, and vice versa.
#      Inherent asymmetry must be declared in
#      `scripts/lib/spec-source-parity-allowlist.txt` under [registry];
#      otherwise the gate exits 2.
#
#   2. Auto-pass DP-only routing prose scan (AC-NF4):
#      Scan auto-pass owning surface — the skill SKILL.md, helper scripts,
#      shared references, and the framework routing rule — for new DP-only
#      routing prose (patterns that gate execution on source type "DP-backed
#      source" while remaining surfaces have already been migrated to
#      source-neutral wording). Surfaces still mid-migration are baselined in
#      the allowlist under [auto-pass-prose]; new DP-only routing prose on
#      surfaces NOT in the allowlist is fail-stop.
#
#   3. Render-body parity proof (DP-302 AC5):
#      Field-driven detection of DP-only body literals in derived task.md
#      render output. The caller supplies one or more dp-render::jira-render
#      pairs (derive output of IDENTICAL refinement.json content, differing
#      only in source.type / container). The gate proves each `design-plans/`
#      body literal in the dp render is CONTAINER-DERIVED (it shifts to a
#      `companies/` literal at the same structural position in the jira render),
#      not HARDCODED. A `design-plans/` literal that appears UNCHANGED in the
#      jira render is a hardcoded DP-only body literal -> exit 2. This replaces
#      a brittle absolute string blacklist (EC3): a task that legitimately
#      mentions `design-plans/` via a container path shifts under jira, while a
#      hardcoded framework literal does not.
#
#   4. Resolver-logic parity face (DP-370 T3):
#      Delegate to scripts/lint-dp-keyed-source-symmetry.sh so DP-keyed
#      resolver/reader/container-enum logic must carry a companies/JIRA-Epic
#      counterpart unless documented in [resolver-logic] allowlist.
#
# Exit codes:
#   0  PASS
#   2  Parity / DP-only drift detected
#   3  Usage / IO error
#
# Inputs (env, all optional):
#   POLARIS_PRODUCER_REGISTRY     default scripts/lib/evidence-producers.json
#   POLARIS_PARITY_ALLOWLIST      default scripts/lib/spec-source-parity-allowlist.txt
#   POLARIS_AUTO_PASS_SURFACES    newline-separated override for the auto-pass
#                                 surface file list (used by the selftest to
#                                 redirect the scan into a fixture).
#   POLARIS_RENDER_BODY_PAIRS     newline-separated render-body parity proofs,
#                                 each "dp_render_path::jira_render_path". When
#                                 empty (the framework PR gate default) Part 3
#                                 is a no-op; callers that can produce a render
#                                 pair (derive selftest, auto-pass dispatch)
#                                 supply pairs to exercise the proof.
#   POLARIS_DP_KEYED_SOURCE_SURFACES
#                                 newline-separated resolver-logic surface
#                                 override, forwarded to the resolver lint.
#
# Usage:
#   bash scripts/validate-spec-source-parity.sh

set -euo pipefail

PREFIX="[spec-source-parity]"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/validate-spec-source-parity.sh

Validates DP / company-Epic source parity in scripts/lib/evidence-producers.json
and scans the auto-pass surface for DP-only routing drift.

Exit:  0 = PASS, 2 = parity / drift detected, 3 = usage / IO error.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REGISTRY="${POLARIS_PRODUCER_REGISTRY:-scripts/lib/evidence-producers.json}"
ALLOWLIST="${POLARIS_PARITY_ALLOWLIST:-scripts/lib/spec-source-parity-allowlist.txt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DP_KEYED_SOURCE_LINT="${POLARIS_DP_KEYED_SOURCE_LINT:-$SCRIPT_DIR/lint-dp-keyed-source-symmetry.sh}"

[[ -f "$REGISTRY" ]] || { echo "$PREFIX registry not found: $REGISTRY" >&2; exit 3; }
[[ -f "$ALLOWLIST" ]] || { echo "$PREFIX allowlist not found: $ALLOWLIST" >&2; exit 3; }
[[ -x "$DP_KEYED_SOURCE_LINT" ]] || { echo "$PREFIX resolver-logic lint not executable: $DP_KEYED_SOURCE_LINT" >&2; exit 3; }

# Default auto-pass surface list — overrideable via POLARIS_AUTO_PASS_SURFACES
# (newline-separated). Selftest fixtures point this at a temp directory.
if [[ -n "${POLARIS_AUTO_PASS_SURFACES:-}" ]]; then
  AUTO_PASS_SURFACES="$POLARIS_AUTO_PASS_SURFACES"
else
  AUTO_PASS_SURFACES="$(cat <<'EOF'
.claude/skills/auto-pass/SKILL.md
scripts/auto-pass-probe.sh
scripts/auto-pass-increment-counter.sh
.claude/skills/references/auto-pass-ledger.md
.claude/skills/references/auto-pass-execution-flow.md
.claude/rules/skill-routing.md
EOF
)"
fi

export POLARIS_REGISTRY_INPUT="$REGISTRY"
export POLARIS_ALLOWLIST_INPUT="$ALLOWLIST"
export POLARIS_AUTO_PASS_SURFACES_INPUT="$AUTO_PASS_SURFACES"
export POLARIS_RENDER_BODY_PAIRS_INPUT="${POLARIS_RENDER_BODY_PAIRS:-}"
export POLARIS_PREFIX="$PREFIX"

POLARIS_PARITY_ALLOWLIST="$ALLOWLIST" bash "$DP_KEYED_SOURCE_LINT" >/dev/null

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_spec_source_parity_1.py"
