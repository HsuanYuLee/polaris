#!/bin/bash
set -euo pipefail

# Support --yes flag for non-interactive mode (e.g., when run by Claude Code)
AUTO_YES=false
for arg in "$@"; do
  case "$arg" in
    --yes|-y|--non-interactive) AUTO_YES=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
USER_CONFIG_DIR="$HOME/.config/worktrunk"
USER_CONFIG="$USER_CONFIG_DIR/config.toml"
PROJECT_CONFIG_DIR=".config"
PROJECT_CONFIG="$PROJECT_CONFIG_DIR/wt.toml"

echo "=== wt (worktrunk) Setup ==="
echo

# 1. Check if wt is installed
if command -v wt &>/dev/null; then
  echo "[OK] wt is installed: $(wt --version 2>/dev/null || echo 'version unknown')"
else
  echo "[MISSING] wt is not installed."
  echo
  if command -v brew &>/dev/null; then
    if [[ "$AUTO_YES" == true ]]; then
      REPLY=y
    else
      read -p "Install via Homebrew? (y/N) " -n 1 -r
      echo
    fi
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      brew install worktrunk
    else
      echo "Please install manually: brew install worktrunk"
      exit 1
    fi
  else
    echo "Please install manually:"
    echo "  brew install worktrunk"
    echo "  # or: cargo install worktrunk"
    exit 1
  fi
fi

echo

# 2. Setup user config
if [[ -f "$USER_CONFIG" ]]; then
  echo "[OK] User config exists: $USER_CONFIG"
else
  echo "[SETUP] Creating user config: $USER_CONFIG"
  mkdir -p "$USER_CONFIG_DIR"
  cp "$SKILL_DIR/references/user-config.toml" "$USER_CONFIG"
  echo "  Copied from references/user-config.toml"
fi

echo

# 3. Setup project config (if in a git repo)
if git rev-parse --is-inside-work-tree &>/dev/null; then
  if [[ -f "$PROJECT_CONFIG" ]]; then
    echo "[OK] Project config exists: $PROJECT_CONFIG"
  else
    echo "[SETUP] Creating project config: $PROJECT_CONFIG"
    mkdir -p "$PROJECT_CONFIG_DIR"
    cp "$SKILL_DIR/references/project-config.toml" "$PROJECT_CONFIG"
    echo "  Copied from references/project-config.toml"
  fi
else
  echo "[SKIP] Not in a git repository — skipping project config."
fi

echo

# 4. Shell integration
if type wt 2>/dev/null | grep -q "function"; then
  echo "[OK] Shell integration is active (wt is a shell function)."
else
  echo "[SETUP] Installing shell integration..."
  wt config shell install
  echo "  Please restart your shell or run: source ~/.zshrc"
fi

echo

# 5. Claude Code permissions
SETTINGS_FILE=".claude/settings.local.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  if grep -q 'Bash(wt:\*)' "$SETTINGS_FILE"; then
    echo "[OK] Claude Code permission 'Bash(wt:*)' already set."
  else
    echo "[INFO] Consider adding 'Bash(wt:*)' to $SETTINGS_FILE permissions.allow"
  fi
else
  echo "[SKIP] No $SETTINGS_FILE found — skipping Claude Code permission check."
fi

echo
echo "=== Setup complete ==="
