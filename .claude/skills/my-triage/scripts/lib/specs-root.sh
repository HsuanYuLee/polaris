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

_specs_root_reject_symlink_primary() {
  local path="$1"
  local label="${2:-specs root}"
  if [[ -L "$path" ]]; then
    printf 'resolve-specs-root: symlink primary path is not allowed for %s: %s\n' "$label" "$path" >&2
    return 1
  fi
  return 0
}

_specs_root_require_dir() {
  local path="$1"
  local label="${2:-specs root}"
  _specs_root_reject_symlink_primary "$path" "$label" || return 1
  if [[ ! -d "$path" ]]; then
    printf 'resolve-specs-root: missing %s: %s; pass --specs-source or run from the main checkout with canonical specs available\n' "$label" "$path" >&2
    return 1
  fi
  return 0
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
  local specs_root=""
  local overlay_workspace_root=""

  if [[ -n "${POLARIS_SPECS_ROOT:-}" ]]; then
    specs_root="$(_specs_root_abs_path "$POLARIS_SPECS_ROOT")"
    _specs_root_require_dir "$specs_root" "explicit specs source" || return 1
    printf '%s\n' "$specs_root"
    return 0
  fi

  if [[ -z "$workspace_root" ]]; then
    workspace_root="$(resolve_specs_workspace_root)" || return 1
  else
    workspace_root="$(_specs_root_abs_path "$workspace_root")"
  fi

  specs_root="$workspace_root/docs-manager/src/content/docs/specs"
  _specs_root_reject_symlink_primary "$specs_root" "workspace specs root" || return 1
  if [[ -d "$specs_root" ]]; then
    printf '%s\n' "$specs_root"
    return 0
  fi

  if overlay_workspace_root="$(resolve_specs_workspace_root "$workspace_root" 2>/dev/null)" \
    && [[ -n "$overlay_workspace_root" && "$overlay_workspace_root" != "$workspace_root" ]]; then
    specs_root="$overlay_workspace_root/docs-manager/src/content/docs/specs"
    _specs_root_reject_symlink_primary "$specs_root" "workspace overlay specs root" || return 1
    if [[ -d "$specs_root" ]]; then
      printf '%s\n' "$specs_root"
      return 0
    fi
  fi

  _specs_root_require_dir "$workspace_root/docs-manager/src/content/docs/specs" "workspace specs root"
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
