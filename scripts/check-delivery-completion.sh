#!/usr/bin/env bash
set -euo pipefail

# check-delivery-completion.sh — Completion-time hard gate for engineering.
# Prevents "mouth-only completion" by requiring the same delivery evidence gates
# before the agent reports task completion to the user.
#
# Usage:
#   bash scripts/check-delivery-completion.sh [--repo <path>] [--ticket <KEY>] [--admin]
#
# Exit: 0 = pass, 2 = block, 64 = usage error

PREFIX="[polaris completion-gate]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
TICKET=""
MODE="auto"

extract_frontmatter_nested_scalar() {
  local file="$1"
  local parent="$2"
  local child="$3"

  python3 - "$file" "$parent" "$child" <<'PY'
import sys

path, parent, child = sys.argv[1:4]
try:
    text = open(path, "r", encoding="utf-8").read()
except OSError:
    sys.exit(0)

if not (text.startswith("---\n") and "\n---\n" in text[4:]):
    sys.exit(0)

fm_end = text.find("\n---\n", 4)
if fm_end == -1:
    sys.exit(0)

frontmatter = text[4:fm_end].splitlines()
in_parent = False
for raw in frontmatter:
    if raw.startswith(parent + ":"):
        in_parent = True
        continue
    if not in_parent:
        continue
    if raw and raw[0] not in (" ", "\t"):
        break
    stripped = raw.strip()
    if stripped.startswith(child + ":"):
        _, _, value = stripped.partition(":")
        print(value.strip())
        sys.exit(0)

print("")
PY
}

resolve_task_for_completion_check() {
  if [[ "$MODE" == "admin" ]]; then
    return 1
  fi

  local candidate=""
  local candidates=()

  local scan_roots=("$REPO_ROOT")
  if [[ -f "${REPO_ROOT}/.git" ]]; then
    local main_checkout=""
    # shellcheck source=lib/main-checkout.sh
    . "${SCRIPT_DIR}/lib/main-checkout.sh"
    if main_checkout="$(resolve_main_checkout "$REPO_ROOT" 2>/dev/null)" && [[ -n "$main_checkout" ]]; then
      scan_roots+=("$main_checkout")
    fi
  fi

  if [[ -n "$TICKET" ]]; then
    local scan_root=""
    for scan_root in "${scan_roots[@]}"; do
      if candidate="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$scan_root" "$TICKET" 2>/dev/null || true)" && [[ -n "$candidate" ]]; then
        candidates+=("$candidate")
        break
      fi
    done
  fi

  if candidate="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$REPO_ROOT" --current 2>/dev/null || true)"; then
    candidates+=("$candidate")
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
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
    --admin)
      MODE="admin"
      shift
      ;;
    -h|--help)
      echo "Usage: bash scripts/check-delivery-completion.sh [--repo <path>] [--ticket <KEY>] [--admin]"
      echo "  --repo <path>   Target repo (default: git rev-parse --show-toplevel)"
      echo "  --ticket <KEY>  JIRA ticket key for verification evidence gate"
      echo "  --admin         Skip ticket-bound verification evidence gate"
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi

if [[ -z "$REPO_ROOT" ]]; then
  echo "$PREFIX unable to resolve repo root" >&2
  exit 64
fi

if [[ "$MODE" == "auto" && -z "$TICKET" ]]; then
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
    TICKET="${BASH_REMATCH[1]}"
  fi
fi

echo "$PREFIX checking completion gates for ${REPO_ROOT}" >&2

# Layer A: repo-level Local CI Mirror. Existing script must be treated as
# authoritative regardless of git tracking state (tracked/untracked/generated).
bash "${SCRIPT_DIR}/gates/gate-ci-local.sh" --repo "$REPO_ROOT"

# Layer B: ticket-bound verify evidence for Developer flows.
if [[ "$MODE" != "admin" && -n "$TICKET" ]]; then
  bash "${SCRIPT_DIR}/gates/gate-evidence.sh" --repo "$REPO_ROOT" --ticket "$TICKET"
fi

# Developer PR metadata/deliverable gates.
if [[ "$MODE" != "admin" ]]; then
  bash "${SCRIPT_DIR}/gates/gate-pr-title.sh" --repo "$REPO_ROOT"
  bash "${SCRIPT_DIR}/gates/gate-changeset.sh" --repo "$REPO_ROOT"

  TASK_MD_PATH=""
  if ! TASK_MD_PATH="$(resolve_task_for_completion_check)"; then
    echo "$PREFIX unable to resolve task.md for completion freshness check (supply --ticket or call from task-bound context)" >&2
    exit 2
  fi

  DELIVERABLE_HEAD_SHA="$(extract_frontmatter_nested_scalar "$TASK_MD_PATH" "deliverable" "head_sha")"
  if [[ -z "$DELIVERABLE_HEAD_SHA" ]]; then
    echo "$PREFIX completion freshness check failed: deliverable.head_sha missing in ${TASK_MD_PATH}" >&2
    exit 2
  fi

  CURRENT_HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  if [[ "$CURRENT_HEAD_SHA" != "$DELIVERABLE_HEAD_SHA" && "$CURRENT_HEAD_SHA" != "${DELIVERABLE_HEAD_SHA}"* ]]; then
    echo "$PREFIX completion freshness check failed: deliverable.head_sha (${DELIVERABLE_HEAD_SHA}) != HEAD (${CURRENT_HEAD_SHA}) in ${TASK_MD_PATH}" >&2
    exit 2
  fi
fi

echo "$PREFIX ✅ completion gates satisfied." >&2
