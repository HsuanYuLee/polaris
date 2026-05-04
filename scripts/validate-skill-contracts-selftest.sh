#!/usr/bin/env bash
# Selftest for validate-skill-contracts.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINTER="$ROOT/scripts/validate-skill-contracts.sh"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/good" "$tmp/bad"

cat > "$tmp/good/SKILL.md" <<'EOF'
---
name: good
description: Good fixture.
---

## Sub-agent Completion Envelope

Use Completion Envelope when dispatching sub-agent work.

## Workspace language policy gate

Run `scripts/validate-language-policy.sh` before external write.

## Post-Task Reflection

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
EOF

bash "$LINTER" --root "$tmp/good" --strict >/dev/null

cat > "$tmp/bad/SKILL.md" <<'EOF'
---
name: bad
description: Bad fixture.
---

Dispatch a sub-agent to inspect code.
Write a JIRA comment with the result.
Produce docs-manager/src/content/docs/specs/foo/refinement.md.
Use legacy specs/{EPIC}/artifacts output.
EOF

if bash "$LINTER" --root "$tmp/bad" --strict >/dev/null 2>&1; then
  echo "FAIL: bad fixture should fail strict lint" >&2
  exit 1
fi

report="$(bash "$LINTER" --root "$tmp/bad" 2>/dev/null || true)"
grep -q 'sub-agent-envelope' <<<"$report"
grep -q 'post-task-reflection' <<<"$report"
grep -q 'external-write-language-gate' <<<"$report"
grep -q 'starlight-authoring' <<<"$report"
grep -q 'legacy-path-pattern' <<<"$report"

echo "PASS: skill contract linter selftest"
