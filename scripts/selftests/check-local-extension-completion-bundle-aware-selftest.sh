#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-280-T1. Asserts that
#   check-local-extension-completion.sh's per-task head-ancestry check is now
#   "strict OR bundle-aware", sharing the SINGLE bundle detector extracted into
#   scripts/lib/bundle-closeout-ancestry.sh (no second detector):
#   - AC7  : a bundle task (task.md carries bundle_branch_alias) whose
#            task_head_sha is NOT a strict ancestor of workspace_commit must NOT
#            block — release-diff ∩ Allowed Files non-empty (or the bundle-head
#            carve-out) plus evidence head accepting the bundle head passes.
#   - AC10 : the existing NON-bundle (no-alias) closeout path is byte-equivalent
#            after the shared-lib extraction — strict per-task-head ancestry still
#            blocks when the head is not contained, and still passes when it is.
#   - AC-NEG4: a bundle task WITH an alias but EMPTY release-diff ∩ Allowed Files
#            AND whose bundle head does not validate must still fail-closed.
#   - AC-NEG5: the no-alias strict path is unchanged (covered alongside AC10).
#   It also asserts the shared lib is the one source of truth: both
#   framework-release-closeout.sh and check-local-extension-completion.sh source
#   scripts/lib/bundle-closeout-ancestry.sh and define neither bundle helper
#   inline.
# Inputs:  none (CLI args ignored). Builds a synthetic git repo, synthetic
#          bundle/no-alias task.md, synthetic release commit, and writer-shaped
#          extension_deliverable frontmatter + verify markers in a private
#          tmpdir.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never calls gh / touches live specs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/check-local-extension-completion.sh"
LIB="$ROOT/scripts/lib/bundle-closeout-ancestry.sh"
CLOSEOUT="$ROOT/scripts/framework-release-closeout.sh"

TMPROOT="$(mktemp -d -t cle-bundle-aware-selftest.XXXXXX)"
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
# Shared-lib single-source assertions (AC10 structural): both closeout + the
# gate must SOURCE the shared lib, and neither may define the bundle helpers
# inline (no second detector).
# ---------------------------------------------------------------------------
{
  _assert_eq "$( [[ -f "$LIB" ]] && echo yes || echo no )" "yes" "shared lib exists"
  _assert_contains "$(cat "$LIB")" "bundle_branch_alias_for_task" "lib defines bundle_branch_alias_for_task"
  _assert_contains "$(cat "$LIB")" "release_diff_intersects_allowed_files" "lib defines release_diff_intersects_allowed_files"

  # closeout must source the lib and NOT redefine the helpers inline.
  closeout_src="$(cat "$CLOSEOUT")"
  _assert_contains "$closeout_src" "lib/bundle-closeout-ancestry.sh" "closeout sources shared lib"
  _assert_not_contains "$closeout_src" "bundle_branch_alias_for_task() {" "closeout has no inline bundle_branch_alias_for_task def"
  _assert_not_contains "$closeout_src" "release_diff_intersects_allowed_files() {" "closeout has no inline release_diff def"

  # gate must source the lib (it consumes the bundle helpers for AC7).
  gate_src="$(cat "$GATE")"
  _assert_contains "$gate_src" "lib/bundle-closeout-ancestry.sh" "gate sources shared lib"
}

# ---------------------------------------------------------------------------
# Helpers to build a hermetic workspace repo + writer-shaped extension task.md.
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

# Write a task.md carrying an extension_deliverable block + Allowed Files.
#   $1 path  $2 task_head_sha  $3 workspace_commit  $4 bundle_alias(empty=none)
#   $5 allowed_file
write_extension_task() {
  local path="$1" head="$2" ws="$3" alias="$4" allowed="$5"
  {
    printf -- '---\n'
    [[ -n "$alias" ]] && printf 'bundle_branch_alias: %s\n' "$alias"
    printf 'status: IMPLEMENTED\n'
    printf 'task_kind: T\n'
    printf 'task_shape: implementation\n'
    printf 'extension_deliverable:\n'
    printf '  endpoint: local_extension\n'
    printf '  extension_id: framework-release\n'
    printf '  task_head_sha: %s\n' "$head"
    printf '  workspace_commit: %s\n' "$ws"
    printf '  template_commit: %s\n' "$ws"
    printf '  version_tag: v1.0.0\n'
    printf '  release_url: N/A\n'
    printf '  completed_at: 2026-06-05T00:00:00Z\n'
    printf '  evidence:\n'
    printf '    verify: %s\n' "$VERIFY_MARKER"
    printf -- '---\n\n'
    printf '# T1: fixture extension task (1 pt)\n\n'
    printf '> Source: DP-FX | Task: DP-FX-T1 | JIRA: N/A | Repo: polaris-framework\n\n'
    printf '## Operational Context\n\n'
    printf '| 欄位 | 值 |\n|------|-----|\n'
    printf '| Source type | dp |\n'
    printf '| Source ID | DP-FX |\n'
    printf '| Task ID | DP-FX-T1 |\n'
    printf '| Base branch | main |\n'
    printf '\n## Allowed Files\n\n'
    printf -- '- `%s`\n' "$allowed"
    printf '\n## Test Environment\n\n- **Level**: static\n'
  } >"$path"
}

