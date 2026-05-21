#!/usr/bin/env bash
# run-verify-command-worktree-selftest.sh — DP-219 worktree-blind fix.
#
# Verifies scripts/run-verify-command.sh correctly resolves REPO_PATH for
# worktrees, --repo / --worktree overrides, and legacy ancestor walk:
#
#   case 1 (AC1)     : PWD inside a worktree → head_sha = worktree HEAD
#   case 2 (AC2)     : PWD inside main checkout (no worktree) → head_sha = main HEAD
#   case 3 (AC3)     : --repo override outranks PWD-based detection
#   case 4 (AC4)     : --worktree override binds to specified worktree
#   case 5 (AC-NF1)  : full selftest wall-clock < 5s
#   case 6 (AC-NF2)  : non-git fixture → exit 1 with clear error
#   case 7 (AC-NEG1) : PWD not in any git repo → fall back to ancestor walk
#   case 8 (AC-NEG2) : --worktree pointing to non-git path → exit 1, no silent pass
#   case 9 (AC-NEG3) : evidence file naming format unchanged (polaris-verified-{TICKET}-{HEAD_SHA}.json)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/run-verify-command.sh"
WORKDIR="$(mktemp -d -t dp219-worktree-blind.XXXXXX)"
# macOS /tmp is a symlink to /private/tmp; realpath so paths compare cleanly.
WORKDIR="$(cd "$WORKDIR" && pwd -P)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: run-verify-command.sh not executable: $SCRIPT" >&2
  exit 1
fi

setup_main_repo() {
  local main_dir="$1"
  rm -rf "$main_dir"
  mkdir -p "$main_dir"
  git -C "$main_dir" init -q
  git -C "$main_dir" config user.email selftest@example.com
  git -C "$main_dir" config user.name "DP-219 selftest"
  echo "init" >"$main_dir/README.md"
  git -C "$main_dir" add -A
  git -C "$main_dir" -c commit.gpgsign=false commit -q -m "init"
}

