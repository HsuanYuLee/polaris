#!/usr/bin/env bash
# Purpose: Assert engineering-worktree-cleanup.sh --apply stops worktree-scoped
#          dev-server processes (cwd inside the worktree) before removing the
#          worktree, while NEVER stopping processes whose cwd is outside the
#          worktree (shared colima / nginx / dev.exampleco.com simulation).
# Inputs:  none (self-contained git fixture under mktemp)
# Outputs: stdout PASS summary; exit 0 on PASS, non-zero on FAIL
# Side effects: spawns local controllable `sleep` fixture processes inside a
#               throwaway fixture worktree; kills only those fixture PIDs on
#               teardown. Never touches shared services or other sessions.
#
# Safety discipline (DP-338-T6 / D6): every process this selftest spawns is a
# controllable `sleep` whose cwd is set explicitly to a fixture path. The
# selftest asserts only fixture PIDs are affected; it does not enumerate, signal,
# or otherwise interact with any real colima / nginx / dev server.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${ROOT_DIR}/scripts/engineering-worktree-cleanup.sh"

PASS=0
TOTAL=0
SPAWNED_PIDS=()
TMP=""

cleanup() {
  local p
  for p in "${SPAWNED_PIDS[@]:-}"; do
    [[ -n "$p" ]] || continue
    kill "$p" >/dev/null 2>&1 || true
    wait "$p" >/dev/null 2>&1 || true
  done
  [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"
}
trap cleanup EXIT

assert() {
  TOTAL=$((TOTAL + 1))
  if eval "$1"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $2" >&2
    return 1
  fi
}

if ! command -v lsof >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:lsof — worktree-cleanup-stop-dev-server-selftest requires lsof" >&2
  exit 2
fi

TMP="$(mktemp -d)"
remote="${TMP}/remote.git"
main="${TMP}/repo"
git init --bare "$remote" >/dev/null
git clone "$remote" "$main" >/dev/null 2>&1
git -C "$main" checkout -b main >/dev/null 2>&1
echo init >"${main}/file.txt"
git -C "$main" add file.txt
git -C "$main" commit -m init >/dev/null
git -C "$main" push -u origin main >/dev/null 2>&1
mkdir -p "${main}/.worktrees"

# ---------------------------------------------------------------------------
# Case 1 (AC6): a worktree-scoped dev server (cwd inside the worktree) must be
# stopped on --apply, and the worktree then removed.
# ---------------------------------------------------------------------------
git -C "$main" branch task/DEVSRV-1-clean main
wt1="${main}/.worktrees/repo-engineering-DEVSRV-1"
git -C "$main" worktree add "$wt1" task/DEVSRV-1-clean >/dev/null 2>&1
( cd "$wt1" && exec sleep 120 ) &
dev_pid=$!
SPAWNED_PIDS+=("$dev_pid")
sleep 1

# Sanity: fixture process is detected as living inside the worktree.
assert "kill -0 \"$dev_pid\" 2>/dev/null" "case1: fixture dev-server process must be alive before apply"

set +e
bash "$HELPER" --repo "$main" --identity DEVSRV-1 --apply >"${TMP}/case1.out" 2>&1
rc1=$?
set -e
assert "[[ \"$rc1\" -eq 0 ]]" "case1: --apply must succeed (stop worktree dev server then remove); got rc=$rc1, out=$(cat "${TMP}/case1.out")"
assert "[[ ! -d \"$wt1\" ]]" "case1: worktree must be removed after stopping worktree-scoped dev server"
# Give the signalled process a moment to exit.
sleep 1
assert "! kill -0 \"$dev_pid\" 2>/dev/null" "case1: worktree-scoped dev-server process must be stopped"

# ---------------------------------------------------------------------------
# Case 2 (AC-NEG3): a process whose cwd is OUTSIDE the worktree (shared
# colima/nginx/dev.exampleco.com simulation) must NOT be stopped, even if cleanup
# runs against a different worktree. The worktree removal must still proceed for
# the clean worktree, and the external process must survive.
# ---------------------------------------------------------------------------
git -C "$main" branch task/DEVSRV-2-clean main
wt2="${main}/.worktrees/repo-engineering-DEVSRV-2"
git -C "$main" worktree add "$wt2" task/DEVSRV-2-clean >/dev/null 2>&1

# Shared-service simulation: cwd lives OUTSIDE any worktree (under TMP root).
shared_dir="${TMP}/shared-service"
mkdir -p "$shared_dir"
( cd "$shared_dir" && exec sleep 120 ) &
shared_pid=$!
SPAWNED_PIDS+=("$shared_pid")
sleep 1

set +e
bash "$HELPER" --repo "$main" --identity DEVSRV-2 --apply >"${TMP}/case2.out" 2>&1
rc2=$?
set -e
assert "[[ \"$rc2\" -eq 0 ]]" "case2: --apply on clean worktree must succeed; got rc=$rc2, out=$(cat "${TMP}/case2.out")"
assert "[[ ! -d \"$wt2\" ]]" "case2: clean worktree must be removed"
sleep 1
assert "kill -0 \"$shared_pid\" 2>/dev/null" "case2 (AC-NEG3): process whose cwd is outside the worktree must NOT be stopped"

# ---------------------------------------------------------------------------
# Case 3 (AC-NEG3 dry-run safety): dry-run mode must never stop any process and
# must never remove any worktree, regardless of worktree-scoped processes.
# ---------------------------------------------------------------------------
git -C "$main" branch task/DEVSRV-3-clean main
wt3="${main}/.worktrees/repo-engineering-DEVSRV-3"
git -C "$main" worktree add "$wt3" task/DEVSRV-3-clean >/dev/null 2>&1
( cd "$wt3" && exec sleep 120 ) &
dry_pid=$!
SPAWNED_PIDS+=("$dry_pid")
sleep 1

set +e
bash "$HELPER" --repo "$main" --identity DEVSRV-3 --dry-run >"${TMP}/case3.out" 2>&1
rc3=$?
set -e
assert "[[ \"$rc3\" -eq 0 ]]" "case3: dry-run must exit 0; got rc=$rc3"
assert "[[ -d \"$wt3\" ]]" "case3: dry-run must not remove worktree"
assert "kill -0 \"$dry_pid\" 2>/dev/null" "case3: dry-run must not stop any worktree-scoped process"

echo "worktree-cleanup-stop-dev-server-selftest.sh PASS (${PASS}/${TOTAL})"