# Writes a verify marker accepted by verification-evidence.sh for the gate's T
# path. ticket = DP-FX-T1, head = arg. The bundle-aware evidence head check must
# accept either the per-task head OR the bundle (workspace) head.
write_verify_marker() {
  local path="$1" head="$2"
  cat >"$path" <<JSON
{"ticket":"DP-FX-T1","work_item_id":"DP-FX-T1","head_sha":"${head}","freshness":{"head_sha":"${head}"},"writer":"run-verify-command.sh","exit_code":0,"at":"2026-06-05T00:00:00Z","status":"PASS"}
JSON
}

run_gate() {
  # $1 repo, $2 task_md. Captures combined output + exit code.
  set +e
  GATE_OUT="$(POLARIS_WORKSPACE_ROOT="$ROOT" bash "$GATE" \
    --repo "$1" --task-md "$2" --task-id DP-FX-T1 --extension-id framework-release 2>&1)"
  GATE_RC=$?
  set -e
}

# ===========================================================================
# Case AC7: bundle task — per-task head NOT a strict ancestor of the release
# (workspace) commit. The release commit's diff touches the task's Allowed
# Files. Gate must NOT block: bundle-aware path validates via release-diff ∩
# Allowed Files, and the evidence head accepts the bundle (workspace) head.
# ===========================================================================
{
  WS="$TMPROOT/ac7-ws"
  init_workspace_repo "$WS"
  mkdir -p "$WS/scripts"

  # Per-task branch with its own commit (the original per-task head).
  git -C "$WS" checkout -q -b task/DP-FX-T1-x
  echo perTask >"$WS/scripts/feature-ac7.sh"
  git -C "$WS" add scripts/feature-ac7.sh
  git -C "$WS" commit -qm "per-task work"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Bundle release commit on main: a SEPARATE fresh commit (cherry-pick style)
  # that touches the same Allowed File. The per-task head is NOT its ancestor.
  git -C "$WS" checkout -q main
  mkdir -p "$WS/scripts"
  echo bundled >"$WS/scripts/feature-ac7.sh"
  git -C "$WS" add scripts/feature-ac7.sh
  git -C "$WS" commit -qm "bundle release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Sanity: per-task head is genuinely NOT an ancestor of the release head.
  if git -C "$WS" merge-base --is-ancestor "$TASK_HEAD" "$RELEASE_HEAD" 2>/dev/null; then
    echo "[setup-error] AC7 per-task head unexpectedly an ancestor" >&2
  fi

  TASK_MD="$TMPROOT/ac7-task.md"
  VERIFY_MARKER="$TMPROOT/ac7-verify.json"
  # Evidence head = bundle (workspace) head — must be accepted by bundle-aware
  # evidence comparison even though task_head_sha is the per-task head.
  write_verify_marker "$VERIFY_MARKER" "$RELEASE_HEAD"
  write_extension_task "$TASK_MD" "$TASK_HEAD" "$RELEASE_HEAD" "bundle-DP-FX-v1.0.0" "scripts/feature-ac7.sh"

  run_gate "$WS" "$TASK_MD"
  _assert_eq "$GATE_RC" "0" "AC7 bundle gate exits 0"
  _assert_not_contains "$GATE_OUT" "workspace_commit does not contain task_head_sha" "AC7 no strict-ancestry block"
}

