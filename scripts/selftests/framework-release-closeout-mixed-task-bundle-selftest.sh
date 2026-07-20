#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-293 T2 — framework-release-closeout.sh treats
#          close-parent-spec-if-complete.sh rc==2 (intentional block: active
#          sibling/verification tasks remain) as a soft-block (log + continue),
#          while any other non-zero close-parent exit still fails loud. Under the
#          DP-280-T2 two-phase closeout the mixed bundle (T1,T2 + a folder-native
#          V1) closes out in ONE invocation: phase 1 flips the listed T tasks,
#          phase 2 auto-enumerates the eligible V1 and archives the parent.
#          DP-303-S5 / DP-354-T2: production refuses a task_kind=V passed as a
#          per-task --task-md, so V1 is driven by the parent-closeout V
#          enumeration (mirroring framework-release-closeout-v-enumeration-
#          selftest.sh), NOT listed via --task-md.
# Asserts:
#   AC3      mixed bundle (T1,T2 via --task-md; V1 folded by V enumeration)
#            single invocation: T1/T2 flip IMPLEMENTED + move to pr-release/, the
#            eligible V1 is folded in via the canonical writer, the parent
#            archives (status IMPLEMENTED), exit 0.
#   AC-NEG2  inject a non-2 terminal close-parent exit (rc=3) -> closeout dies loud.
#   Static   the parent close routes through run_close_parent (rc==2 soft-block,
#            other non-zero dies), and the only bare close-parent invocation lives
#            inside the run_close_parent helper (single per-container call site).
# Inputs:  none (CLI args ignored). Builds a synthetic git repo + specs container +
#          stub scripts dir in a private tmpdir.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never mutates the real workspace.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMPROOT="$(mktemp -d -t fr-closeout-mixed-selftest.XXXXXX)"
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

_assert_no_path() {
  TOTAL=$((TOTAL + 1))
  if [[ -e "$1" ]]; then
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: path should NOT exist: %s\n' "$TOTAL" "$2" "$1" >&2
  else
    PASS=$((PASS + 1))
  fi
}

# ---------------------------------------------------------------------------
# Stub scripts dir: real closeout + parser + lib, with side-effecting downstream
# helpers replaced by deterministic stubs. The close-parent stub is configurable:
#   POLARIS_TEST_CP_RC_NONTERMINAL  exit code for non-archive (non-terminal) calls
#   POLARIS_TEST_CP_RC_TERMINAL     exit code for the --archive-terminal-parent call
# On a terminal call with rc 0 it flips the parent index.md to IMPLEMENTED, mimicking
# a real archive so the test can observe the parent status.
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
                check-local-extension-completion.sh engineering-clean-worktree.sh; do
    cat >"$dst/$helper" <<STUB
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$helper" "\$*" >>"\${POLARIS_STUB_LOG:?}"
exit 0
STUB
    chmod +x "$dst/$helper"
  done

  # REAL canonical writer: the parent-closeout V enumeration folds the bundle V
  # in through mark-spec-implemented.sh (flip IMPLEMENTED + move to pr-release/).
  cp "$ROOT/scripts/mark-spec-implemented.sh" "$dst/mark-spec-implemented.sh"

  # close-parent stub: mirrors the real active_verification block slice (a
  # non-ABANDONED V still active under tasks/ — not pr-release — blocks with
  # exit 2). The terminal (--archive-terminal-parent) exit code is configurable
  # via POLARIS_TEST_CP_RC_TERMINAL so AC-NEG2 can inject a non-2 failure; on a
  # terminal rc 0 it flips the parent index.md to IMPLEMENTED (simulated archive)
  # so the test can observe the parent status.
  cat >"$dst/close-parent-spec-if-complete.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
TASK_MD=""; ARCHIVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="$2"; shift 2 ;;
    --archive-terminal-parent) ARCHIVE=1; shift ;;
    --workspace) shift 2 ;;
    *) shift ;;
  esac
done
printf 'close-parent task-md=%s archive=%s\n' "$TASK_MD" "$ARCHIVE" >>"${POLARIS_STUB_LOG:?}"
container="$TASK_MD"
while [[ -n "$container" && "$(basename "$container")" != "tasks" ]]; do
  container="$(dirname "$container")"
done
container="$(dirname "$container")"
# Active-verification block slice: a non-ABANDONED V sibling still active under
# tasks/ (not pr-release) blocks the parent with exit 2 (the real BLOCK code).
if [[ -d "$container/tasks" ]]; then
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    case "$v" in
      */tasks/pr-release/*) continue ;;
    esac
    if grep -q '^status: ABANDONED$' "$v"; then
      continue
    fi
    printf '[polaris parent-closeout] BLOCKED: active verification tasks remain: %s\n' "$v" >&2
    exit 2
  done < <(find "$container/tasks" \( -path '*/V*/index.md' -o -name 'V*.md' \) -type f 2>/dev/null)
