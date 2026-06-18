#!/usr/bin/env bash
# Purpose: DP-334 T2 / AC2 / AC-NEG1 — selftest for gate-base-check.sh feat/DP-NNN
#          lifecycle. Framework DP delivery routes through a per-DP feat/DP-NNN
#          aggregation branch: a DP task PR MUST target feat/DP-NNN and a DP task
#          PR that directly targets main fails closed (the v3.76.18 raw-commit
#          escape this DP closes). Asserts positive (target feat -> PASS) and
#          negative (target main -> fail-closed exit 2) fixtures, including that
#          the legacy --aggregate-release escape cannot launder a feat-lifecycle
#          DP task into a main-targeting PR.
# Inputs:  none (builds a throwaway git repo + task.md fixture in mktemp).
# Outputs: stdout PASS line; exit 0 = all assertions pass, 1 = a case failed.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-base-check.sh"
WORKDIR="$(mktemp -d -t dp334-base-check.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$GATE" ]]; then
  echo "FAIL: gate is not executable: $GATE" >&2
  exit 1
fi

FEAT_BRANCH="feat/DP-999"
TASK_BRANCH="task/DP-999-T1-fixture"

# write_task_md <task_md_path> <base_branch>
# Produces a minimal task.md whose Operational Context binds Task branch to
# TASK_BRANCH and Base branch to <base_branch>. resolve-task-base.sh returns a
# feat/* base verbatim, so Base branch=feat/DP-999 makes the gate expect
# feat/DP-999.
write_task_md() {
  local task_md="$1"
  local base_branch="$2"
  mkdir -p "$(dirname "$task_md")"
  cat >"$task_md" <<MD
---
status: IN_PROGRESS
---

# T1: gate-base-check feat lifecycle fixture (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Base branch | ${base_branch} |
| Branch chain | ${base_branch} -> ${TASK_BRANCH} |
| Task branch | ${TASK_BRANCH} |
| Depends on | N/A |

## Allowed Files

- \`scripts/gates/gate-base-check.sh\`
MD
}

# Build a hermetic Polaris-governed git repo, checked out on the DP task branch.
# gate-base-check.sh resolves task.md via `resolve-task-md-by-branch.sh --current`
# from cwd, so the repo must carry workspace-config.yaml + a scannable task.md.
make_repo() {
  local repo="$WORKDIR/repo"
  rm -rf "$repo"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "DP-334 selftest"
  cat >"$repo/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
  # Task.md under the standard DP specs path so the by-branch resolver finds it.
  write_task_md \
    "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks/T1/index.md" \
    "$FEAT_BRANCH"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "seed"
  git -C "$repo" branch "$FEAT_BRANCH"
  git -C "$repo" checkout -q -b "$TASK_BRANCH"
  printf '%s\n' "$repo"
}

REPO="$(make_repo)"

# --- Case 1 (AC2 positive): DP task PR targets feat/DP-999 -> PASS (exit 0). ---
set +e
out1="$(cd "$REPO" && bash "$GATE" --repo "$REPO" --base "$FEAT_BRANCH" 2>&1)"
rc1=$?
set -e
if [[ "$rc1" -ne 0 ]]; then
  echo "FAIL (case1: target feat): expected exit 0, got $rc1" >&2
  echo "$out1" >&2
  exit 1
fi
grep -q 'PR base matches task.md' <<<"$out1" || {
  echo "FAIL (case1: target feat): expected base-match PASS message" >&2
  echo "$out1" >&2
  exit 1
}

# --- Case 2 (AC2 / AC-NEG1 negative): DP task PR targets main -> fail-closed
#     (exit 2). ---
set +e
out2="$(cd "$REPO" && bash "$GATE" --repo "$REPO" --base "main" 2>&1)"
rc2=$?
set -e
if [[ "$rc2" -ne 2 ]]; then
  echo "FAIL (case2: target main): expected exit 2, got $rc2" >&2
  echo "$out2" >&2
  exit 1
fi
grep -q 'must target its feat/DP-NNN aggregation branch, not main' <<<"$out2" || {
  echo "FAIL (case2: target main): expected feat-lifecycle block message" >&2
  echo "$out2" >&2
  exit 1
}

# --- Case 3 (AC-NEG1 adversarial): --aggregate-release must NOT launder a
#     feat-lifecycle DP task into a main-targeting PR. Still exit 2. ---
set +e
out3="$(cd "$REPO" && bash "$GATE" --repo "$REPO" --base "main" --aggregate-release 2>&1)"
rc3=$?
set -e
if [[ "$rc3" -ne 2 ]]; then
  echo "FAIL (case3: aggregate-release escape): expected exit 2, got $rc3" >&2
  echo "$out3" >&2
  exit 1
fi
grep -q 'must target its feat/DP-NNN aggregation branch, not main' <<<"$out3" || {
  echo "FAIL (case3: aggregate-release escape): feat-lifecycle guard must fire before bundle escape" >&2
  echo "$out3" >&2
  exit 1
}

# --- Case 4 (regression): bypass env still works (exit 0) so the gate stays a
#     gate, not an unconditional blocker. ---
set +e
out4="$(cd "$REPO" && POLARIS_SKIP_PR_BASE_GATE=1 bash "$GATE" --repo "$REPO" --base "main" 2>&1)"
rc4=$?
set -e
if [[ "$rc4" -ne 0 ]]; then
  echo "FAIL (case4: bypass env): expected exit 0, got $rc4" >&2
  echo "$out4" >&2
  exit 1
fi

echo "PASS: gate-base-check feat-lifecycle selftest"
