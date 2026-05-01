#!/usr/bin/env bash
# Print the canonical specs source root for this workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<'USAGE'
usage: resolve-specs-root.sh [--workspace <path>] [--legacy]

stdout: absolute specs root path
exit: 0 = resolved
      1 = workspace root could not be resolved
      2 = usage error
USAGE
}

workspace_root=""
legacy=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      workspace_root="${2:-}"
      [[ -n "$workspace_root" ]] || { usage; exit 2; }
      shift 2
      ;;
    --legacy)
      legacy=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ "$legacy" -eq 1 ]]; then
  resolve_legacy_specs_root "$workspace_root"
else
  resolve_specs_root "$workspace_root"
fi
