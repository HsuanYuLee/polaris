#!/usr/bin/env bash
# scripts/lib/workspace-config-root.sh — shared root workspace-config resolver.
#
# Sourced (not executed) by scripts that need the canonical root
# `workspace-config.yaml` even when running from a linked worktree outside the
# main workspace ancestry.
#
# Public functions:
#   resolve_workspace_config_root [START]
#   resolve_workspace_config_path [START]

# shellcheck source=lib/main-checkout.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/main-checkout.sh"

_workspace_config_anchor_dir() {
  local start="${1:-$(pwd)}"
  if [[ -d "$start" ]]; then
    cd "$start" 2>/dev/null && pwd
  elif [[ -f "$start" ]]; then
    cd "$(dirname "$start")" 2>/dev/null && pwd
  else
    cd "$(dirname "$start")" 2>/dev/null && pwd || pwd
  fi
}

_workspace_config_scan_highest_dir() {
  local start="${1:-$(pwd)}"
  local dir=""
  local highest=""
  dir="$(_workspace_config_anchor_dir "$start")" || return 1
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/workspace-config.yaml" ]]; then
      highest="$dir"
    fi
    dir="$(dirname "$dir")"
  done
  if [[ -n "$highest" ]]; then
    printf '%s\n' "$highest"
    return 0
  fi
  return 1
}

resolve_workspace_config_root() {
  local start="${1:-$(pwd)}"
  local override="${POLARIS_WORKSPACE_CONFIG_ROOT:-}"
  local root=""
  local main_checkout=""

  if [[ -n "$override" ]]; then
    if [[ -d "$override" && -f "$override/workspace-config.yaml" ]]; then
      cd "$override" 2>/dev/null && pwd
      return 0
    fi
    if [[ -f "$override" && "$(basename "$override")" == "workspace-config.yaml" ]]; then
      cd "$(dirname "$override")" 2>/dev/null && pwd
      return 0
    fi
    return 1
  fi

  if root="$(_workspace_config_scan_highest_dir "$start" 2>/dev/null)"; then
    printf '%s\n' "$root"
    return 0
  fi

  if main_checkout="$(resolve_main_checkout "$start" 2>/dev/null || true)" && [[ -n "$main_checkout" ]]; then
    if root="$(_workspace_config_scan_highest_dir "$main_checkout" 2>/dev/null)"; then
      printf '%s\n' "$root"
      return 0
    fi
  fi

  return 1
}

resolve_workspace_config_path() {
  local root=""
  root="$(resolve_workspace_config_root "${1:-$(pwd)}")" || return 1
  printf '%s/workspace-config.yaml\n' "$root"
}
