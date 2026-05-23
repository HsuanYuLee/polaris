#!/usr/bin/env bash
# DP plan authoring gate. Thin alias for the source-agnostic primary doc
# authoring wrapper (scripts/validate-spec-primary-doc-authoring.sh). Retained
# so existing DP-only callers (references, selftests, docs) keep working while
# Epic primary docs share the same gate stack.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-dp-plan-authoring.sh <path/to/index.md|plan.md>...

Runs the deterministic authoring checks required for Design Plan primary docs.

Thin alias: delegates to scripts/validate-spec-primary-doc-authoring.sh.
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$script_dir/validate-spec-primary-doc-authoring.sh" "$@"