fi
if [[ "$ARCHIVE" -eq 1 ]]; then
  rc="${POLARIS_TEST_CP_RC_TERMINAL:-0}"
  if [[ "$rc" -eq 0 ]]; then
    parent="$container/index.md"
    if [[ -f "$parent" ]]; then
      sed -i.bak 's/^status: .*/status: IMPLEMENTED/' "$parent" && rm -f "$parent.bak"
    fi
  fi
  exit "$rc"
fi
exit 0
STUB
  chmod +x "$dst/close-parent-spec-if-complete.sh"
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

# No-branch content-delivered task at tasks/<suffix>/index.md.
#   $1 repo  $2 dp  $3 suffix  $4 shape  $5 allowed
write_task_container() {
  local repo="$1" dp="$2" suffix="$3" shape="$4" allowed="$5"
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
    printf 'task_kind: %s\n' "${suffix:0:1}"
    printf 'task_shape: %s\n' "$shape"
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
    printf '\n## Allowed Files\n\n'
    printf -- '- `%s`\n' "$allowed"
    printf '\n## Test Environment\n\n- **Level**: static\n'
  } >"$dir/tasks/$suffix/index.md"
}

# Folder-native verify task at tasks/<stem>/index.md carrying an ac_verification
# frontmatter block (the verify-AC writer output shape). The bundle V is folded
# in by the parent-closeout V enumeration, NOT listed via --task-md (production
# refuses task_kind=V per-task — DP-303-S5 / DP-354-T2).
#   $1 container dir  $2 stem (V1)  $3 ac status  $4 human_disposition
#   $5 task frontmatter status (default IN_PROGRESS)
write_v_task() {
  local dir="$1" stem="$2" ac_status="$3" disposition="${4:-}" task_status="${5:-IN_PROGRESS}"
  mkdir -p "$dir/tasks/$stem"
  {
    printf -- '---\n'
    printf 'title: "%s fixture verification task"\n' "$stem"
    printf 'status: %s\n' "$task_status"
    printf 'task_kind: V\n'
    if [[ "$ac_status" != "NONE" ]]; then
      printf 'ac_verification:\n'
      printf '  status: %s\n' "$ac_status"
      if [[ -n "$disposition" ]]; then
        printf '  human_disposition: %s\n' "$disposition"
      fi
      printf '  ac_total: 1\n'
      printf '  ac_pass: 1\n'
    fi
    printf -- '---\n\n'
    printf '# %s fixture\n' "$stem"
  } >"$dir/tasks/$stem/index.md"
}

