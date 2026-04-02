#!/usr/bin/env bash
# install-deps.sh — Install Polaris framework dependencies
#
# Installs node_modules for framework tools (E2E, Mockoon).
# Called by /init and sync-from-polaris.sh after version upgrades.
#
# Usage:
#   scripts/install-deps.sh              # Install all
#   scripts/install-deps.sh --check      # Check status only (no install)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_ONLY="${1:-}"

status_ok=0
status_missing=0

check_module() {
  local name="$1"
  local dir="$2"

  if [[ ! -f "$dir/package.json" ]]; then
    return 0  # No package.json → not a module, skip
  fi

  if [[ -d "$dir/node_modules" ]]; then
    echo "  ✅ $name"
    status_ok=$((status_ok + 1))
  else
    echo "  ❌ $name (not installed)"
    status_missing=$((status_missing + 1))
  fi
}

install_module() {
  local name="$1"
  local dir="$2"

  if [[ ! -f "$dir/package.json" ]]; then
    return 0
  fi

  if [[ -d "$dir/node_modules" ]]; then
    echo "  ✅ $name (already installed)"
    return 0
  fi

  echo "  📦 Installing $name..."
  npm install --prefix "$dir" --silent 2>&1
  echo "  ✅ $name"
}

install_playwright_browser() {
  local e2e_dir="$SCRIPT_DIR/e2e"

  if [[ ! -d "$e2e_dir/node_modules" ]]; then
    return 0
  fi

  echo ""
  echo "Playwright browser:"
  # Check if chromium is already installed
  if npx --prefix "$e2e_dir" playwright install --dry-run chromium 2>&1 | grep -q "already installed"; then
    echo "  ✅ Chromium (already installed)"
  else
    if [[ "$CHECK_ONLY" == "--check" ]]; then
      echo "  ❌ Chromium (not installed)"
      status_missing=$((status_missing + 1))
    else
      echo "  📦 Installing Chromium..."
      npx --prefix "$e2e_dir" playwright install chromium 2>&1
      echo "  ✅ Chromium"
    fi
  fi
}

echo "═══════════════════════════════"
echo "Polaris Framework Dependencies"
echo "═══════════════════════════════"
echo ""

if [[ "$CHECK_ONLY" == "--check" ]]; then
  echo "Status:"
  check_module "E2E (Playwright)" "$SCRIPT_DIR/e2e"
  check_module "Mockoon CLI" "$SCRIPT_DIR/mockoon"
  install_playwright_browser
  echo ""
  echo "Installed: $status_ok | Missing: $status_missing"
  [[ $status_missing -eq 0 ]] && exit 0 || exit 1
else
  echo "Installing:"
  install_module "E2E (Playwright)" "$SCRIPT_DIR/e2e"
  install_module "Mockoon CLI" "$SCRIPT_DIR/mockoon"
  install_playwright_browser
  echo ""
  echo "Done."
fi
