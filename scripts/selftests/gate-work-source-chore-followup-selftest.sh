#!/usr/bin/env bash
# gate-work-source-chore-followup-selftest.sh — DP-217 chore-followup lane +
# DP-334 feat/DP-NNN lifecycle work source + feat/DP-NNN -> main release PR lane.
#
# DP-217 carves out a narrow chore-followup lane in gate-work-source.sh so
# release-tail manifest / housekeeping fixes don't need a fresh task.md.
# DP-334 adds the feature-branch aggregation release model: per-task branches
# merge into feat/DP-NNN (T2 lifecycle work source), then a single feat/DP-NNN
# -> main release PR is opened from the feat/DP-NNN branch itself (T4 / AC5).
# This selftest verifies:
#
#   1. PASS: chore/DP-NNN-<slug> branch + DP container has IMPLEMENTED
#      tasks/pr-release/T*.md → exit 0.
#   2. PASS via archived container: DP container only exists under archive/
#      → exit 0.
#   3. BLOCKED: chore/DP-NNN-<slug> branch + DP container exists but no
#      tasks/pr-release/T*.md is status: IMPLEMENTED → exit 2.
#   4. BLOCKED: chore/DP-NNN-<slug> branch + no DP container at all →
#      exit 2.
#   5. BLOCKED: chore/<other>-<slug> branch (doesn't match DP regex) → falls
#      through to normal task.md resolver, which finds nothing → exit 2.
#   6. PASS: task/DP-NNN-T1-feat branch (base feat/DP-NNN) → feat-lifecycle work
#      source accepted via table-form Task branch (DP-334 T2).
#   7. BLOCKED: main branch → protected/default branch is never a work source.
#   8. PASS: feat/DP-NNN branch + DP container has IMPLEMENTED tasks/pr-release/
#      T*.md → exit 0 (DP-334 T4 / AC5 feat-release lane, release PR source).
#   9. BLOCKED: feat/DP-NNN branch but feat name has no legal DP container →
#      fail-closed exit 2 (DP-334 AC-NEG1).
#  10. BLOCKED: feat/DP-NNN branch + DP container exists but no IMPLEMENTED
#      pr-release task → fail-closed exit 2 (DP-334 AC-NEG1).
#  11. BLOCKED: feat/DP-NNN-<slug> branch (trailing slug, not exactly
#      feat/DP-NNN) does NOT enter feat-release lane; the anchored ^feat/DP-NNN$
#      regex makes it fall through to the normal task.md resolver → exit 2.
#
# Cases 3-5 cover AC-NEG3 ("chore lane must not become a generic escape").
# Cases 9-11 cover DP-334 AC-NEG1 ("feat-release lane must fail closed and must
# not become a generic escape").

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-work-source.sh"
WORKDIR="$(mktemp -d -t dp217-chore-followup.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$GATE" ]]; then
  echo "FAIL: gate is not executable: $GATE" >&2
  exit 1
fi

setup_repo() {
  local repo="$1"
  local branch="$2"
  rm -rf "$repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "DP-217 selftest"
  # Mark as a Polaris-governed repo via workspace-config.yaml presence.
  cat >"$repo/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
  mkdir -p "$repo/scripts"
  touch "$repo/AGENTS.md"
  # Provide an executable polaris-pr-create stub so is_polaris_governed_repo
  # treats the workspace-config.yaml signal as sufficient.
  echo "#!/usr/bin/env bash" >"$repo/scripts/polaris-pr-create.sh"
  chmod +x "$repo/scripts/polaris-pr-create.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "init"
  git -C "$repo" checkout -q -b "$branch"
}

