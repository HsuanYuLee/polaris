#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE="$SCRIPT_DIR/validate-task-md.sh"
TMPROOT="$(mktemp -d -t validate-task-md-snapshot-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

task="$TMPROOT/task.md"
snapshot="$TMPROOT/snapshot.json"

cat >"$task" <<'EOF'
---
depends_on: [T1]
---

# T2: snapshot selftest (1 pt)

> Source: DP-999 | Task: DP-999-T2 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Base branch | task/DP-999-T1-upstream |

## Allowed Files

- `scripts/example.sh`

## Verify Command

```bash
echo ok
```
EOF

python3 - "$snapshot" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()

planner_owned = {
    "verify_command": "echo ok",
    "depends_on": ["T1"],
    "base_branch": "task/DP-999-T1-upstream",
    "allowed_files": ["`scripts/example.sh`"],
}
payload = {
    "schema_version": 1,
    "writer": "validate-task-md-selftest",
    "task_id": "DP-999-T2",
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

bash "$VALIDATE" --snapshot "$snapshot" "$task" >/dev/null

perl -0pi -e 's/echo ok/echo changed/' "$task"
if bash "$VALIDATE" --snapshot "$snapshot" "$task" >/tmp/validate-task-md-selftest.out 2>&1; then
  echo "validate-task-md-selftest: expected snapshot mismatch to fail" >&2
  exit 1
fi
grep -q "Verify Command changed" /tmp/validate-task-md-selftest.out

echo "PASS: validate-task-md snapshot selftest"
