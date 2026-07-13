#!/usr/bin/env bash
# Purpose: DP-417 T14 — framework-release tail end-to-end trial-run acceptance
#          harness. Drives a framework DP specimen through the release tail
#          (auto-pass terminal -> framework-release full-tail: execute / sync / tag
#          / release / closeout) in DRY-RUN / ISOLATION and asserts ZERO spec<->check
#          bounces. It is the framework-side counterpart of the T13 real-epic
#          harness: a product epic cannot reach the framework-release code path by
#          contract, so tail acceptance MUST be provided by a framework specimen
#          (AC-NEG12) — T13's product-epic run does not substitute for this.
#
#          Two deterministic stages, both reusing existing gates:
#            stage 1 (release-tail): framework-release-execute.sh --enumerate
#                                    — the framework-release-specific full-tail
#                                    precondition contract, a pure dry-run lister
#                                    that reads no git state and executes nothing.
#                                    This is the code path a product epic never
#                                    reaches. It NEVER pushes a tag or runs
#                                    sync-to-polaris — the harness deliberately only
#                                    ever invokes --enumerate, so there is no real
#                                    release side-effect.
#            stage 2 (contract)    : validate-spec-check-contract-parity.sh
#                                    --repo-root — the T11 bidirectional spec<->check
#                                    parity gate.
#          A "bounce" is any stage that rejects the specimen (non-zero exit). Zero
#          bounces => the release-tail flow is repaired; any bounce => DP-417 is NOT
#          complete (AC-NEG12). A warning is NOT a pass — only exit 0 counts.
# Inputs:  --source-id DP-NNN   framework DP specimen id (optional label; the tail
#                               dry-run is specimen-agnostic by design)
#          --repo-root <path>   (default: git toplevel of cwd, else this script's repo)
#          --json               (emit a machine-readable one-line JSON summary)
# Outputs: stdout human/JSON summary; exit 0 = 0 bounces (CLEAN),
#          exit 2 = >=1 bounce (POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE) or missing gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE_ID=""
REPO_ROOT=""
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
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

RELEASE_EXECUTE="$SCRIPT_DIR/framework-release-execute.sh"
PARITY="$SCRIPT_DIR/validate-spec-check-contract-parity.sh"
for gate in "$RELEASE_EXECUTE" "$PARITY"; do
  if [[ ! -x "$gate" && ! -f "$gate" ]]; then
    echo "POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE: required gate missing: $gate" >&2
    exit 2
  fi
done

BOUNCES=0
declare -a BOUNCED_STAGES=()

# run_stage <label> <cmd...> — run a tail/contract gate; a non-zero exit is a bounce.
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

echo "spec-check framework-release tail trial run"
echo "  specimen : ${SOURCE_ID:-<framework DP specimen>}"
echo "  repo-root: $REPO_ROOT"
echo "  isolation: release tail runs --enumerate only (no real tag/sync/push)"

# stage 1 drives the framework-release-specific code path (product epics cannot
# reach it) in pure dry-run: --enumerate reads no git state and executes nothing.
run_stage "release-tail(framework-release-execute --enumerate)" \
  bash "$RELEASE_EXECUTE" --enumerate
run_stage "contract(spec-check-parity)" bash "$PARITY" --repo-root "$REPO_ROOT"

if [[ "$JSON" -eq 1 ]]; then
  printf '{"specimen":"%s","bounces":%d,"result":"%s"}\n' \
    "${SOURCE_ID:-framework-dp-specimen}" "$BOUNCES" \
    "$([[ $BOUNCES -eq 0 ]] && echo CLEAN || echo BOUNCE)"
fi

if [[ "$BOUNCES" -eq 0 ]]; then
  echo "TRIAL RUN CLEAN: 0 spec<->check bounce(s) on framework-release tail (dry-run)"
  exit 0
fi

echo "POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE: ${BOUNCES} bounce(s): ${BOUNCED_STAGES[*]}" >&2
exit 2
