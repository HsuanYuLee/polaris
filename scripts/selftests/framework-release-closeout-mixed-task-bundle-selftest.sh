#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-293 T2 — framework-release-closeout.sh per-task
#          loop must treat close-parent-spec-if-complete.sh rc==2 (intentional block:
#          active sibling/verification tasks remain) as a soft-block (log + continue)
#          so a mixed bundle (T1,T2,V1) closes out in ONE invocation, while any other
#          non-zero close-parent exit still fails loud.
# Asserts:
#   AC3      bundle (T1,T2,V1) single invocation: the non-terminal implementation
#            tasks' close-parent returns 2 (V1 still active) yet the loop continues,
#            reaches the terminal V1, archives the parent (status IMPLEMENTED), exit 0.
#   AC-NEG2  inject a non-2 close-parent exit (rc=3) -> closeout dies loud.
#   Static   BOTH close-parent call sites in framework-release-closeout.sh route
#            through run_close_parent (so the branch path gets the same soft-block).
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
  if printf '%s' "$1" | grep -qF -- "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: substring not found: %q\n' "$TOTAL" "$3" "$2" >&2
    printf '       in: %s\n' "$1" >&2
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

  # mark-spec-implemented stub: flips frontmatter status to IMPLEMENTED in place.
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

  # Configurable close-parent stub (see header).
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
if [[ "$ARCHIVE" -eq 1 ]]; then
  rc="${POLARIS_TEST_CP_RC_TERMINAL:-0}"
  if [[ "$rc" -eq 0 && -n "$TASK_MD" ]]; then
    parent="$(cd "$(dirname "$TASK_MD")/../.." && pwd)/index.md"
    if [[ -f "$parent" ]]; then
      sed -i.bak 's/^status: .*/status: IMPLEMENTED/' "$parent" && rm -f "$parent.bak"
    fi
  fi
  exit "$rc"
fi
exit "${POLARIS_TEST_CP_RC_NONTERMINAL:-2}"
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

# Build a mixed bundle DP-950: T1 (confirmation), T2 (confirmation), V1 (verify) —
# all no-branch content-delivered, released in one commit. Returns via globals.
build_mixed_bundle() {
  local ws="$1" stub="$2"
  build_stub_scripts_dir "$stub"
  init_workspace_repo "$ws"
  write_task_container "$ws" DP-950 T1 confirmation 'docs-manager/a'
  write_task_container "$ws" DP-950 T2 confirmation 'docs-manager/b'
  write_task_container "$ws" DP-950 V1 verify 'docs-manager/c'
  git -C "$ws" add -A
  git -C "$ws" commit -qm "mixed bundle release"
  RELEASE_HEAD="$(git -C "$ws" rev-parse HEAD)"
  local base="$ws/docs-manager/src/content/docs/specs/design-plans/DP-950-fixture/tasks"
  T1_MD="$base/T1/index.md"; T2_MD="$base/T2/index.md"; V1_MD="$base/V1/index.md"
  PARENT_MD="$ws/docs-manager/src/content/docs/specs/design-plans/DP-950-fixture/index.md"
  valid_verify_marker "$TMPROOT/m-t1.json" DP-950-T1 "$RELEASE_HEAD"
  valid_verify_marker "$TMPROOT/m-t2.json" DP-950-T2 "$RELEASE_HEAD"
  valid_verify_marker "$TMPROOT/m-v1.json" DP-950-V1 "$RELEASE_HEAD"
}

