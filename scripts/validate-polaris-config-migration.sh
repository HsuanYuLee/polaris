#!/usr/bin/env bash
# validate-polaris-config-migration.sh — DP-079 migration closure gate.
#
# This is intentionally local-workspace aware: it uses --no-ignore scans and
# repo-local ignored artifact checks so release closeout cannot pass only
# because ignored runtime files were invisible to git.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FAILURES=0

fail() {
  echo "[polaris-config-migration] FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

info() {
  echo "[polaris-config-migration] $*" >&2
}

check_no_ai_config_root() {
  local legacy_dirs=()
  while IFS= read -r path; do
    legacy_dirs+=("$path")
  done < <(find "$ROOT_DIR" -mindepth 2 -maxdepth 2 -type d -name ai-config \
    -not -path "$ROOT_DIR/.git/*" \
    -not -path "$ROOT_DIR/.worktrees/*" \
    -not -path "$ROOT_DIR/.claude/worktrees/*" 2>/dev/null | sort)

  if [[ ${#legacy_dirs[@]} -gt 0 ]]; then
    fail "legacy ai-config directories remain: ${legacy_dirs[*]}"
  fi
}

check_no_active_ai_config_references() {
  local targets=(
    "$ROOT_DIR/CLAUDE.md"
    "$ROOT_DIR/AGENTS.md"
    "$ROOT_DIR/.codex"
    "$ROOT_DIR/.github"
    "$ROOT_DIR/.claude/instructions"
    "$ROOT_DIR/.claude/hooks"
    "$ROOT_DIR/.claude/rules"
    "$ROOT_DIR/.claude/skills"
    "$ROOT_DIR/scripts"
    "$ROOT_DIR/README.md"
    "$ROOT_DIR/README.zh-TW.md"
  )

  while IFS= read -r config; do
    targets+=("$config")
  done < <(find "$ROOT_DIR" -mindepth 2 -maxdepth 2 -name workspace-config.yaml \
    -not -path "$ROOT_DIR/_template/*" \
    -not -path "$ROOT_DIR/.git/*" \
    -not -path "$ROOT_DIR/.worktrees/*" \
    -not -path "$ROOT_DIR/.claude/worktrees/*" 2>/dev/null | sort)

  local hits
  hits="$(rg --no-ignore -n "ai-config" "${targets[@]}" \
    --glob '!**/node_modules/**' \
    --glob '!**/.git/**' \
    --glob '!**/.worktrees/**' \
    --glob '!**/.claude/worktrees/**' \
    --glob '!scripts/validate-polaris-config-migration.sh' 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    fail "active runtime files still reference ai-config:"
    printf '%s\n' "$hits" >&2
  fi
}

check_no_runtime_polaris_sync_references() {
  local targets=(
    "$ROOT_DIR/CLAUDE.md"
    "$ROOT_DIR/AGENTS.md"
    "$ROOT_DIR/.codex"
    "$ROOT_DIR/.github"
    "$ROOT_DIR/.claude/instructions"
    "$ROOT_DIR/.claude/hooks"
    "$ROOT_DIR/.claude/rules"
    "$ROOT_DIR/.claude/skills"
    "$ROOT_DIR/scripts"
    "$ROOT_DIR/README.md"
    "$ROOT_DIR/README.zh-TW.md"
  )

  local hits
  hits="$(rg --no-ignore -n "polaris-sync\\.sh" "${targets[@]}" \
    --glob '!**/node_modules/**' \
    --glob '!**/.git/**' \
    --glob '!**/.worktrees/**' \
    --glob '!**/.claude/worktrees/**' \
    --glob '!scripts/validate-polaris-config-migration.sh' 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    fail "active runtime files still reference transitional polaris-sync.sh:"
    printf '%s\n' "$hits" >&2
  fi
}

check_polaris_config_git_policy() {
  local tracked
  tracked="$(git -C "$ROOT_DIR" ls-files -- '*/polaris-config' '*/polaris-config/*' 2>/dev/null || true)"
  if [[ -n "$tracked" ]]; then
    fail "polaris-config must be local-only and not git tracked:"
    printf '%s\n' "$tracked" >&2
  fi

  local config_dirs=()
  while IFS= read -r path; do
    config_dirs+=("$path")
  done < <(find "$ROOT_DIR" -mindepth 2 -maxdepth 2 -type d -name polaris-config \
    -not -path "$ROOT_DIR/.git/*" \
    -not -path "$ROOT_DIR/.worktrees/*" \
    -not -path "$ROOT_DIR/.claude/worktrees/*" 2>/dev/null | sort)

  local dir rel
  for dir in "${config_dirs[@]}"; do
    rel="${dir#$ROOT_DIR/}"
    if ! git -C "$ROOT_DIR" check-ignore -q "$rel" 2>/dev/null; then
      fail "polaris-config directory is not ignored: $rel"
    fi
  done
}

company_dirs_from_workspace_configs() {
  find "$ROOT_DIR" -mindepth 2 -maxdepth 2 -name workspace-config.yaml \
    -not -path "$ROOT_DIR/_template/*" \
    -not -path "$ROOT_DIR/.git/*" \
    -not -path "$ROOT_DIR/.worktrees/*" \
    -not -path "$ROOT_DIR/.claude/worktrees/*" 2>/dev/null |
    while IFS= read -r config; do
      dirname "$config"
    done | sort -u
}

check_company_dir_git_policy() {
  local company_dir rel tracked
  while IFS= read -r company_dir; do
    [[ -n "$company_dir" ]] || continue
    rel="${company_dir#$ROOT_DIR/}"

    tracked="$(git -C "$ROOT_DIR" ls-files -- "$rel" "$rel/*" 2>/dev/null || true)"
    if [[ -n "$tracked" ]]; then
      fail "company directory must be local-only and not git tracked: $rel"
      printf '%s\n' "$tracked" >&2
    fi

    if ! git -C "$ROOT_DIR" check-ignore -q "$rel" 2>/dev/null; then
      fail "company directory is not ignored: $rel"
    fi
  done < <(company_dirs_from_workspace_configs)
}

projects_from_config() {
  local config="$1"
  awk '
    /^projects:/ { in_projects=1; next }
    /^[a-z_]+:/ && !/^  / { in_projects=0 }
    in_projects && /^  - name:/ { gsub(/.*name: *"/, ""); gsub(/".*/, ""); print }
  ' "$config"
}

ignored_in_repo() {
  local repo="$1"
  local rel="$2"
  [[ -e "$repo/$rel" ]] || return 1
  git -C "$repo" check-ignore -q "$rel" 2>/dev/null
}

check_company_config() {
  local company_dir="$1"
  local config="$company_dir/workspace-config.yaml"
  [[ -f "$config" ]] || return 0

  local project
  while IFS= read -r project; do
    [[ -n "$project" ]] || continue

    local repo="$company_dir/$project"
    local sot="$company_dir/polaris-config/$project"
    [[ -d "$repo/.git" ]] || continue

    if [[ ! -d "$sot" ]]; then
      fail "$project has no workspace-owned polaris-config directory"
    fi

    if ignored_in_repo "$repo" ".claude/rules/handbook"; then
      fail "$project still has ignored repo-local handbook overlay: $repo/.claude/rules/handbook"
    fi

    if ignored_in_repo "$repo" ".claude/scripts/ci-local.sh"; then
      fail "$project still has ignored repo-local ci-local legacy script: $repo/.claude/scripts/ci-local.sh"
    fi

    if ignored_in_repo "$repo" ".claude/settings.local.json"; then
      fail "$project still has ignored repo-local settings overlay: $repo/.claude/settings.local.json"
    fi

    if [[ -d "$repo/.claude/skills" ]] && ignored_in_repo "$repo" ".claude/skills"; then
      fail "$project still has ignored repo-local skills overlay: $repo/.claude/skills"
    fi

    if [[ -f "$repo/.claude/scripts/ci-local.sh" && ! -f "$sot/generated-scripts/ci-local.sh" ]]; then
      fail "$project has legacy ci-local without canonical generated script"
    fi
  done < <(projects_from_config "$config")
}

main() {
  check_no_ai_config_root
  check_no_active_ai_config_references
  check_no_runtime_polaris_sync_references
  check_company_dir_git_policy
  check_polaris_config_git_policy

  while IFS= read -r company_dir; do
    check_company_config "$company_dir"
  done < <(company_dirs_from_workspace_configs)

  if [[ "$FAILURES" -gt 0 ]]; then
    fail "$FAILURES migration issue(s) detected"
    exit 1
  fi

  info "PASS"
}

main "$@"
