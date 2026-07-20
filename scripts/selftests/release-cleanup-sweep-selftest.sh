#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-305-T4 — idempotent release-cleanup sweep
#          (scripts/release-cleanup-sweep.sh, D3). Asserts:
#   - AC3 (sweep over released DPs): the sweep enumerates "all already-released
#     DPs" (frontmatter status: IMPLEMENTED and/or archived container location,
#     i.e. canonical release evidence — NOT a re-implemented release-status
#     classifier) and, for each, plans cleanup of orphan task PRs +
#     task/bundle REMOTE branches + corresponding CLEAN worktrees. Default mode
#     is --dry-run (reports only, mutates nothing); destructive actions require
#     --apply. The cycle dry-run -> apply -> dry-run ends with ZERO planned
#     changes on the second dry-run (idempotent).
#   - AC-NEG1 (destructive safety, HARD): the sweep must NOT touch the branch /
#     PR of an in-progress (LOCKED, not-yet-released) DP, and must NOT remove a
#     worktree that has uncommitted changes (dirty worktree is always preserved).
#   - AC7 (gh fail-stop): when gh is missing the destructive (--apply) PR path
#     fail-stops with POLARIS_TOOL_MISSING; when gh is present but
#     unauthenticated it fail-stops with POLARIS_TOOL_AUTH_FAILED. Neither
#     swallows the error.
# Inputs:  none (CLI args ignored). Builds a synthetic workspace: a real git
#          repo + a fake "origin" remote carrying task/bundle branches, three
#          fixture DP containers (released / active-LOCKED / dirty-worktree),
#          and a fake gh CLI in a private tmpdir.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never mutates the real workspace and
#          never touches real remote branches / PRs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWEEP="$ROOT/scripts/release-cleanup-sweep.sh"

TMPROOT="$(mktemp -d -t release-cleanup-sweep-selftest.XXXXXX)"
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
    printf '       in: %s\n' "$1" >&2
  else
    PASS=$((PASS + 1))
  fi
}

# ---------------------------------------------------------------------------
# Fake gh CLI: records every invocation to a log, and answers the two queries
# the sweep makes:
#   gh pr view <ref> --json state -q .state   -> prints state line from a state map
#   gh auth status                            -> exit 0 (authenticated)
#   gh pr close <ref> --delete-branch ...     -> records close (mutating)
#   gh pr comment <ref> ...                   -> records comment (mutating)
# State map file: $FAKE_GH_STATE_FILE, lines "<ref> <STATE>".
# ---------------------------------------------------------------------------
make_fake_gh() {
  local bin="$1"
  cat >"$bin" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
log="${FAKE_GH_LOG:?}"
state_file="${FAKE_GH_STATE_FILE:-}"
printf 'gh %s\n' "$*" >>"$log"
case "$1" in
  auth)
    # gh auth status
    exit 0
    ;;
  pr)
    sub="$2"
    case "$sub" in
      view)
        ref="$3"            # bare PR number, e.g. 901
        st="OPEN"
        if [[ -n "$state_file" && -f "$state_file" ]]; then
          while read -r r s; do
            # State map keys are full PR URLs; match on the basename (number).
            [[ "${r##*/}" == "$ref" ]] && st="$s"
          done <"$state_file"
        fi
        printf '%s\n' "$st"
        exit 0
        ;;
      close|comment)
        if [[ "$sub" == "comment" ]]; then
          body_file=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --body-file) body_file="$2"; shift 2 ;;
              *) shift ;;
            esac
          done
          if [[ -n "$body_file" && -f "$body_file" ]]; then
            printf 'body-file-content %s\n' "$(cat "$body_file")" >>"$log"
          fi
        fi
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
GH
  chmod +x "$bin"
}

# ---------------------------------------------------------------------------
# Build a synthetic workspace with a git repo whose `origin` is a local bare
# remote. The remote carries task/bundle branches; the work repo can later
# delete them via `git push origin --delete`.
# ---------------------------------------------------------------------------
write_dp_container() {
  # $1 specs_root  $2 dp_dir_name  $3 status  $4 task_id  $5 pr_url
  local specs="$1" dp="$2" status="$3" task_id="$4" pr_url="$5"
  local dir="$specs/design-plans/$dp"
  mkdir -p "$dir/tasks/T1"
  cat >"$dir/index.md" <<EOF
---
title: "$dp"
status: $status
---

# $dp
EOF
  cat >"$dir/tasks/T1/index.md" <<EOF
---
title: "$task_id T1"
task_kind: T
deliverable:
  pr_url: "$pr_url"
---

# $task_id
EOF
}

