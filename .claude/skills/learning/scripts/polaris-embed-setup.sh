#!/usr/bin/env bash
# polaris-embed-setup.sh — Create ~/.polaris/venv and install fastembed.
# Idempotent: safe to run multiple times; upgrades fastembed if newer.
set -euo pipefail

VENV_DIR="${POLARIS_VENV:-$HOME/.polaris/venv}"
PYTHON_BIN="${POLARIS_EMBED_PYTHON:-python3.13}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "polaris-embed-setup: $PYTHON_BIN not found. Install via 'brew install python@3.13' or set POLARIS_EMBED_PYTHON." >&2
  exit 2
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "creating venv at $VENV_DIR (python: $PYTHON_BIN)"
  mkdir -p "$(dirname "$VENV_DIR")"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

echo "installing/upgrading fastembed in $VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet --upgrade fastembed

echo "verifying import"
"$VENV_DIR/bin/python" -c "from fastembed import TextEmbedding; print('fastembed ok')"

echo "polaris-embed-setup: ready at $VENV_DIR"
