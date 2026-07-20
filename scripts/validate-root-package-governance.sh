#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: bash scripts/validate-root-package-governance.sh [--root <repo>]

Validates root package.json / pnpm-workspace.yaml governance for Polaris.

Root package.json is allowed to expose thin aliases for compatibility and
package-local Node workflows. It must not become the root runtime manager and
must not declare third-party dependencies.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_root_package_governance_1.py" "$ROOT_DIR"
