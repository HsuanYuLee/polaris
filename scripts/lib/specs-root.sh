#!/usr/bin/env bash
# scripts/lib/specs-root.sh — single source of truth for canonical specs root.
#
# DP-066 moves the canonical specs source into Starlight's native content root:
# docs-manager/src/content/docs/specs. This helper centralizes
# workspace/worktree resolution so scripts do not each hard-code specs root
# policy.
#
# This file is sourced, not executed — no set -e, no top-level side effects.

_specs_root_abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
  fi
}

resolve_specs_workspace_root() {
  local start="${1:-$(pwd)}"
  local script_dir=""
  local main_checkout=""
  local probe=""

  if [[ -n "${POLARIS_WORKSPACE_ROOT:-}" ]]; then
    [[ -d "$POLARIS_WORKSPACE_ROOT" ]] || return 1
    (cd "$POLARIS_WORKSPACE_ROOT" && pwd)
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=main-checkout.sh
    . "$script_dir/main-checkout.sh"
    if main_checkout="$(resolve_main_checkout "$start" 2>/dev/null)"; then
      printf '%s\n' "$main_checkout"
      return 0
    fi
  fi

  probe="$start"
  if [[ -f "$probe" ]]; then
    probe="$(dirname "$probe")"
  fi
  probe="$(_specs_root_abs_path "$probe")"

  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -d "$probe/docs-manager" || -f "$probe/workspace-config.yaml" ]]; then
      printf '%s\n' "$probe"
      return 0
    fi
    probe="$(dirname "$probe")"
  done

  return 1
}

resolve_specs_root() {
  local workspace_root="${1:-}"

  if [[ -n "${POLARIS_SPECS_ROOT:-}" ]]; then
    _specs_root_abs_path "$POLARIS_SPECS_ROOT"
    return 0
  fi

  if [[ -z "$workspace_root" ]]; then
    workspace_root="$(resolve_specs_workspace_root)" || return 1
  else
    workspace_root="$(_specs_root_abs_path "$workspace_root")"
  fi

  printf '%s\n' "$workspace_root/docs-manager/src/content/docs/specs"
}

resolve_legacy_specs_root() {
  local workspace_root="${1:-}"

  if [[ -z "$workspace_root" ]]; then
    workspace_root="$(resolve_specs_workspace_root)" || return 1
  else
    workspace_root="$(_specs_root_abs_path "$workspace_root")"
  fi

  printf '%s\n' "$workspace_root/specs"
}
