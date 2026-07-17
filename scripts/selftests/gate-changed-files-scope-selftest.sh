#!/usr/bin/env bash
# Purpose: prove the changed-files scope adapter consumes only task.md Allowed Files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-changed-files-scope.sh"
WORKDIR="$(mktemp -d -t dp422-t4-scope.XXXXXX)"
META="${WORKDIR}-meta"
mkdir -p "$META"
trap 'rm -rf "$WORKDIR" "$META"' EXIT

git -C "$WORKDIR" init -q
git -C "$WORKDIR" config user.email test@example.com
git -C "$WORKDIR" config user.name "Scope Gate Test"
mkdir -p "$WORKDIR/scripts" "$WORKDIR/docs"
echo base >"$WORKDIR/scripts/allowed.sh"
git -C "$WORKDIR" add scripts/allowed.sh
git -C "$WORKDIR" commit -q -m base

TASK_MD="$META/task.md"
cat >"$TASK_MD" <<'TASK'
# T1 — Demo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Work item ID | DP-999-T1 |
| Base branch | HEAD~1 |

## Allowed Files

- `scripts/**`

## Test Command

```bash
echo ok
```
TASK

# A contradictory refinement preview must have no effect on delivery scope.
cat >"$META/refinement.json" <<'JSON'
{"changed_files":["docs/**"]}
JSON

echo changed >"$WORKDIR/scripts/allowed.sh"
git -C "$WORKDIR" commit -am allowed -q
out="$($GATE --repo "$WORKDIR" --task-md "$TASK_MD" --base HEAD~1)"
grep -Fq '"scope_additions": []' <<<"$out"

echo extra >"$WORKDIR/docs/extra.md"
git -C "$WORKDIR" add docs/extra.md
git -C "$WORKDIR" commit -q -m extra
if "$GATE" --repo "$WORKDIR" --task-md "$TASK_MD" --base HEAD~1 >/dev/null 2>&1; then
  echo "FAIL: file outside task.md Allowed Files should fail" >&2
  exit 1
fi

if "$GATE" --repo "$WORKDIR" --refinement "$META/refinement.json" --base HEAD~1 >/dev/null 2>&1; then
  echo "FAIL: retired --refinement authority must be rejected" >&2
  exit 1
fi

echo "PASS: task.md Allowed Files is the only changed-files scope authority"
