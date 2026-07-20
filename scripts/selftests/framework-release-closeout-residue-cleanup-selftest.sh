#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-393 T2 — framework-release closeout mandatory
#          release-residue branch/worktree cleanup + fail-loud FINAL verification.
#          Asserts that closeout, with NO --delete-branches flag, deletes each
#          released DP's feat/DP-NNN, task/DP-NNN-* and chore/DP-NNN-* branches
#          (local AND remote) and removes their clean implementation worktrees;
#          that cleanup is idempotent (already-gone residue is a no-op, not an
#          error, EC4); that the FINAL verification fails loud with
#          POLARIS_FRAMEWORK_RELEASE_RESIDUE (exit 2) when residue survives; and
#          that the legacy --delete-branches flag is accepted as a deprecated
#          no-op while cleanup still runs by default (AC-NEG4).
# Inputs:  none (CLI args ignored). Builds synthetic git repos + a bare origin +
#          specs containers + release commits + fixture worktrees in a private
#          tmpdir. NEVER touches the live workspace, feat/DP-393, or any sibling
#          task branch — every branch/worktree is a throwaway DP-95x fixture.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMPROOT="$(mktemp -d -t fr-closeout-residue-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
TOTAL=0

_assert_eq() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: expected=%q got=%q\n' "$TOTAL" "$3" "$2" "$1" >&2
  fi
}

_assert_contains() {
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$2" <<< "$1"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: substring not found: %q\n' "$TOTAL" "$3" "$2" >&2
    printf '       in: %s\n' "$1" >&2
  fi
}

_assert_not_contains() {
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$2" <<< "$1"; then
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: substring should NOT appear: %q\n' "$TOTAL" "$3" "$2" >&2
  else
    PASS=$((PASS + 1))
  fi
}

# local_branch_absent <repo> <short-branch> -> "absent" | "present"
local_branch_absent() {
  if git -C "$1" show-ref --verify --quiet "refs/heads/$2"; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}

# remote_branch_absent <repo> <short-branch> -> "absent" | "present" on origin.
remote_branch_absent() {
  if git -C "$1" ls-remote --exit-code --heads origin "$2" >/dev/null 2>&1; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}

# worktree_registered <repo> <path> -> "yes" | "no"
worktree_registered() {
  if git -C "$1" worktree list --porcelain | grep -qF "worktree $2"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# ---------------------------------------------------------------------------
# Stub scripts dir: real closeout + parser + lib, side-effecting downstream
# helpers stubbed. Mirrors the shape used by the sibling closeout selftests so
# the REAL cleanup + verification logic is exercised while staying hermetic.
# ---------------------------------------------------------------------------
build_stub_scripts_dir() {
  local dst="$1"
  mkdir -p "$dst/selftests"
  cp -R "$ROOT/scripts/lib" "$dst/lib"
  cp "$ROOT/scripts/framework-release-closeout.sh" "$dst/framework-release-closeout.sh"
  cp "$ROOT/scripts/parse-task-md.sh" "$dst/parse-task-md.sh"
  cp "$ROOT/scripts/resolve-task-base.sh" "$dst/resolve-task-base.sh"

  local helper
  for helper in check-release-eligible.sh check-release-completed.sh \
                check-main-chain-compliance.sh write-extension-deliverable.sh \
                check-local-extension-completion.sh engineering-clean-worktree.sh \
                close-parent-spec-if-complete.sh; do
    cat >"$dst/$helper" <<STUB
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$helper" "\$*" >>"\${POLARIS_STUB_LOG:?}"
exit 0
STUB
    chmod +x "$dst/$helper"
  done

  # mark-spec-implemented stub: flips frontmatter status IN PLACE so the parent
  # close + flip assertions have a real status to observe (matches the sibling
  # order-independent selftest stub).
  cat >"$dst/mark-spec-implemented.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
TASK_ID="$1"; shift
WORKSPACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'mark-spec-implemented.sh %s\n' "$TASK_ID" >>"${POLARIS_STUB_LOG:?}"
specs="$WORKSPACE/docs-manager/src/content/docs/specs"
suffix="${TASK_ID##*-}"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  python3 - "$f" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1]); t = p.read_text(encoding="utf-8"); lines = t.split("\n")
if lines and lines[0] == "---":
    end = lines.index("---", 1)
    fm = lines[1:end]
    done = False
    for i, l in enumerate(fm):
        if re.match(r"^status:\s*", l):
            fm[i] = "status: IMPLEMENTED"; done = True; break
    if not done: fm.append("status: IMPLEMENTED")
    p.write_text("---\n" + "\n".join(fm) + "\n---\n" + "\n".join(lines[end+1:]), encoding="utf-8")
