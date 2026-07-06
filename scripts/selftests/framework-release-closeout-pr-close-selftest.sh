#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-305-T1 — framework-release closeout bundled
#          task PR-close (D1) + release-evidence-keyed cleanup trigger (D2) +
#          gh fail-stop (AC7). Asserts:
#   - AC1 (PR close): closeout runs `gh pr close --delete-branch` + a
#     zh-TW `已發版 vX.Y.Z` comment for each bundled task PR resolved from task.md
#     deliverable.pr_url (NOT head ancestry). Already-merged / already-closed PRs
#     are idempotent-skipped (re-run produces zero extra gh close/comment calls).
#   - AC2 (release-evidence-keyed trigger): a bundle re-fold whose per-task head
#     is NOT a main-ancestor still triggers PR-close — the close lane keys on
#     release evidence (closeout invoked = release evidence) + the recorded
#     deliverable PR, never on `merge-base --is-ancestor`, so it does NOT
#     silently skip.
#   - AC7 (gh fail-stop): when gh is missing the close lane fail-stops with
#     POLARIS_TOOL_MISSING; when gh is present but unauthenticated it fail-stops
#     with POLARIS_TOOL_AUTH_FAILED. Neither swallows the error.
# Inputs:  none (CLI args ignored). Builds synthetic git repos + specs
#          containers + release commits + a fake gh CLI in a private tmpdir.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never mutates the real workspace.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMPROOT="$(mktemp -d -t fr-closeout-pr-close-selftest.XXXXXX)"
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
# Build a stub scripts/ dir: real closeout + parser + lib, with side-effecting
# downstream helpers replaced by deterministic stubs. The PR-close + cleanup
# trigger logic under test runs INSIDE the real closeout.
# ---------------------------------------------------------------------------
build_stub_scripts_dir() {
  local dst="$1"
  mkdir -p "$dst/selftests"
  cp -R "$ROOT/scripts/lib" "$dst/lib"
  cp "$ROOT/scripts/framework-release-closeout.sh" "$dst/framework-release-closeout.sh"
  cp "$ROOT/scripts/parse-task-md.sh" "$dst/parse-task-md.sh"
  cp "$ROOT/scripts/resolve-task-base.sh" "$dst/resolve-task-base.sh" 2>/dev/null || true
  cat >"$dst/polaris-external-write-gate.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
body_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file) body_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$body_file" && -f "$body_file" ]] || exit 2
printf 'external-write-gate %s\n' "$body_file" >>"${POLARIS_STUB_LOG:?}"
exit 0
STUB
  chmod +x "$dst/polaris-external-write-gate.sh"

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

  cat >"$dst/close-parent-spec-if-complete.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'close-parent-spec-if-complete.sh %s\n' "$*" >>"${POLARIS_STUB_LOG:?}"
exit 0
STUB
  chmod +x "$dst/close-parent-spec-if-complete.sh"
}

# ---------------------------------------------------------------------------
# Fake gh CLI. Behaviour is driven by env:
#   FAKE_GH_PR_STATE_<num>  => OPEN | MERGED | CLOSED  (per PR number)
#   FAKE_GH_LOG             => path; every gh invocation is appended verbatim
#   FAKE_GH_AUTH            => ok (default) | fail
# Supports: `gh auth status`, `gh pr view <n> --json state -q .state`,
#           `gh pr comment <n> ...`, `gh pr close <n> --delete-branch`.
# ---------------------------------------------------------------------------
make_fake_gh() {
  local path="$1"
  cat >"$path" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >>"${FAKE_GH_LOG:?}"

# pr_number_from_args: scan for the first bare integer arg (the PR number).
pr_num=""
for a in "$@"; do
  if [[ "$a" =~ ^[0-9]+$ ]]; then pr_num="$a"; break; fi
done

state_for() {
  local n="$1"
  local var="FAKE_GH_PR_STATE_${n}"
  printf '%s' "${!var:-OPEN}"
}

case "$1" in
  auth)
    if [[ "${FAKE_GH_AUTH:-ok}" == "ok" ]]; then exit 0; else exit 1; fi
    ;;
  pr)
    case "$2" in
      view)
        # Emit the state for the requested PR. We only support `--json state -q .state`.
        state_for "$pr_num"
        echo
        exit 0
        ;;
      comment)
        body_file=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --body-file) body_file="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        if [[ -n "$body_file" && -f "$body_file" ]]; then
          printf 'body-file-content %s\n' "$(cat "$body_file")" >>"${FAKE_GH_LOG:?}"
        fi
        exit 0
        ;;
      close) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
