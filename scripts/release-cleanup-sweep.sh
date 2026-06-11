#!/usr/bin/env bash
# Purpose: Idempotent release-cleanup sweep (DP-305 D3). Input is "all
#          already-released DPs" — DP spec containers whose canonical RELEASE
#          evidence shows they shipped (frontmatter `status: IMPLEMENTED` and/or
#          relocation under `design-plans/archive/`). For each released DP it
#          cleans the residue the closeout chain may have left behind: orphan
#          task PRs (closed via gh), task/bundle REMOTE branches (deleted via
#          `git push origin --delete`), and the corresponding CLEAN local
#          worktrees. Re-running after --apply yields ZERO changes (idempotent):
#          already-closed PRs, already-absent branches, and already-removed
#          worktrees are skipped.
#
#          This sweep is NOT a second release-status classifier: "released" is
#          derived from the same canonical release evidence the closeout chain
#          already uses (frontmatter IMPLEMENTED / archive location), so there is
#          a single source of release truth (canonical-contract-governance
#          "no special writer paths"). The destructive primitives mirror
#          framework-release-closeout.sh (branch delete, gh pr close, gh
#          fail-stop) rather than inventing a parallel close lane.
#
# Inputs:  [--workspace <path>]   workspace root (default: resolved specs root)
#          [--dry-run]            (DEFAULT) report planned actions; mutate nothing
#          [--apply]              execute destructive actions (close PR / delete
#                                 remote branch / remove clean worktree)
#          [--json]               also emit a machine-readable JSON report
#          env RELEASE_CLEANUP_SWEEP_GH_BIN  gh binary (default gh). Required for
#                                 the PR path under --apply; missing/unauth =>
#                                 fail-stop with POLARIS_TOOL_MISSING /
#                                 POLARIS_TOOL_AUTH_FAILED (AC7).
# Outputs: stdout — human summary (and JSON when --json). exit 0 on a successful
#          sweep; exit 1 on usage / environment failure; exit 2 on a fail-stop
#          contract violation (gh missing/unauth on the destructive path).
# Side effects: with --apply — gh pr close --delete-branch, gh pr comment,
#          git push origin --delete, git worktree remove. Dirty worktrees and
#          active (not-yet-released, e.g. LOCKED) DPs are NEVER touched
#          (AC-NEG1).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

GH_BIN="${RELEASE_CLEANUP_SWEEP_GH_BIN:-gh}"

WORKSPACE_ROOT=""
APPLY=0
EMIT_JSON=0
GH_RESOLVED=0

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  sed -n '2,40p' "$0" >&2
  exit 2
}

# Extract the `status:` field from a spec frontmatter file. Same shape as
# detect-closeout-drift.sh / archive-spec.sh frontmatter_status so the release
# evidence reading stays aligned across the closeout chain.
frontmatter_status() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F ':' '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^status:/ {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

# Extract the deliverable PR url from a task frontmatter file (deliverable.pr_url
# nested key). Returns empty when absent.
task_pr_url() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && /^deliverable:/ { in_deliverable = 1; next }
    in_fm && in_deliverable && /^[[:space:]]+pr_url:/ {
      line = $0
      sub(/^[[:space:]]+pr_url:[[:space:]]*/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
    in_fm && in_deliverable && /^[^[:space:]]/ { in_deliverable = 0 }
  ' "$file"
}

# DP-305 D3/AC7: resolve gh before any destructive PR action, mirroring
# framework-release-closeout.sh resolve_gh_bin. exit 2 (fail-stop) with
# POLARIS_TOOL_MISSING when absent/non-executable, POLARIS_TOOL_AUTH_FAILED when
# present but unauthenticated. Memoized so a multi-DP sweep preflights gh once.
resolve_gh_bin() {
  [[ "$GH_RESOLVED" -eq 1 ]] && return 0
  local candidate="$GH_BIN"
  if [[ "$candidate" != "gh" ]]; then
    if [[ ! -x "$candidate" ]]; then
      echo "POLARIS_TOOL_MISSING tool=gh owner=delivery install_authority=system hint=RELEASE_CLEANUP_SWEEP_GH_BIN is not executable: $candidate" >&2
      exit 2
    fi
  else
    if ! command -v gh >/dev/null 2>&1; then
      echo "POLARIS_TOOL_MISSING tool=gh owner=delivery install_authority=system hint=GitHub CLI (gh) not found on PATH; run 'mise install'" >&2
      exit 2
    fi
  fi
  if ! "$candidate" auth status >/dev/null 2>&1; then
    echo "POLARIS_TOOL_AUTH_FAILED tool=gh owner=delivery install_authority=system hint=GitHub CLI is installed but not authenticated" >&2
    exit 2
  fi
  GH_RESOLVED=1
  return 0
}

# D7 readiness-probe carve-out: read-only PR state query. When gh is unavailable
# for a dry-run we cannot read PR state; return empty so the caller treats the PR
# as state-unknown and does not plan a destructive action it cannot verify.
pr_state() {
  local pr_ref="$1"
  command -v "$GH_BIN" >/dev/null 2>&1 || { [[ -x "$GH_BIN" ]] || return 0; }
  "$GH_BIN" pr view "$pr_ref" --json state -q .state 2>/dev/null \
    || "$GH_BIN" pr view "$pr_ref" 2>/dev/null \
    || return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE_ROOT="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    --json) EMIT_JSON=1; shift ;;
    -h|--help) usage ;;
    *) fail "unexpected argument: $1" ;;
  esac
