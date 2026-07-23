#!/usr/bin/env bash
# Purpose: validate an auto-pass terminal report JSON against the report
#          contract (.claude/skills/references/auto-pass-report.md): schema
#          shape, follow-up DP seed threshold, overlap disposition,
#          friction_log_summary ledger aggregation, plus DP-311 T3 fail-closed
#          cross-checks — (a) report.terminal_status=complete ↔ referenced
#          ledger terminal state; (b) report.verification.status=PASS ↔ the V
#          work item's task.md `ac_verification.status=PASS`, while an optional
#          verification.head_sha is bound to the required T task's canonical
#          deliverable.head_sha (report PR rows cannot self-attest authority).
#          DP-360 T7: the head-sha-keyed ac_verification marker is retired; the
#          V task lifecycle block + required_prs[] are the durable authorities.
# Inputs:  [--lifecycle-phase terminal|prearchive] /path/to/report.json.
#          prearchive is reserved for the canonical report writer and delays only
#          the terminal parent lifecycle postcondition; every other check remains
#          active. Optional env POLARIS_WORKSPACE_ROOT
#          overrides the scan root used to resolve the V work item's task.md
#          (hermetic selftests); default resolves the main checkout via
#          scripts/lib/main-checkout.sh from the report location.
# Outputs: "PASS: ..." on stdout. On failure: error list on stderr; cross-check
#          violations additionally emit structured POLARIS_AUTO_PASS_REPORT_*
#          markers and exit 2; schema-only violations exit 1.
set -euo pipefail

LIFECYCLE_PHASE="terminal"
REPORT_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lifecycle-phase)
      [[ $# -ge 2 ]] || { echo "error: --lifecycle-phase requires a value" >&2; exit 2; }
      LIFECYCLE_PHASE="$2"
      shift 2
      ;;
    -h|--help)
      REPORT_PATH=""
      break
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      exit 2
      ;;
    *)
      [[ -z "$REPORT_PATH" ]] || { echo "error: multiple report paths" >&2; exit 2; }
      REPORT_PATH="$1"
      shift
      ;;
  esac
done

if [[ "$LIFECYCLE_PHASE" != "terminal" && "$LIFECYCLE_PHASE" != "prearchive" ]]; then
  echo "error: --lifecycle-phase must be terminal or prearchive" >&2
  exit 2
fi

if [[ -z "$REPORT_PATH" ]]; then
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-report.sh \
    [--lifecycle-phase terminal|prearchive] /path/to/report.json

env:
  POLARIS_WORKSPACE_ROOT  override scan root for resolving the V work item's
                          task.md lifecycle block (selftests)
USAGE
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# DP-330 T2: workspace root for follow_up_dp_seed.contract_evidence path:line
# validation. This is the repo containing scripts/, resolved from this script's
# location — distinct from EVIDENCE_ROOT (which can be overridden to a hermetic
# temp dir for ac_verification marker selftests). contract_evidence points at
# real source files, so it always resolves against the actual repo.
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# DP-311 T3: resolve the evidence root for head-bound ac_verification markers.
# Order: explicit env override → main checkout resolved from the report path
# (worktree-safe; markers live only in the main checkout) → main checkout
# resolved from this script's location.
EVIDENCE_ROOT="${POLARIS_WORKSPACE_ROOT:-}"
if [[ -z "$EVIDENCE_ROOT" ]]; then
  # shellcheck source=lib/main-checkout.sh
  source "$SCRIPT_DIR/lib/main-checkout.sh"
  report_dir="$(cd "$(dirname "$REPORT_PATH")" 2>/dev/null && pwd || true)"
  if [[ -n "$report_dir" ]]; then
    EVIDENCE_ROOT="$(resolve_main_checkout "$report_dir" 2>/dev/null || true)"
  fi
  if [[ -z "$EVIDENCE_ROOT" ]]; then
    EVIDENCE_ROOT="$(resolve_main_checkout "$SCRIPT_DIR" 2>/dev/null || true)"
  fi
fi

# DP-303 T5: resolve the specs root used for the follow_up_dp_seed collision
# check. The seed's DP number must not already be occupied across the active
# (design-plans/DP-*) and archive (design-plans/archive/DP-*) namespaces — the
# same occupancy semantics as scripts/allocate-design-plan-number.sh. Order:
# explicit POLARIS_SPECS_ROOT override (hermetic selftests) → workspace docs
# specs root resolved from this script's location.
SPECS_ROOT="${POLARIS_SPECS_ROOT:-$WORKSPACE_ROOT/docs-manager/src/content/docs/specs}"

RESOLVER="$SCRIPT_DIR/resolve-task-md.sh" PARSER="$SCRIPT_DIR/parse-task-md.sh" \
PR_OWNERSHIP_GATE="$SCRIPT_DIR/auto-pass-pr-ownership-gate.sh" \
python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_validate_auto_pass_report_1.py" \
  "$REPORT_PATH" "$EVIDENCE_ROOT" "$WORKSPACE_ROOT" "$SPECS_ROOT" "$LIFECYCLE_PHASE"
