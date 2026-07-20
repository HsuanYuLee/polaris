#!/usr/bin/env bash
# Purpose: Enforce lazy first-touch loading for a repo-scoped Polaris handbook.
# Inputs: Repo, tracked mutation path, project identity, session identity, resolver.
# Outputs: Surfaced handbook index plus a session/repo marker, or fail-closed marker.

set -euo pipefail

REPO=""
TARGET_PATH=""
PROJECT="${POLARIS_PROJECT:-}"
SESSION_ID="${POLARIS_SESSION_ID:-${CLAUDE_SESSION_ID:-${CODEX_THREAD_ID:-shell-${PPID}}}}"
RESOLVER="${POLARIS_HANDBOOK_RESOLVER:-}"

usage() {
  echo "usage: validate-handbook-load-gate.sh --repo PATH --path FILE [--project ID] [--session-id ID] [--resolver PATH]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --path) TARGET_PATH="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --session-id) SESSION_ID="${2:-}"; shift 2 ;;
    --resolver) RESOLVER="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -n "$TARGET_PATH" ]] || usage
REPO="$(cd "$REPO" && pwd)"
[[ -n "$RESOLVER" ]] || RESOLVER="$REPO/scripts/resolve-handbook.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

relative_path="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_handbook_load_gate_1.py" "$REPO" "$TARGET_PATH"
)"
[[ -n "$relative_path" ]] || exit 0
git -C "$REPO" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1 || exit 0

if [[ -z "$PROJECT" ]]; then
  PROJECT="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_handbook_load_gate_2.py" "$REPO"
)" || {
    echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:ambiguous_project" >&2
    exit 1
  }
fi
[[ -n "$PROJECT" ]] || exit 0

config_path="$REPO/polaris-config/$PROJECT/handbook/config.yaml"
index_path="$REPO/polaris-config/$PROJECT/handbook/index.md"
if [[ ! -e "$config_path" && ! -e "$index_path" ]]; then
  if find "$REPO/polaris-config" -mindepth 3 -maxdepth 3 \
      \( -path '*/handbook/config.yaml' -o -path '*/handbook/index.md' \) \
      -type f -print -quit 2>/dev/null | grep -q .; then
    echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:project_mapping_not_found:$PROJECT" >&2
    exit 1
  fi
  exit 0
fi

runtime_dir="${POLARIS_RUNTIME_DIR:-$REPO/.polaris/runtime}"
marker_dir="$runtime_dir/handbook-load"
marker_path="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_handbook_load_gate_3.py" "$marker_dir" "$REPO" "$SESSION_ID"
)"

if [[ -f "$marker_path" ]] && python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_handbook_load_gate_4.py" "$marker_path" "$REPO" "$SESSION_ID"
then
  exit 0
fi

if [[ ! -x "$RESOLVER" ]]; then
  echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:resolver_unavailable:$RESOLVER" >&2
  exit 1
fi

if ! payload="$("$RESOLVER" --scope-root "$REPO" --scope-id "$PROJECT" 2>&1)"; then
  echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:resolver_failed:$payload" >&2
  exit 1
fi

if ! index="$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_handbook_load_gate_5.py" "$payload" "$REPO" "$PROJECT" "$config_path" "$index_path"
)"; then
  echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:broken_payload" >&2
  exit 1
fi

mkdir -p "$marker_dir"
python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_handbook_load_gate_6.py" "$marker_path" "$REPO" "$SESSION_ID" "$PROJECT" "$index"

printf 'HANDBOOK_INDEX=%s\n' "$index"
