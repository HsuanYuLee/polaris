#!/usr/bin/env bash
set -euo pipefail

# Smoke test for DP-048 local_extension lifecycle metadata:
# DP task head evidence → release metadata writer → extension completion gate.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

workspace="$tmp_dir/workspace"
template="$tmp_dir/template"
task_md="$tmp_dir/specs/design-plans/DP-048-fixture/tasks/T1.md"

mkdir -p "$workspace" "$template" "$(dirname "$task_md")"

git -C "$workspace" init -q
git -C "$workspace" config user.email "selftest@example.invalid"
git -C "$workspace" config user.name "Polaris Selftest"
printf 'base\n' > "$workspace/README.md"
git -C "$workspace" add README.md
git -C "$workspace" commit -q -m "base"
printf 'task\n' > "$workspace/task.txt"
git -C "$workspace" add task.txt
git -C "$workspace" commit -q -m "task head"
task_head_sha="$(git -C "$workspace" rev-parse HEAD)"

ci_evidence="/tmp/polaris-ci-local-DP-048-T1-${task_head_sha}.json"
verify_evidence="/tmp/polaris-verified-DP-048-T1-${task_head_sha}.json"
cat > "$ci_evidence" <<JSON
{
  "branch": "task/DP-048-T1-fixture",
  "head_sha": "${task_head_sha}",
  "status": "PASS",
  "writer": "ci-local.sh",
  "timestamp": "2026-04-29T00:00:00Z"
}
JSON
cat > "$verify_evidence" <<JSON
{
  "ticket": "DP-048-T1",
  "head_sha": "${task_head_sha}",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "at": "2026-04-29T00:00:00Z"
}
JSON

printf 'release\n' > "$workspace/VERSION"
git -C "$workspace" add VERSION
git -C "$workspace" commit -q -m "release commit"
workspace_commit="$(git -C "$workspace" rev-parse HEAD)"

git -C "$template" init -q
git -C "$template" config user.email "selftest@example.invalid"
git -C "$template" config user.name "Polaris Selftest"
printf 'release\n' > "$template/VERSION"
git -C "$template" add VERSION
git -C "$template" commit -q -m "template release"
template_commit="$(git -C "$template" rev-parse HEAD)"
git -C "$template" tag v0.0.1

cat > "$task_md" <<'MD'
---
status: IN_PROGRESS
depends_on: []
---

# T1: Local extension fixture (1 pt)

> Epic: DP-048 | JIRA: DP-048-T1 | Repo: work

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-048-T1 |
| Parent Epic | DP-048 |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-048-T1-fixture |
| Task branch | task/DP-048-T1-fixture |
| Depends on | N/A |
| References to load | - `.claude/skills/references/task-md-schema.md` |

## Verification Handoff

Framework fixture; verification is covered by this script.

## 目標

Exercise local extension deliverable metadata.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/write-extension-deliverable.sh` | test | Fixture writer path |

## Allowed Files

- `scripts/write-extension-deliverable.sh`

## 估點理由

1 pt - fixture only.

## 測試計畫（code-level）

- writer + completion gate smoke test

## Test Command

```bash
bash scripts/local-extension-completion-selftest.sh
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo PASS
```
MD

bash "$ROOT_DIR/scripts/write-extension-deliverable.sh" "$task_md" \
  --extension-id example-extension \
  --task-head-sha "$task_head_sha" \
  --workspace-commit "$workspace_commit" \
  --template-commit "$template_commit" \
  --version-tag v0.0.1 \
  --release-url https://github.com/example/template/releases/tag/v0.0.1 \
  --ci-local-evidence "$ci_evidence" \
  --verify-evidence "$verify_evidence" \
  --completed-at 2026-04-29T00:00:00Z

bash "$ROOT_DIR/scripts/check-local-extension-completion.sh" \
  --repo "$workspace" \
  --task-md "$task_md" \
  --task-id DP-048-T1 \
  --extension-id example-extension \
  --template-repo "$template"

bash "$ROOT_DIR/scripts/validate-task-md.sh" "$task_md"

bash "$ROOT_DIR/scripts/write-extension-deliverable.sh" "$task_md" \
  --extension-id example-extension \
  --task-head-sha "$task_head_sha" \
  --workspace-commit "$workspace_commit" \
  --template-commit "$template_commit" \
  --version-tag v0.0.1 \
  --release-url https://github.com/example/template/releases/tag/v0.0.1 \
  --ci-local-evidence N/A \
  --verify-evidence "$verify_evidence" \
  --completed-at 2026-04-29T00:00:00Z

bash "$ROOT_DIR/scripts/check-local-extension-completion.sh" \
  --repo "$workspace" \
  --task-md "$task_md" \
  --task-id DP-048-T1 \
  --extension-id example-extension \
  --template-repo "$template"

bash "$ROOT_DIR/scripts/validate-task-md.sh" "$task_md"

rm -f "$ci_evidence" "$verify_evidence"

echo "PASS: local extension completion smoke test"
