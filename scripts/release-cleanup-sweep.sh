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
# DP-314 D3: the same sweep also retires aged Polaris runtime STATE files —
#          skill-workflow-boundary baselines and stop-gate per-session
#          block-state — so the runtime dir does not accumulate forever (which
#          would keep the stop gate's "any baseline = parked work" signal
#          permanently true). State files whose mtime is older than the
#          retention window (default 30 days) are removed; newer files and any
#          non-.json file are preserved. This runtime retention runs regardless
#          of whether any released DPs were found.
#
# Inputs:  [--workspace <path>]   workspace root (default: resolved specs root)
#          [--dry-run]            (DEFAULT) report planned actions; mutate nothing
#          [--apply]              execute destructive actions (close PR / delete
#                                 remote branch / remove clean worktree / remove
#                                 aged runtime state file)
#          [--json]               also emit a machine-readable JSON report
#          env RELEASE_CLEANUP_SWEEP_GH_BIN  gh binary (default gh). Required for
#                                 the PR path under --apply; missing/unauth =>
#                                 fail-stop with POLARIS_TOOL_MISSING /
#                                 POLARIS_TOOL_AUTH_FAILED (AC7).
#          env POLARIS_RUNTIME_STATE_RETENTION_DAYS  retention window in days for
#                                 runtime state files (DP-314 D3; default 30).
#          env POLARIS_RUNTIME_DIR  runtime dir (default <workspace>/.polaris/runtime).
# Outputs: stdout — human summary (and JSON when --json). exit 0 on a successful
#          sweep; exit 1 on usage / environment failure; exit 2 on a fail-stop
#          contract violation (gh missing/unauth on the destructive path).
# Side effects: with --apply — gh pr close --delete-branch, gh pr comment,
#          git push origin --delete, git worktree remove, rm aged runtime state
#          files. Dirty worktrees and active (not-yet-released, e.g. LOCKED) DPs
#          are NEVER touched (AC-NEG1); non-.json runtime files are never removed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"
# shellcheck source=lib/workspace-config-root.sh
. "$SCRIPT_DIR/lib/workspace-config-root.sh"

GH_BIN="${RELEASE_CLEANUP_SWEEP_GH_BIN:-gh}"

# DP-314 D3: runtime state retention window (days). Files in the runtime state
# dirs older than this are swept. Default 30; env override for review tuning.
RUNTIME_STATE_RETENTION_DAYS="${POLARIS_RUNTIME_STATE_RETENTION_DAYS:-30}"

WORKSPACE_ROOT=""
APPLY=0
EMIT_JSON=0
GH_RESOLVED=0

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

read_workspace_language() {
  local start="${1:-$WORKSPACE_ROOT}"
  local config_path=""
  config_path="$(resolve_workspace_config_path "$start" 2>/dev/null || true)"
  [[ -n "$config_path" && -f "$config_path" ]] || return 0
  awk -F ':' '
    /^[[:space:]]*language[[:space:]]*:/ {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", v)
      if (v != "") print v
      exit
    }
  ' "$config_path"
}

workspace_root_for_language_gate() {
  local start="${1:-$WORKSPACE_ROOT}"
  local root=""
  root="$(resolve_workspace_config_root "$start" 2>/dev/null || true)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$WORKSPACE_ROOT"
  fi
}

is_zh_language() {
  case "$1" in
    zh|zh-*|zh_*) return 0 ;;
    *) return 1 ;;
  esac
}

write_orphan_pr_cleanup_comment() {
  local target="$1"
  local dp_id="$2"
  local language="$3"
  if is_zh_language "$language"; then
    printf '已發版：%s 的孤立 task PR 已由 release-cleanup-sweep 清理。\n' "$dp_id" >"$target"
  else
    printf 'released — orphan task PR cleaned by release-cleanup-sweep for %s.\n' "$dp_id" >"$target"
  fi
}

