#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-273-T1 (Wall A + Wall C) framework-release
#          closeout-tail robustness. Asserts:
#   - Wall A (AC1): bundle releases (cherry-pick / fresh-commit / copy-content)
#     whose per-task head is NOT an ancestor of the release commit do NOT die at
#     the head-ancestry check; closeout proceeds and flips the task.
#   - Wall A non-bundle (AC-NEG1): single-DP release keeps the ORIGINAL strict
#     per-task-head ancestry assertion (die when head not contained).
#   - Wall C (AC3): no-branch confirmation / verify tasks (no task_branch) are
#     driven via content-delivered semantics — flipped IMPLEMENTED, parent close
#     invoked — instead of dying at the "Task branch missing" check.
#   - Wall C fail-closed (AC-NEG3): a no-branch task with MISSING deliverable
#     evidence is NOT flipped (closeout dies, no spurious flip / archive).
#   - Idempotency (AC5): re-running closeout on an already-closed fixture has no
#     duplicate side effects and exits 0.
#   - engineering-clean-worktree copy-content variant: bundle release head is
#     accepted as authoritative even when worktree HEAD != delivered head.
# Inputs:  none (CLI args ignored). Builds synthetic git repos + specs
#          containers + release commits in a private tmpdir.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never mutates the real workspace.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMPROOT="$(mktemp -d -t fr-closeout-bundle-selftest.XXXXXX)"
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
  if printf '%s' "$1" | grep -qF -- "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: substring not found: %q\n' "$TOTAL" "$3" "$2" >&2
    printf '       in: %s\n' "$1" >&2
  fi
}

_assert_not_contains() {
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$1" | grep -qF -- "$2"; then
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: substring should NOT appear: %q\n' "$TOTAL" "$3" "$2" >&2
  else
    PASS=$((PASS + 1))
  fi
}

# ---------------------------------------------------------------------------
# Build a stub scripts/ dir: real closeout + clean-worktree + parser + lib,
# with the side-effecting downstream helpers replaced by deterministic stubs.
# Running the REAL closeout with SCRIPT_DIR pointing here exercises the actual
# Wall A / Wall C logic while keeping the test hermetic and focused.
# ---------------------------------------------------------------------------
build_stub_scripts_dir() {
  local dst="$1"
  mkdir -p "$dst/selftests"
  cp -R "$ROOT/scripts/lib" "$dst/lib"
  cp "$ROOT/scripts/framework-release-closeout.sh" "$dst/framework-release-closeout.sh"
  cp "$ROOT/scripts/parse-task-md.sh" "$dst/parse-task-md.sh"
  cp "$ROOT/scripts/resolve-task-base.sh" "$dst/resolve-task-base.sh"
  cp "$ROOT/scripts/engineering-worktree-cleanup.sh" "$dst/engineering-worktree-cleanup.sh" 2>/dev/null || true

  # Stub helpers: each records its invocation into $POLARIS_STUB_LOG and exits 0
  # (or performs the real frontmatter flip for mark-spec-implemented so the test
  # can observe IMPLEMENTED status). They are intentionally side-effect-light;
  # the walls under test run BEFORE / AROUND these calls.
  # NOTE: engineering-clean-worktree.sh is STUBBED here for the closeout-driven
  # cases (its own Wall A copy-content variant is exercised directly with the
  # REAL script in Case CW below).
  local helper
  for helper in check-release-eligible.sh check-release-completed.sh \
                check-main-chain-compliance.sh write-extension-deliverable.sh \
                check-local-extension-completion.sh engineering-clean-worktree.sh; do
    cat >"$dst/$helper" <<STUB
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$helper" "\$*" >>"\${POLARIS_STUB_LOG:?}"
exit 0
STUB
    chmod +x "$dst/$helper"
  done

  # mark-spec-implemented stub: flips frontmatter status to IMPLEMENTED in place
  # (mimics the non-archived task path) so the parent-close + idempotency checks
  # have a real status to observe.
  cat >"$dst/mark-spec-implemented.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TASK_ID="$1"; shift
WORKSPACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'mark-spec-implemented.sh %s\n' "$TASK_ID" >>"${POLARIS_STUB_LOG:?}"
# Find the task file for this id under the workspace specs tree and flip status.
specs="$WORKSPACE/docs-manager/src/content/docs/specs"
suffix="${TASK_ID##*-}"   # e.g. DP-900-T1 -> T1
src="${TASK_ID%-*}"       # DP-900
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

  # close-parent-spec-if-complete stub: records args (incl. --archive-terminal-parent)
  # so the test can assert the parent-close was driven for content-delivered tasks.
  cat >"$dst/close-parent-spec-if-complete.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'close-parent-spec-if-complete.sh %s\n' "$*" >>"${POLARIS_STUB_LOG:?}"
exit 0
STUB
  chmod +x "$dst/close-parent-spec-if-complete.sh"
}

