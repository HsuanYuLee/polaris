#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOSEOUT="${SCRIPT_DIR}/framework-release-closeout.sh"

git_quiet() {
  git "$@" >/dev/null 2>&1
}

write_task() {
  local path="$1"
  local task_no="$2"
  local branch="$3"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<MD
# ${task_no}: Folder-native closeout selftest (1 pt)

> Source: DP-999 | Task: DP-999-${task_no} | JIRA: N/A | Repo: selftest-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-${task_no} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> ${branch} |
| Task branch | ${branch} |
| Depends on | N/A |
| References to load | - scripts/framework-release-closeout.sh |

## 目標

Selftest task.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`selftest.txt\` | modify | Selftest change |

## Allowed Files

- \`selftest.txt\`

## 估點理由

1 pt - selftest fixture.

## Test Command

\`\`\`bash
true
\`\`\`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
MD
}

write_verify_evidence() {
  local path="$1"
  local task_id="$2"
  local head_sha="$3"
  python3 - "$path" "$task_id" "$head_sha" <<'PY'
import json
import sys

path, task_id, head_sha = sys.argv[1:4]
with open(path, "w", encoding="utf-8") as fh:
    json.dump(
        {
            "ticket": task_id,
            "head_sha": head_sha,
            "writer": "run-verify-command.sh",
            "exit_code": 0,
        },
        fh,
    )
PY
}

TMP="$(mktemp -d -t framework-closeout-folder-native.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

REPO="${TMP}/repo"
TEMPLATE="${TMP}/template"
git init -b main "$REPO" >/dev/null
git -C "$REPO" config user.email selftest@example.test
git -C "$REPO" config user.name "Self Test"
echo base >"${REPO}/selftest.txt"
git -C "$REPO" add selftest.txt
git_quiet -C "$REPO" commit -m "base"

git init -b main "$TEMPLATE" >/dev/null
git -C "$TEMPLATE" config user.email selftest@example.test
git -C "$TEMPLATE" config user.name "Self Test"
echo template >"${TEMPLATE}/template.txt"
git -C "$TEMPLATE" add template.txt
git_quiet -C "$TEMPLATE" commit -m "template"
git -C "$TEMPLATE" tag v0.0.1

DP_DIR="${REPO}/docs-manager/src/content/docs/specs/design-plans/DP-999-folder-native-closeout"
mkdir -p "${DP_DIR}/tasks/T1" "${DP_DIR}/tasks/T2"
cat >"${DP_DIR}/plan.md" <<'MD'
---
topic: folder-native closeout selftest
created: 2026-05-06
status: LOCKED
locked_at: 2026-05-06
---

# DP-999

## Implementation Checklist

- [ ] T1: First task — `tasks/T1/index.md`
- [ ] T2: Remaining task — `tasks/T2/index.md`

## Work Orders

| Task | Work order |
|------|------------|
| T1 | `tasks/T1/index.md` |
| T2 | `tasks/T2/index.md` |
MD

BRANCH="task/DP-999-T1-folder-native-closeout"
TASK_MD="${DP_DIR}/tasks/T1/index.md"
write_task "$TASK_MD" T1 "$BRANCH"
write_task "${DP_DIR}/tasks/T2/index.md" T2 "task/DP-999-T2-folder-native-closeout"

mkdir -p "${REPO}/.worktrees"
git -C "$REPO" branch "$BRANCH" main
git -C "$REPO" worktree add "${REPO}/.worktrees/t1" "$BRANCH" >/dev/null 2>&1
echo t1 >"${REPO}/.worktrees/t1/selftest-t1.txt"
git -C "${REPO}/.worktrees/t1" add selftest-t1.txt
git_quiet -C "${REPO}/.worktrees/t1" commit -m "task t1"
TASK_HEAD="$(git -C "${REPO}/.worktrees/t1" rev-parse HEAD)"
git -C "$REPO" checkout main >/dev/null 2>&1
git_quiet -C "$REPO" merge --no-ff "$BRANCH" -m "merge ${BRANCH}"

WORKSPACE_COMMIT="$(git -C "$REPO" rev-parse HEAD)"
TEMPLATE_COMMIT="$(git -C "$TEMPLATE" rev-parse HEAD)"
EVIDENCE="${TMP}/verify-t1.json"
write_verify_evidence "$EVIDENCE" DP-999-T1 "$TASK_HEAD"

bash "$CLOSEOUT" \
  --repo "$REPO" \
  --template-repo "$TEMPLATE" \
  --task-md "$TASK_MD" \
  --verify-evidence "$EVIDENCE" \
  --workspace-commit "$WORKSPACE_COMMIT" \
  --template-commit "$TEMPLATE_COMMIT" \
  --version-tag v0.0.1 \
  --release-url https://github.com/example/polaris/releases/tag/v0.0.1

MOVED_TASK="${DP_DIR}/tasks/pr-release/T1/index.md"
[[ -f "$MOVED_TASK" ]] || {
  echo "[selftest] folder-native task was not moved to ${MOVED_TASK}" >&2
  exit 1
}
grep -q '^status: IMPLEMENTED$' "$MOVED_TASK" || {
  echo "[selftest] folder-native task status missing" >&2
  exit 1
}
[[ -f "${DP_DIR}/tasks/T2/index.md" ]] || {
  echo "[selftest] active sibling should remain in place" >&2
  exit 1
}
[[ ! -d "${REPO}/.worktrees/t1" ]] || {
  echo "[selftest] folder-native task worktree was not removed" >&2
  exit 1
}

echo "[framework-release-closeout-folder-native-selftest] PASS"