write_dp_container() {
  local repo="$1"
  local dp="$2"   # e.g. DP-217
  local archived="$3"  # 1 = under archive/, 0 = active
  local implemented="$4"  # 1 = at least one task.md status IMPLEMENTED
  local base="$repo/docs-manager/src/content/docs/specs/design-plans"
  local container
  if [[ "$archived" == "1" ]]; then
    container="$base/archive/${dp}-archived-fixture"
  else
    container="$base/${dp}-active-fixture"
  fi
  mkdir -p "$container/tasks/pr-release/T1"
  cat >"$container/index.md" <<MD
---
title: "$dp fixture"
status: IMPLEMENTED
---

# $dp
MD
  local status
  if [[ "$implemented" == "1" ]]; then
    status="IMPLEMENTED"
  else
    status="PLANNED"
  fi
  cat >"$container/tasks/pr-release/T1/index.md" <<MD
---
title: "$dp T1"
status: $status
---

# $dp T1
MD
  git -C "$repo" add -A >/dev/null
  git -C "$repo" -c commit.gpgsign=false commit -q -m "$dp fixture (archived=$archived implemented=$implemented)"
}

# Case 1: PASS active container with IMPLEMENTED pr-release task.
repo1="$WORKDIR/repo1"
setup_repo "$repo1" "chore/DP-217-followup"
write_dp_container "$repo1" "DP-217" 0 1
set +e
(cd "$repo1" && "$GATE" --repo "$repo1") >"$WORKDIR/case1.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case1: active+IMPLEMENTED): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case1.out" >&2
  exit 1
fi
grep -q 'chore-followup lane' "$WORKDIR/case1.out"

# Case 2: PASS via archived container.
repo2="$WORKDIR/repo2"
setup_repo "$repo2" "chore/DP-555-archived-followup"
write_dp_container "$repo2" "DP-555" 1 1
set +e
(cd "$repo2" && "$GATE" --repo "$repo2") >"$WORKDIR/case2.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case2: archived+IMPLEMENTED): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case2.out" >&2
  exit 1
fi
grep -q 'chore-followup lane' "$WORKDIR/case2.out"

# Case 3: BLOCKED active container with no IMPLEMENTED pr-release task.
repo3="$WORKDIR/repo3"
setup_repo "$repo3" "chore/DP-999-no-impl"
write_dp_container "$repo3" "DP-999" 0 0
set +e
(cd "$repo3" && "$GATE" --repo "$repo3") >"$WORKDIR/case3.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case3: no IMPLEMENTED task): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case3.out" >&2
  exit 1
fi
grep -q 'requires parent DP DP-999 to have an IMPLEMENTED pr-release task' "$WORKDIR/case3.out"

# Case 4: BLOCKED chore branch references DP with NO container at all.
repo4="$WORKDIR/repo4"
setup_repo "$repo4" "chore/DP-777-missing-container"
# Make a non-related commit so git is happy.
echo "x" >"$repo4/scratch.txt"
git -C "$repo4" add -A >/dev/null
git -C "$repo4" -c commit.gpgsign=false commit -q -m "noop"
set +e
(cd "$repo4" && "$GATE" --repo "$repo4") >"$WORKDIR/case4.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case4: no container): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case4.out" >&2
  exit 1
fi
grep -q 'could not resolve DP container for DP-777' "$WORKDIR/case4.out"

# Case 5: BLOCKED non-DP chore/* branch (e.g. chore/cleanup-foo) falls through
# to normal task resolution and fails (no task.md to resolve).
repo5="$WORKDIR/repo5"
setup_repo "$repo5" "chore/cleanup-misc"
echo "x" >"$repo5/scratch.txt"
git -C "$repo5" add -A >/dev/null
git -C "$repo5" -c commit.gpgsign=false commit -q -m "noop"
set +e
(cd "$repo5" && "$GATE" --repo "$repo5") >"$WORKDIR/case5.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case5: non-DP chore): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case5.out" >&2
  exit 1
fi
if grep -q 'chore-followup lane' "$WORKDIR/case5.out"; then
  echo "FAIL (case5: non-DP chore): gate should not enter chore-followup lane" >&2
  cat "$WORKDIR/case5.out" >&2
  exit 1
fi

