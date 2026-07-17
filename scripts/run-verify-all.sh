#!/usr/bin/env bash
# Purpose: Run each task-declared verification layer once, then delegate marker
# validation to the existing artifact validator and shared gate-evidence gate.
# Inputs: --task-md PATH [--repo PATH] [--ticket KEY].
# Outputs: PASS only when every declared layer and head-bound marker passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK="$SCRIPT_DIR/parse-task-md.sh"
VALIDATE_TASK="$SCRIPT_DIR/validate-task-md.sh"
RUN_VERIFY="$SCRIPT_DIR/run-verify-command.sh"
RUN_VR="$SCRIPT_DIR/run-visual-snapshot.sh"
RUN_BEHAVIOR="$SCRIPT_DIR/run-behavior-contract.sh"
VALIDATE_LOCATION="$SCRIPT_DIR/validate-artifact-location.sh"
GATE_EVIDENCE="$SCRIPT_DIR/gates/gate-evidence.sh"
TASK_MD=""
REPO=""
TICKET=""

usage() {
  local fd=2
  [[ "${1:-2}" -eq 0 ]] && fd=1
  cat >&"$fd" <<'USAGE'
Usage: run-verify-all.sh --task-md PATH [--repo PATH] [--ticket KEY]
USAGE
  exit "${1:-2}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md|--repo|--ticket)
      option="$1"
      [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != --* ]] || {
        echo "POLARIS_VERIFY_ALL_OPTION_VALUE_REQUIRED:$option" >&2
        exit 2
      }
      case "$option" in
        --task-md) TASK_MD="$2" ;;
        --repo) REPO="$2" ;;
        --ticket) TICKET="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage 0 ;;
    *) echo "POLARIS_VERIFY_ALL_INVALID_ARGUMENT:$1" >&2; usage ;;
  esac
done

[[ -n "$TASK_MD" && -f "$TASK_MD" ]] || {
  echo "POLARIS_VERIFY_ALL_TASK_MD_INVALID:${TASK_MD:-missing}" >&2
  exit 2
}
[[ -x "$PARSE_TASK" && -x "$VALIDATE_TASK" && -x "$RUN_VERIFY" && -x "$RUN_VR" && -x "$RUN_BEHAVIOR" && -x "$VALIDATE_LOCATION" && -x "$GATE_EVIDENCE" ]] || {
  echo "POLARIS_VERIFY_ALL_CALLABLE_MISSING" >&2
  exit 2
}
if ! "$VALIDATE_TASK" "$TASK_MD"; then
  echo "POLARIS_VERIFY_ALL_TASK_SCHEMA_INVALID:$TASK_MD" >&2
  exit 2
fi
if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO" && -d "$REPO" ]] || {
  echo "POLARIS_VERIFY_ALL_REPO_INVALID:${REPO:-missing}" >&2
  exit 2
}
parse_field() {
  "$PARSE_TASK" "$TASK_MD" --field "$1" --no-resolve
}

[[ -n "$TICKET" ]] || TICKET="$(parse_field delivery_ticket_key)"
[[ -n "$TICKET" ]] || TICKET="$(parse_field work_item_id)"
[[ -n "$TICKET" ]] || {
  echo "POLARIS_VERIFY_ALL_TICKET_REQUIRED" >&2
  exit 2
}
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$HEAD_SHA" ]] || { echo "POLARIS_VERIFY_ALL_HEAD_REQUIRED" >&2; exit 2; }

verify_command="$(parse_field verify_command)"
if [[ "$verify_command" == *"run-verify-all.sh"* ]]; then
  echo "POLARIS_VERIFY_ALL_RECURSIVE_COMMAND:$verify_command" >&2
  exit 2
fi

"$RUN_VERIFY" --task-md "$TASK_MD" --ticket "$TICKET" --repo "$REPO" --worktree "$REPO"
"$VALIDATE_LOCATION" --kind verify --repo "$REPO" --ticket "$TICKET" --head-sha "$HEAD_SHA"

visual_expected="$(parse_field verification_visual_regression_expected)"
if [[ -n "$visual_expected" ]]; then
  "$RUN_VR" --task-md "$TASK_MD" --mode compare --repo "$REPO" --ticket "$TICKET"
  "$VALIDATE_LOCATION" --kind vr --repo "$REPO" --ticket "$TICKET" --head-sha "$HEAD_SHA"
else
  echo "run-verify-all: visual regression not declared; layer skipped"
fi

behavior_applies="$(parse_field verification_behavior_contract_applies)"
if [[ "$behavior_applies" == "true" ]]; then
  "$RUN_BEHAVIOR" --task-md "$TASK_MD" --mode compare --repo "$REPO" --ticket "$TICKET"
  POLARIS_GATE_EVIDENCE_BEHAVIOR_ONLY=1 \
    POLARIS_EVIDENCE_ROOT="$REPO/.polaris/evidence" \
    "$GATE_EVIDENCE" --repo "$REPO" --ticket "$TICKET" --task-md "$TASK_MD"
else
  echo "run-verify-all: behavior_contract.applies is not true; layer skipped"
  "$GATE_EVIDENCE" --repo "$REPO" --ticket "$TICKET" --task-md "$TASK_MD"
fi
echo "PASS: run-verify-all ticket=$TICKET head=$HEAD_SHA"
