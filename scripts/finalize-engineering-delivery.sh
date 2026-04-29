#!/usr/bin/env bash
set -euo pipefail

# finalize-engineering-delivery.sh — Developer-lane completion closer.
#
# This helper binds the pre-report completion gate to the task lifecycle
# write-back so agents do not report completion while forgetting the
# move-first pr-release closeout.
#
# Usage:
#   bash scripts/finalize-engineering-delivery.sh --repo <repo> --ticket <KEY> [--workspace <path>] [--status IMPLEMENTED]
#
# Exit: 0 = completion gate passed and task lifecycle finalized
#       1 = invalid input / lifecycle verification failed
#       2 = completion gate or mark-spec helper blocked

PREFIX="[polaris finalize-delivery]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT=""
TICKET=""
STATUS="IMPLEMENTED"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/finalize-engineering-delivery.sh --repo <repo> --ticket <KEY> [--workspace <path>] [--status IMPLEMENTED]

Options:
  --repo <path>       Product repo root whose delivery gates should be checked.
  --ticket <KEY>      Task ticket key or DP pseudo-task id.
  --workspace <path>  Polaris workspace root. Defaults to this script's parent.
  --status <status>   Lifecycle status to write. Defaults to IMPLEMENTED.
USAGE
}

extract_frontmatter_scalar() {
  local file="$1"
  local key="$2"

  python3 - "$file" "$key" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
try:
    text = path.read_text(encoding="utf-8")
except OSError:
    sys.exit(0)

if not text.startswith("---\n"):
    sys.exit(0)

end = text.find("\n---\n", 4)
if end == -1:
    sys.exit(0)

for line in text[4:end].splitlines():
    if line.startswith(key + ":"):
        print(line.split(":", 1)[1].strip())
        sys.exit(0)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --ticket)
      TICKET="${2:-}"
      shift 2
      ;;
    --workspace)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    --status)
      STATUS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REPO_ROOT" || -z "$TICKET" ]]; then
  echo "$PREFIX --repo and --ticket are required" >&2
  usage
  exit 1
fi

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX repo not found: $REPO_ROOT" >&2
  exit 1
fi

if [[ ! -d "$WORKSPACE_ROOT" ]]; then
  echo "$PREFIX workspace not found: $WORKSPACE_ROOT" >&2
  exit 1
fi

case "$STATUS" in
  IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION) ;;
  *)
    echo "$PREFIX invalid --status: $STATUS" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"

echo "$PREFIX running completion gate for ${TICKET} ..." >&2
if ! bash "${SCRIPT_DIR}/check-delivery-completion.sh" --repo "$REPO_ROOT" --ticket "$TICKET"; then
  echo "$PREFIX completion gate blocked; task lifecycle was not changed" >&2
  exit 2
fi

echo "$PREFIX marking task lifecycle: ${TICKET} -> ${STATUS}" >&2
if ! bash "${SCRIPT_DIR}/mark-spec-implemented.sh" "$TICKET" --status "$STATUS" --workspace "$WORKSPACE_ROOT"; then
  echo "$PREFIX mark-spec-implemented failed after completion gate passed" >&2
  exit 2
fi

TASK_MD_PATH="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$WORKSPACE_ROOT" "$TICKET" 2>/dev/null || true)"
if [[ -z "$TASK_MD_PATH" || ! -f "$TASK_MD_PATH" ]]; then
  echo "$PREFIX unable to resolve finalized task.md for ${TICKET}" >&2
  exit 1
fi

case "$TASK_MD_PATH" in
  */tasks/pr-release/*.md) ;;
  *)
    echo "$PREFIX finalized task is not under tasks/pr-release/: $TASK_MD_PATH" >&2
    exit 1
    ;;
esac

ACTUAL_STATUS="$(extract_frontmatter_scalar "$TASK_MD_PATH" "status")"
if [[ "$ACTUAL_STATUS" != "$STATUS" ]]; then
  echo "$PREFIX finalized task status mismatch: expected ${STATUS}, got ${ACTUAL_STATUS:-<empty>} in ${TASK_MD_PATH}" >&2
  exit 1
fi

echo "$PREFIX ✅ finalized ${TICKET}: ${TASK_MD_PATH}" >&2