# ── DP-334 T2 / AC2 / AC5 / AC-NEG1: feat/DP-NNN lifecycle work source ─────────
# Framework DP delivery keys off feat/DP-NNN aggregation. gate-work-source must
# accept a DP task whose Task branch (base = feat/DP-NNN) matches the current
# branch (POSITIVE / "target feat" lifecycle), and reject PR creation from the
# protected `main` branch (NEGATIVE / "target main"). The work-source binding is
# the table-form `Task branch` check — no bundle_branch_alias is needed for the
# feat-lifecycle source. A real schema-valid DP task.md is reused so the gate's
# final validate-task-md.sh step is exercised, not stubbed.

# write_feat_task_md <task_md_path>: emit a minimal schema-valid DP task.md bound
# to task/DP-999-T1-feat with Base branch feat/DP-999.
write_feat_task_md() {
  local task_md="$1"
  mkdir -p "$(dirname "$task_md")"
  cat >"$task_md" <<'MD'
---
status: IN_PROGRESS
task_kind: T
task_shape: implementation
depends_on: []
---

# T1: feat 生命週期 work source 固定樣本 (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | feat/DP-999 |
| Branch chain | feat/DP-999 -> task/DP-999-T1-feat |
| Task branch | task/DP-999-T1-feat |
| Depends on | N/A |
| References to load | - none |

## 改動範圍

| 檔案 | 動作 | 變更摘要 |
|------|------|----------|
| `scripts/x.sh` | modify | fixture change |

## Allowed Files

- `scripts/x.sh`

## 估點理由

1 pt — fixture work order.

## Test Command

```bash
true
```

## Test Environment

- **Level**: build
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
true
```
MD
}

# setup_feat_repo <repo> <branch>: Polaris-governed repo on <branch> with a
# feat-lifecycle DP task.md under the standard specs path.
setup_feat_repo() {
  local repo="$1"
  local branch="$2"
  rm -rf "$repo"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "DP-334 selftest"
  printf 'language: zh-TW\n' >"$repo/workspace-config.yaml"
  touch "$repo/AGENTS.md"
  printf '#!/usr/bin/env bash\n' >"$repo/scripts/polaris-pr-create.sh"
  chmod +x "$repo/scripts/polaris-pr-create.sh"
  write_feat_task_md \
    "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-feat-fixture/tasks/T1/index.md"
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q -m "init"
  git -C "$repo" branch feat/DP-999
  git -C "$repo" checkout -q -b "$branch"
}

# Case 6 (POSITIVE / target feat): on the DP task branch whose base is feat/DP-999
# -> gate accepts the feat-lifecycle work source (exit 0).
repo6="$WORKDIR/repo6"
setup_feat_repo "$repo6" "task/DP-999-T1-feat"
set +e
(cd "$repo6" && "$GATE" --repo "$repo6") >"$WORKDIR/case6.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case6: feat-lifecycle task source): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case6.out" >&2
  exit 1
fi
grep -q 'source valid' "$WORKDIR/case6.out" || {
  echo "FAIL (case6: feat-lifecycle task source): expected 'source valid' PASS message" >&2
  cat "$WORKDIR/case6.out" >&2
  exit 1
}

# Case 7 (NEGATIVE / target main): the same repo checked out on main -> PR
# creation from the protected/default branch is fail-closed (exit 2). This is the
# work-source half of AC-NEG1: main is never a legal DP task work source.
repo7="$WORKDIR/repo7"
setup_feat_repo "$repo7" "task/DP-999-T1-feat"
git -C "$repo7" checkout -q main
set +e
(cd "$repo7" && "$GATE" --repo "$repo7") >"$WORKDIR/case7.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case7: main is not a legal work source): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case7.out" >&2
  exit 1
fi
grep -q 'protected/default branch' "$WORKDIR/case7.out" || {
  echo "FAIL (case7: main is not a legal work source): expected protected-branch block message" >&2
  cat "$WORKDIR/case7.out" >&2
  exit 1
}

# ── DP-334 T4 / AC5 / AC-NEG1: feat/DP-NNN -> main release PR lane ─────────────
# The feat/DP-NNN -> main release PR is opened from the feat/DP-NNN branch
# itself, which has no table-form Task branch binding. The feat-release lane
# accepts it as a legal release work source when the DP container has at least
# one IMPLEMENTED tasks/pr-release task, and fails closed otherwise. The
# write_dp_container / setup_repo helpers (case 1-5) are reused here.

# Case 8 (POSITIVE / AC5): feat/DP-660 + DP container with IMPLEMENTED
# pr-release task -> feat-release lane accepts (exit 0).
repo8="$WORKDIR/repo8"
setup_repo "$repo8" "feat/DP-660"
write_dp_container "$repo8" "DP-660" 0 1
set +e
(cd "$repo8" && "$GATE" --repo "$repo8") >"$WORKDIR/case8.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case8: feat-release lane IMPLEMENTED): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case8.out" >&2
  exit 1
fi
grep -q 'feat-release lane' "$WORKDIR/case8.out" || {
  echo "FAIL (case8: feat-release lane IMPLEMENTED): expected feat-release lane PASS message" >&2
  cat "$WORKDIR/case8.out" >&2
  exit 1
}

# Case 9 (NEGATIVE / AC-NEG1): feat/DP-770 with NO DP container at all ->
# fail-closed exit 2 (cannot resolve container).
repo9="$WORKDIR/repo9"
setup_repo "$repo9" "feat/DP-770"
echo "x" >"$repo9/scratch.txt"
git -C "$repo9" add -A >/dev/null
git -C "$repo9" -c commit.gpgsign=false commit -q -m "noop"
set +e
(cd "$repo9" && "$GATE" --repo "$repo9") >"$WORKDIR/case9.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case9: feat-release no container): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case9.out" >&2
  exit 1
fi
grep -q 'feat-release lane could not resolve DP container for DP-770' "$WORKDIR/case9.out" || {
  echo "FAIL (case9: feat-release no container): expected container-resolve block message" >&2
  cat "$WORKDIR/case9.out" >&2
  exit 1
}

# Case 10 (NEGATIVE / AC-NEG1): feat/DP-880 + DP container exists but no
# IMPLEMENTED pr-release task -> fail-closed exit 2.
repo10="$WORKDIR/repo10"
setup_repo "$repo10" "feat/DP-880"
write_dp_container "$repo10" "DP-880" 0 0
set +e
(cd "$repo10" && "$GATE" --repo "$repo10") >"$WORKDIR/case10.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case10: feat-release no IMPLEMENTED task): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case10.out" >&2
  exit 1
fi
grep -q 'feat-release lane requires DP DP-880 to have an IMPLEMENTED pr-release task' "$WORKDIR/case10.out" || {
  echo "FAIL (case10: feat-release no IMPLEMENTED task): expected no-IMPLEMENTED block message" >&2
  cat "$WORKDIR/case10.out" >&2
  exit 1
}

# Case 11 (NEGATIVE / anchored-regex guard): feat/DP-990-some-slug (trailing
# slug) must NOT enter the feat-release lane — the ^feat/DP-NNN$ anchor only
# matches the bare feat/DP-NNN release branch. It falls through to the normal
# task.md resolver, which finds nothing -> exit 2.
repo11="$WORKDIR/repo11"
setup_repo "$repo11" "feat/DP-990-some-slug"
write_dp_container "$repo11" "DP-990" 0 1
set +e
(cd "$repo11" && "$GATE" --repo "$repo11") >"$WORKDIR/case11.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case11: feat/DP-NNN-slug must not enter lane): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case11.out" >&2
  exit 1
fi
if grep -q 'feat-release lane' "$WORKDIR/case11.out"; then
  echo "FAIL (case11: feat/DP-NNN-slug must not enter lane): gate entered feat-release lane" >&2
  cat "$WORKDIR/case11.out" >&2
  exit 1
fi

echo "PASS: gate-work-source chore-followup selftest"