# ===========================================================================
# Case AC3: non-terminal close-parent returns 2 (active V remains) -> soft-block
# continue; terminal V1 archives parent; single invocation exits 0.
# ===========================================================================
{
  WS="$TMPROOT/ac3-ws"; SCRIPTS="$TMPROOT/ac3-scripts"; STUB_LOG="$TMPROOT/ac3.log"
  : >"$STUB_LOG"
  build_mixed_bundle "$WS" "$SCRIPTS"

  export POLARIS_TEST_CP_RC_NONTERMINAL=2
  export POLARIS_TEST_CP_RC_TERMINAL=0
  run_closeout "$SCRIPTS" \
    --task-md "$T1_MD" --verify-evidence "$TMPROOT/m-t1.json" \
    --task-md "$T2_MD" --verify-evidence "$TMPROOT/m-t2.json" \
    --task-md "$V1_MD" --verify-evidence "$TMPROOT/m-v1.json" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"
  unset POLARIS_TEST_CP_RC_NONTERMINAL POLARIS_TEST_CP_RC_TERMINAL

  _assert_eq "$CLOSEOUT_RC" "0" "AC3 mixed bundle single invocation exits 0"
  _assert_contains "$CLOSEOUT_OUT" "parent closeout soft-block for DP-950-T1" "AC3 T1 soft-block logged"
  _assert_contains "$CLOSEOUT_OUT" "parent closeout soft-block for DP-950-T2" "AC3 T2 soft-block logged"
  # All three tasks flipped IMPLEMENTED; parent archived to IMPLEMENTED on terminal V1.
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$T1_MD")" "1" "AC3 T1 IMPLEMENTED"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$T2_MD")" "1" "AC3 T2 IMPLEMENTED"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$V1_MD")" "1" "AC3 V1 IMPLEMENTED"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$PARENT_MD")" "1" "AC3 parent IMPLEMENTED (archived)"
  _assert_contains "$(cat "$STUB_LOG")" "archive=1" "AC3 terminal parent archive invoked"
}

# ===========================================================================
# Case AC-NEG2: a non-2 close-parent exit (rc=3) on the first task must fail loud.
# ===========================================================================
{
  WS="$TMPROOT/neg2-ws"; SCRIPTS="$TMPROOT/neg2-scripts"; STUB_LOG="$TMPROOT/neg2.log"
  : >"$STUB_LOG"
  build_mixed_bundle "$WS" "$SCRIPTS"

  export POLARIS_TEST_CP_RC_NONTERMINAL=3
  export POLARIS_TEST_CP_RC_TERMINAL=0
  run_closeout "$SCRIPTS" \
    --task-md "$T1_MD" --verify-evidence "$TMPROOT/m-t1.json" \
    --task-md "$T2_MD" --verify-evidence "$TMPROOT/m-t2.json" \
    --task-md "$V1_MD" --verify-evidence "$TMPROOT/m-v1.json" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"
  unset POLARIS_TEST_CP_RC_NONTERMINAL POLARIS_TEST_CP_RC_TERMINAL

  [[ "$CLOSEOUT_RC" -ne 0 ]] && NEG2_DIED=1 || NEG2_DIED=0
  _assert_eq "$NEG2_DIED" "1" "AC-NEG2 non-2 close-parent exit fails loud"
  _assert_contains "$CLOSEOUT_OUT" "close-parent-spec-if-complete.sh failed (rc=3)" "AC-NEG2 die message names rc=3"
}

# ===========================================================================
# Static: BOTH close-parent call sites route through run_close_parent (so the
# branch path inherits the same soft-block as the no-branch path exercised above),
# and no bare `bash .../close-parent-spec-if-complete.sh` call site remains.
# ===========================================================================
{
  CLOSEOUT_SRC="$ROOT/scripts/framework-release-closeout.sh"
  _assert_eq "$(grep -c 'run_close_parent "\$task_id"' "$CLOSEOUT_SRC")" "2" "Static: 2 run_close_parent call sites"
  _assert_eq "$(grep -c 'bash "${SCRIPT_DIR}/close-parent-spec-if-complete.sh"' "$CLOSEOUT_SRC")" "1" "Static: only the helper invokes close-parent (no bare loop call site)"
}

printf '\n[framework-release-closeout-mixed-task-bundle-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: framework-release closeout mixed-task bundle selftest"
