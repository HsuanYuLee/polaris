#!/usr/bin/env bash
# Pre-push delivery gate.
#
# Legacy versions checked /tmp/.quality-gate-passed-* marker files. That marker
# flow is retired; push readiness now delegates to the same portable gates used
# by generated git hooks and PR creation.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HOOK_DIR/../.." && pwd)"
GATES_DIR="$ROOT_DIR/scripts/gates"

input="$(cat || true)"
if [[ -z "$input" && -n "${CLAUDE_TOOL_INPUT:-}" ]]; then
  input="$CLAUDE_TOOL_INPUT"
fi

command="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("tool_input",{}).get("command",""))
except Exception:
    print("")
' 2>/dev/null || true)"

[[ -z "$command" || "$command" =~ (^|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push\b ]] || exit 0

repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
if [[ -n "$command" ]]; then
  extracted="$(printf '%s' "$command" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //' || true)"
  [[ -n "$extracted" ]] && repo_root="$extracted"
fi

[[ -d "$repo_root" ]] || exit 0

if printf '%s' "$command" | grep -qE -- '--delete|--tags'; then
  exit 0
fi

branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
case "$branch" in
  ""|HEAD|main|master|develop) exit 0 ;;
esac

if [[ -x "$GATES_DIR/gate-ci-local.sh" ]]; then
  bash "$GATES_DIR/gate-ci-local.sh" --repo "$repo_root" --push-mode
fi

if [[ -x "$GATES_DIR/gate-revision-rebase.sh" ]]; then
  bash "$GATES_DIR/gate-revision-rebase.sh" --repo "$repo_root"
fi

if [[ -x "$GATES_DIR/gate-evidence.sh" ]]; then
  bash "$GATES_DIR/gate-evidence.sh" --repo "$repo_root"
fi

if [[ -x "$GATES_DIR/gate-changeset.sh" ]]; then
  bash "$GATES_DIR/gate-changeset.sh" --repo "$repo_root"
fi