done

if [[ -z "$WORKSPACE_ROOT" ]]; then
  WORKSPACE_ROOT="$(resolve_specs_workspace_root)" || fail "unable to resolve workspace root"
fi
[[ -d "$WORKSPACE_ROOT" ]] || fail "workspace not found: $WORKSPACE_ROOT"
WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"
SPECS_ROOT="$(resolve_specs_root "$WORKSPACE_ROOT")" || fail "unable to resolve specs root"

DESIGN_PLANS_DIR="$SPECS_ROOT/design-plans"
[[ -d "$DESIGN_PLANS_DIR" ]] || fail "design-plans dir not found: $DESIGN_PLANS_DIR"

MODE_LABEL="dry-run"
[[ "$APPLY" -eq 1 ]] && MODE_LABEL="apply"

# ---------------------------------------------------------------------------
# 1. Enumerate released DPs via canonical release evidence.
#    A DP is "released" when its index.md frontmatter status is IMPLEMENTED, OR
#    its container lives under design-plans/archive/. Active DPs (LOCKED,
#    IN_PROGRESS, DISCUSSION, anything not IMPLEMENTED and not archived) are
#    excluded — they must never be swept (AC-NEG1).
# ---------------------------------------------------------------------------
declare -a RELEASED_DP_IDS=()