setup_workspace() {
  local ws="$1"
  mkdir -p "$ws"
  printf 'language: "zh-TW"\n' >"$ws/workspace-config.yaml"
  local specs="$ws/docs-manager/src/content/docs/specs"
  mkdir -p "$specs/design-plans/archive"

  # Bare remote acting as origin.
  local remote="$TMPROOT/origin.git"
  rm -rf "$remote"
  git init --bare --quiet "$remote"

  git -C "$ws" init --quiet
  git -C "$ws" config user.email selftest@example.com
  git -C "$ws" config user.name selftest
  git -C "$ws" config commit.gpgsign false

  # Fixture 1: RELEASED DP (IMPLEMENTED) -> should be swept.
  write_dp_container "$specs" "DP-901-released" "IMPLEMENTED" "DP-901-T1" \
    "https://github.com/exampleco/exampleco-framework/pull/901"
  # Fixture 2: ACTIVE LOCKED DP -> must be preserved (AC-NEG1).
  write_dp_container "$specs" "DP-902-active" "LOCKED" "DP-902-T1" \
    "https://github.com/exampleco/exampleco-framework/pull/902"
  # Fixture 3: RELEASED DP with a DIRTY worktree -> branch swept but worktree
  # preserved (AC-NEG1). Uses its own task/branch.
  write_dp_container "$specs" "DP-903-released-dirty" "IMPLEMENTED" "DP-903-T1" \
    "https://github.com/exampleco/exampleco-framework/pull/903"

  git -C "$ws" add -A
  git -C "$ws" commit --quiet -m "seed fixtures"
  git -C "$ws" remote add origin "$remote"
  git -C "$ws" push --quiet origin HEAD:refs/heads/main

  # Push task + bundle branches for released DPs (901, 903) and the active DP
  # (902). The sweep should target 901/903 branches but NOT 902's.
  local b
  for b in task/DP-901-T1-impl bundle-DP-901-v9.9.901 \
           task/DP-903-T1-impl \
           task/DP-902-T1-impl bundle-DP-902-v9.9.902; do
    git -C "$ws" push --quiet origin HEAD:"refs/heads/$b"
  done

  # Clean worktree for DP-901 on a task/DP-901-* branch (sweep target; removable).
  # Worktree paths are case-scoped under "$ws" so parallel cases never collide.
  git -C "$ws" worktree add --quiet -b task/DP-901-T1-impl "$ws/wt-901" HEAD

  # Dirty worktree for DP-903 on a task/DP-903-* branch (must be preserved).
  git -C "$ws" worktree add --quiet -b task/DP-903-T1-impl "$ws/wt-903" HEAD
  echo "uncommitted" >"$ws/wt-903/DIRTY.txt"
}

remote_branches() {
  local ws="$1"
  git -C "$ws" ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's#refs/heads/##'
}

# ===========================================================================
# Case A — AC3 + AC-NEG1: dry-run -> apply -> dry-run idempotency, with active
# DP and dirty worktree preserved.
# ===========================================================================
WS_A="$TMPROOT/ws-a"
setup_workspace "$WS_A"

GH_BIN="$TMPROOT/gh-a"
make_fake_gh "$GH_BIN"
GH_LOG="$TMPROOT/gh-a.log"
GH_STATE="$TMPROOT/gh-a-state"
# 901/903 PRs are OPEN (orphan, to be closed); leave 902 OPEN too (active).
cat >"$GH_STATE" <<EOF
https://github.com/exampleco/exampleco-framework/pull/901 OPEN
https://github.com/exampleco/exampleco-framework/pull/903 OPEN
https://github.com/exampleco/exampleco-framework/pull/902 OPEN
EOF

