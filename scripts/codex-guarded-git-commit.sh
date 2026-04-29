#!/usr/bin/env bash
# codex-guarded-git-commit.sh
# Codex fallback command gate for git commit.
#
# Runs P0 commit gates:
#  - ci-local-required (Dimension B; D12-c)
#  - version-docs-lint-gate
#
# Usage:
#   codex-guarded-git-commit.sh [--dry-run] [git commit args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER="$SCRIPT_DIR/gate-hook-adapter.sh"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

if [[ $# -eq 0 ]]; then
  set -- -m "chore: 測試 gated commit"
fi

# Commit message language checks are delegated to gate-commit-language.sh,
# which wraps validate-language-policy.sh-compatible workspace language policy.
commit_cmd="$(
  python3 - "$@" <<'PY'
import shlex
import sys

print(" ".join(shlex.quote(part) for part in ["git", "commit", *sys.argv[1:]]))
PY
)"

"$ROOT_DIR/scripts/gates/gate-commit-language.sh" --repo "${GATE_PROJECT_DIR:-$(pwd)}" --command "$commit_cmd"
"$ADAPTER" "$ROOT_DIR/.claude/hooks/ci-local-gate.sh" "$commit_cmd"
"$ADAPTER" "$ROOT_DIR/.claude/hooks/version-docs-lint-gate.sh" "$commit_cmd"

if [[ "$dry_run" == true ]]; then
  echo "PASS: commit gates passed (dry-run)"
  exit 0
fi

exec git commit "$@"