collect_released() {
  local index_file dp_dir dp_id status rel
  while IFS= read -r index_file; do
    [[ -n "$index_file" ]] || continue
    dp_dir="$(dirname "$index_file")"
    dp_id="$(basename "$dp_dir")"
    # Normalize the DP id to the DP-NNN token used by branch names.
    dp_id="$(printf '%s\n' "$dp_id" | grep -oE '^DP-[0-9]+' || true)"
    [[ -n "$dp_id" ]] || continue

    rel="${dp_dir#"$DESIGN_PLANS_DIR/"}"
    status="$(frontmatter_status "$index_file")"

    if [[ "$rel" == archive/* || "$status" == "IMPLEMENTED" ]]; then
      RELEASED_DP_IDS+=("$dp_id")
    fi
  done < <(find "$DESIGN_PLANS_DIR" -type f -name index.md 2>/dev/null \
            | grep -E '/DP-[0-9]+[^/]*/index\.md$' || true)

  # De-duplicate (a DP could match both archive location and IMPLEMENTED).
  if [[ "${#RELEASED_DP_IDS[@]}" -gt 0 ]]; then
    local sorted
    sorted="$(printf '%s\n' "${RELEASED_DP_IDS[@]}" | sort -u)"
    RELEASED_DP_IDS=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && RELEASED_DP_IDS+=("$line")
    done <<< "$sorted"
  fi
}

# ---------------------------------------------------------------------------
# 2. For one released DP, collect candidate destructive actions and (under
#    --apply) execute them. Idempotent: each candidate is skipped when already
#    in its terminal state. Returns the count of actions taken (apply) or
#    planned (dry-run) on stdout's last numeric token via the global counter.
# ---------------------------------------------------------------------------
ACTIONS_PLANNED=0

emit() { printf '%s\n' "$*"; }

sweep_remote_branches_for_dp() {
  local dp_id="$1"
  local ref short
  # task/DP-NNN-* and bundle-DP-NNN-* remote branches.
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    short="${ref#refs/heads/}"
    ACTIONS_PLANNED=$((ACTIONS_PLANNED + 1))
    if [[ "$APPLY" -eq 1 ]]; then
      git -C "$WORKSPACE_ROOT" push origin --delete "$short" >/dev/null 2>&1 \
        || emit "  WARN: failed to delete remote branch origin/$short"
      emit "  [apply] deleted remote branch: $short ($dp_id)"
    else
      emit "  [dry-run] would delete remote branch: $short ($dp_id)"
    fi
  done < <(git -C "$WORKSPACE_ROOT" ls-remote --heads origin \
              "refs/heads/task/${dp_id}-*" "refs/heads/bundle-${dp_id}-*" 2>/dev/null \
            | awk '{print $2}')
}

sweep_orphan_prs_for_dp() {
  local dp_id="$1"
  local dp_dir="$2"
  local task_md pr_url pr_ref state
  while IFS= read -r task_md; do
    [[ -n "$task_md" ]] || continue
    pr_url="$(task_pr_url "$task_md")"
    [[ -n "$pr_url" ]] || continue
    pr_ref="${pr_url##*/}"
    [[ -n "$pr_ref" ]] || continue

    state="$(pr_state "$pr_ref")"
    # Idempotent skip: already merged / closed.
    case "$state" in
      MERGED|merged|CLOSED|closed) continue ;;
    esac

    ACTIONS_PLANNED=$((ACTIONS_PLANNED + 1))
    if [[ "$APPLY" -eq 1 ]]; then
      resolve_gh_bin
      "$GH_BIN" pr comment "$pr_ref" \
        --body "released — orphan task PR cleaned by release-cleanup-sweep for ${dp_id}." \
        >/dev/null 2>&1 \
        || { echo "POLARIS_TOOL_AUTH_FAILED tool=gh owner=delivery hint=failed to comment on PR #${pr_ref} for ${dp_id}" >&2; exit 2; }
      "$GH_BIN" pr close "$pr_ref" --delete-branch >/dev/null 2>&1 \
        || { echo "POLARIS_TOOL_AUTH_FAILED tool=gh owner=delivery hint=failed to close PR #${pr_ref} for ${dp_id}" >&2; exit 2; }
      emit "  [apply] closed orphan PR: #${pr_ref} ($dp_id)"
    else
      emit "  [dry-run] would close orphan PR: #${pr_ref} ($dp_id)"
    fi
  done < <(find "$dp_dir" -type f -path '*/tasks/*/index.md' 2>/dev/null)
}

sweep_clean_worktrees_for_dp() {
  local dp_id="$1"
  local line branch
  # git worktree list --porcelain emits "worktree <path>" then "branch <ref>".
  local cur_wt=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur_wt="${line#worktree }" ;;
      "branch "*)
        branch="${line#branch }"
        branch="${branch#refs/heads/}"
        if [[ "$branch" == task/${dp_id}-* || "$branch" == bundle-${dp_id}-* ]]; then
          [[ -d "$cur_wt" ]] || { cur_wt=""; continue; }
          # AC-NEG1 (HARD): never remove a dirty worktree.
          if [[ -n "$(git -C "$cur_wt" status --porcelain 2>/dev/null)" ]]; then
            emit "  [preserve] dirty worktree kept: $cur_wt ($dp_id)"
            cur_wt=""
            continue
          fi
          ACTIONS_PLANNED=$((ACTIONS_PLANNED + 1))
          if [[ "$APPLY" -eq 1 ]]; then
            git -C "$WORKSPACE_ROOT" worktree remove "$cur_wt" >/dev/null 2>&1 \
              || emit "  WARN: failed to remove worktree $cur_wt"
            emit "  [apply] removed clean worktree: $cur_wt ($dp_id)"
          else
            emit "  [dry-run] would remove clean worktree: $cur_wt ($dp_id)"
          fi
        fi
        cur_wt=""
        ;;
      "") cur_wt="" ;;
    esac
  done < <(git -C "$WORKSPACE_ROOT" worktree list --porcelain 2>/dev/null)
}

resolve_dp_dir() {
  local dp_id="$1"
  local d
  d="$(find "$DESIGN_PLANS_DIR" -maxdepth 2 -type d -name "${dp_id}-*" 2>/dev/null | head -n1)"
  printf '%s\n' "$d"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
collect_released

emit "release-cleanup-sweep (${MODE_LABEL}) — workspace: $WORKSPACE_ROOT"
emit "released DPs: ${#RELEASED_DP_IDS[@]}"

if [[ "${#RELEASED_DP_IDS[@]}" -eq 0 ]]; then
  emit "no released DPs found; 0 actions"
  [[ "$EMIT_JSON" -eq 1 ]] && printf '{"mode":"%s","released_dps":0,"actions":0}\n' "$MODE_LABEL"
  exit 0
fi

for dp_id in "${RELEASED_DP_IDS[@]}"; do
  dp_dir="$(resolve_dp_dir "$dp_id")"
  emit "$dp_id:"
  sweep_orphan_prs_for_dp "$dp_id" "$dp_dir"
  sweep_remote_branches_for_dp "$dp_id"
  sweep_clean_worktrees_for_dp "$dp_id"
done

emit "${ACTIONS_PLANNED} action(s) ${MODE_LABEL}"

if [[ "$EMIT_JSON" -eq 1 ]]; then
  printf '{"mode":"%s","released_dps":%d,"actions":%d}\n' \
    "$MODE_LABEL" "${#RELEASED_DP_IDS[@]}" "$ACTIONS_PLANNED"
fi

exit 0