GH
  chmod +x "$path"
}

init_workspace_repo() {
  local repo="$1"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  git -C "$repo" checkout -q -b main
  printf 'language: "zh-TW"\n' >"$repo/workspace-config.yaml"
  mkdir -p "$repo/docs-manager/src/content/docs/specs/design-plans"
  echo init >"$repo/seed.txt"
  git -C "$repo" add seed.txt workspace-config.yaml
  git -C "$repo" commit -qm init
}

# Write a DP container with one task carrying a bundle alias + deliverable PR url.
#   $1 repo  $2 dp  $3 suffix  $4 branch  $5 bundle-alias  $6 allowed  $7 pr_url
write_bundle_task_container() {
  local repo="$1" dp="$2" suffix="$3" branch="$4" alias="$5" allowed="$6" pr_url="$7"
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
    printf 'bundle_branch_alias: %s\n' "$alias"
    [[ -n "$pr_url" ]] && {
      printf 'deliverable:\n'
      printf '  pr_url: %s\n' "$pr_url"
      printf '  pr_state: OPEN\n'
    }
    printf 'status: IN_PROGRESS\n'
    printf 'task_kind: T\n'
    printf 'task_shape: implementation\n'
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

valid_verify_marker() {
  local path="$1" ticket="$2" head="$3"
  cat >"$path" <<JSON
{"ticket":"${ticket}","head_sha":"${head}","writer":"run-verify-command.sh","exit_code":0,"at":"2026-06-05T00:00:00Z","status":"PASS"}
JSON
}

run_closeout() {
  local scripts_dir="$1"; shift
  set +e
  CLOSEOUT_OUT="$(POLARIS_STUB_LOG="$STUB_LOG" GH_BIN="${GH_BIN:-}" \
    FAKE_GH_LOG="${FAKE_GH_LOG:-}" FAKE_GH_AUTH="${FAKE_GH_AUTH:-ok}" \
    FAKE_GH_PR_STATE_1="${FAKE_GH_PR_STATE_1:-OPEN}" \
    bash "$scripts_dir/framework-release-closeout.sh" "$@" 2>&1)"
  CLOSEOUT_RC=$?
  set -e
}

# Build a re-fold bundle workspace: per-task branch head is NOT an ancestor of
# the release commit; the task carries a deliverable PR url (#1).
#   sets WS, SCRIPTS, STUB_LOG, TASK_MD, TASK_HEAD, RELEASE_HEAD, MARKER
build_refold_bundle() {
  local tag="$1" dp="$2" pr_url="$3"
  WS="$TMPROOT/$tag-ws"
  SCRIPTS="$TMPROOT/$tag-scripts"
  STUB_LOG="$TMPROOT/$tag-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  git -C "$WS" checkout -q -b "task/${dp}-T1-x"
  mkdir -p "$WS/scripts"
  echo perTask >"$WS/scripts/feature-${tag}.sh"
  git -C "$WS" add "scripts/feature-${tag}.sh"
  git -C "$WS" commit -qm "per-task work"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  git -C "$WS" checkout -q main
  mkdir -p "$WS/scripts"
  echo bundled >"$WS/scripts/feature-${tag}.sh"
  write_bundle_task_container "$WS" "$dp" T1 "task/${dp}-T1-x" "bundle-${dp}-v1.0.0" "scripts/feature-${tag}.sh" "$pr_url"
  git -C "$WS" add scripts docs-manager
  git -C "$WS" commit -qm "bundle release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/${dp}-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/$tag-verify.json"
  valid_verify_marker "$MARKER" "${dp}-T1" "$TASK_HEAD"

  # Sanity: re-fold head is genuinely NOT an ancestor of the release head.
  if git -C "$WS" merge-base --is-ancestor "$TASK_HEAD" "$RELEASE_HEAD" 2>/dev/null; then
    echo "[setup-error] $tag per-task head unexpectedly an ancestor" >&2
  fi
}

# ===========================================================================
# Case PR1 (AC1 + AC2): re-fold bundle with an OPEN deliverable PR #1. Closeout
# must run `gh pr close 1 --delete-branch` + a zh-TW release comment even
# though the per-task head is NOT a main-ancestor. Then a SECOND run with PR #1
# now CLOSED must idempotent-skip (no extra close/comment gh calls).
# ===========================================================================
{
  build_refold_bundle pr1 DP-900 "https://github.com/example-org/example/pull/1"
  GH="$TMPROOT/pr1-gh"; make_fake_gh "$GH"
  GH_LOG="$TMPROOT/pr1-gh.log"; : >"$GH_LOG"

  GH_BIN="$GH" FAKE_GH_LOG="$GH_LOG" FAKE_GH_AUTH=ok FAKE_GH_PR_STATE_1=OPEN \
    run_closeout "$SCRIPTS" \
      --task-md "$TASK_MD" --task-head-sha "DP-900-T1=${TASK_HEAD}" \
      --verify-evidence "$MARKER" \
      --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
      --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "PR1 closeout exits 0"
  GH_OUT="$(cat "$GH_LOG")"
  _assert_contains "$GH_OUT" "pr close 1" "PR1 gh pr close called for PR #1"
  _assert_contains "$GH_OUT" "--delete-branch" "PR1 close uses --delete-branch"
  _assert_contains "$GH_OUT" "pr comment 1" "PR1 released-version comment posted"
  _assert_contains "$GH_OUT" "已發版 v1.0.0" "PR1 comment carries zh-TW released version"
  _assert_not_contains "$GH_OUT" "bundled into the release" "PR1 comment no longer uses English default prose"

  # Second run: PR #1 now CLOSED. Idempotent skip — no further close/comment.
  : >"$GH_LOG"
  GH_BIN="$GH" FAKE_GH_LOG="$GH_LOG" FAKE_GH_AUTH=ok FAKE_GH_PR_STATE_1=CLOSED \
    run_closeout "$SCRIPTS" \
      --task-md "$TASK_MD" --task-head-sha "DP-900-T1=${TASK_HEAD}" \
      --verify-evidence "$MARKER" \
      --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
      --version-tag v1.0.0 --release-url N/A --repo "$WS"
  _assert_eq "$CLOSEOUT_RC" "0" "PR1 rerun exits 0 (idempotent)"
  GH_OUT2="$(cat "$GH_LOG")"
  _assert_not_contains "$GH_OUT2" "pr close 1" "PR1 rerun does NOT re-close closed PR"
  _assert_not_contains "$GH_OUT2" "pr comment 1" "PR1 rerun does NOT re-comment closed PR"
}

# ===========================================================================
# Case PRM (AC1 idempotency): a deliverable PR that is already MERGED must be
# idempotent-skipped on the first run too (no close, no comment).
# ===========================================================================
{
  build_refold_bundle prm DP-901 "https://github.com/example-org/example/pull/1"
  GH="$TMPROOT/prm-gh"; make_fake_gh "$GH"
  GH_LOG="$TMPROOT/prm-gh.log"; : >"$GH_LOG"

  GH_BIN="$GH" FAKE_GH_LOG="$GH_LOG" FAKE_GH_AUTH=ok FAKE_GH_PR_STATE_1=MERGED \
    run_closeout "$SCRIPTS" \
      --task-md "$TASK_MD" --task-head-sha "DP-901-T1=${TASK_HEAD}" \
      --verify-evidence "$MARKER" \
      --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
      --version-tag v1.0.0 --release-url N/A --repo "$WS"
  _assert_eq "$CLOSEOUT_RC" "0" "PRM merged-PR closeout exits 0"
  GH_OUT="$(cat "$GH_LOG")"
  _assert_not_contains "$GH_OUT" "pr close 1" "PRM does NOT close already-merged PR"
  _assert_not_contains "$GH_OUT" "pr comment 1" "PRM does NOT comment already-merged PR"
}

# ===========================================================================
# Case AUTH-MISSING (AC7): gh binary missing => fail-stop POLARIS_TOOL_MISSING.
# ===========================================================================
{
  build_refold_bundle ghm DP-902 "https://github.com/example-org/example/pull/1"
  GH_LOG="$TMPROOT/ghm-gh.log"; : >"$GH_LOG"

  GH_BIN="$TMPROOT/does-not-exist-gh" FAKE_GH_LOG="$GH_LOG" FAKE_GH_PR_STATE_1=OPEN \
    run_closeout "$SCRIPTS" \
      --task-md "$TASK_MD" --task-head-sha "DP-902-T1=${TASK_HEAD}" \
      --verify-evidence "$MARKER" \
      --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
      --version-tag v1.0.0 --release-url N/A --repo "$WS"
  _assert_eq "$CLOSEOUT_RC" "2" "AUTH-MISSING fail-stops"
  _assert_contains "$CLOSEOUT_OUT" "POLARIS_TOOL_MISSING" "AUTH-MISSING emits POLARIS_TOOL_MISSING"
}

# ===========================================================================
# Case AUTH-FAIL (AC7): gh present but unauthenticated => fail-stop
# POLARIS_TOOL_AUTH_FAILED.
# ===========================================================================
{
  build_refold_bundle gha DP-903 "https://github.com/example-org/example/pull/1"
  GH="$TMPROOT/gha-gh"; make_fake_gh "$GH"
  GH_LOG="$TMPROOT/gha-gh.log"; : >"$GH_LOG"

  GH_BIN="$GH" FAKE_GH_LOG="$GH_LOG" FAKE_GH_AUTH=fail FAKE_GH_PR_STATE_1=OPEN \
    run_closeout "$SCRIPTS" \
      --task-md "$TASK_MD" --task-head-sha "DP-903-T1=${TASK_HEAD}" \
      --verify-evidence "$MARKER" \
      --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
      --version-tag v1.0.0 --release-url N/A --repo "$WS"
  _assert_eq "$CLOSEOUT_RC" "2" "AUTH-FAIL fail-stops"
  _assert_contains "$CLOSEOUT_OUT" "POLARIS_TOOL_AUTH_FAILED" "AUTH-FAIL emits POLARIS_TOOL_AUTH_FAILED"
}

# ===========================================================================
# Case NO-PR (AC1 boundary): a bundle task with NO deliverable.pr_url must NOT
# attempt any gh pr close/comment (nothing to close), and closeout still exits 0.
# gh must still be resolvable (present + auth ok) but is simply not used for
# pr close/comment.
# ===========================================================================
{
  build_refold_bundle nopr DP-904 ""
  GH="$TMPROOT/nopr-gh"; make_fake_gh "$GH"
  GH_LOG="$TMPROOT/nopr-gh.log"; : >"$GH_LOG"

  GH_BIN="$GH" FAKE_GH_LOG="$GH_LOG" FAKE_GH_AUTH=ok \
    run_closeout "$SCRIPTS" \
      --task-md "$TASK_MD" --task-head-sha "DP-904-T1=${TASK_HEAD}" \
      --verify-evidence "$MARKER" \
      --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
      --version-tag v1.0.0 --release-url N/A --repo "$WS"
  _assert_eq "$CLOSEOUT_RC" "0" "NO-PR closeout exits 0"
  GH_OUT="$(cat "$GH_LOG")"
  _assert_not_contains "$GH_OUT" "pr close" "NO-PR makes no pr close call"
  _assert_not_contains "$GH_OUT" "pr comment" "NO-PR makes no pr comment call"
}

printf '\n[framework-release-closeout-pr-close-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: framework-release closeout PR-close selftest"
