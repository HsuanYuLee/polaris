#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG_PATH="${ROOT_DIR}/scripts/command-catalog.json"
PACKAGE_PATH="${ROOT_DIR}/package.json"
MISE_PATH="${ROOT_DIR}/mise.toml"

usage() {
  cat <<'USAGE'
Usage: bash scripts/validate-polaris-command-catalog.sh [--root <repo>] [--catalog <path>]

Validates the Polaris common command catalog against root package scripts and script owners.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="${2:-}"
      CATALOG_PATH="${ROOT_DIR}/scripts/command-catalog.json"
      PACKAGE_PATH="${ROOT_DIR}/package.json"
      MISE_PATH="${ROOT_DIR}/mise.toml"
      shift 2
      ;;
    --catalog)
      CATALOG_PATH="${2:-}"
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

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_polaris_command_catalog_1.py" "$ROOT_DIR" "$CATALOG_PATH" "$PACKAGE_PATH" "$MISE_PATH"