run_sweep() {
  local mode="$1"
  FAKE_GH_LOG="$GH_LOG" FAKE_GH_STATE_FILE="$GH_STATE" \
  RELEASE_CLEANUP_SWEEP_GH_BIN="$GH_BIN" \
    bash "$SWEEP" --workspace "$WS_A" "$mode" --json 2>&1
}

# --- First dry-run: should PLAN actions for 901 + 903, but not 902. ---
: >"$GH_LOG"
DRY1="$(run_sweep --dry-run)" || { echo "dry-run1 unexpected non-zero" >&2; }
_assert_contains "$DRY1" "DP-901" "AC3: dry-run plans released DP-901"
_assert_contains "$DRY1" "DP-903" "AC3: dry-run plans released DP-903"
_assert_not_contains "$DRY1" "DP-902" "AC-NEG1: dry-run never touches active LOCKED DP-902"
_assert_contains "$DRY1" "dry-run" "AC3: default/explicit dry-run labelled"

# dry-run must NOT mutate: remote branches for 901/903 still present.
RB_AFTER_DRY="$(remote_branches "$WS_A")"
_assert_contains "$RB_AFTER_DRY" "task/DP-901-T1-impl" "AC3: dry-run does not delete remote branch"
_assert_contains "$RB_AFTER_DRY" "task/DP-903-T1-impl" "AC3: dry-run does not delete remote branch (903)"
# dry-run must NOT call gh pr close.
DRY_GH="$(cat "$GH_LOG" 2>/dev/null || true)"
_assert_not_contains "$DRY_GH" "pr close" "AC3: dry-run issues no gh pr close"

# --- Apply: execute destructive actions for 901 + 903. ---
: >"$GH_LOG"
APPLY1="$(run_sweep --apply)" || { echo "apply unexpected non-zero" >&2; }
_assert_contains "$APPLY1" "DP-901" "AC3: apply acts on DP-901"
_assert_not_contains "$APPLY1" "DP-902" "AC-NEG1: apply never touches active LOCKED DP-902"

RB_AFTER_APPLY="$(remote_branches "$WS_A")"
_assert_not_contains "$RB_AFTER_APPLY" "task/DP-901-T1-impl" "AC3: apply deletes released task remote branch"
_assert_not_contains "$RB_AFTER_APPLY" "bundle-DP-901-v9.9.901" "AC3: apply deletes released bundle remote branch"
_assert_not_contains "$RB_AFTER_APPLY" "task/DP-903-T1-impl" "AC3: apply deletes released DP-903 task remote branch"
# AC-NEG1: active DP-902 branches survive.
_assert_contains "$RB_AFTER_APPLY" "task/DP-902-T1-impl" "AC-NEG1: active DP-902 task branch preserved"
_assert_contains "$RB_AFTER_APPLY" "bundle-DP-902-v9.9.902" "AC-NEG1: active DP-902 bundle branch preserved"

# apply must have issued gh pr close for 901/903 (orphan PRs), not 902.
APPLY_GH="$(cat "$GH_LOG" 2>/dev/null || true)"
_assert_contains "$APPLY_GH" "pr close 901" "AC3: apply closes orphan PR 901"
_assert_contains "$APPLY_GH" "pr close 903" "AC3: apply closes orphan PR 903"
_assert_contains "$APPLY_GH" "已發版：DP-901" "AC4: orphan cleanup comment follows zh-TW workspace language"
_assert_not_contains "$APPLY_GH" "orphan task PR cleaned" "AC4: orphan cleanup comment no longer uses English default prose"
_assert_not_contains "$APPLY_GH" "pr close 902" "AC-NEG1: apply never closes active DP-902 PR"
_assert_not_contains "$APPLY_GH" "pr view 902" "AC-NEG1: apply never even queries active DP-902 PR"

# AC-NEG1: dirty worktree for 903 preserved; clean worktree for 901 removed.
_assert_eq "$([[ -d "$WS_A/wt-903" ]] && echo present || echo gone)" "present" \
  "AC-NEG1: dirty worktree preserved after apply"
_assert_eq "$([[ -f "$WS_A/wt-903/DIRTY.txt" ]] && echo present || echo gone)" "present" \
  "AC-NEG1: dirty worktree contents preserved"
