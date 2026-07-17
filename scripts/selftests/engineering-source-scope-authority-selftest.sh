#!/usr/bin/env bash
# Purpose: prevent live engineering delivery docs/adapters from restoring
#          refinement.json.changed_files as a delivery gate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLOW="$ROOT/.claude/skills/references/engineer-delivery-flow.md"
GATE="$ROOT/scripts/gates/gate-changed-files-scope.sh"

grep -Fq 'task.md `Allowed Files`' "$FLOW"
grep -Fq 'planning preview' "$FLOW"
grep -Fq -- '--task-md PATH' "$GATE"
grep -Fq 'scripts/check-scope.sh' "$GATE"

if grep -Eq -- '--refinement|json\.loads|changed_files.*required' "$GATE"; then
  echo "FAIL: delivery scope adapter still consumes refinement changed_files" >&2
  exit 1
fi

if grep -Fq -- '--refinement <main-checkout-source-container>/refinement.json' "$FLOW"; then
  echo "FAIL: live engineering flow still instructs refinement scope gating" >&2
  exit 1
fi

echo "PASS: engineering source scope authority is task.md Allowed Files only"
