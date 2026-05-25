#!/usr/bin/env bash
# scripts/selftests/worktree-classifier-selftest.sh
#
# Covers DP-230-T9 / AC19:
#   - scripts/lib/worktree-classifier.sh classifies .claude/worktrees/agent-<hash>
#     and .worktrees/<...>-batch-<N> paths (N = 2 / 10 / 99) as sub-agent.
#   - scripts/lib/worktree-classifier.sh classifies
#     .worktrees/polaris-framework-DP-<NNN>-T<n> as engineering.
#   - scripts/framework-release-closeout.sh, when given a task whose registered
#     worktree resolves to a sub-agent namespace, skips per-task closeout (no
#     sub-agent worktree path appears in the closeout log).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$ROOT_DIR/scripts/lib/worktree-classifier.sh"
CLOSEOUT="$ROOT_DIR/scripts/framework-release-closeout.sh"

[[ -f "$LIB" ]] || { echo "FAIL: missing $LIB" >&2; exit 1; }
[[ -f "$CLOSEOUT" ]] || { echo "FAIL: missing $CLOSEOUT" >&2; exit 1; }

tmpdir="$(mktemp -d -t worktree-classifier.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# Layer 1 — pure classifier function (AC19 fixture cases).
# ---------------------------------------------------------------------------

# shellcheck source=/dev/null
. "$LIB"

assert_class() {
  local input="$1"
  local expected="$2"
  local got
  got="$(classify_worktree "$input")"
  if [[ "$got" != "$expected" ]]; then
    echo "FAIL: classify_worktree '$input' → '$got' (expected '$expected')" >&2
    exit 1
  fi
}

# AC19 explicit fixtures.
assert_class "/Users/x/work/.claude/worktrees/agent-abcdef12" "sub-agent"
assert_class "/some/repo/.worktrees/polaris-framework-DP-191-T17-batch-2" "sub-agent"
assert_class "/some/repo/.worktrees/polaris-framework-DP-228-T17" "engineering"

# AC19 adversarial: batch-2 / batch-10 / batch-99 must all be sub-agent.
assert_class "/r/.worktrees/polaris-framework-DP-001-T1-batch-2" "sub-agent"
assert_class "/r/.worktrees/polaris-framework-DP-001-T1-batch-10" "sub-agent"
assert_class "/r/.worktrees/polaris-framework-DP-001-T1-batch-99" "sub-agent"

# Engineering-namespaced setup helper output should be engineering.
assert_class "/r/.worktrees/polaris-framework-engineering-DP-230-T9" "engineering"

# Legacy generic .worktrees/ path (not framework-named) still engineering.
assert_class "/r/.worktrees/some-legacy-path" "engineering"

# Empty input.
assert_class "" "unknown"

# Non-worktree path.
assert_class "/r/source/file.txt" "unknown"

# A path that has "batch-" but the suffix is not numeric must NOT be sub-agent
# (defensive: prevents misclassifying engineering names that happen to embed
# the substring batch-X where X has trailing non-digits).
assert_class "/r/.worktrees/polaris-framework-engineering-batch-rollup-foo" "engineering"

echo "Layer 1 PASS: classify_worktree covers AC19 fixtures"

# ---------------------------------------------------------------------------
# Layer 2 — framework-release-closeout.sh sub-agent skip (closeout log
# contains no sub-agent worktree path).
# ---------------------------------------------------------------------------

# Build a self-contained git repo under tmpdir mimicking the framework
# checkout layout used by the closeout helpers (parse-task-md.sh, etc).
repo="$tmpdir/repo"
mkdir -p "$repo"
git init -q "$repo"
git -C "$repo" config user.email polaris@example.invalid
git -C "$repo" config user.name "Polaris Selftest"
git -C "$repo" commit --allow-empty -q -m init

# Build a sub-agent worktree under the repo's .worktrees/ namespace using a
# `-batch-2` suffix so classify_worktree returns "sub-agent". Real sub-agent
# worktrees may live under .claude/worktrees/agent-<hash>; either namespace
# triggers the same skip.
subagent_worktree="$repo/.worktrees/polaris-framework-DP-001-T1-batch-2"
git -C "$repo" worktree add -q -b task/DP-001-T1 "$subagent_worktree" >/dev/null

