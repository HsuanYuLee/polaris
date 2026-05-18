#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FINALIZE="$SCRIPT_DIR/finalize-engineering-delivery.sh"
TMPROOT="$(mktemp -d -t finalize-baseline-selftest-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

write_task() {
  local workspace="$1"
  mkdir -p "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-baseline/tasks/T1"
  cat > "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-baseline/tasks/T1/index.md" <<'EOF'
---
status: IN_PROGRESS
depends_on: []
---

# T1: finalize baseline fixture (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Task branch | task/DP-999-T1-finalize-baseline |

## Allowed Files

- `scripts/**`

## Test Command

```bash
echo ok
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo ok
```
EOF
}

write_mismatch_snapshot() {
  local repo="$1"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/.polaris/evidence/baseline-snapshot"
  python3 - "$repo/.polaris/evidence/baseline-snapshot/DP-999-T1-${head}.json" "$head" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()

planner_owned = {
    "verify_command": "echo changed",
    "depends_on": [],
    "base_branch": "main",
    "allowed_files": ["`scripts/**`"],
}
payload = {
    "schema_version": 1,
    "writer": "finalize-engineering-delivery-selftest",
    "task_id": "DP-999-T1",
    "head_sha": sys.argv[2],
    "planner_owned": planner_owned,
    "hashes": {
        "verify_command_sha256": digest(planner_owned["verify_command"]),
        "depends_on_sha256": digest(planner_owned["depends_on"]),
        "base_branch_sha256": digest(planner_owned["base_branch"]),
        "allowed_files_sha256": digest(planner_owned["allowed_files"]),
    },
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

repo="$TMPROOT/workspace"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" checkout -q -b task/DP-999-T1-finalize-baseline
git -C "$repo" config user.email "polaris@example.test"
git -C "$repo" config user.name "Polaris Selftest"
echo init > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m init
write_task "$repo"

set +e
out="$("$FINALIZE" --repo "$repo" --ticket DP-999-T1 --workspace "$repo" 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "missing planner-owned baseline snapshot" <<<"$out"

write_mismatch_snapshot "$repo"
set +e
out="$("$FINALIZE" --repo "$repo" --ticket DP-999-T1 --workspace "$repo" 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "planner-owned task.md fields changed" <<<"$out"

echo "PASS: finalize-engineering-delivery baseline snapshot selftest"