valid_verify_marker() {
  local path="$1" ticket="$2" head="$3"
  cat >"$path" <<JSON
{"ticket":"${ticket}","head_sha":"${head}","writer":"run-verify-command.sh","exit_code":0,"at":"2026-06-07T00:00:00Z","status":"PASS"}
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

# Build a mixed bundle DP-950: T1 (confirmation), T2 (confirmation) listed via
# --task-md, plus a folder-native V1 (kind=V, ac_verification PASS + passed) that
# is folded in by the parent-closeout V enumeration. All no-branch
# content-delivered, released in one commit. Returns via globals.
build_mixed_bundle() {
  local ws="$1" stub="$2"
  build_stub_scripts_dir "$stub"
  init_workspace_repo "$ws"
  local dir="$ws/docs-manager/src/content/docs/specs/design-plans/DP-950-fixture"
  write_task_container "$ws" DP-950 T1 confirmation 'docs-manager/a'
  write_task_container "$ws" DP-950 T2 confirmation 'docs-manager/b'
  write_v_task "$dir" V1 PASS passed
  git -C "$ws" add -A
  git -C "$ws" commit -qm "mixed bundle release"
  RELEASE_HEAD="$(git -C "$ws" rev-parse HEAD)"
  local base="$dir/tasks"
  T1_MD="$base/T1/index.md"; T2_MD="$base/T2/index.md"; V1_MD="$base/V1/index.md"
  PARENT_MD="$dir/index.md"
  valid_verify_marker "$TMPROOT/m-t1.json" DP-950-T1 "$RELEASE_HEAD"
  valid_verify_marker "$TMPROOT/m-t2.json" DP-950-T2 "$RELEASE_HEAD"
}

# ===========================================================================
# Case AC3: mixed bundle (T1, T2 confirmation via --task-md; folder-native V1
# folded in by parent-closeout V enumeration). Two-phase closeout (DP-280-T2)
# flips T1/T2 IMPLEMENTED in phase 1, then phase 2 auto-enumerates the eligible
# V1, folds it in through the canonical writer (pr-release/ + IMPLEMENTED), and
# archives the parent in a SINGLE invocation, exit 0. Because the V1 is folded
# in BEFORE the single parent close, no active-verification soft-block fires.
# ===========================================================================
{
  WS="$TMPROOT/ac3-ws"; SCRIPTS="$TMPROOT/ac3-scripts"; STUB_LOG="$TMPROOT/ac3.log"
  : >"$STUB_LOG"
  build_mixed_bundle "$WS" "$SCRIPTS"
  DIR="$WS/docs-manager/src/content/docs/specs/design-plans/DP-950-fixture"

  run_closeout "$SCRIPTS" \
    --task-md "$T1_MD" --verify-evidence "$TMPROOT/m-t1.json" \
    --task-md "$T2_MD" --verify-evidence "$TMPROOT/m-t2.json" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "AC3 mixed bundle single invocation exits 0"
  # T1/T2 confirmation tasks flipped IMPLEMENTED + moved to pr-release/.
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$DIR/tasks/pr-release/T1/index.md" || true)" "1" "AC3 T1 IMPLEMENTED"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$DIR/tasks/pr-release/T2/index.md" || true)" "1" "AC3 T2 IMPLEMENTED"
  # V1 folded in by parent-closeout enumeration (canonical writer move).
  _assert_no_path "$DIR/tasks/V1" "AC3 active tasks/V1 folded into pr-release"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$DIR/tasks/pr-release/V1/index.md" || true)" "1" "AC3 V1 IMPLEMENTED"
  # Parent archived to IMPLEMENTED on the single terminal close, no soft-block.
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$PARENT_MD")" "1" "AC3 parent IMPLEMENTED (archived)"
  _assert_not_contains "$CLOSEOUT_OUT" "active verification tasks remain" "AC3 no verification block after fold-in"
  _assert_contains "$(cat "$STUB_LOG")" "archive=1" "AC3 terminal parent archive invoked"
}

# ===========================================================================
# Case AC-NEG2: a non-2 close-parent exit (rc=3) on the terminal parent close
# must fail loud (run_close_parent only soft-blocks rc==2; any other non-zero
# exit dies). Injected via POLARIS_TEST_CP_RC_TERMINAL=3.
# ===========================================================================
{
  WS="$TMPROOT/neg2-ws"; SCRIPTS="$TMPROOT/neg2-scripts"; STUB_LOG="$TMPROOT/neg2.log"
  : >"$STUB_LOG"
  build_mixed_bundle "$WS" "$SCRIPTS"

  export POLARIS_TEST_CP_RC_TERMINAL=3
  run_closeout "$SCRIPTS" \
    --task-md "$T1_MD" --verify-evidence "$TMPROOT/m-t1.json" \
    --task-md "$T2_MD" --verify-evidence "$TMPROOT/m-t2.json" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"
  unset POLARIS_TEST_CP_RC_TERMINAL

  [[ "$CLOSEOUT_RC" -ne 0 ]] && NEG2_DIED=1 || NEG2_DIED=0
  _assert_eq "$NEG2_DIED" "1" "AC-NEG2 non-2 close-parent exit fails loud"
  _assert_contains "$CLOSEOUT_OUT" "close-parent-spec-if-complete.sh failed (rc=3)" "AC-NEG2 die message names rc=3"
}

# ===========================================================================
# Static: the parent close routes through run_close_parent (so rc==2 is a
# soft-block, any other non-zero dies), and the only bare
# `bash .../close-parent-spec-if-complete.sh` invocation lives inside the
# run_close_parent helper itself (two-phase closeout — DP-280-T2 — invokes
# close-parent exactly once per distinct parent container).
# ===========================================================================
{
  CLOSEOUT_SRC="$ROOT/scripts/framework-release-closeout.sh"
  _assert_eq "$(grep -c 'run_close_parent "\$parent_container"' "$CLOSEOUT_SRC")" "1" "Static: single run_close_parent call site (per-container)"
  _assert_eq "$(grep -c 'bash "${SCRIPT_DIR}/close-parent-spec-if-complete.sh"' "$CLOSEOUT_SRC")" "1" "Static: only the helper invokes close-parent (no bare loop call site)"
}

printf '\n[framework-release-closeout-mixed-task-bundle-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: framework-release closeout mixed-task bundle selftest"
