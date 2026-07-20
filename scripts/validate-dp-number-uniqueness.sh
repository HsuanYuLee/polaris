#!/usr/bin/env bash
# Validate Design Plan number uniqueness across active and archive namespaces.
# Both folder-native index.md and legacy plan.md containers are counted.

set -euo pipefail

specs_root="docs-manager/src/content/docs/specs"
mode="hard"
plan_scope=""

usage() {
  cat >&2 <<'EOF'
usage: validate-dp-number-uniqueness.sh [--specs-root <path>] [--report] [--plan <plan.md>]

Default mode hard-fails on any duplicate DP number found in active or archive.
--report prints the duplicate inventory but exits 0.
--plan only hard-fails when the supplied plan's DP number is duplicated.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --specs-root)
      specs_root="${2:-}"
      shift 2
      ;;
    --report)
      mode="report"
      shift
      ;;
    --plan)
      plan_scope="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_dp_number_uniqueness_1.py" "$specs_root" "$mode" "$plan_scope"
