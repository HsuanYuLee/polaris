#!/usr/bin/env bash
# Validate the head-and-worktree-bound Critic outcome used by engineering Phase 3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/tool-resolution.sh
source "$ROOT/scripts/lib/tool-resolution.sh"
PYTHON_BIN="$(polaris_require_python)"

"$PYTHON_BIN" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_engineering_self_review_result_1.py" "$@"
