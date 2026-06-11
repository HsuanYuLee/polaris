#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-280-T2 (F2 / AC8) framework-release closeout
#          order-independent parent closeout. Asserts that the second
#          (per-task) loop no longer drives close-parent-spec-if-complete.sh
#          once-per-task with --archive-terminal-parent pinned to the LAST
#          task. Instead, ALL tasks are flipped first (flip-all phase), then
#          close-parent-spec-if-complete.sh is invoked EXACTLY ONCE after the
#          loop, always with --archive-terminal-parent. The consequence is that
#          a V / verification task may sit at ANY position in --task-md ordering
#          (first / middle / last) and closeout still completes cleanly and
#          identically:
#            - closeout exits 0 in all three orderings;
#            - close-parent-spec-if-complete.sh is invoked exactly ONCE
#              (not once per task) in each ordering;
#            - that single invocation always carries --archive-terminal-parent;
#            - every task (including the V task) is flipped IMPLEMENTED.
#          A simulated active_verification block stub proves the false-positive
#          per-task block is gone: a stub that BLOCKS (exit non-zero + emits
#          "active verification tasks remain") whenever it observes a sibling V
#          task still active under tasks/ would, under the OLD per-task trigger,
#          fail closeout when the V task is not last. Under the order-independent
#          refactor the stub only runs once after every task is already flipped,
#          so it never blocks regardless of V position.
# Inputs:  none (CLI args ignored). Builds synthetic git repos + specs
#          containers + release commits in a private tmpdir.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never mutates the real workspace.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMPROOT="$(mktemp -d -t fr-closeout-order-selftest.XXXXXX)"
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
# Build a stub scripts/ dir: real closeout + parser + lib, with the
# side-effecting downstream helpers replaced by deterministic stubs. Running the
# REAL closeout with SCRIPT_DIR pointing here exercises the actual flip-all /
# single-close-parent logic while keeping the test hermetic.
#
# The close-parent-spec-if-complete.sh stub SIMULATES the active_verification
# block: it scans the workspace specs tree for any sibling task that is still
# active (status != IMPLEMENTED) under tasks/ whose stem starts with V, and if
# found it emits "active verification tasks remain" and exits 1 (block). Because
# the order-independent refactor flips ALL tasks before invoking close-parent
# once, the stub never sees an active V sibling — proving the per-task-ordering
# false-positive block is gone.
# ---------------------------------------------------------------------------
build_stub_scripts_dir() {
  local dst="$1"
  mkdir -p "$dst/selftests"
  cp -R "$ROOT/scripts/lib" "$dst/lib"
  cp "$ROOT/scripts/framework-release-closeout.sh" "$dst/framework-release-closeout.sh"
  cp "$ROOT/scripts/parse-task-md.sh" "$dst/parse-task-md.sh"
  cp "$ROOT/scripts/resolve-task-base.sh" "$dst/resolve-task-base.sh"
  cp "$ROOT/scripts/engineering-worktree-cleanup.sh" "$dst/engineering-worktree-cleanup.sh" 2>/dev/null || true

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
  # so the parent-close + flip assertions have a real status to observe.
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
suffix="${TASK_ID##*-}"   # e.g. DP-910-T1 -> T1
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

  # close-parent-spec-if-complete stub: records args AND simulates the
  # active_verification block. If any sibling V task is still active (status
  # not IMPLEMENTED) under a tasks/ dir, it BLOCKS (emit + exit 1). Under the
  # order-independent refactor every task is flipped before this runs, so it
  # never blocks.
  cat >"$dst/close-parent-spec-if-complete.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'close-parent-spec-if-complete.sh %s\n' "$*" >>"${POLARIS_STUB_LOG:?}"
TASK_MD=""
WORKSPACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
# Derive the container (parent of the tasks/ tree) from the task path.
container="$TASK_MD"
while [[ -n "$container" && "$(basename "$container")" != "tasks" ]]; do
  container="$(dirname "$container")"
done
container="$(dirname "$container")"   # strip the trailing tasks/
# Scan for any active V sibling: V*/index.md under tasks/ (not pr-release) whose
# status is NOT IMPLEMENTED. Presence => false-positive verification block.
if [[ -d "$container/tasks" ]]; then
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    case "$v" in
      */tasks/pr-release/*) continue ;;
    esac
    if ! grep -q '^status: IMPLEMENTED$' "$v"; then
      printf 'active verification tasks remain: %s\n' "$v" >&2
      exit 1
    fi
  done < <(find "$container/tasks" -path '*/V*/index.md' -type f 2>/dev/null)
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

# Write a no-branch (content-delivered) task at tasks/<suffix>/index.md under a
# shared DP container.
#   $1 repo  $2 dp-id  $3 suffix  $4 task-shape  $5 allowed-file  $6 kind(default T)
write_no_branch_task() {
  local repo="$1" dp="$2" suffix="$3" shape="$4" allowed="$5"
  local kind="${6:-T}"
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

# count how many times close-parent-spec-if-complete.sh appears in the stub log
count_close_parent() {
  grep -c '^close-parent-spec-if-complete.sh' "$STUB_LOG" || true
}

# ===========================================================================
# Order-independence cases: a DP with two implementation tasks (T1, T2) and one
# verify task (V1). Run closeout with the V task in FIRST / MIDDLE / LAST
# position of --task-md ordering. AC8 requires identical clean closeout in all
# three orderings: exit 0, close-parent invoked exactly once (after flip-all),
# always with --archive-terminal-parent, all tasks flipped IMPLEMENTED.
# ===========================================================================
run_ordering_case() {
  local label="$1"; shift
  local -a order=("$@")   # ordered list of suffixes, e.g. V1 T1 T2

  local WS="$TMPROOT/${label}-ws"
  local SCRIPTS="$TMPROOT/${label}-scripts"
  STUB_LOG="$TMPROOT/${label}-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  local dp="DP-910"
  write_no_branch_task "$WS" "$dp" T1 confirmation 'docs-manager/a'
  write_no_branch_task "$WS" "$dp" T2 confirmation 'docs-manager/b'
  write_no_branch_task "$WS" "$dp" V1 verify 'docs-manager/c'
  git -C "$WS" add -A
  git -C "$WS" commit -qm "no-branch tasks release (${label})"
  local RELEASE_HEAD
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  local base="$WS/docs-manager/src/content/docs/specs/design-plans/${dp}-fixture/tasks"
  local -a args=()
  local suffix marker
  for suffix in "${order[@]}"; do
    marker="$TMPROOT/${label}-${suffix}.json"
    valid_verify_marker "$marker" "${dp}-${suffix}" "$RELEASE_HEAD"
    args+=(--task-md "$base/$suffix/index.md" --verify-evidence "$marker")
  done

  run_closeout "$SCRIPTS" "${args[@]}" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "${label} closeout exits 0 (V at this position)"
  _assert_contains "$CLOSEOUT_OUT" "content-delivered" "${label} content-delivered path taken"
  # All three tasks flipped IMPLEMENTED.
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$base/T1/index.md")" "1" "${label} T1 IMPLEMENTED"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$base/T2/index.md")" "1" "${label} T2 IMPLEMENTED"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$base/V1/index.md")" "1" "${label} V1 IMPLEMENTED"
  # close-parent invoked exactly ONCE (flip-all then single close), not per-task.
  _assert_eq "$(count_close_parent)" "1" "${label} close-parent invoked exactly once"
  # That single invocation carries --archive-terminal-parent regardless of order.
  _assert_contains "$(cat "$STUB_LOG")" "--archive-terminal-parent" "${label} terminal parent archive requested"
  # The simulated active_verification block never fired (no block message).
  _assert_not_contains "$CLOSEOUT_OUT" "active verification tasks remain" \
    "${label} no false-positive verification block"
}

run_ordering_case "v-first"  V1 T1 T2
run_ordering_case "v-middle" T1 V1 T2
run_ordering_case "v-last"   T1 T2 V1

printf '\n[framework-release-closeout-order-independent-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: framework-release closeout order-independent selftest"
