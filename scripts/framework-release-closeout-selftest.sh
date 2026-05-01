#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOSEOUT="${SCRIPT_DIR}/framework-release-closeout.sh"

git_quiet() {
  git "$@" >/dev/null 2>&1
}

write_plan() {
  local dp_dir="$1"
  local task_count="${2:-2}"
  local t2_checklist="- [ ] T2: Second task — \`tasks/T2.md\`"
  local t2_work_order="| T2 | \`tasks/T2.md\` |"
  if [[ "$task_count" == "1" ]]; then
    t2_checklist=""
    t2_work_order=""
  fi
  cat >"${dp_dir}/plan.md" <<'MD'
---
topic: release closeout selftest
created: 2026-04-30
status: LOCKED
locked_at: 2026-04-30
---

# DP-999

## Implementation Checklist

- [ ] T1: First task — `tasks/T1.md`
MD
  if [[ -n "$t2_checklist" ]]; then
    printf '%s\n' "$t2_checklist" >>"${dp_dir}/plan.md"
  fi
  cat >>"${dp_dir}/plan.md" <<'MD'

## Work Orders

| Task | Work order |
|------|------------|
| T1 | `tasks/T1.md` |
MD
  if [[ -n "$t2_work_order" ]]; then
    printf '%s\n' "$t2_work_order" >>"${dp_dir}/plan.md"
  fi
}

