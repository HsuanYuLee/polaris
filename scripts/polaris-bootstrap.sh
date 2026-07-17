#!/usr/bin/env bash
# Bootstrap Polaris-owned root runtime tools and package-local assets.

set -euo pipefail

# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  command printf '%s\n' 'Usage:'
  command printf '%s\n' '  scripts/polaris-bootstrap.sh [--profile core|runtime|delivery|full] [--dry-run]'
  command printf '%s\n' '  scripts/polaris-bootstrap.sh --help'
  command printf '%s\n' ''
  command printf '%s\n' 'Bootstraps Polaris framework runtime dependencies from repo-owned contracts.'
  exit 0
fi
# POLARIS_SAFE_CLI_INTROSPECTION_END

usage() {
  cat <<'EOF'
Usage:
  scripts/polaris-bootstrap.sh [--profile core|runtime|delivery|full] [--dry-run]
  scripts/polaris-bootstrap.sh --help

Bootstraps Polaris framework runtime dependencies from repo-owned contracts:
  - mise.toml for managed runtimes and native tools
  - package-local pnpm installs for Polaris-owned Node packages
  - workspace-shared Playwright browser cache at .polaris/toolchain/ms-playwright

Missing mise is reported with repair hints. This script does not silently install
global CLIs or require Homebrew.
EOF
}

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$WORKSPACE_ROOT/scripts"
DRY_RUN=false
PROFILE="runtime"
# shellcheck source=lib/tool-resolution.sh
source "$SCRIPT_DIR/lib/tool-resolution.sh"
MAIN_CHECKOUT_RESOLVER="resolve_main_checkout"

log() {
  printf '[polaris-bootstrap] %s\n' "$*"
}

blocked_env() {
  local blocker_class="$1"
  local message="$2"
  printf '[polaris-bootstrap] BLOCKED_ENV blocker_class=%s %s\n' "$blocker_class" "$message" >&2
}

die() {
  printf '[polaris-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

run_cmd() {
  log "+ $*"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  (cd "$TOOLCHAIN_ROOT" && "$@")
}

resolve_toolchain_root() {
  if [[ -n "${POLARIS_TOOLCHAIN_ROOT:-}" ]]; then
    (cd "$POLARIS_TOOLCHAIN_ROOT" && pwd) || return 1
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]] && command -v git >/dev/null 2>&1; then
    # shellcheck source=lib/main-checkout.sh
    . "$SCRIPT_DIR/lib/main-checkout.sh"
    "$MAIN_CHECKOUT_RESOLVER" "$WORKSPACE_ROOT" 2>/dev/null && return 0
  fi

  printf '%s\n' "$WORKSPACE_ROOT"
}

print_mise_repair_hints() {
  cat >&2 <<'EOF'
[polaris-bootstrap] mise is required before bootstrap can install managed tools.

Repair:
  1. Install mise using the official installation path for your platform:
     https://mise.jdx.dev/getting-started.html
  2. Re-open your shell so `mise` is on PATH.
  3. Re-run:
     bash scripts/polaris-bootstrap.sh

Notes:
  - Homebrew is optional, not a Polaris prerequisite.
  - Do not rely on a VS Code extension bundle PATH for rg, jq, node, pnpm, or python.
  - Automatic mise installation must be an explicit opt-in flow; this bootstrap
    does not perform silent global installs.
EOF
}

require_mise() {
  if polaris_find_mise >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "mise missing; dry-run continues after repair hint."
    print_mise_repair_hints
    return 0
  fi
  blocked_env "mise-missing" "mise is required before bootstrap."
  print_mise_repair_hints
  return 1
}

require_managed_tool() {
  local command_name="$1"
  local label="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "would verify mise-managed $label: $command_name"
    return 0
  fi
  if POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_require_mise_tool "$command_name" >/dev/null; then
    return 0
  fi
  blocked_env "mise-managed:${command_name}" "mise-managed $label missing after mise install."
  return 1
}

require_gh_delivery() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "would verify gh binary and auth"
    return 0
  fi
  if ! polaris_require_delivery_tool gh >/dev/null; then
    if ! command -v gh >/dev/null 2>&1; then
    blocked_env "gh-missing" "GitHub CLI is required for delivery/full bootstrap profiles."
    return 1
    fi
    blocked_env "gh-unauth" "GitHub CLI is installed but not authenticated."
    return 1
  fi
}

validate_profile() {
  case "$PROFILE" in
    core|runtime|delivery|full) ;;
    *) die "invalid --profile: $PROFILE" ;;
  esac
}

run_mise() {
  local mise_bin
  if [[ "$DRY_RUN" == "true" ]]; then
    log "+ mise $*"
    return 0
  fi
  mise_bin="$(polaris_find_mise)" || return 1
  (cd "$TOOLCHAIN_ROOT" && "$mise_bin" "$@")
}

run_managed() {
  local command="$1"
  shift || true
  if [[ "$DRY_RUN" == "true" ]]; then
    log "+ mise exec -- $command $*"
    return 0
  fi
  POLARIS_WORKSPACE_ROOT="$TOOLCHAIN_ROOT" polaris_with_runtime_tools "$command" "$@"
}

bootstrap_core() {
  run_mise trust "$TOOLCHAIN_ROOT/mise.toml"
  run_mise install
}

bootstrap_runtime() {
  require_managed_tool node "Node" || return 1
  require_managed_tool pnpm "pnpm" || return 1
  run_managed bash scripts/polaris-toolchain.sh run docs.viewer.install
  run_managed bash scripts/polaris-toolchain.sh run fixtures.mockoon.install
  run_managed bash scripts/polaris-toolchain.sh run browser.playwright.install-browser
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

validate_profile

TOOLCHAIN_ROOT="$(resolve_toolchain_root)" || die "cannot resolve POLARIS_TOOLCHAIN_ROOT"
PLAYWRIGHT_BROWSERS_PATH="$TOOLCHAIN_ROOT/.polaris/toolchain/ms-playwright"
export POLARIS_TOOLCHAIN_ROOT="$TOOLCHAIN_ROOT"
export PLAYWRIGHT_BROWSERS_PATH

log "workspace: $WORKSPACE_ROOT"
log "toolchain root: $POLARIS_TOOLCHAIN_ROOT"
log "profile: $PROFILE"
log "PLAYWRIGHT_BROWSERS_PATH=$PLAYWRIGHT_BROWSERS_PATH"

run_cmd mkdir -p "$POLARIS_TOOLCHAIN_ROOT/.polaris/toolchain"
require_mise || exit 1

case "$PROFILE" in
  core)
    bootstrap_core
    ;;
  runtime)
    bootstrap_core
    bootstrap_runtime
    ;;
  delivery)
    bootstrap_core
    require_gh_delivery || exit 1
    log "delivery profile gh checks passed."
    ;;
  full)
    bootstrap_core
    bootstrap_runtime
    require_gh_delivery || exit 1
    log "full profile delivery checks passed."
    ;;
esac

log "bootstrap complete"