gate_github_comment_body() {
  local body_file="$1"
  local language=""
  language="$(read_workspace_language "$WORKSPACE_ROOT")"
  local gate_args=(--surface github-comment --body-file "$body_file" --blocking)
  [[ -n "$language" ]] && gate_args+=(--language "$language")
  POLARIS_EXTERNAL_WRITE_WRITER=framework-release:pr-body \
    bash "$SCRIPT_DIR/polaris-external-write-gate.sh" \
      "${gate_args[@]}" >/dev/null
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
      local comment_file
      comment_file="$(mktemp -t release-cleanup-comment.XXXXXX.md)"
      write_orphan_pr_cleanup_comment "$comment_file" "$dp_id" "$(read_workspace_language "$WORKSPACE_ROOT")"
      gate_github_comment_body "$comment_file"
      resolve_gh_bin
      "$GH_BIN" pr comment "$pr_ref" \
        --body-file "$comment_file" \
        >/dev/null 2>&1 \
        || { echo "POLARIS_TOOL_AUTH_FAILED tool=gh owner=delivery hint=failed to comment on PR #${pr_ref} for ${dp_id}" >&2; exit 2; }
      rm -f "$comment_file"
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

# DP-314 D3: retire aged runtime STATE files. Sweeps the skill-workflow-boundary
# baseline dir and the stop-gate block-state dir, removing only *.json files
# whose mtime is older than the retention window. Newer files and any non-.json
# file are preserved (adversarial: the glob must not delete arbitrary files).
# Missing dirs are a no-op (fail-open enumerate) so an empty runtime never errors.
# Increments STATE_ACTIONS_PLANNED for each planned/applied removal.
STATE_ACTIONS_PLANNED=0

sweep_runtime_state() {
  local runtime_dir="${POLARIS_RUNTIME_DIR:-$WORKSPACE_ROOT/.polaris/runtime}"
  # Cutoff epoch: files with mtime strictly older than this are expired.
  local now cutoff
  now="$(date +%s)"
  cutoff=$((now - RUNTIME_STATE_RETENTION_DAYS * 86400))

  local state_dir label f mtime
  for state_dir in \
    "$runtime_dir/skill-workflow-boundary" \
    "$runtime_dir/stop-gate"; do
    label="$(basename "$state_dir")"
    [[ -d "$state_dir" ]] || continue
    for f in "$state_dir"/*.json; do
      # Only target *.json state files; the literal glob (no match) is skipped.
      [[ -e "$f" ]] || continue
      mtime="$(date -r "$f" +%s 2>/dev/null || echo 0)"
      # Age (now - mtime) >= retention window => expired, i.e. mtime <= cutoff.
      # Files newer than the window are preserved. Using <= (not <) makes a
      # 0-day window retire today's files despite whole-second mtime resolution.
      [[ "$mtime" -le "$cutoff" ]] || continue
      STATE_ACTIONS_PLANNED=$((STATE_ACTIONS_PLANNED + 1))
      if [[ "$APPLY" -eq 1 ]]; then
        rm -f "$f" \
          || emit "  WARN: failed to remove runtime state file $f"
        emit "  [apply] removed aged ${label} state: $(basename "$f")"
      else
        emit "  [dry-run] would remove aged ${label} state: $(basename "$f")"
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
collect_released

emit "release-cleanup-sweep (${MODE_LABEL}) — workspace: $WORKSPACE_ROOT"
emit "released DPs: ${#RELEASED_DP_IDS[@]}"

if [[ "${#RELEASED_DP_IDS[@]}" -eq 0 ]]; then
  emit "no released DPs found"
else
  for dp_id in "${RELEASED_DP_IDS[@]}"; do
    dp_dir="$(resolve_dp_dir "$dp_id")"
    emit "$dp_id:"
    sweep_orphan_prs_for_dp "$dp_id" "$dp_dir"
    sweep_remote_branches_for_dp "$dp_id"
    sweep_clean_worktrees_for_dp "$dp_id"
  done
fi

# DP-314 D3: runtime state retention runs regardless of released-DP count.
emit "runtime state retention (window: ${RUNTIME_STATE_RETENTION_DAYS}d):"
sweep_runtime_state

TOTAL_ACTIONS=$((ACTIONS_PLANNED + STATE_ACTIONS_PLANNED))
emit "${TOTAL_ACTIONS} action(s) ${MODE_LABEL} (${ACTIONS_PLANNED} release, ${STATE_ACTIONS_PLANNED} runtime-state)"

if [[ "$EMIT_JSON" -eq 1 ]]; then
  printf '{"mode":"%s","released_dps":%d,"actions":%d,"release_actions":%d,"runtime_state_actions":%d}\n' \
    "$MODE_LABEL" "${#RELEASED_DP_IDS[@]}" "$TOTAL_ACTIONS" "$ACTIONS_PLANNED" "$STATE_ACTIONS_PLANNED"
fi

exit 0
