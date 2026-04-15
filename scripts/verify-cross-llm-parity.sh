#!/usr/bin/env bash
set -euo pipefail

# verify-cross-llm-parity.sh
#
# Verify that generated Codex artifacts are in sync with Claude source-of-truth.
#
# Usage:
#   bash scripts/verify-cross-llm-parity.sh
#
# This script checks:
#   1) .claude/skills -> .agents/skills parity
#   2) .claude/rules -> .codex/AGENTS.md parity

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/2] Verify Claude/Codex skills parity"
bash "$SCRIPT_DIR/mechanism-parity.sh" --strict

echo
echo "[2/2] Verify Codex rules transpile parity"
bash "$SCRIPT_DIR/transpile-rules-to-codex.sh" --check

echo
echo "Result: CROSS-LLM PARITY OK"