# Minimal task.md that parse-task-md.sh can read.
write_task_md() {
  local task_path="$1"
  local repo_name="$2"
  local task_id="$3"
  mkdir -p "$(dirname "$task_path")"
  cat >"$task_path" <<MD
---
title: "$task_id"
description: "selftest fixture"
status: PLANNED
verification:
  behavior_contract:
    applies: false
    reason: "selftest"
depends_on: []
---

# $task_id

> Source: DP-219 | Task: $task_id | JIRA: N/A | Repo: $repo_name

## 改動範圍

selftest fixture.

## Allowed Files

- README.md

## Test Command

\`\`\`bash
true
\`\`\`

## Test Environment

- **Level**: static

## Verify Command

\`\`\`bash
echo "PASS: selftest fixture"
\`\`\`
MD
}

t_start_ns=$(python3 -c "import time; print(int(time.monotonic_ns()))")

# ---- Case 1 (AC1): worktree → head_sha = worktree HEAD --------------------
fix1_main="$WORKDIR/case1-main"
setup_main_repo "$fix1_main"
fix1_wt="$WORKDIR/case1-worktree"
git -C "$fix1_main" worktree add -q -b case1-branch "$fix1_wt"
echo "wt change" >>"$fix1_wt/README.md"
git -C "$fix1_wt" add -A
git -C "$fix1_wt" -c commit.gpgsign=false commit -q -m "case1 wt commit"
fix1_main_basename="$(basename "$fix1_main")"
fix1_task="$WORKDIR/case1-task.md"
write_task_md "$fix1_task" "$fix1_main_basename" "DP-219-T1-case1"
fix1_wt_head="$(git -C "$fix1_wt" rev-parse HEAD)"
(
  cd "$fix1_wt"
  "$SCRIPT" --task-md "$fix1_task" --ticket DP-219-T1-case1 >"$WORKDIR/case1.out" 2>&1
)
fix1_evidence="/tmp/polaris-verified-DP-219-T1-case1-${fix1_wt_head}.json"
if [[ ! -f "$fix1_evidence" ]]; then
  echo "FAIL (case1): expected evidence at $fix1_evidence (worktree HEAD)" >&2
  cat "$WORKDIR/case1.out" >&2
  ls /tmp/polaris-verified-DP-219-T1-case1-*.json >&2 2>/dev/null || true
  exit 1
fi
rm -f /tmp/polaris-verified-DP-219-T1-case1-*.json

# ---- Case 2 (AC2): main-only → head_sha = main HEAD -----------------------
fix2_main="$WORKDIR/case2-main"
setup_main_repo "$fix2_main"
fix2_main_basename="$(basename "$fix2_main")"
fix2_task="$WORKDIR/case2-task.md"
write_task_md "$fix2_task" "$fix2_main_basename" "DP-219-T1-case2"
fix2_main_head="$(git -C "$fix2_main" rev-parse HEAD)"
(
  cd "$fix2_main"
  "$SCRIPT" --task-md "$fix2_task" --ticket DP-219-T1-case2 >"$WORKDIR/case2.out" 2>&1
)
fix2_evidence="/tmp/polaris-verified-DP-219-T1-case2-${fix2_main_head}.json"
if [[ ! -f "$fix2_evidence" ]]; then
  echo "FAIL (case2): expected evidence at $fix2_evidence (main HEAD)" >&2
  cat "$WORKDIR/case2.out" >&2
  exit 1
fi
rm -f /tmp/polaris-verified-DP-219-T1-case2-*.json

# ---- Case 3 (AC3): --repo override outranks PWD-based detection -----------
# Stand inside fix1_wt but pass --repo fix1_main → evidence should bind to main HEAD.
fix3_main_head="$(git -C "$fix1_main" rev-parse HEAD)"
fix3_task="$WORKDIR/case3-task.md"
write_task_md "$fix3_task" "$fix1_main_basename" "DP-219-T1-case3"
(
  cd "$fix1_wt"
  "$SCRIPT" --task-md "$fix3_task" --ticket DP-219-T1-case3 --repo "$fix1_main" >"$WORKDIR/case3.out" 2>&1
)
fix3_evidence="/tmp/polaris-verified-DP-219-T1-case3-${fix3_main_head}.json"
if [[ ! -f "$fix3_evidence" ]]; then
  echo "FAIL (case3): expected evidence at $fix3_evidence (--repo override)" >&2
  cat "$WORKDIR/case3.out" >&2
  exit 1
fi
rm -f /tmp/polaris-verified-DP-219-T1-case3-*.json

# ---- Case 4 (AC4): --worktree override binds to specified worktree --------
fix4_task="$WORKDIR/case4-task.md"
write_task_md "$fix4_task" "$fix1_main_basename" "DP-219-T1-case4"
fix4_wt_head="$(git -C "$fix1_wt" rev-parse HEAD)"
(
  # Run from /tmp (not in any relevant git repo)
  cd /tmp
  "$SCRIPT" --task-md "$fix4_task" --ticket DP-219-T1-case4 --worktree "$fix1_wt" >"$WORKDIR/case4.out" 2>&1
)
fix4_evidence="/tmp/polaris-verified-DP-219-T1-case4-${fix4_wt_head}.json"
if [[ ! -f "$fix4_evidence" ]]; then
  echo "FAIL (case4): expected evidence at $fix4_evidence (--worktree override)" >&2
  cat "$WORKDIR/case4.out" >&2
  exit 1
fi
rm -f /tmp/polaris-verified-DP-219-T1-case4-*.json

# ---- Case 6 (AC-NF2): non-git fixture → exit 1 with clear error -----------
# (Case 5 is wall-clock checked at the end.)
fix6_task="$WORKDIR/case6-task.md"
write_task_md "$fix6_task" "nonexistent-repo-name" "DP-219-T1-case6"
set +e
(
  cd "$WORKDIR"
  "$SCRIPT" --task-md "$fix6_task" --ticket DP-219-T1-case6 >"$WORKDIR/case6.out" 2>&1
)
rc6=$?
set -e
if [[ "$rc6" -eq 0 ]]; then
  echo "FAIL (case6): expected non-zero exit for non-git fixture" >&2
  cat "$WORKDIR/case6.out" >&2
  exit 1
fi
if ! grep -q "could not locate repo" "$WORKDIR/case6.out"; then
  echo "FAIL (case6): expected 'could not locate repo' error message" >&2
  cat "$WORKDIR/case6.out" >&2
  exit 1
fi

# ---- Case 7 (AC-NEG1): PWD not in any git repo → fall back to ancestor walk
# task.md lives at $WORKDIR/case7-task.md (sibling to repo so the repo working
# tree stays clean; ancestor walk still finds $WORKDIR/case2-main = fix2_main).
fix7_task="$WORKDIR/case7-task.md"
write_task_md "$fix7_task" "$fix2_main_basename" "DP-219-T1-case7"
fix7_main_head="$(git -C "$fix2_main" rev-parse HEAD)"
(
  cd "$WORKDIR"  # not inside any matching repo
  "$SCRIPT" --task-md "$fix7_task" --ticket DP-219-T1-case7 >"$WORKDIR/case7.out" 2>&1
)
fix7_evidence="/tmp/polaris-verified-DP-219-T1-case7-${fix7_main_head}.json"
if [[ ! -f "$fix7_evidence" ]]; then
  echo "FAIL (case7): expected ancestor-walk fallback evidence at $fix7_evidence" >&2
  cat "$WORKDIR/case7.out" >&2
  exit 1
fi
rm -f /tmp/polaris-verified-DP-219-T1-case7-*.json

# ---- Case 8 (AC-NEG2): --worktree pointing to non-git path → exit 1 -------
fix8_task="$WORKDIR/case8-task.md"
write_task_md "$fix8_task" "$fix1_main_basename" "DP-219-T1-case8"
nongit_dir="$WORKDIR/case8-nongit"
mkdir -p "$nongit_dir"
set +e
"$SCRIPT" --task-md "$fix8_task" --ticket DP-219-T1-case8 --worktree "$nongit_dir" >"$WORKDIR/case8.out" 2>&1
rc8=$?
set -e
if [[ "$rc8" -eq 0 ]]; then
  echo "FAIL (case8): expected exit 1 for --worktree non-git path" >&2
  cat "$WORKDIR/case8.out" >&2
  exit 1
fi
if ! grep -q "not a git working tree" "$WORKDIR/case8.out"; then
  echo "FAIL (case8): expected 'not a git working tree' error" >&2
  cat "$WORKDIR/case8.out" >&2
  exit 1
fi

# ---- Case 9 (AC-NEG3): evidence file naming format unchanged --------------
# We already rely on /tmp/polaris-verified-{TICKET}-{HEAD_SHA}.json above; assert
# the script's success message also matches that pattern.
fix9_task="$WORKDIR/case9-task.md"
write_task_md "$fix9_task" "$fix2_main_basename" "DP-219-T1-case9"
(
  cd "$fix2_main"
  "$SCRIPT" --task-md "$fix9_task" --ticket DP-219-T1-case9 >"$WORKDIR/case9.out" 2>&1
)
if ! grep -Eq "polaris-verified-DP-219-T1-case9-[0-9a-f]{40}\.json" "$WORKDIR/case9.out"; then
  echo "FAIL (case9): evidence file naming pattern changed" >&2
  cat "$WORKDIR/case9.out" >&2
  exit 1
fi
rm -f /tmp/polaris-verified-DP-219-T1-case9-*.json

# ---- Case 5 (AC-NF1): wall-clock < 5s -------------------------------------
t_end_ns=$(python3 -c "import time; print(int(time.monotonic_ns()))")
elapsed_ms=$(( (t_end_ns - t_start_ns) / 1000000 ))
if [[ "$elapsed_ms" -gt 5000 ]]; then
  echo "FAIL (case5): selftest wall-clock ${elapsed_ms}ms > 5000ms budget" >&2
  exit 1
fi

echo "PASS: run-verify-command-worktree-selftest (9/9 cases, timing=${elapsed_ms}ms)"
