#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_MANAGER="${ROOT}/docs-manager"
CONTENT_CONFIG="${DOCS_MANAGER}/src/content.config.ts"

# shellcheck source=lib/specs-root.sh
. "${ROOT}/scripts/lib/specs-root.sh"

if ! rg -n 'docsLoader\(' "$CONTENT_CONFIG" >/dev/null; then
  echo "FAIL: docs-manager does not use Starlight docsLoader" >&2
  exit 1
fi

if rg -n 'canonicalSpecsLoader|specs-loader' "$CONTENT_CONFIG" "${DOCS_MANAGER}/src" >/dev/null; then
  echo "FAIL: docs-manager still references the custom specs loader" >&2
  exit 1
fi

if [[ -e "${DOCS_MANAGER}/src/lib/specs-loader.ts" ]]; then
  echo "FAIL: custom specs loader file still exists" >&2
  exit 1
fi

if [[ -e "${DOCS_MANAGER}/specs" ]]; then
  echo "FAIL: legacy docs-manager/specs source still exists" >&2
  exit 1
fi

SPECS_ROOT="$(resolve_specs_root "$ROOT")" || {
  echo "FAIL: unable to resolve canonical specs root" >&2
  exit 1
}

if [[ ! -f "${SPECS_ROOT}/design-plans/archive/DP-063-docs-manager-source-unification/plan.md" ]]; then
  echo "FAIL: canonical archived DP-063 plan not found under ${SPECS_ROOT}" >&2
  exit 1
fi

if [[ "${SPECS_ROOT}" != "${DOCS_MANAGER}/src/content/docs/specs" ]]; then
  echo "FAIL: specs root is not Starlight native content root: ${SPECS_ROOT}" >&2
  exit 1
fi

echo "PASS: docs-manager Starlight-native source contract"