# ===========================================================================
# Case AC10 (positive): NON-bundle (no alias) task whose head IS a strict
# ancestor of the workspace commit must pass exactly as before extraction.
# ===========================================================================
{
  WS="$TMPROOT/ac10-ws"
  init_workspace_repo "$WS"
  mkdir -p "$WS/scripts"

  git -C "$WS" checkout -q -b task/DP-FX-T1-y
  echo work >"$WS/scripts/feature-ac10.sh"
  git -C "$WS" add scripts/feature-ac10.sh
  git -C "$WS" commit -qm "task work"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"
  # Merge into main so the task head IS an ancestor (strict path passes).
  git -C "$WS" checkout -q main
  git -C "$WS" merge -q --no-ff task/DP-FX-T1-y -m "merge task"
  WS_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$TMPROOT/ac10-task.md"
  VERIFY_MARKER="$TMPROOT/ac10-verify.json"
  write_verify_marker "$VERIFY_MARKER" "$TASK_HEAD"
  write_extension_task "$TASK_MD" "$TASK_HEAD" "$WS_HEAD" "" "scripts/feature-ac10.sh"

  run_gate "$WS" "$TASK_MD"
  _assert_eq "$GATE_RC" "0" "AC10 no-alias strict-ancestor gate exits 0"
}

# ===========================================================================
# Case AC10 / AC-NEG5 (negative): NON-bundle (no alias) task whose head is NOT
# contained must keep the ORIGINAL strict ancestry block — byte-equivalent
# behavior, no bundle-aware leniency for no-alias tasks.
# ===========================================================================
{
  WS="$TMPROOT/aneg5-ws"
  init_workspace_repo "$WS"
  mkdir -p "$WS/scripts"

  git -C "$WS" checkout -q -b task/DP-FX-T1-z
  echo perTask >"$WS/scripts/feature-aneg5.sh"
  git -C "$WS" add scripts/feature-aneg5.sh
  git -C "$WS" commit -qm "per-task work"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  git -C "$WS" checkout -q main
  mkdir -p "$WS/scripts"
  echo other >"$WS/scripts/feature-aneg5.sh"
  git -C "$WS" add scripts/feature-aneg5.sh
  git -C "$WS" commit -qm "divergent release (no bundle)"
  WS_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Sanity: head not contained.
  if git -C "$WS" merge-base --is-ancestor "$TASK_HEAD" "$WS_HEAD" 2>/dev/null; then
    echo "[setup-error] AC-NEG5 head unexpectedly an ancestor" >&2
  fi

  TASK_MD="$TMPROOT/aneg5-task.md"
  VERIFY_MARKER="$TMPROOT/aneg5-verify.json"
  write_verify_marker "$VERIFY_MARKER" "$TASK_HEAD"
  write_extension_task "$TASK_MD" "$TASK_HEAD" "$WS_HEAD" "" "scripts/feature-aneg5.sh"

  run_gate "$WS" "$TASK_MD"
  _assert_eq "$GATE_RC" "2" "AC-NEG5 no-alias strict-ancestry blocks"
  _assert_contains "$GATE_OUT" "workspace_commit does not contain task_head_sha" "AC-NEG5 original strict block fires"
}

# ===========================================================================
# Case AC-NEG4: bundle task WITH an alias, but the release commit's diff does
# NOT intersect the task's Allowed Files AND the bundle head does not validate
# the evidence → must still fail-closed (alias alone is not a free pass).
# ===========================================================================
{
  WS="$TMPROOT/aneg4-ws"
  init_workspace_repo "$WS"
  mkdir -p "$WS/scripts"

  git -C "$WS" checkout -q -b task/DP-FX-T1-w
  echo perTask >"$WS/scripts/feature-aneg4.sh"
  git -C "$WS" add scripts/feature-aneg4.sh
  git -C "$WS" commit -qm "per-task work"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # Release commit touches an UNRELATED file (not the task's Allowed File), so
  # release-diff ∩ Allowed Files is EMPTY. The task head is NOT contained.
  git -C "$WS" checkout -q main
  echo unrelated >"$WS/unrelated.txt"
  git -C "$WS" add unrelated.txt
  git -C "$WS" commit -qm "bundle release touching unrelated file"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$TMPROOT/aneg4-task.md"
  VERIFY_MARKER="$TMPROOT/aneg4-verify.json"
  # Evidence head = the per-task head, which is NOT contained in the release —
  # so neither strict ancestry, nor diff-intersection, nor a contained bundle
  # head can validate. Fail-closed expected.
  write_verify_marker "$VERIFY_MARKER" "$TASK_HEAD"
  write_extension_task "$TASK_MD" "$TASK_HEAD" "$RELEASE_HEAD" "bundle-DP-FX-v1.0.0" "scripts/feature-aneg4.sh"

  run_gate "$WS" "$TASK_MD"
  _assert_eq "$GATE_RC" "2" "AC-NEG4 alias + empty diff + uncontained head fails closed"
}

printf '\n[check-local-extension-completion-bundle-aware-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: check-local-extension-completion bundle-aware selftest"