_assert_eq "$([[ -d "$WS_A/wt-901" ]] && echo present || echo gone)" "gone" \
  "AC3: clean worktree removed after apply"

# --- Second dry-run: idempotent, ZERO planned changes. ---
: >"$GH_LOG"
# After apply, the orphan PRs are closed; reflect that in the state map so the
# sweep sees them as already-closed (idempotent skip).
cat >"$GH_STATE" <<EOF
https://github.com/exampleco/exampleco-framework/pull/901 CLOSED
https://github.com/exampleco/exampleco-framework/pull/903 CLOSED
https://github.com/exampleco/exampleco-framework/pull/902 OPEN
EOF
DRY2="$(run_sweep --dry-run)" || { echo "dry-run2 unexpected non-zero" >&2; }
_assert_contains "$DRY2" "0 action" "AC3: second dry-run reports zero planned changes (idempotent)"
_assert_not_contains "$DRY2" "task/DP-901-T1-impl" "AC3: nothing left to delete for 901 (idempotent)"
_assert_not_contains "$DRY2" "task/DP-903-T1-impl" "AC3: nothing left to delete for 903 (idempotent)"

# --- Re-apply: idempotent, must not error and must not re-delete. ---
: >"$GH_LOG"
APPLY2="$(run_sweep --apply)" || { echo "apply2 unexpected non-zero" >&2; }
APPLY2_GH="$(cat "$GH_LOG" 2>/dev/null || true)"
_assert_contains "$APPLY2" "0 action" "AC3: re-apply reports zero actions (idempotent)"
_assert_not_contains "$APPLY2_GH" "pr close" "AC3: re-apply issues no further gh pr close (idempotent)"

# ===========================================================================
# Case B — AC3: default mode is dry-run (no flag => dry-run, no mutation).
# ===========================================================================
WS_B="$TMPROOT/ws-b"
setup_workspace "$WS_B"
GH_BIN_B="$TMPROOT/gh-b"
make_fake_gh "$GH_BIN_B"
GH_LOG_B="$TMPROOT/gh-b.log"
: >"$GH_LOG_B"
DEFAULT_OUT="$(FAKE_GH_LOG="$GH_LOG_B" FAKE_GH_STATE_FILE="" \
  RELEASE_CLEANUP_SWEEP_GH_BIN="$GH_BIN_B" \
  bash "$SWEEP" --workspace "$WS_B" --json 2>&1)" || true
RB_B="$(remote_branches "$WS_B")"
_assert_contains "$RB_B" "task/DP-901-T1-impl" "AC3: default (no flag) is dry-run, no remote branch deleted"
_assert_contains "$DEFAULT_OUT" "dry-run" "AC3: default mode reports dry-run"

# ===========================================================================
# Case C — AC7: gh missing => POLARIS_TOOL_MISSING on the destructive path.
# ===========================================================================
WS_C="$TMPROOT/ws-c"
setup_workspace "$WS_C"
MISSING_OUT="$(RELEASE_CLEANUP_SWEEP_GH_BIN="$TMPROOT/no-such-gh-binary" \
  bash "$SWEEP" --workspace "$WS_C" --apply --json 2>&1)" && C_EXIT=0 || C_EXIT=$?
_assert_contains "$MISSING_OUT" "POLARIS_TOOL_MISSING" "AC7: gh missing fail-stops with POLARIS_TOOL_MISSING"
_assert_eq "$([[ "$C_EXIT" -ne 0 ]] && echo nonzero || echo zero)" "nonzero" \
  "AC7: gh missing yields non-zero exit"

# ===========================================================================
# Case D — AC7: gh present but unauthenticated => POLARIS_TOOL_AUTH_FAILED.
# ===========================================================================
WS_D="$TMPROOT/ws-d"
setup_workspace "$WS_D"
GH_UNAUTH="$TMPROOT/gh-unauth"
cat >"$GH_UNAUTH" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" ]]; then
  exit 1   # unauthenticated
fi
exit 0
GH
chmod +x "$GH_UNAUTH"
UNAUTH_OUT="$(RELEASE_CLEANUP_SWEEP_GH_BIN="$GH_UNAUTH" \
  bash "$SWEEP" --workspace "$WS_D" --apply --json 2>&1)" && D_EXIT=0 || D_EXIT=$?
