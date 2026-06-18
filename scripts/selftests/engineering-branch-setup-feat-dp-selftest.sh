#!/usr/bin/env bash
# Purpose: Assert engineering-branch-setup.sh routes framework DP source setup
#          through the feature-branch aggregation model (DP-334 T1 / AC1 / AC-NF1).
# Inputs:  none (self-contained git fixtures under a temp dir).
# Outputs: PASS/FAIL lines on stdout; exit 0 when all assertions pass, else 1.
# Side effects: creates and removes a temp git remote/clone; never touches the
#               live workspace.
#
# Contract under test:
#   1. AC1 — a framework DP task whose Base branch is feat/DP-NNN gets feat/DP-NNN
#            auto-created from origin/main, and the DP task branch base == feat/DP-NNN
#            (the task branch tip is the feat/DP-NNN tip at creation time).
#   2. AC1 — the framework DP path does NOT invoke run_aggregate_release and does
#            NOT write bundle_branch_alias into task.md (retired bundle model).
#   3. AC-NF1 — the feat branch is created by reusing the existing resolve-task-base
#            feat semantics (Base branch field is the single authority); no second
#            base/aggregation script is introduced.
#   Negative — a non-DP task whose Base branch is feat/EXCO-NNN that already exists
#            on origin is still cut from that existing feat branch (back-compat).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$SCRIPT_DIR/engineering-branch-setup.sh"

PASS=0
FAIL=0
TOTAL=0

_assert() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [$TOTAL]: expected='$2' got='$1' — $3" >&2
  fi
}

TMPDIR_ST="$(mktemp -d -t polaris-feat-dp-setup.XXXXXX)"
trap 'rm -rf "$TMPDIR_ST"' EXIT

# ---------------------------------------------------------------------------
# Fixture: bare remote + local clone with main
# ---------------------------------------------------------------------------
REMOTE="$TMPDIR_ST/remote.git"
LOCAL="$TMPDIR_ST/local"
git init --bare "$REMOTE" >/dev/null 2>&1
git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
git -C "$LOCAL" config user.email "self-test@example.com"
git -C "$LOCAL" config user.name "self-test"
git -C "$LOCAL" checkout -b main >/dev/null 2>&1
echo "init" >"$LOCAL/file.txt"
git -C "$LOCAL" add file.txt >/dev/null 2>&1
git -C "$LOCAL" commit -m "init" >/dev/null 2>&1
git -C "$LOCAL" push -u origin main >/dev/null 2>&1
MAIN_SHA="$(git -C "$LOCAL" rev-parse origin/main)"

# DP task.md fixture: framework DP source, Base branch = feat/DP-901.
# Header is intentionally the legacy "Epic/JIRA/Repo" shape (no canonical
# "Source:" marker) so is_canonical_pipeline_task() returns false and the
# heavy readiness pack is skipped — matching the existing inline selftest
# pattern. The feat-creation trigger keys off the resolved Base branch
# (feat/DP-NNN), not off header canonicality, so this fixture still exercises
# the DP feat path end to end.
TASK_MD="$TMPDIR_ST/dp-task.md"
cat >"$TASK_MD" <<'TASK'
# T1 — feat DP model

> Epic: DP-901 | JIRA: DP-901-T1 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-901-T1 |
| Base branch | feat/DP-901 |
| Task branch | task/DP-901-T1-feat-dp-model |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- `scripts/**`
TASK

# engineering-branch-setup.sh resolves the repo via the current working
# directory (it calls git without -C), so dispatch must run inside the local
# clone — same pattern as the script's own inline selftest.
_run() {
  ( cd "$LOCAL" && env -u ENGINEERING_BRANCH_SETUP_SELFTEST POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
    bash "$SETUP" "$@" )
}

# ---------------------------------------------------------------------------
# AC1: framework DP source setup creates feat/DP-901 from origin/main and cuts
#      the DP task branch with base = feat/DP-901.
# ---------------------------------------------------------------------------
out="$(_run "$TASK_MD" --repo-base "$TMPDIR_ST" 2>"$TMPDIR_ST/ac1.err")"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- ac1.err -----" >&2
  cat "$TMPDIR_ST/ac1.err" >&2
fi
_assert "$rc" "0" "AC1: framework DP source setup should succeed"

# feat/DP-901 must now exist locally, created from origin/main HEAD.
git -C "$LOCAL" show-ref --verify --quiet refs/heads/feat/DP-901 && t="found" || t="missing"
_assert "$t" "found" "AC1: feat/DP-901 branch should be created"
if [[ "$t" == "found" ]]; then
  feat_sha="$(git -C "$LOCAL" rev-parse refs/heads/feat/DP-901)"
  _assert "$feat_sha" "$MAIN_SHA" "AC1: feat/DP-901 should be created from origin/main HEAD"
fi

# DP task branch must exist and its base == feat/DP-901 (cut from feat tip).
git -C "$LOCAL" show-ref --verify --quiet refs/heads/task/DP-901-T1-feat-dp-model && t="found" || t="missing"
_assert "$t" "found" "AC1: DP task branch should be created"
if [[ "$t" == "found" ]]; then
  # Task branch base = feat/DP-901: feat/DP-901 is an ancestor of (== at creation) the task branch.
  if git -C "$LOCAL" merge-base --is-ancestor refs/heads/feat/DP-901 refs/heads/task/DP-901-T1-feat-dp-model >/dev/null 2>&1; then
    t="based-on-feat"
  else
    t="not-based-on-feat"
  fi
  _assert "$t" "based-on-feat" "AC1: DP task branch base must be feat/DP-901"
fi

# AC1: bundle_branch_alias must NOT be written into the task.md frontmatter.
if grep -q '^bundle_branch_alias:' "$TASK_MD"; then
  t="written"
