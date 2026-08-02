#!/usr/bin/env bash
# scripts/lib/ci-local-path.sh — single source of truth for ci-local.sh path.
#
# DP-079 relocates framework-generated ci-local mirrors out of product repo
# overlays. Canonical generated scripts live in the workspace-controlled
# company config root:
#
#   {company}/polaris-config/{project}/generated-scripts/ci-local.sh
#
# Repo-local `.claude/scripts/ci-local.sh` is legacy compatibility only. It is
# not the default canonical path and must carry a reason code if used.
#
# This file is sourced, not executed — it intentionally has no `set -e` and
# no top-level side effects beyond defining variables and functions.

CI_LOCAL_GENERATED_RELATIVE_PATH="generated-scripts/ci-local.sh"
CI_LOCAL_LEGACY_RELATIVE_PATH=".claude/scripts/ci-local.sh"
CI_LOCAL_LEGACY_REASON="legacy-compat"

_ci_local_path_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ci_local_main_checkout_for_repo() {
  local start="$1"
  # shellcheck source=main-checkout.sh
  . "${_ci_local_path_lib_dir}/main-checkout.sh"
  resolve_main_checkout "$start"
}

ci_local_workspace_config_root_for_repo() {
  local repo_root="$1"
  local main
  main="$(ci_local_main_checkout_for_repo "$repo_root")" || return 1

  local project
  project="$(basename "$main")"
  local company_dir
  company_dir="$(dirname "$main")"

  if [[ -d "$company_dir/polaris-config" || -f "$company_dir/workspace-config.yaml" ]]; then
    printf '%s/polaris-config/%s\n' "$company_dir" "$project"
    return 0
  fi

  # Framework workspace fallback: still workspace-owned, never product repo tracked.
  printf '%s/.polaris/config/%s\n' "$main" "$project"
}

# ci_local_path_for_repo <repo_root>
#   Echo the canonical absolute path for the generated ci-local mirror.
#   No filesystem check — pure path composition.
ci_local_path_for_repo() {
  local repo_root="$1"
  if [[ -z "$repo_root" ]]; then
    echo "ci_local_path_for_repo: missing repo_root argument" >&2
    return 1
  fi
  local config_root
  config_root="$(ci_local_workspace_config_root_for_repo "$repo_root")" || return 1
  printf '%s/%s\n' "$config_root" "$CI_LOCAL_GENERATED_RELATIVE_PATH"
}

ci_local_legacy_path_for_repo() {
  local repo_root="$1"
  if [[ -z "$repo_root" ]]; then
    echo "ci_local_legacy_path_for_repo: missing repo_root argument" >&2
    return 1
  fi
  local main
  main="$(ci_local_main_checkout_for_repo "$repo_root")" || return 1
  printf '%s/%s\n' "$main" "$CI_LOCAL_LEGACY_RELATIVE_PATH"
}

# ci_local_canonical_path [start_dir]
#   Echo absolute path to the workspace-owned canonical ci-local.sh.
ci_local_canonical_path() {
  local start="${1:-$(pwd)}"
  ci_local_path_for_repo "$start"
}
