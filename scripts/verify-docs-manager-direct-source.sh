#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_MANAGER="${ROOT}/docs-manager"
CONTENT_CONFIG="${DOCS_MANAGER}/src/content.config.ts"
LOADER="${DOCS_MANAGER}/src/lib/specs-loader.ts"

resolve_workspace_root() {
  if [[ -n "${POLARIS_WORKSPACE_ROOT:-}" && -d "${POLARIS_WORKSPACE_ROOT}/specs" ]]; then
    cd "$POLARIS_WORKSPACE_ROOT" && pwd
    return 0
  fi

  local probe="$ROOT"
  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -d "${probe}/specs" ]]; then
      cd "$probe" && pwd
      return 0
    fi
    if [[ "$(basename "$probe")" == ".worktrees" ]]; then
      local parent
      parent="$(dirname "$probe")"
      if [[ -d "${parent}/specs" ]]; then
        cd "$parent" && pwd
        return 0
      fi
    fi
    probe="$(dirname "$probe")"
  done

  return 1
}

if rg -n 'docsLoader\(' "$CONTENT_CONFIG" >/dev/null; then
  echo "FAIL: docs-manager still uses Starlight docsLoader mirror source" >&2
  exit 1
fi

if [[ -d "${DOCS_MANAGER}/src/content/docs/specs" ]]; then
  echo "FAIL: docs-manager mirror content directory still exists" >&2
  exit 1
fi

if [[ ! -f "$LOADER" ]]; then
  echo "FAIL: direct specs loader is missing: $LOADER" >&2
  exit 1
fi

if ! rg -n 'canonicalSpecsLoader|resolveWorkspaceRoot|specs/' "$CONTENT_CONFIG" "$LOADER" >/dev/null; then
  echo "FAIL: content config does not reference canonical specs loader" >&2
  exit 1
fi

WORKSPACE_ROOT="$(resolve_workspace_root)" || {
  echo "FAIL: unable to resolve workspace root containing specs/" >&2
  exit 1
}

if [[ ! -f "${WORKSPACE_ROOT}/specs/design-plans/DP-063-docs-manager-source-unification/plan.md" ]]; then
  echo "FAIL: canonical DP-063 plan not found under ${WORKSPACE_ROOT}/specs" >&2
  exit 1
fi

if [[ -e "${DOCS_MANAGER}/src/content/docs/specs/design-plans/DP-063-docs-manager-source-unification/plan.md" ]]; then
  echo "FAIL: DP-063 plan is present as generated mirror content" >&2
  exit 1
fi

echo "PASS: docs-manager direct source contract"