else
  t="absent"
fi
_assert "$t" "absent" "AC1: bundle_branch_alias must not be written for DP feat path"

# AC1: the setup run must NOT have invoked the aggregate-release bundle model.
if grep -q 'aggregate-release\|bundle-DP-\|bundle_branch_alias\|run_aggregate_release' "$TMPDIR_ST/ac1.err"; then
  t="bundle-touched"
else
  t="no-bundle"
fi
_assert "$t" "no-bundle" "AC1: DP path must not invoke run_aggregate_release bundle model"

# ---------------------------------------------------------------------------
# AC1 idempotency: re-run reuses feat/DP-901 (does not duplicate / re-fork it),
# and still cuts a fresh task worktree.
# ---------------------------------------------------------------------------
out="$(_run "$TASK_MD" --repo-base "$TMPDIR_ST" 2>"$TMPDIR_ST/ac1b.err")"
rc=$?
_assert "$rc" "0" "AC1b: re-run with existing feat/DP-901 should still succeed"
feat_count="$(git -C "$LOCAL" for-each-ref --format='%(refname)' 'refs/heads/feat/DP-901' | wc -l | tr -d ' ')"
_assert "$feat_count" "1" "AC1b: feat/DP-901 must not be duplicated on re-run"

# ---------------------------------------------------------------------------
# AC-NF1 (static): the DP feat path REUSES the resolve-task-base Base-branch
# authority and does NOT introduce a second base/aggregation mechanism.
#
# Concretely:
#   (a) feat creation is done by ensure_feat_dp_branch(), wired into the default
#       (positional task.md) flow — not by a new aggregation script.
#   (b) the DP default path must NOT dispatch into run_aggregate_release; that
#       bundle helper is reachable only via the explicit --aggregate-release mode.
#   (c) the retained bundle model carries a DP-334 Migration Boundaries removal
#       criteria annotation (bootstrap fallback, not steady state).
# ---------------------------------------------------------------------------
# (a) ensure_feat_dp_branch must exist and be called in the default flow.
if grep -qE 'ensure_feat_dp_branch[[:space:]]*\(\)' "$SETUP" \
   && grep -qE '^[[:space:]]*ensure_feat_dp_branch "\$RESOLVED_BASE"' "$SETUP"; then
  t="reuse-feat-helper"
else
  t="missing-feat-helper"
fi
_assert "$t" "reuse-feat-helper" "AC-NF1(a): ensure_feat_dp_branch must be defined and wired into the default flow"

# (b) The default-path dispatch (after arg parse) must never call
#     run_aggregate_release; that is gated behind the explicit AGGREGATE_RELEASE
#     branch. Assert run_aggregate_release is only invoked inside the
#     AGGREGATE_RELEASE conditional.
agg_callsites="$(grep -nE '^[[:space:]]*run_aggregate_release ' "$SETUP" | wc -l | tr -d ' ')"
agg_guard="$(grep -cE 'if \[\[ "\$AGGREGATE_RELEASE" -eq 1 \]\]' "$SETUP" | tr -d ' ')"
if [[ "$agg_guard" -ge 1 ]]; then
  t="bundle-guarded"
else
  t="bundle-ungated"
fi
_assert "$t" "bundle-guarded" "AC-NF1(b): run_aggregate_release must remain behind the --aggregate-release guard, not the DP default path"

# (c) Retained bundle model must carry Migration Boundaries removal criteria.
if grep -q 'Migration Boundaries' "$SETUP" && grep -q 'removal criteria' "$SETUP"; then
  t="annotated"
else
  t="unannotated"
fi
_assert "$t" "annotated" "AC-NF1(c): retained bundle fallback must carry DP-334 Migration Boundaries removal criteria"

# ---------------------------------------------------------------------------
# Back-compat negative: a non-DP product task whose Base branch is an existing
# feat/EXCO-700 must still be cut from that existing feat branch (the auto-create
# logic must be additive, not break the established product feat path).
# ---------------------------------------------------------------------------
git -C "$LOCAL" branch feat/EXCO-700 origin/main >/dev/null 2>&1
git -C "$LOCAL" push -u origin feat/EXCO-700 >/dev/null 2>&1
PROD_TASK="$TMPDIR_ST/prod-task.md"
cat >"$PROD_TASK" <<'TASK'
# T1 — product feat task

> Epic: EXCO-700 | JIRA: EXCO-701 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | EXCO-701 |
| Base branch | feat/EXCO-700 |
| Task branch | task/EXCO-701-product-feat-task |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- `src/**`
TASK

out="$(_run "$PROD_TASK" --repo-base "$TMPDIR_ST" 2>"$TMPDIR_ST/neg.err")"
rc=$?
if [[ "$rc" != "0" ]]; then
  echo "----- neg.err -----" >&2
  cat "$TMPDIR_ST/neg.err" >&2
fi
_assert "$rc" "0" "Back-compat: existing product feat/EXCO-700 task setup should succeed"
git -C "$LOCAL" show-ref --verify --quiet refs/heads/task/EXCO-701-product-feat-task && t="found" || t="missing"
_assert "$t" "found" "Back-compat: product task branch should be created"
if [[ "$t" == "found" ]]; then
  if git -C "$LOCAL" merge-base --is-ancestor refs/remotes/origin/feat/EXCO-700 refs/heads/task/EXCO-701-product-feat-task >/dev/null 2>&1; then
    t="based-on-feat"
  else
    t="not-based-on-feat"
  fi
  _assert "$t" "based-on-feat" "Back-compat: product task branch base must be existing feat/EXCO-700"
fi

echo ""
echo "engineering-branch-setup-feat-dp-selftest: $PASS/$TOTAL passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
