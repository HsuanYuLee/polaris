#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATE_TASK_MD="$SCRIPT_DIR/validate-task-md.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d -t lifecycle-status-validator.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

task_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-999-lifecycle-status/tasks/T1"
mkdir -p "$task_dir"

cat >"$task_dir/index.md" <<'MD'
# T1: 測試 status validator (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A |
| AC 驗收單 | N/A |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1 |
| Task branch | task/DP-999-T1 |

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/example.sh` | modify | fixture |

## Allowed Files

- `scripts/example.sh`

## Test Environment

- **Level**: static

## Test Command

```bash
true
```

## Verify Command

```bash
true
```
MD

if bash "$VALIDATE_TASK_MD" "$task_dir/index.md" >/tmp/lifecycle-status.out 2>/tmp/lifecycle-status.err; then
  fail "missing status should fail active task validation"
fi
grep -q 'frontmatter status is required' /tmp/lifecycle-status.err || fail "missing status error not reported"

python3 - "$task_dir/index.md" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text(encoding="utf-8")
path.write_text("---\nstatus: IMPLEMENTED\n---\n\n" + text, encoding="utf-8")
PY

set +e
bash "$VALIDATE_TASK_MD" "$task_dir/index.md" >/tmp/lifecycle-status.out 2>/tmp/lifecycle-status.err
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "direct IMPLEMENTED edit in active tasks/ should hard fail with exit 2"
grep -q 'completion invariant violated' /tmp/lifecycle-status.err || fail "direct edit invariant error not reported"

echo "[selftest] PASS"