PY
done < <(find "$specs" -path "*/tasks/$suffix/index.md" 2>/dev/null)
exit 0
STUB
  chmod +x "$dst/mark-spec-implemented.sh"
}

init_workspace_repo() {
  local repo="$1"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  git -C "$repo" checkout -q -b main
  mkdir -p "$repo/docs-manager/src/content/docs/specs/design-plans"
  echo init >"$repo/seed.txt"
  git -C "$repo" add seed.txt
  git -C "$repo" commit -qm init
}

# Write a branch-bearing DP task with a deliverable.head_sha delivery block.
#   $1 repo  $2 dp  $3 suffix  $4 task-branch  $5 allowed-file  $6 deliver-head
write_branch_task() {
  local repo="$1" dp="$2" suffix="$3" branch="$4" allowed="$5" deliver_head="$6"
  local dir="$repo/docs-manager/src/content/docs/specs/design-plans/${dp}-fixture"
  mkdir -p "$dir/tasks/$suffix"
  cat >"$dir/index.md" <<MD
---
title: "${dp} fixture parent"
status: LOCKED
---

# ${dp}
MD
  {
    printf -- '---\n'
    printf 'status: IN_PROGRESS\n'
    printf 'task_kind: T\n'
    printf 'task_shape: implementation\n'
    printf 'deliverable:\n'
    printf '  head_sha: %s\n' "$deliver_head"
    printf -- '---\n\n'
    printf '# %s: fixture task (1 pt)\n\n' "$suffix"
    printf '> Source: %s | Task: %s-%s | JIRA: N/A | Repo: polaris-framework\n\n' "$dp" "$dp" "$suffix"
    printf '## Operational Context\n\n'
    printf '| 欄位 | 值 |\n|------|-----|\n'
    printf '| Source type | dp |\n'
    printf '| Source ID | %s |\n' "$dp"
    printf '| Task ID | %s-%s |\n' "$dp" "$suffix"
    printf '| JIRA key | N/A |\n'
    printf '| Base branch | main |\n'
    printf '| Task branch | %s |\n' "$branch"
    printf '\n## Allowed Files\n\n'
    printf -- '- `%s`\n' "$allowed"
    printf '\n## Test Environment\n\n- **Level**: static\n'
  } >"$dir/tasks/$suffix/index.md"
}

# Write a no-branch (content-delivered) confirmation task.
#   $1 repo  $2 dp  $3 suffix  $4 allowed-file
write_no_branch_task() {
  local repo="$1" dp="$2" suffix="$3" allowed="$4"
  local dir="$repo/docs-manager/src/content/docs/specs/design-plans/${dp}-fixture"
  mkdir -p "$dir/tasks/$suffix"
  cat >"$dir/index.md" <<MD
---
title: "${dp} fixture parent"
status: LOCKED
---

# ${dp}
MD
  {
    printf -- '---\n'
    printf 'status: IN_PROGRESS\n'
    printf 'task_kind: T\n'
    printf 'task_shape: confirmation\n'
    printf -- '---\n\n'
    printf '# %s: fixture confirmation task (1 pt)\n\n' "$suffix"
    printf '> Source: %s | Task: %s-%s | JIRA: N/A | Repo: polaris-framework\n\n' "$dp" "$dp" "$suffix"
    printf '## Operational Context\n\n'
    printf '| 欄位 | 值 |\n|------|-----|\n'
    printf '| Source type | dp |\n'
    printf '| Source ID | %s |\n' "$dp"
    printf '| Task ID | %s-%s |\n' "$dp" "$suffix"
    printf '| JIRA key | N/A |\n'
    printf '| Base branch | main |\n'
    printf '\n## Allowed Files\n\n'
    printf -- '- `%s`\n' "$allowed"
    printf '\n## Test Environment\n\n- **Level**: static\n'
  } >"$dir/tasks/$suffix/index.md"
}

