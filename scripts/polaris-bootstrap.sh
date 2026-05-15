#!/usr/bin/env bash
# Bootstrap Polaris-owned root runtime tools and package-local assets.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$WORKSPACE_ROOT/scripts"
DRY_RUN=false
PROFILE="runtime"

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

log() {
  printf '[polaris-bootstrap] %s\n' "$*"
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
  (cd "$WORKSPACE_ROOT" && "$@")
}

resolve_toolchain_root() {
  if [[ -n "${POLARIS_TOOLCHAIN_ROOT:-}" ]]; then
    (cd "$POLARIS_TOOLCHAIN_ROOT" && pwd) || return 1
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]] && command -v git >/dev/null 2>&1; then
    # shellcheck source=lib/main-checkout.sh
    . "$SCRIPT_DIR/lib/main-checkout.sh"
    resolve_main_checkout "$WORKSPACE_ROOT" 2>/dev/null && return 0
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
  if command -v mise >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "mise missing; dry-run continues after repair hint."
    print_mise_repair_hints
    return 0
  fi
  print_mise_repair_hints
  return 1
}

validate_profile() {
  case "$PROFILE" in
    core|runtime|delivery|full) ;;
    *) die "invalid --profile: $PROFILE" ;;
  esac
}

run_mise() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "+ mise $*"
    return 0
  fi
  (cd "$WORKSPACE_ROOT" && mise "$@")
}

run_managed() {
  local command="$1"
  shift || true
  if [[ "$DRY_RUN" == "true" ]]; then
    log "+ mise exec -- $command $*"
    return 0
  fi
  (cd "$WORKSPACE_ROOT" && mise exec -- "$command" "$@")
}

bootstrap_core() {
  run_mise trust "$WORKSPACE_ROOT/mise.toml"
  run_mise install
}

bootstrap_runtime() {
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
    log "delivery profile requires gh auth; use polaris-doctor delivery checks after bootstrap."
    ;;
  full)
    bootstrap_core
    bootstrap_runtime
    log "full profile includes delivery checks; use polaris-doctor delivery checks for gh auth."
    ;;
esac

log "bootstrap complete"
