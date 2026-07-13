#!/usr/bin/env bash
# Purpose: DP-417 T13 — real-epic end-to-end trial-run acceptance harness. Runs the
#          deterministic refinement -> auto-pass chain against a specimen source
#          container and asserts ZERO spec<->check bounces / zero rule-fighting
#          bounces. This is the integration acceptance of DP-417's thesis — "author
#          the artifact per the spec => the deterministic checks pass BY
#          CONSTRUCTION" — that goes beyond each task's unit selftest.
#
#          Two deterministic stages, both reusing existing gates (no re-implemented
#          spec<->check detection):
#            stage 1 (chain)   : validate-refinement-lock-preflight.sh <specimen>
#                                — full-derives each planned task.md and runs the
#                                real breakdown-ready gate (covers derive /
#                                lock-preflight / handoff / breakdown-ready).
#            stage 2 (contract): validate-spec-check-contract-parity.sh --repo-root
#                                — the T11 bidirectional spec<->check parity gate.
#          A "bounce" is any stage that rejects the specimen (non-zero exit). Zero
#          bounces => the flow is repaired; any bounce => DP-417 is NOT complete
#          (AC-NEG11). A warning is NOT a pass — only exit 0 counts.
#
#          The harness is specimen-agnostic: the real acceptance specimen (e.g. a
#          live product epic) is supplied at invocation via --source, so no live
#          ticket key is baked into this template-facing source. The selftest drives
#          it with generic fixtures.
# Inputs:  --source <refinement.json | source-container dir>  (required specimen)
#          --repo-root <path>   (default: git toplevel of cwd, else this script's repo)
#          --json               (emit a machine-readable one-line JSON summary)
# Outputs: stdout human/JSON summary; exit 0 = 0 bounces (CLEAN),
#          exit 2 = >=1 bounce (POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE) or missing input.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE=""
REPO_ROOT=""
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="${2:-}"; shift 2 ;;
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help)
      grep -E '^# ' "${BASH_SOURCE[0]}" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SOURCE" ]]; then
  echo "POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE: --source <refinement.json|container dir> is required" >&2
  exit 2
fi
if [[ ! -e "$SOURCE" ]]; then
  echo "POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE: specimen source not found: $SOURCE" >&2
  exit 2
fi

if [[ -z "$REPO_ROOT" ]]; then
  # git toplevel if inside a repo, else fall back to this script's parent dir.
  # NB: keep the git branch and the fallback as separate statements — a single
  # `git ... || cd ... && pwd` chain mis-parses (|| and && are left-associative
  # with equal precedence), appending pwd to a successful git result.
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || REPO_ROOT=""
  if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  fi
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

PREFLIGHT="$SCRIPT_DIR/validate-refinement-lock-preflight.sh"
PARITY="$SCRIPT_DIR/validate-spec-check-contract-parity.sh"
for gate in "$PREFLIGHT" "$PARITY"; do
  if [[ ! -x "$gate" && ! -f "$gate" ]]; then
    echo "POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE: required gate missing: $gate" >&2
    exit 2
  fi
done

BOUNCES=0
declare -a BOUNCED_STAGES=()

# run_stage <label> <cmd...> — run a chain/contract gate; a non-zero exit is a bounce.
run_stage() {
  local label="$1"; shift
  local err rc
  err="$(mktemp)"
  if "$@" >/dev/null 2>"$err"; then
    echo "  [stage] ${label}: PASS (0 bounce)"
  else
    rc=$?
    BOUNCES=$((BOUNCES + 1))
    BOUNCED_STAGES+=("$label")
    echo "  [stage] ${label}: BOUNCE (exit ${rc})"
    sed 's/^/    /' "$err" | grep -E 'POLARIS_|FAIL|BLOCKED' | head -3 || true
  fi
  rm -f "$err"
}

echo "spec-check real-epic trial run"
echo "  specimen : $SOURCE"
echo "  repo-root: $REPO_ROOT"

run_stage "chain(lock-preflight-derive-breakdown-ready)" bash "$PREFLIGHT" "$SOURCE"
run_stage "contract(spec-check-parity)" bash "$PARITY" --repo-root "$REPO_ROOT"

if [[ "$JSON" -eq 1 ]]; then
  printf '{"specimen":"%s","bounces":%d,"result":"%s"}\n' \
    "$SOURCE" "$BOUNCES" "$([[ $BOUNCES -eq 0 ]] && echo CLEAN || echo BOUNCE)"
fi

if [[ "$BOUNCES" -eq 0 ]]; then
  echo "TRIAL RUN CLEAN: 0 spec<->check bounce(s) for $SOURCE"
  exit 0
fi

echo "POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE: ${BOUNCES} bounce(s): ${BOUNCED_STAGES[*]}" >&2
exit 2