_assert_contains "$UNAUTH_OUT" "POLARIS_TOOL_AUTH_FAILED" "AC7: gh unauth fail-stops with POLARIS_TOOL_AUTH_FAILED"
_assert_eq "$([[ "$D_EXIT" -ne 0 ]] && echo nonzero || echo zero)" "nonzero" \
  "AC7: gh unauth yields non-zero exit"

# ===========================================================================
# Case E — DP-314 AC3: runtime state retention sweep. The sweep removes
# skill-workflow-boundary baseline files and stop-gate block-state files older
# than the retention window, while preserving:
#   - files inside the window (not expired),
#   - non-.json files in the same directories (adversarial: glob must not
#     delete arbitrary files),
#   - and never failing on a missing/empty runtime dir (fail-open enumerate).
# The sweep is dry-run by default (reports only) and only deletes under --apply.
# Runtime retention applies even when there are no released DPs to clean.
# ===========================================================================
WS_E="$TMPROOT/ws-e"
mkdir -p "$WS_E"
git -C "$WS_E" init --quiet
git -C "$WS_E" config user.email selftest@example.com
git -C "$WS_E" config user.name selftest
git -C "$WS_E" config commit.gpgsign false
mkdir -p "$WS_E/docs-manager/src/content/docs/specs/design-plans/archive"
git -C "$WS_E" add -A
git -C "$WS_E" commit --quiet --allow-empty -m "seed empty specs"

RUNTIME_E="$WS_E/.polaris/runtime"
BOUNDARY_DIR_E="$RUNTIME_E/skill-workflow-boundary"
STOPGATE_DIR_E="$RUNTIME_E/stop-gate"
mkdir -p "$BOUNDARY_DIR_E" "$STOPGATE_DIR_E"

# Expired (older than 30d retention default): 40 days old.
EXPIRED_TS="$(date -v-40d +%Y%m%d%H%M 2>/dev/null || date -d '40 days ago' +%Y%m%d%H%M)"
# Fresh (inside the window): 1 day old.
FRESH_TS="$(date -v-1d +%Y%m%d%H%M 2>/dev/null || date -d '1 day ago' +%Y%m%d%H%M)"

printf '{"skill":"refinement"}\n' >"$BOUNDARY_DIR_E/refinement-expired.json"
printf '{"skill":"breakdown"}\n' >"$BOUNDARY_DIR_E/breakdown-fresh.json"
printf '{"session_id":"sess-old"}\n' >"$STOPGATE_DIR_E/sess-old.json"
printf '{"session_id":"sess-new"}\n' >"$STOPGATE_DIR_E/sess-new.json"
# Adversarial: a non-.json file in the boundary dir, expired by mtime, must
# survive (the sweep must only target *.json state files).
printf 'not a state file\n' >"$BOUNDARY_DIR_E/README.txt"

touch -t "$EXPIRED_TS" "$BOUNDARY_DIR_E/refinement-expired.json"
touch -t "$FRESH_TS" "$BOUNDARY_DIR_E/breakdown-fresh.json"
touch -t "$EXPIRED_TS" "$STOPGATE_DIR_E/sess-old.json"
touch -t "$FRESH_TS" "$STOPGATE_DIR_E/sess-new.json"
touch -t "$EXPIRED_TS" "$BOUNDARY_DIR_E/README.txt"

# --- Dry-run: plans the two expired deletions, mutates nothing. ---
DRY_E="$(bash "$SWEEP" --workspace "$WS_E" --dry-run --json 2>&1)" || true
_assert_contains "$DRY_E" "refinement-expired.json" "AC3: dry-run plans expired baseline removal"
_assert_contains "$DRY_E" "sess-old.json" "AC3: dry-run plans expired stop-gate state removal"
_assert_not_contains "$DRY_E" "breakdown-fresh.json" "AC3: dry-run does not plan fresh baseline"
_assert_not_contains "$DRY_E" "sess-new.json" "AC3: dry-run does not plan fresh stop-gate state"
_assert_eq "$([[ -f "$BOUNDARY_DIR_E/refinement-expired.json" ]] && echo present || echo gone)" "present" \
  "AC3: dry-run does not delete expired baseline"