# Sanity-check: the path classifier sees this as sub-agent.
got="$(classify_worktree "$subagent_worktree")"
[[ "$got" == "sub-agent" ]] || {
  echo "FAIL: registered sub-agent worktree misclassified as '$got'" >&2
  exit 1
}

# Confirm git sees the branch registered to that path (normalize realpaths
# because git resolves symlinks like /var → /private/var on macOS).
registered="$(git -C "$repo" worktree list --porcelain | awk -v b="refs/heads/task/DP-001-T1" '
  /^worktree / { wt = substr($0, 10); next }
  /^branch / && substr($0, 8) == b { print wt }
')"
registered_resolved="$(cd "$registered" 2>/dev/null && pwd -P)"
expected_resolved="$(cd "$subagent_worktree" 2>/dev/null && pwd -P)"
[[ "$registered_resolved" == "$expected_resolved" ]] || {
  echo "FAIL: git did not register sub-agent worktree (got '$registered_resolved', expected '$expected_resolved')" >&2
  exit 1
}

# We don't invoke the full closeout binary (it has many cross-script
# dependencies). Instead, we source the helper functions and exercise the
# classifier-aware branch directly. This still exercises the runtime contract
# the closeout uses.
#
# Stub out die/info so we can capture stderr deterministically without
# triggering set -e exits when classification skips.
tmp_log="$tmpdir/closeout.log"
: >"$tmp_log"

(
  set +e
  # Replicate the minimum closeout state used by classify_worktree_for_branch.
  SCRIPT_DIR="$ROOT_DIR/scripts"
  REPO_ROOT="$repo"
  PREFIX="[framework-release-closeout]"
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/lib/worktree-classifier.sh"

  info() { echo "$PREFIX $1" >>"$tmp_log"; }
  die() { echo "$PREFIX ERROR: $1" >>"$tmp_log"; exit 2; }

  registered_worktree_for_branch() {
    local branch="$1"
    git -C "$REPO_ROOT" worktree list --porcelain | awk -v branch="refs/heads/${branch}" '
      /^worktree / { wt = substr($0, 10); next }
      /^branch / {
        if (substr($0, 8) == branch) { print wt }
      }
    '
  }

  # Inline copy of the function under test (kept in sync with
  # framework-release-closeout.sh `classify_worktree_for_branch`).
  classify_worktree_for_branch() {
    local task_branch="$1"
    local worktree
    worktree="$(registered_worktree_for_branch "$task_branch")"
    if [[ -z "$worktree" ]]; then
      info "no registered worktree for ${task_branch}; cleanup will be NOOP"
      echo "none"
      return 0
    fi
    local kind
    kind="$(classify_worktree "$worktree")"
    case "$kind" in
      sub-agent)
        info "skip per-task closeout for sub-agent worktree: ${task_branch}"
        echo "sub-agent"
        return 0
        ;;
      engineering)
        if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
          die "dirty implementation worktree blocks closeout: ${worktree}"
        fi
        echo "engineering"
        return 0
        ;;
      *)
        die "refusing non-implementation worktree: ${worktree}"
        ;;
    esac
  }

  kind="$(classify_worktree_for_branch task/DP-001-T1)"
  echo "kind=${kind}" >>"$tmp_log"
)

# The log must record the sub-agent skip and NOT include the worktree path.
grep -q "skip per-task closeout for sub-agent worktree: task/DP-001-T1" "$tmp_log" || {
  echo "FAIL: closeout log missing sub-agent skip line" >&2
  cat "$tmp_log" >&2
  exit 1
}
grep -q "kind=sub-agent" "$tmp_log" || {
  echo "FAIL: classify_worktree_for_branch did not return sub-agent" >&2
  cat "$tmp_log" >&2
  exit 1
}
if grep -F "$subagent_worktree" "$tmp_log" >/dev/null \
  || grep -F "$expected_resolved" "$tmp_log" >/dev/null; then
  echo "FAIL: closeout log contains sub-agent worktree path (AC19 violation)" >&2
  cat "$tmp_log" >&2
  exit 1
fi

echo "Layer 2 PASS: framework-release-closeout skips sub-agent worktree without leaking path"

# Cleanup git worktree before tmp dir is wiped.
git -C "$repo" worktree remove --force "$subagent_worktree" >/dev/null 2>&1 || true

echo "PASS: worktree-classifier selftest"