valid_verify_marker() {
  local path="$1" ticket="$2" head="$3"
  cat >"$path" <<JSON
{"ticket":"${ticket}","head_sha":"${head}","writer":"run-verify-command.sh","exit_code":0,"at":"2026-06-05T00:00:00Z","status":"PASS"}
JSON
}

run_closeout() {
  local scripts_dir="$1"; shift
  set +e
  CLOSEOUT_OUT="$(POLARIS_STUB_LOG="$STUB_LOG" \
    bash "$scripts_dir/framework-release-closeout.sh" "$@" 2>&1)"
  CLOSEOUT_RC=$?
  set -e
}

# ===========================================================================
# Case 1 (AC3): DEFAULT cleanup — feat/task/chore branches (local AND remote) +
# clean implementation worktree deleted WITHOUT any --delete-branches flag.
# ===========================================================================
{
  WS="$TMPROOT/c1-ws"
  ORIGIN="$TMPROOT/c1-origin.git"
  SCRIPTS="$TMPROOT/c1-scripts"
  STUB_LOG="$TMPROOT/c1-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"
  git init -q --bare "$ORIGIN"
  git -C "$WS" remote add origin "$ORIGIN"

  # A residue feat branch (points at pre-task main).
  git -C "$WS" branch feat/DP-950 main

  # The delivery head lives on the task branch; merge it into main so it is an
  # ancestor of the workspace release commit.
  git -C "$WS" checkout -q -b task/DP-950-T1-x
  mkdir -p "$WS/scripts"
  echo work >"$WS/scripts/feature-950.sh"
  git -C "$WS" add scripts/feature-950.sh
  git -C "$WS" commit -qm "delivery head"
  DELIVERY_HEAD="$(git -C "$WS" rev-parse HEAD)"
  git -C "$WS" checkout -q main
  git -C "$WS" merge -q --no-ff task/DP-950-T1-x -m "merge delivery"

  # A residue chore branch.
  git -C "$WS" branch chore/DP-950-followup main

  write_branch_task "$WS" DP-950 T1 task/DP-950-T1-x 'scripts/feature-950.sh' "$DELIVERY_HEAD"
  git -C "$WS" add docs-manager
  git -C "$WS" commit -qm "container"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Push main + all three residue branches to origin (local + remote residue).
  git -C "$WS" push -q -u origin main feat/DP-950 task/DP-950-T1-x chore/DP-950-followup

  # A clean engineering implementation worktree on the task branch.
  WT="$WS/.worktrees/polaris-framework-engineering-DP-950-T1"
  git -C "$WS" worktree add -q "$WT" task/DP-950-T1-x

  git -C "$WS" checkout -q main

  MARKER="$TMPROOT/c1-verify.json"
  valid_verify_marker "$MARKER" DP-950-T1 "$DELIVERY_HEAD"

  # NO --delete-branches flag: cleanup must happen by default.
  run_closeout "$SCRIPTS" \
    --task-md "$WS/docs-manager/src/content/docs/specs/design-plans/DP-950-fixture/tasks/T1/index.md" \
    --task-head-sha "DP-950-T1=${DELIVERY_HEAD}" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "C1 closeout exits 0"
  _assert_eq "$(local_branch_absent "$WS" feat/DP-950)" "absent" "C1 local feat/DP-950 deleted"
  _assert_eq "$(local_branch_absent "$WS" task/DP-950-T1-x)" "absent" "C1 local task/DP-950-T1-x deleted"
  _assert_eq "$(local_branch_absent "$WS" chore/DP-950-followup)" "absent" "C1 local chore/DP-950-followup deleted"
  _assert_eq "$(remote_branch_absent "$WS" feat/DP-950)" "absent" "C1 remote feat/DP-950 deleted"
  _assert_eq "$(remote_branch_absent "$WS" task/DP-950-T1-x)" "absent" "C1 remote task/DP-950-T1-x deleted"
  _assert_eq "$(remote_branch_absent "$WS" chore/DP-950-followup)" "absent" "C1 remote chore/DP-950-followup deleted"
  _assert_eq "$(worktree_registered "$WS" "$WT")" "no" "C1 clean worktree removed"
  _assert_contains "$CLOSEOUT_OUT" "verified no release residue for DP-950" "C1 final residue verification passed"
  _assert_not_contains "$CLOSEOUT_OUT" "POLARIS_FRAMEWORK_RELEASE_RESIDUE" "C1 no residue error"
}

