#!/usr/bin/env bash
# Purpose: Validate framework/control-plane source writes against the active task.md
#          lineage and Allowed Files contract. This is the single authority used by
#          Claude hooks, Codex adapters, guarded bash, and the framework PR gate.
# Exit:    0 = allowed/no framework source touched; 2 = blocked or invalid input.
set -euo pipefail

REPO=""
MODE="pre-write"
TASK_MD="${POLARIS_TASK_MD:-${POLARIS_FRAMEWORK_TASK_MD:-}}"
WRITER=""
BASE="${POLARIS_FRAMEWORK_SOURCE_BASE:-HEAD}"
SELF_CHECK_WIRING=0
PATHS=()
COMMAND_STRING=""

usage() {
  sed -n '2,18p' "$0" >&2
  cat >&2 <<'USAGE'
Usage:
  validate-framework-source-write.sh --repo <repo> --mode <pre-write|diff-audit|pr-gate> \
    --writer <writer> [--task-md <task.md>] [--path <path> ...] [--changed-file <path> ...]
  validate-framework-source-write.sh --repo <repo> --command "<shell command>" [--task-md <task.md>]
  validate-framework-source-write.sh --repo <repo> --self-check-wiring
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --writer) WRITER="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --path|--changed-file) PATHS+=("${2:-}"); shift 2 ;;
    --command) COMMAND_STRING="${2:-}"; shift 2 ;;
    --self-check-wiring) SELF_CHECK_WIRING=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:usage unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO="$(cd "$REPO" && pwd)"
OWNED_PATHS_JSON="$REPO/scripts/lib/framework-source-owned-paths.json"

if [[ ! -f "$OWNED_PATHS_JSON" ]]; then
  echo "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:missing owned-path registry: $OWNED_PATHS_JSON" >&2
  exit 2
fi

if [[ "$SELF_CHECK_WIRING" -eq 1 ]]; then
  python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_framework_source_write_1.py" "$REPO"
  exit $?
fi

if [[ "$MODE" == "pr-gate" && "${#PATHS[@]}" -eq 0 && -z "$COMMAND_STRING" ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && PATHS+=("$p")
  done < <(git -C "$REPO" diff --name-only "$BASE" HEAD 2>/dev/null || true)
  while IFS= read -r p; do
    [[ -n "$p" ]] && PATHS+=("$p")
  done < <(git -C "$REPO" status --porcelain=v1 -z --untracked-files=all 2>/dev/null \
    | python3 -c 'import sys; data=sys.stdin.buffer.read().decode("utf-8","replace"); [print(e[3:]) for e in data.split("\0") if e and len(e) >= 4]')
fi

PY_ARGS=("$REPO" "$OWNED_PATHS_JSON" "$MODE" "$TASK_MD" "$WRITER" "$COMMAND_STRING")
if [[ "${#PATHS[@]}" -gt 0 ]]; then
  PY_ARGS+=("${PATHS[@]}")
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_framework_source_write_2.py" "${PY_ARGS[@]}"
