#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/check-delivery-completion.sh"
TMPROOT="$(mktemp -d -t completion-baseline-selftest-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

write_task() {
  local repo="$1"
  mkdir -p "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-baseline/tasks/T1"
  cat > "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-baseline/tasks/T1/index.md" <<'EOF'
---
deliverable:
  pr_url: https://github.com/demo/example/pull/1
  pr_state: OPEN
  head_sha: HEAD_SHA_PLACEHOLDER
status: IN_PROGRESS
depends_on: []
---

# T1: completion baseline fixture (1 pt)

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
| Task branch | task/DP-999-T1-completion-baseline |

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
  local head
  head="$(git -C "$repo" rev-parse HEAD)"
  perl -0pi -e "s/HEAD_SHA_PLACEHOLDER/$head/g" "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-baseline/tasks/T1/index.md"
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
    "writer": "check-delivery-completion-selftest",
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

setup_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" checkout -q -b main
  git -C "$repo" config user.email "polaris@example.test"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" remote add origin https://github.com/demo/example.git
  echo init > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m init
  git -C "$repo" checkout -q -b task/DP-999-T1-completion-baseline
  write_task "$repo"
}

repo="$TMPROOT/repo"
setup_repo "$repo"

set +e
out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "missing planner-owned baseline snapshot" <<<"$out"

write_mismatch_snapshot "$repo"
set +e
out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "planner-owned task.md fields changed" <<<"$out"

echo "PASS: check-delivery-completion baseline snapshot selftest"