write_task() {
  local path="$1"
  local task_no="$2"
  local branch="$3"
  local depends="$4"

  if [[ -n "$depends" ]]; then
    cat >"$path" <<MD
---
depends_on: [${depends}]
---

# ${task_no}: Closeout selftest ${task_no} (1 pt)
MD
  else
    cat >"$path" <<MD
# ${task_no}: Closeout selftest ${task_no} (1 pt)
MD
  fi

  cat >>"$path" <<MD

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

make_repos() {
  local tmp="$1"
  local repo="${tmp}/repo"
  local template="${tmp}/template"

  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  echo base >"${repo}/selftest.txt"
  git -C "$repo" add selftest.txt
  git_quiet -C "$repo" commit -m "base"

  git init -b main "$template" >/dev/null
  git -C "$template" config user.email selftest@example.test
  git -C "$template" config user.name "Self Test"
  echo template >"${template}/template.txt"
  git -C "$template" add template.txt
  git_quiet -C "$template" commit -m "template"
  git -C "$template" tag v0.0.1

  printf '%s\n%s\n' "$repo" "$template"
}

add_task_branch_and_worktree() {
  local repo="$1"
  local branch="$2"
  local suffix="$3"
  local wt="${repo}/.worktrees/selftest-${suffix}"

  mkdir -p "${repo}/.worktrees"
  git -C "$repo" branch "$branch" main
  git -C "$repo" worktree add "$wt" "$branch" >/dev/null 2>&1
  echo "$suffix" >"${wt}/selftest-${suffix}.txt"
  git -C "$wt" add "selftest-${suffix}.txt"
  git_quiet -C "$wt" commit -m "task ${suffix}"
  printf '%s\n' "$wt"
}

merge_task_branch() {
  local repo="$1"
  local branch="$2"
  git -C "$repo" checkout main >/dev/null 2>&1
  git_quiet -C "$repo" merge --no-ff "$branch" -m "merge ${branch}"
}

run_single_task_case() {
  local tmp repos repo template dp_dir archived_dp_dir task_md branch wt task_head workspace_commit template_commit evidence
  tmp="$(mktemp -d -t framework-closeout-single.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repos="$(make_repos "$tmp")"
  repo="$(printf '%s\n' "$repos" | sed -n '1p')"
  template="$(printf '%s\n' "$repos" | sed -n '2p')"

  dp_dir="${repo}/docs-manager/src/content/docs/specs/design-plans/DP-999-release-closeout"
  mkdir -p "${dp_dir}/tasks"
  write_plan "$dp_dir" 1
  branch="task/DP-999-T1-closeout"
  task_md="${dp_dir}/tasks/T1.md"
  write_task "$task_md" T1 "$branch" ""
  wt="$(add_task_branch_and_worktree "$repo" "$branch" "t1")"
  task_head="$(git -C "$wt" rev-parse HEAD)"
  merge_task_branch "$repo" "$branch"
  workspace_commit="$(git -C "$repo" rev-parse HEAD)"
  template_commit="$(git -C "$template" rev-parse HEAD)"
  evidence="${tmp}/verify-t1.json"
  write_verify_evidence "$evidence" DP-999-T1 "$task_head"

  bash "$CLOSEOUT" \
    --repo "$repo" \
    --template-repo "$template" \
    --task-md "$task_md" \
    --verify-evidence "$evidence" \
    --workspace-commit "$workspace_commit" \
    --template-commit "$template_commit" \
    --version-tag v0.0.1 \
    --release-url https://github.com/example/polaris/releases/tag/v0.0.1

  archived_dp_dir="${repo}/docs-manager/src/content/docs/specs/design-plans/archive/DP-999-release-closeout"
  [[ ! -d "$dp_dir" && -d "$archived_dp_dir" ]] || { echo "[selftest] single parent DP was not archived" >&2; return 1; }
  [[ -f "${archived_dp_dir}/tasks/pr-release/T1.md" ]] || { echo "[selftest] single task was not moved" >&2; return 1; }
  grep -q '^status: IMPLEMENTED$' "${archived_dp_dir}/tasks/pr-release/T1.md" || { echo "[selftest] single task status missing" >&2; return 1; }
  [[ ! -d "$wt" ]] || { echo "[selftest] single task worktree was not removed" >&2; return 1; }
}

run_stacked_task_case() {
  local tmp repos repo template dp_dir archived_dp_dir branch1 branch2 task1 task2 wt1 wt2 head1 head2 workspace_commit template_commit ev1 ev2
  tmp="$(mktemp -d -t framework-closeout-stacked.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repos="$(make_repos "$tmp")"
  repo="$(printf '%s\n' "$repos" | sed -n '1p')"
  template="$(printf '%s\n' "$repos" | sed -n '2p')"

  dp_dir="${repo}/docs-manager/src/content/docs/specs/design-plans/DP-999-release-closeout"
  mkdir -p "${dp_dir}/tasks"
  write_plan "$dp_dir"
  branch1="task/DP-999-T1-closeout"
  branch2="task/DP-999-T2-closeout"
  task1="${dp_dir}/tasks/T1.md"
  task2="${dp_dir}/tasks/T2.md"
  write_task "$task1" T1 "$branch1" ""
  write_task "$task2" T2 "$branch2" "T1"
  wt1="$(add_task_branch_and_worktree "$repo" "$branch1" "t1")"
  wt2="$(add_task_branch_and_worktree "$repo" "$branch2" "t2")"
  head1="$(git -C "$wt1" rev-parse HEAD)"
  head2="$(git -C "$wt2" rev-parse HEAD)"
  merge_task_branch "$repo" "$branch1"
  merge_task_branch "$repo" "$branch2"
  workspace_commit="$(git -C "$repo" rev-parse HEAD)"
  template_commit="$(git -C "$template" rev-parse HEAD)"
  ev1="${tmp}/verify-t1.json"
  ev2="${tmp}/verify-t2.json"
  write_verify_evidence "$ev1" DP-999-T1 "$head1"
  write_verify_evidence "$ev2" DP-999-T2 "$head2"

  bash "$CLOSEOUT" \
    --repo "$repo" \
    --template-repo "$template" \
    --task-md "$task1" \
    --verify-evidence "$ev1" \
    --task-md "$task2" \
    --verify-evidence "$ev2" \
    --workspace-commit "$workspace_commit" \
    --template-commit "$template_commit" \
    --version-tag v0.0.1 \
    --release-url https://github.com/example/polaris/releases/tag/v0.0.1

  archived_dp_dir="${repo}/docs-manager/src/content/docs/specs/design-plans/archive/DP-999-release-closeout"
  [[ ! -d "$dp_dir" && -d "$archived_dp_dir" ]] || { echo "[selftest] stacked parent DP was not archived" >&2; return 1; }
  [[ -f "${archived_dp_dir}/tasks/pr-release/T1.md" && -f "${archived_dp_dir}/tasks/pr-release/T2.md" ]] || { echo "[selftest] stacked tasks were not moved" >&2; return 1; }
  grep -q '^status: IMPLEMENTED$' "${archived_dp_dir}/plan.md" || { echo "[selftest] parent DP was not closed" >&2; return 1; }
  [[ ! -d "$wt1" && ! -d "$wt2" ]] || { echo "[selftest] stacked worktrees were not removed" >&2; return 1; }
}

run_archived_pr_release_case() {
  local tmp repos repo template archived_dp_dir branch task_md wt task_head workspace_commit template_commit evidence
  tmp="$(mktemp -d -t framework-closeout-archived.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repos="$(make_repos "$tmp")"
  repo="$(printf '%s\n' "$repos" | sed -n '1p')"
  template="$(printf '%s\n' "$repos" | sed -n '2p')"

  archived_dp_dir="${repo}/docs-manager/src/content/docs/specs/design-plans/archive/DP-999-release-closeout"
  mkdir -p "${archived_dp_dir}/tasks/pr-release"
  write_plan "$archived_dp_dir" 1
  branch="task/DP-999-T1-closeout"
  task_md="${archived_dp_dir}/tasks/pr-release/T1.md"
  write_task "$task_md" T1 "$branch" ""
  wt="$(add_task_branch_and_worktree "$repo" "$branch" "t1")"
  task_head="$(git -C "$wt" rev-parse HEAD)"
  merge_task_branch "$repo" "$branch"
  workspace_commit="$(git -C "$repo" rev-parse HEAD)"
  template_commit="$(git -C "$template" rev-parse HEAD)"
  evidence="${tmp}/verify-t1.json"
  write_verify_evidence "$evidence" DP-999-T1 "$task_head"

  bash "$CLOSEOUT" \
    --repo "$repo" \
    --template-repo "$template" \
    --task-md "$task_md" \
    --verify-evidence "$evidence" \
    --workspace-commit "$workspace_commit" \
    --template-commit "$template_commit" \
    --version-tag v0.0.1 \
    --release-url https://github.com/example/polaris/releases/tag/v0.0.1

  [[ -d "$archived_dp_dir" ]] || { echo "[selftest] archived DP directory disappeared" >&2; return 1; }
  [[ -f "$task_md" ]] || { echo "[selftest] archived pr-release task missing" >&2; return 1; }
  grep -q '^status: IMPLEMENTED$' "$task_md" || { echo "[selftest] archived task status missing" >&2; return 1; }
  grep -q '^status: IMPLEMENTED$' "${archived_dp_dir}/plan.md" || { echo "[selftest] archived parent DP was not closed" >&2; return 1; }
  [[ ! -d "$wt" ]] || { echo "[selftest] archived task worktree was not removed" >&2; return 1; }
}

run_stale_evidence_case() {
  local tmp repos repo template dp_dir branch task_md wt task_head workspace_commit template_commit evidence rc
  tmp="$(mktemp -d -t framework-closeout-stale.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repos="$(make_repos "$tmp")"
  repo="$(printf '%s\n' "$repos" | sed -n '1p')"
  template="$(printf '%s\n' "$repos" | sed -n '2p')"

  dp_dir="${repo}/docs-manager/src/content/docs/specs/design-plans/DP-999-release-closeout"
  mkdir -p "${dp_dir}/tasks"
  write_plan "$dp_dir"
  branch="task/DP-999-T1-closeout"
  task_md="${dp_dir}/tasks/T1.md"
  write_task "$task_md" T1 "$branch" ""
  wt="$(add_task_branch_and_worktree "$repo" "$branch" "t1")"
  task_head="$(git -C "$wt" rev-parse HEAD)"
  merge_task_branch "$repo" "$branch"
  workspace_commit="$(git -C "$repo" rev-parse HEAD)"
  template_commit="$(git -C "$template" rev-parse HEAD)"
  evidence="${tmp}/verify-stale.json"
  write_verify_evidence "$evidence" DP-999-T1 "$(git -C "$repo" rev-parse HEAD~1)"

  rc=0
  bash "$CLOSEOUT" \
    --repo "$repo" \
    --template-repo "$template" \
    --task-md "$task_md" \
    --verify-evidence "$evidence" \
    --workspace-commit "$workspace_commit" \
    --template-commit "$template_commit" \
    --version-tag v0.0.1 \
    --release-url https://github.com/example/polaris/releases/tag/v0.0.1 >/dev/null 2>&1 || rc=$?

  [[ "$rc" -ne 0 ]] || { echo "[selftest] stale evidence unexpectedly passed" >&2; return 1; }
  [[ -f "$task_md" ]] || { echo "[selftest] stale evidence moved task unexpectedly" >&2; return 1; }
  [[ -d "$wt" ]] || { echo "[selftest] stale evidence removed worktree unexpectedly" >&2; return 1; }
  grep -q 'extension_deliverable:' "$task_md" || { echo "[selftest] stale case should still leave diagnostic metadata" >&2; return 1; }
  [[ -n "$task_head" ]]
}

run_dirty_worktree_case() {
  local tmp repos repo template dp_dir branch task_md wt task_head workspace_commit template_commit evidence rc
  tmp="$(mktemp -d -t framework-closeout-dirty.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repos="$(make_repos "$tmp")"
  repo="$(printf '%s\n' "$repos" | sed -n '1p')"
  template="$(printf '%s\n' "$repos" | sed -n '2p')"

  dp_dir="${repo}/docs-manager/src/content/docs/specs/design-plans/DP-999-release-closeout"
  mkdir -p "${dp_dir}/tasks"
  write_plan "$dp_dir"
  branch="task/DP-999-T1-closeout"
  task_md="${dp_dir}/tasks/T1.md"
  write_task "$task_md" T1 "$branch" ""
  wt="$(add_task_branch_and_worktree "$repo" "$branch" "t1")"
  task_head="$(git -C "$wt" rev-parse HEAD)"
  echo dirty >>"${wt}/selftest-t1.txt"
  merge_task_branch "$repo" "$branch"
  workspace_commit="$(git -C "$repo" rev-parse HEAD)"
  template_commit="$(git -C "$template" rev-parse HEAD)"
  evidence="${tmp}/verify-t1.json"
  write_verify_evidence "$evidence" DP-999-T1 "$task_head"

  rc=0
  bash "$CLOSEOUT" \
    --repo "$repo" \
    --template-repo "$template" \
    --task-md "$task_md" \
    --verify-evidence "$evidence" \
    --workspace-commit "$workspace_commit" \
    --template-commit "$template_commit" \
    --version-tag v0.0.1 \
    --release-url https://github.com/example/polaris/releases/tag/v0.0.1 >/dev/null 2>&1 || rc=$?

  [[ "$rc" -ne 0 ]] || { echo "[selftest] dirty worktree unexpectedly passed" >&2; return 1; }
  [[ -f "$task_md" ]] || { echo "[selftest] dirty worktree moved task unexpectedly" >&2; return 1; }
  [[ -d "$wt" ]] || { echo "[selftest] dirty worktree removed unexpectedly" >&2; return 1; }
  ! grep -q 'extension_deliverable:' "$task_md" || { echo "[selftest] dirty preflight wrote metadata unexpectedly" >&2; return 1; }
}

run_single_task_case
run_stacked_task_case
run_archived_pr_release_case
run_stale_evidence_case
run_dirty_worktree_case

echo "[framework-release-closeout-selftest] PASS"