_assert_eq "$([[ -f "$STOPGATE_DIR_E/sess-old.json" ]] && echo present || echo gone)" "present" \
  "AC3: dry-run does not delete expired stop-gate state"

# --- Apply: removes only the expired .json state files. ---
bash "$SWEEP" --workspace "$WS_E" --apply --json >/dev/null 2>&1 || true
_assert_eq "$([[ -f "$BOUNDARY_DIR_E/refinement-expired.json" ]] && echo present || echo gone)" "gone" \
  "AC3: apply removes expired baseline"
_assert_eq "$([[ -f "$STOPGATE_DIR_E/sess-old.json" ]] && echo present || echo gone)" "gone" \
  "AC3: apply removes expired stop-gate state"
_assert_eq "$([[ -f "$BOUNDARY_DIR_E/breakdown-fresh.json" ]] && echo present || echo gone)" "present" \
  "AC3: apply preserves fresh baseline (inside window)"
_assert_eq "$([[ -f "$STOPGATE_DIR_E/sess-new.json" ]] && echo present || echo gone)" "present" \
  "AC3: apply preserves fresh stop-gate state (inside window)"
_assert_eq "$([[ -f "$BOUNDARY_DIR_E/README.txt" ]] && echo present || echo gone)" "present" \
  "AC3 (adversarial): apply never deletes a non-.json file even when expired"

# --- Idempotent re-apply: nothing left to remove. ---
APPLY_E2="$(bash "$SWEEP" --workspace "$WS_E" --apply --json 2>&1)" || true
_assert_not_contains "$APPLY_E2" "refinement-expired.json" "AC3: re-apply has nothing to remove (idempotent)"
_assert_not_contains "$APPLY_E2" "sess-old.json" "AC3: re-apply has nothing to remove (idempotent, stop-gate)"

# --- Retention window override via env: a 0-day window expires everything. ---
WS_F="$TMPROOT/ws-f"
mkdir -p "$WS_F/docs-manager/src/content/docs/specs/design-plans/archive"
git -C "$WS_F" init --quiet
git -C "$WS_F" config user.email selftest@example.com
git -C "$WS_F" config user.name selftest
git -C "$WS_F" config commit.gpgsign false
git -C "$WS_F" add -A
git -C "$WS_F" commit --quiet --allow-empty -m "seed empty specs"
BOUNDARY_DIR_F="$WS_F/.polaris/runtime/skill-workflow-boundary"
mkdir -p "$BOUNDARY_DIR_F"
printf '{"skill":"engineering"}\n' >"$BOUNDARY_DIR_F/engineering-today.json"
POLARIS_RUNTIME_STATE_RETENTION_DAYS=0 \
  bash "$SWEEP" --workspace "$WS_F" --apply --json >/dev/null 2>&1 || true
_assert_eq "$([[ -f "$BOUNDARY_DIR_F/engineering-today.json" ]] && echo present || echo gone)" "gone" \
  "AC3: POLARIS_RUNTIME_STATE_RETENTION_DAYS=0 expires even a today baseline"

# --- Missing runtime dir: sweep must not error (fail-open enumerate). ---
WS_G="$TMPROOT/ws-g"
mkdir -p "$WS_G/docs-manager/src/content/docs/specs/design-plans/archive"
git -C "$WS_G" init --quiet
git -C "$WS_G" config user.email selftest@example.com
git -C "$WS_G" config user.name selftest
git -C "$WS_G" config commit.gpgsign false
git -C "$WS_G" add -A
git -C "$WS_G" commit --quiet --allow-empty -m "seed empty specs"
bash "$SWEEP" --workspace "$WS_G" --apply --json >/dev/null 2>&1 && G_EXIT=0 || G_EXIT=$?
_assert_eq "$([[ "$G_EXIT" -eq 0 ]] && echo zero || echo nonzero)" "zero" \
  "AC3: sweep with no runtime dir exits 0 (fail-open enumerate)"

# ---------------------------------------------------------------------------
printf '\n=== release-cleanup-sweep selftest: %d passed, %d failed (of %d) ===\n' \
  "$PASS" "$FAIL" "$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