# ===========================================================================
# Case 2 (EC4): idempotent no-op when residue is already absent. A DP with no
# feat/task/chore branches at all closes out cleanly — cleanup finds nothing and
# the FINAL verification passes (behaviorally identical to a closeout re-run
# after the branches were already deleted).
# ===========================================================================
{
  WS="$TMPROOT/c2-ws"
  SCRIPTS="$TMPROOT/c2-scripts"
  STUB_LOG="$TMPROOT/c2-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  write_no_branch_task "$WS" DP-953 T1 'docs-manager/a'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "no-branch confirmation task release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  MARKER="$TMPROOT/c2-verify.json"
  valid_verify_marker "$MARKER" DP-953-T1 "$RELEASE_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$WS/docs-manager/src/content/docs/specs/design-plans/DP-953-fixture/tasks/T1/index.md" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "C2 closeout exits 0 (no residue present)"
  _assert_contains "$CLOSEOUT_OUT" "verified no release residue for DP-953" "C2 verification passes on already-clean DP"
  _assert_not_contains "$CLOSEOUT_OUT" "POLARIS_FRAMEWORK_RELEASE_RESIDUE" "C2 no residue error (idempotent no-op)"
}

# ===========================================================================
# Case 3 (AC3 fail-loud): the FINAL verification errors when residue survives.
# Closeout is run while standing ON a DP residue branch (feat/DP-954): cleanup
# cannot delete the checked-out branch, so it survives and the fail-loud FINAL
# verification exits 2 with POLARIS_FRAMEWORK_RELEASE_RESIDUE.
# ===========================================================================
{
  WS="$TMPROOT/c3-ws"
  SCRIPTS="$TMPROOT/c3-scripts"
  STUB_LOG="$TMPROOT/c3-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  write_no_branch_task "$WS" DP-954 T1 'docs-manager/a'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "no-branch confirmation task release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Create the residue branch and STAND ON IT (cleanup cannot delete HEAD).
  git -C "$WS" branch feat/DP-954 main
  git -C "$WS" checkout -q feat/DP-954

  MARKER="$TMPROOT/c3-verify.json"
  valid_verify_marker "$MARKER" DP-954-T1 "$RELEASE_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$WS/docs-manager/src/content/docs/specs/design-plans/DP-954-fixture/tasks/T1/index.md" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "2" "C3 closeout fail-closed on surviving residue"
  _assert_contains "$CLOSEOUT_OUT" "POLARIS_FRAMEWORK_RELEASE_RESIDUE" "C3 fail-loud residue token emitted"
}

# ===========================================================================
# Case 4 (AC-NEG4): the legacy --delete-branches flag is accepted as a
# DEPRECATED no-op, and cleanup still runs by default. A chore/DP-955-* residue
# branch is deleted even though the flag no longer gates the behavior.
# ===========================================================================
{
  WS="$TMPROOT/c4-ws"
  SCRIPTS="$TMPROOT/c4-scripts"
  STUB_LOG="$TMPROOT/c4-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  write_no_branch_task "$WS" DP-955 T1 'docs-manager/a'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "no-branch confirmation task release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # A residue chore branch that must be cleaned regardless of the flag.
  git -C "$WS" branch chore/DP-955-note main
  git -C "$WS" checkout -q main

  MARKER="$TMPROOT/c4-verify.json"
  valid_verify_marker "$MARKER" DP-955-T1 "$RELEASE_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$WS/docs-manager/src/content/docs/specs/design-plans/DP-955-fixture/tasks/T1/index.md" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS" \
    --delete-branches

  _assert_eq "$CLOSEOUT_RC" "0" "C4 closeout exits 0 with deprecated flag"
  _assert_contains "$CLOSEOUT_OUT" "--delete-branches is DEPRECATED and a no-op" "C4 deprecation note emitted"
  _assert_eq "$(local_branch_absent "$WS" chore/DP-955-note)" "absent" "C4 residue cleaned despite flag being a no-op (mandatory)"
  _assert_contains "$CLOSEOUT_OUT" "verified no release residue for DP-955" "C4 final verification passed"
}

printf '\n[framework-release-closeout-residue-cleanup-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: framework-release closeout residue-cleanup selftest"
