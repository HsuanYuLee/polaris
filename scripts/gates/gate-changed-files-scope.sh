#!/usr/bin/env bash
# Purpose: stable engineering scope adapter. The resolved task.md `Allowed Files`
#          section is the only delivery scope authority; refinement.json
#          changed_files is planning preview data and is never consumed here.
# Inputs:  --repo PATH --task-md PATH [--base REF]
# Outputs: delegates the canonical check-scope.sh JSON/exit contract.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/gates/gate-changed-files-scope.sh --repo PATH --task-md PATH [--base REF]

Fails when repository changes are outside the resolved task.md Allowed Files.
USAGE
  exit 2
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO=""
TASK_MD=""
BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -n "$TASK_MD" ]] || usage
[[ -d "$REPO" ]] || { echo "ERROR: repo not found: $REPO" >&2; exit 2; }
[[ -f "$TASK_MD" ]] || { echo "ERROR: task.md not found: $TASK_MD" >&2; exit 2; }

args=()
if [[ -n "$BASE" ]]; then
  args+=(--base-branch "$BASE")
fi

(
  cd "$REPO"
  bash "$ROOT_DIR/scripts/check-scope.sh" "${args[@]}" "$TASK_MD"
)
