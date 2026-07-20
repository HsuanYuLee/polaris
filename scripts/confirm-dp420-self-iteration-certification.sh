#!/usr/bin/env bash
# Purpose: certify DP-420 terminal source inputs before the one full-corpus backstop.
# Inputs: canonical repo/source/evidence paths; outputs PASS or POLARIS_DP420_CERTIFICATION diagnostics.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGINAL_ARGS=("$@")
REPO="$ROOT"
SOURCE_CONTAINER=""
EVIDENCE_ROOT=""
GAP_LEDGER="$ROOT/scripts/current-head-gap-ledger.json"
SCRIPT_LEDGER="$ROOT/scripts/script-layer-governance-ledger.json"
MAX_AGE_HOURS=48
CURRENT_WORK_ITEM="DP-420-T14"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --evidence-root) EVIDENCE_ROOT="${2:-}"; shift 2 ;;
    --gap-ledger) GAP_LEDGER="${2:-}"; shift 2 ;;
    --script-ledger) SCRIPT_LEDGER="${2:-}"; shift 2 ;;
    --max-age-hours) MAX_AGE_HOURS="${2:-}"; shift 2 ;;
    --current-work-item) CURRENT_WORK_ITEM="${2:-}"; shift 2 ;;
    -h|--help)
      echo 'usage: scripts/confirm-dp420-self-iteration-certification.sh --source-container PATH --evidence-root PATH [--repo PATH] [--gap-ledger PATH] [--script-ledger PATH] [--current-work-item DP-420-Tn] [--max-age-hours N]'
      exit 0
      ;;
    *) echo "POLARIS_DP420_CERTIFICATION: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$REPO" ]] || { echo "POLARIS_DP420_CERTIFICATION: repo not found: $REPO" >&2; exit 2; }
[[ -d "$SOURCE_CONTAINER" ]] || { echo "POLARIS_DP420_CERTIFICATION: source container not found: $SOURCE_CONTAINER" >&2; exit 2; }
[[ -d "$EVIDENCE_ROOT" ]] || { echo "POLARIS_DP420_CERTIFICATION: evidence root not found: $EVIDENCE_ROOT" >&2; exit 2; }

# Evidence context includes toolchain versions. Normalize direct callers into
# the repo-declared mise environment before recomputing canonical identities.
if [[ -z "${__MISE_DIFF:-}" && -f "$REPO/mise.toml" ]]; then
  command -v mise >/dev/null 2>&1 || {
    echo 'POLARIS_DP420_CERTIFICATION: mise is required; run `mise install` from the Polaris workspace' >&2
    exit 2
  }
  cd "$REPO"
  exec mise exec -- bash "$ROOT/scripts/confirm-dp420-self-iteration-certification.sh" "${ORIGINAL_ARGS[@]}"
fi

# Canonical authorities: source inventory is structured Python; gap/script
# ledgers and evidence identity stay with their existing validators.
records_file="$(mktemp -t dp420-certification-records.XXXXXX)"
trap 'rm -f "$records_file"' EXIT
python3 "$ROOT/scripts/lib/confirm_dp420_self_iteration_certification.py" \
  --repo "$REPO" \
  --source-container "$SOURCE_CONTAINER" \
  --evidence-root "$EVIDENCE_ROOT" \
  --gap-ledger "$GAP_LEDGER" \
  --script-ledger "$SCRIPT_LEDGER" \
  --current-work-item "$CURRENT_WORK_ITEM" \
  --max-age-hours "$MAX_AGE_HOURS" \
  --records >"$records_file"

bash "$ROOT/scripts/validate-current-head-gap-ledger.sh" \
  --ledger "$GAP_LEDGER" \
  --repo "$REPO" \
  --source-container "$SOURCE_CONTAINER" \
  --source-id DP-420 \
  --require-terminal >/dev/null
for owner in DP-420-T4 DP-420-T5 DP-420-T6 DP-420-T10 DP-420-T11 DP-420-T12 DP-420-T13; do
  bash "$ROOT/scripts/validate-script-layer-migration-coverage.sh" \
    --ledger "$SCRIPT_LEDGER" \
    --owner "$owner" \
    --require-terminal >/dev/null
done

# shellcheck source=lib/verification-evidence.sh
. "$ROOT/scripts/lib/verification-evidence.sh"
task_count=0
while IFS=$'\t' read -r work_item_id task_md head_sha evidence execution_cwd; do
  [[ -n "$work_item_id" ]] || continue
  if ! detail="$(verification_evidence_validate_file "$evidence" "$work_item_id" "$head_sha" 2>&1)"; then
    echo "POLARIS_DP420_CERTIFICATION: ${work_item_id} evidence file invalid: $detail" >&2
    exit 2
  fi
  if ! detail="$(verification_evidence_is_pass "$evidence" 2>&1)"; then
    echo "POLARIS_DP420_CERTIFICATION: ${work_item_id} verification did not pass: $detail" >&2
    exit 2
  fi
  if [[ -d "$execution_cwd" ]]; then
    if ! detail="$(verification_evidence_validate_current_identity "$evidence" "$task_md" "$execution_cwd" 2>&1)"; then
      echo "POLARIS_DP420_CERTIFICATION: ${work_item_id} evidence identity drift: $detail" >&2
      exit 2
    fi
  elif ! detail="$(python3 "$ROOT/scripts/lib/confirm_dp420_self_iteration_certification.py" \
      --validate-archived-identity --repo "$REPO" --task-md "$task_md" --evidence "$evidence" 2>&1)"; then
    echo "POLARIS_DP420_CERTIFICATION: ${work_item_id} archived evidence identity drift: $detail" >&2
    exit 2
  fi
  task_count=$((task_count + 1))
done <"$records_file"

[[ "$task_count" -gt 0 ]] || { echo 'POLARIS_DP420_CERTIFICATION: no terminal task evidence resolved' >&2; exit 2; }
echo "PASS: DP-420 corrected-harness certification (${task_count} terminal tasks; promotion full-corpus rerun still required)"