# ---------------------------------------------------------------------------
# Build a hermetic workspace repo with a specs container + release commit.
#   $1 dst workspace path
#   sets globals: WS_REPO, WORKSPACE_COMMIT (release HEAD)
# Returns the repo with HEAD = release commit. Per-task branches/heads are
# created separately by each case.
# ---------------------------------------------------------------------------
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

# Write a DP container with one task at tasks/<suffix>/index.md.
#   $1 repo  $2 dp-id (DP-900)  $3 task-suffix (T1)  $4 task-shape
#   $5 task-branch (empty for no-branch)  $6 bundle-alias (empty for none)
#   $7 allowed-file (relative, written into Allowed Files + created in repo)
write_task_container() {
  local repo="$1" dp="$2" suffix="$3" shape="$4" branch="$5" alias="$6" allowed="$7"
  # DP-273 amendment: optional 8th arg overrides task_kind (default T). Legacy
  # verify tasks use kind=V with an empty shape so no task_shape line is written.
  local kind="${8:-T}"
  local dir="$repo/docs-manager/src/content/docs/specs/design-plans/${dp}-fixture"
  mkdir -p "$dir/tasks/$suffix"
  # parent index.md
  cat >"$dir/index.md" <<MD
---
title: "${dp} fixture parent"
status: LOCKED
---

# ${dp}
MD
  # task index.md
  {
    printf -- '---\n'
    [[ -n "$alias" ]] && printf 'bundle_branch_alias: %s\n' "$alias"
    printf 'status: IN_PROGRESS\n'
    printf 'task_kind: %s\n' "$kind"
    [[ -n "$shape" ]] && printf 'task_shape: %s\n' "$shape"
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
    [[ -n "$branch" ]] && printf '| Task branch | %s |\n' "$branch"
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
  # $1 stub scripts dir, rest = closeout args. Captures combined output into
  # CLOSEOUT_OUT and exit code into CLOSEOUT_RC.
  local scripts_dir="$1"; shift
  set +e
  CLOSEOUT_OUT="$(POLARIS_STUB_LOG="$STUB_LOG" \
    bash "$scripts_dir/framework-release-closeout.sh" "$@" 2>&1)"
  CLOSEOUT_RC=$?
  set -e
}

# ===========================================================================
# Case A1 (Wall A, AC1): cherry-pick / fresh-commit bundle — per-task head is
# NOT an ancestor of the release commit; closeout must NOT die at the ancestry
# check. Bundle detected via bundle_branch_alias.
# ===========================================================================
{
  WS="$TMPROOT/a1-ws"
  SCRIPTS="$TMPROOT/a1-scripts"
  STUB_LOG="$TMPROOT/a1-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  # Per-task branch with its own commit (the "original per-task head").
  git -C "$WS" checkout -q -b task/DP-900-T1-x
  mkdir -p "$WS/scripts"
  echo perTask >"$WS/scripts/feature-a1.sh"
  git -C "$WS" add scripts/feature-a1.sh
  git -C "$WS" commit -qm "per-task work"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Bundle release commit on main = a SEPARATE fresh commit (cherry-pick style):
  # it re-introduces the same content but the per-task head is NOT its ancestor.
  git -C "$WS" checkout -q main
  mkdir -p "$WS/scripts"
  echo bundled >"$WS/scripts/feature-a1.sh"
  write_task_container "$WS" DP-900 T1 implementation task/DP-900-T1-x bundle-DP-900-v1.0.0 'scripts/feature-a1.sh'
  git -C "$WS" add scripts/feature-a1.sh docs-manager
  git -C "$WS" commit -qm "bundle release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/a1-verify.json"
  valid_verify_marker "$MARKER" DP-900-T1 "$TASK_HEAD"

  # Sanity: per-task head is genuinely NOT an ancestor of the release head.
  if git -C "$WS" merge-base --is-ancestor "$TASK_HEAD" "$RELEASE_HEAD" 2>/dev/null; then
    echo "[setup-error] A1 per-task head unexpectedly an ancestor" >&2
  fi

  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" --task-head-sha "DP-900-T1=${TASK_HEAD}" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "A1 bundle closeout exits 0"
  _assert_not_contains "$CLOSEOUT_OUT" "workspace commit does not contain task head" "A1 no Wall-A die"
  _assert_contains "$CLOSEOUT_OUT" "bundle delivery" "A1 bundle-aware path taken"
}

# ===========================================================================
# Case A-NEG1 (Wall A, AC-NEG1): single-DP NON-bundle release whose per-task
# head is NOT contained must keep the ORIGINAL strict ancestry die.
# ===========================================================================
{
  WS="$TMPROOT/aneg1-ws"
  SCRIPTS="$TMPROOT/aneg1-scripts"
  STUB_LOG="$TMPROOT/aneg1-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  git -C "$WS" checkout -q -b task/DP-901-T1-x
  echo perTask >"$WS/scripts-dummy.txt" 2>/dev/null || echo perTask >"$WS/dummy.txt"
  git -C "$WS" add -A
  git -C "$WS" commit -qm "per-task work"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  git -C "$WS" checkout -q main
  # NON-bundle: no bundle_branch_alias on the task.
  echo other >"$WS/release.txt"
  write_task_container "$WS" DP-901 T1 implementation task/DP-901-T1-x '' 'release.txt'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "single-DP release (no bundle)"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-901-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/aneg1-verify.json"
  valid_verify_marker "$MARKER" DP-901-T1 "$TASK_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" --task-head-sha "DP-901-T1=${TASK_HEAD}" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "2" "A-NEG1 non-bundle strict ancestry dies"
  _assert_contains "$CLOSEOUT_OUT" "workspace commit does not contain task head" "A-NEG1 original strict die fires"
}

# ===========================================================================
# Case C3 (Wall C, AC3): no-branch confirmation + verify tasks with deliverable
# evidence present — flipped IMPLEMENTED + parent close invoked, no "Task branch
# missing" die.
# ===========================================================================
{
  WS="$TMPROOT/c3-ws"
  SCRIPTS="$TMPROOT/c3-scripts"
  STUB_LOG="$TMPROOT/c3-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  # confirmation + verify tasks live under one DP; release commit on main.
  write_task_container "$WS" DP-902 T4 confirmation '' '' 'docs-manager/x'
  write_task_container "$WS" DP-902 V1 verify '' '' 'docs-manager/y'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "no-branch tasks release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  T4_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-902-fixture/tasks/T4/index.md"
  V1_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-902-fixture/tasks/V1/index.md"
  T4_MARKER="$TMPROOT/c3-t4.json"
  V1_MARKER="$TMPROOT/c3-v1.json"
  valid_verify_marker "$T4_MARKER" DP-902-T4 "$RELEASE_HEAD"
  valid_verify_marker "$V1_MARKER" DP-902-V1 "$RELEASE_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$T4_MD" --verify-evidence "$T4_MARKER" \
    --task-md "$V1_MD" --verify-evidence "$V1_MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "C3 no-branch closeout exits 0"
  _assert_not_contains "$CLOSEOUT_OUT" "Task branch missing" "C3 no Wall-C die"
  _assert_contains "$CLOSEOUT_OUT" "content-delivered" "C3 content-delivered path taken"
  # Both no-branch tasks flipped IMPLEMENTED.
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$T4_MD")" "1" "C3 T4 flipped IMPLEMENTED"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$V1_MD")" "1" "C3 V1 flipped IMPLEMENTED"
  # Parent-close invoked (terminal archive on the last task).
  _assert_contains "$(cat "$STUB_LOG")" "close-parent-spec-if-complete.sh" "C3 parent close invoked"
  _assert_contains "$(cat "$STUB_LOG")" "--archive-terminal-parent" "C3 terminal parent archive requested"
}

# ===========================================================================
# Case C-LEGV (Wall C, AC4 legacy): a no-branch LEGACY verify task — task_kind: V
# with NO task_shape (predates the task_shape field) — with deliverable evidence
# present must flip IMPLEMENTED + parent archive, exactly like a task_shape=verify
# task. This is the DP-273 amendment that unblocks the 7 stranded legacy-V
# containers (DP-238/242/262/264/269/274/281), whose V1 tasks are all legacy
# task_kind: V with no task_shape.
# ===========================================================================
{
  WS="$TMPROOT/clegv-ws"
  SCRIPTS="$TMPROOT/clegv-scripts"
  STUB_LOG="$TMPROOT/clegv-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  # Legacy verify task: kind=V, empty shape (no task_shape line emitted), no branch.
  write_task_container "$WS" DP-905 V1 '' '' '' 'docs-manager/z' V
  git -C "$WS" add -A
  git -C "$WS" commit -qm "legacy-V no-branch task release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  V1_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-905-fixture/tasks/V1/index.md"
  # Sanity: the fixture really is legacy-shaped (task_kind: V, no task_shape).
  _assert_eq "$(grep -c '^task_kind: V$' "$V1_MD")" "1" "C-LEGV fixture has task_kind: V"
  _assert_eq "$(grep -c '^task_shape:' "$V1_MD")" "0" "C-LEGV fixture has NO task_shape"

  V1_MARKER="$TMPROOT/clegv-v1.json"
  valid_verify_marker "$V1_MARKER" DP-905-V1 "$RELEASE_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$V1_MD" --verify-evidence "$V1_MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "C-LEGV legacy-V no-branch closeout exits 0"
  _assert_not_contains "$CLOSEOUT_OUT" "Task branch missing" "C-LEGV no Wall-C die"
  _assert_contains "$CLOSEOUT_OUT" "content-delivered" "C-LEGV content-delivered path taken"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$V1_MD")" "1" "C-LEGV V1 flipped IMPLEMENTED"
  _assert_contains "$(cat "$STUB_LOG")" "close-parent-spec-if-complete.sh" "C-LEGV parent close invoked"
  _assert_contains "$(cat "$STUB_LOG")" "--archive-terminal-parent" "C-LEGV terminal parent archive requested"
}

# ===========================================================================
# Case C-NEG3 (Wall C, AC-NEG3): no-branch task with MISSING deliverable
# evidence must NOT flip (fail-closed). Closeout dies; task stays not-implemented.
# ===========================================================================
{
  WS="$TMPROOT/cneg3-ws"
  SCRIPTS="$TMPROOT/cneg3-scripts"
  STUB_LOG="$TMPROOT/cneg3-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  write_task_container "$WS" DP-903 T4 confirmation '' '' 'docs-manager/x'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "no-branch task release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  T4_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-903-fixture/tasks/T4/index.md"

  run_closeout "$SCRIPTS" \
    --task-md "$T4_MD" --verify-evidence "$TMPROOT/cneg3-missing.json" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "2" "C-NEG3 missing evidence fails closed"
  _assert_contains "$CLOSEOUT_OUT" "content-delivered evidence missing" "C-NEG3 fail-closed message"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$T4_MD")" "0" "C-NEG3 task NOT flipped"
  _assert_not_contains "$(cat "$STUB_LOG")" "close-parent-spec-if-complete.sh" "C-NEG3 parent close NOT invoked"
}

# ===========================================================================
# Case A5 (idempotency, AC5): re-run the C3-style closeout twice; second run
# must skip already-IMPLEMENTED no-branch tasks (no duplicate parent-close),
# exit 0.
# ===========================================================================
{
  WS="$TMPROOT/a5-ws"
  SCRIPTS="$TMPROOT/a5-scripts"
  STUB_LOG="$TMPROOT/a5-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  write_task_container "$WS" DP-904 T4 confirmation '' '' 'docs-manager/x'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "no-branch task release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"
  T4_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-904-fixture/tasks/T4/index.md"
  MARKER="$TMPROOT/a5-t4.json"
  valid_verify_marker "$MARKER" DP-904-T4 "$RELEASE_HEAD"

  # First run flips IMPLEMENTED in place (stub keeps file at same path).
  run_closeout "$SCRIPTS" \
    --task-md "$T4_MD" --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"
  _assert_eq "$CLOSEOUT_RC" "0" "A5 first run exits 0"

  # Move the now-IMPLEMENTED task into pr-release/ to mimic a real flip+move, so
  # the idempotency skip predicate (pr-release + IMPLEMENTED) fires on rerun.
  prdir="$WS/docs-manager/src/content/docs/specs/design-plans/DP-904-fixture/tasks/pr-release/T4"
  mkdir -p "$prdir"
  git -C "$WS" mv "docs-manager/src/content/docs/specs/design-plans/DP-904-fixture/tasks/T4/index.md" \
    "docs-manager/src/content/docs/specs/design-plans/DP-904-fixture/tasks/pr-release/T4/index.md"
  git -C "$WS" commit -qm "move to pr-release"
  RERUN_HEAD="$(git -C "$WS" rev-parse HEAD)"
  PR_T4_MD="$prdir/index.md"
  RERUN_MARKER="$TMPROOT/a5-t4-rerun.json"
  valid_verify_marker "$RERUN_MARKER" DP-904-T4 "$RERUN_HEAD"

  : >"$STUB_LOG"
  run_closeout "$SCRIPTS" \
    --task-md "$PR_T4_MD" --verify-evidence "$RERUN_MARKER" \
    --workspace-commit "$RERUN_HEAD" --template-commit "$RERUN_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"
  _assert_eq "$CLOSEOUT_RC" "0" "A5 rerun exits 0 (idempotent)"
  _assert_contains "$CLOSEOUT_OUT" "already IMPLEMENTED" "A5 rerun skips already-implemented"
  _assert_not_contains "$(cat "$STUB_LOG")" "close-parent-spec-if-complete.sh" "A5 rerun no duplicate parent close"
}

# ===========================================================================
# Case CW (engineering-clean-worktree Wall A copy-content variant): bundle
# release head accepted as authoritative even when worktree HEAD != delivered
# head; non-bundle still blocks.
# ===========================================================================
{
  WS="$TMPROOT/cw-ws"
  REMOTE="$TMPROOT/cw-remote.git"
  git init -q --bare "$REMOTE"
  git clone -q "$REMOTE" "$WS" 2>/dev/null
  git -C "$WS" config user.email selftest@example.com
  git -C "$WS" config user.name selftest
  git -C "$WS" checkout -q -b main
  echo init >"$WS/file.txt"
  git -C "$WS" add file.txt
  git -C "$WS" commit -qm init
  git -C "$WS" push -q -u origin main

  # Engineering worktree on a per-task branch with its OWN divergent commit, so
  # the worktree HEAD is NOT an ancestor of the bundle release head (copy-content
  # bundles never commit the per-task branch into the release lineage).
  git -C "$WS" branch task/DP-905-T1-cw main
  mkdir -p "$WS/.worktrees"
  git -C "$WS" worktree add -q "$WS/.worktrees/polaris-framework-engineering-DP-905-T1" task/DP-905-T1-cw
  WT="$WS/.worktrees/polaris-framework-engineering-DP-905-T1"
  echo perTask >"$WT/per-task.txt"
  git -C "$WT" add per-task.txt
  git -C "$WT" commit -qm "per-task divergent work"
  WT_HEAD="$(git -C "$WT" rev-parse HEAD)"

  # Bundle release head = a DIVERGENT commit on main (copy-content style): the
  # worktree HEAD is NOT its ancestor and vice versa.
  echo bundled >"$WS/file.txt"
  git -C "$WS" commit -qam "bundle release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Sanity: worktree HEAD is genuinely NOT an ancestor of the release head.
  if git -C "$WS" merge-base --is-ancestor "$WT_HEAD" "$RELEASE_HEAD" 2>/dev/null; then
    echo "[setup-error] CW worktree head unexpectedly an ancestor" >&2
  fi

  # Bundle task.md: delivered head = release head; worktree HEAD differs.
  TASK_MD="$TMPROOT/cw-task.md"
  cat >"$TASK_MD" <<MD
---
bundle_branch_alias: bundle-DP-905-v1.0.0
extension_deliverable:
  endpoint: local_extension
  extension_id: framework-release
  task_head_sha: ${RELEASE_HEAD}
  workspace_commit: ${RELEASE_HEAD}
  template_commit: ${RELEASE_HEAD}
  version_tag: v1.0.0
  release_url: N/A
status: IMPLEMENTED
---
# T1: bundle copy-content (1 pt)

> Source: DP-905 | Task: DP-905-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-905 |
| Task ID | DP-905-T1 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-905-T1-cw |
MD

  set +e
  OUT_CW="$(bash "$ROOT/scripts/engineering-clean-worktree.sh" --task-md "$TASK_MD" --repo "$WS" 2>&1)"
  CW_RC=$?
  set -e
  _assert_eq "$CW_RC" "0" "CW bundle clean-worktree exits 0"
  _assert_contains "$OUT_CW" "bundle release head is authoritative" "CW bundle authoritative path"
  [[ -d "$WT" ]] && CW_WT_STATE=exists || CW_WT_STATE=removed
  _assert_eq "$CW_WT_STATE" "removed" "CW bundle worktree removed"

  # Non-bundle twin: same head mismatch but NO bundle alias → must block.
  git -C "$WS" branch task/DP-906-T1-cw "$RELEASE_HEAD"
  git -C "$WS" worktree add -q "$WS/.worktrees/polaris-framework-engineering-DP-906-T1" task/DP-906-T1-cw
  WT2="$WS/.worktrees/polaris-framework-engineering-DP-906-T1"
  echo more >"$WS/file.txt"
  git -C "$WS" commit -qam "advance main past worktree"
  ADV_HEAD="$(git -C "$WS" rev-parse HEAD)"
  WT2_HEAD="$(git -C "$WT2" rev-parse HEAD)"
  TASK_MD2="$TMPROOT/cw-task-nobundle.md"
  cat >"$TASK_MD2" <<MD
---
deliverable:
  pr_url: https://example.test/pr/1
  pr_state: OPEN
  head_sha: ${ADV_HEAD}
status: IMPLEMENTED
---
# T1: non-bundle (1 pt)

> Source: DP-906 | Task: DP-906-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-906 |
| Task ID | DP-906-T1 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-906-T1-cw |
MD
  set +e
  OUT_CW2="$(bash "$ROOT/scripts/engineering-clean-worktree.sh" --task-md "$TASK_MD2" --repo "$WS" 2>&1)"
  CW2_RC=$?
  set -e
  _assert_eq "$CW2_RC" "2" "CW non-bundle head mismatch blocks"
  _assert_contains "$OUT_CW2" "delivered head" "CW non-bundle block message"
}

printf '\n[framework-release-closeout-bundle-task-closeout-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: framework-release closeout bundle/task closeout selftest"
