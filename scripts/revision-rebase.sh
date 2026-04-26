#!/usr/bin/env bash
# scripts/revision-rebase.sh — DP-028 R0 deterministic automation (backlog #3)
#
# 用途：engineering Revision Mode R0 的單一指令封裝。將原本 SKILL.md 內由 AI 自律執行的
# 4 步流程（task.md 定位 → resolve base → fetch + rebase → PR base sync）抽成 deterministic
# script，確保 revision mode 一律先 rebase 後動工，且 PR `baseRefName` 與 task.md snapshot
# 解析後的 base 一致。
#
# 設計準則：
#   - Pure deterministic：無 AI 判斷層；input → output 唯一決定。
#   - Fail-loud：上游 helper（resolve-task-md-by-branch.sh / resolve-task-base.sh）缺失或
#     fetch / rebase / `gh pr edit` 失敗 → exit 1 + stderr message + JSON evidence on stdout。
#   - No bypass env var：要繞過必須改 SKILL.md 規範或直接拒呼 script，不允許 silent skip。
#   - Conflict 不自動解：rebase 衝突時 git 仍處於 rebase-in-progress 狀態（讓人手動處理），
#     script 印 advisory 後 exit 1。
#
# Interface:
#   revision-rebase.sh [--repo PATH] [--task-md PATH] [--pr PR_NUMBER] [-h|--help]
#
# Defaults:
#   --repo     → `git rev-parse --show-toplevel` (cwd)
#   --task-md  → `resolve-task-md-by-branch.sh --current` 結果（在 repo 內執行）
#   --pr       → `gh pr view --json number --jq .number` for current branch
#
# Exit codes:
#   0  rebase clean (or already up-to-date) + PR base 已同步
#   1  conflict / fetch failure / rebase failure / PR base sync failure / helper missing
#   2  usage error
#
# JSON evidence (stdout, single line):
#   {
#     "repo": "<absolute>",
#     "task_md": "<absolute or null>",
#     "resolved_base": "<branch>",
#     "rebase_status": "clean | conflict | not_needed",
#     "pr_number": <int|null>,
#     "pr_base_before": "<branch|null>",
#     "pr_base_after": "<branch|null>",
#     "pr_base_synced": true|false,
#     "legacy_fallback": true|false,
#     "writer": "revision-rebase.sh",
#     "at": "<ISO 8601 UTC>"
#   }
#
# Selftest:
#   bash scripts/revision-rebase-selftest.sh
#
# Consumed by:
#   - .claude/skills/engineering/SKILL.md § R0 Pre-Revision Rebase + PR Base Sync
#   - .agents/skills/engineering/SKILL.md (mirror)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_TASK_MD_BY_BRANCH="$SCRIPT_DIR/resolve-task-md-by-branch.sh"
RESOLVE_TASK_BASE="$SCRIPT_DIR/resolve-task-base.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_err() {
  printf '[revision-rebase] %s\n' "$*" >&2
}

log_info() {
  printf '[revision-rebase] %s\n' "$*" >&2
}

iso_now_utc() {
  # Portable ISO-8601 UTC timestamp (works on macOS BSD date and GNU date).
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

usage() {
  cat >&2 <<'USAGE'
usage: revision-rebase.sh [--repo PATH] [--task-md PATH] [--pr PR_NUMBER]
       revision-rebase.sh -h | --help

Defaults:
  --repo     → git rev-parse --show-toplevel (cwd)
  --task-md  → resolve-task-md-by-branch.sh --current (within repo)
  --pr       → gh pr view --json number --jq .number (current branch)

Exit:
  0 rebase clean + PR base synced
  1 conflict / rebase failure / fetch failure / PR base sync failure / helper missing
  2 usage error

Evidence: single-line JSON on stdout (see header comment for schema).
USAGE
}

# Emit final JSON evidence to stdout. All args are strings; null sentinel "__NULL__"
# becomes JSON null (unquoted).
emit_evidence() {
  local repo="$1"
  local task_md="$2"
  local resolved_base="$3"
  local rebase_status="$4"
  local pr_number="$5"
  local pr_base_before="$6"
  local pr_base_after="$7"
  local pr_base_synced="$8"
  local legacy_fallback="$9"

  python3 - "$repo" "$task_md" "$resolved_base" "$rebase_status" \
    "$pr_number" "$pr_base_before" "$pr_base_after" \
    "$pr_base_synced" "$legacy_fallback" "$(iso_now_utc)" <<'PYEOF'
import json, sys
(_, repo, task_md, resolved_base, rebase_status, pr_number,
 pr_base_before, pr_base_after, pr_base_synced, legacy_fallback, at) = sys.argv

def maybe_null(v):
    return None if v == "__NULL__" else v

def maybe_int_null(v):
    if v == "__NULL__":
        return None
    try:
        return int(v)
    except ValueError:
        return None

def maybe_bool(v):
    return v == "true"

evidence = {
    "repo": repo,
    "task_md": maybe_null(task_md),
    "resolved_base": resolved_base,
    "rebase_status": rebase_status,
    "pr_number": maybe_int_null(pr_number),
    "pr_base_before": maybe_null(pr_base_before),
    "pr_base_after": maybe_null(pr_base_after),
    "pr_base_synced": maybe_bool(pr_base_synced),
    "pr_base_already_aligned": (rebase_status != "conflict") and (pr_base_before == pr_base_after) and pr_base_before not in ("__NULL__", None),
    "legacy_fallback": maybe_bool(legacy_fallback),
    "writer": "revision-rebase.sh",
    "at": at,
}
# pr_base_already_aligned: only meaningful when we attempted PR base sync; for legacy_fallback it's vacuously True
sys.stdout.write(json.dumps(evidence, separators=(",", ":")) + "\n")
PYEOF
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

REPO_ARG=""
TASK_MD_ARG=""
PR_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || { log_err "--repo requires a value"; usage; exit 2; }
      REPO_ARG="$2"; shift 2 ;;
    --task-md)
      [ "$#" -ge 2 ] || { log_err "--task-md requires a value"; usage; exit 2; }
      TASK_MD_ARG="$2"; shift 2 ;;
    --pr)
      [ "$#" -ge 2 ] || { log_err "--pr requires a value"; usage; exit 2; }
      PR_ARG="$2"; shift 2 ;;
    -h|--help)
      usage; exit 2 ;;
    *)
      log_err "unknown arg: $1"; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Step 1: Resolve repo path
# ---------------------------------------------------------------------------

if [ -n "$REPO_ARG" ]; then
  if [ ! -d "$REPO_ARG/.git" ] && [ ! -f "$REPO_ARG/.git" ]; then
    # Allow plain dir if `git -C <path> rev-parse --show-toplevel` succeeds.
    if ! REPO=$(git -C "$REPO_ARG" rev-parse --show-toplevel 2>/dev/null); then
      log_err "--repo path is not a git repo: $REPO_ARG"
      exit 1
    fi
  else
    REPO=$(git -C "$REPO_ARG" rev-parse --show-toplevel 2>/dev/null) || {
      log_err "git -C $REPO_ARG rev-parse failed"; exit 1
    }
  fi
else
  REPO=$(git rev-parse --show-toplevel 2>/dev/null) || {
    log_err "cwd is not inside a git repo (use --repo to specify)"; exit 1
  }
fi

# ---------------------------------------------------------------------------
# Step 2: Resolve task.md (or legacy fallback)
# ---------------------------------------------------------------------------

LEGACY_FALLBACK=false
TASK_MD=""

if [ -n "$TASK_MD_ARG" ]; then
  if [ ! -f "$TASK_MD_ARG" ]; then
    log_err "--task-md not found: $TASK_MD_ARG"
    exit 1
  fi
  TASK_MD="$TASK_MD_ARG"
else
  # Use resolve-task-md-by-branch.sh --current. Helper required on path.
  if [ ! -f "$RESOLVE_TASK_MD_BY_BRANCH" ]; then
    log_err "helper missing: $RESOLVE_TASK_MD_BY_BRANCH"
    exit 1
  fi
  # Run helper in repo context (it scans from cwd by default; use --scan-root REPO).
  TASK_MD_OUT=$("$RESOLVE_TASK_MD_BY_BRANCH" --scan-root "$REPO" --current 2>/dev/null) && rc=0 || rc=$?
  if [ "$rc" = "0" ] && [ -n "$TASK_MD_OUT" ]; then
    # Take first line if multi-match.
    TASK_MD=$(printf '%s\n' "$TASK_MD_OUT" | head -n 1)
  else
    LEGACY_FALLBACK=true
    log_info "no task.md for current branch — entering legacy fallback (PR baseRefName as base, no PR base sync)"
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: Resolve PR number (always — even legacy fallback needs it for base lookup)
# ---------------------------------------------------------------------------

PR_NUMBER="__NULL__"
PR_BASE_BEFORE="__NULL__"

if [ -n "$PR_ARG" ]; then
  PR_NUMBER="$PR_ARG"
else
  # Query gh for current branch's PR.
  if command -v gh >/dev/null 2>&1; then
    PR_VIEW=$(gh -R "$REPO" pr view --json number,baseRefName 2>/dev/null) && rc=0 || rc=$?
    # Fall back to gh pr view (uses cwd → PR for HEAD branch).
    if [ "$rc" != "0" ] || [ -z "$PR_VIEW" ]; then
      PR_VIEW=$(GIT_DIR="$REPO/.git" gh pr view --json number,baseRefName 2>/dev/null || true)
    fi
    if [ -n "$PR_VIEW" ]; then
      PR_NUMBER=$(printf '%s' "$PR_VIEW" | python3 -c 'import json,sys
try:
  d=json.loads(sys.stdin.read() or "{}"); n=d.get("number")
  print(n if n is not None else "")
except Exception:
  pass')
      PR_BASE_BEFORE=$(printf '%s' "$PR_VIEW" | python3 -c 'import json,sys
try:
  d=json.loads(sys.stdin.read() or "{}"); b=d.get("baseRefName") or ""
  print(b)
except Exception:
  pass')
      [ -z "$PR_NUMBER" ] && PR_NUMBER="__NULL__"
      [ -z "$PR_BASE_BEFORE" ] && PR_BASE_BEFORE="__NULL__"
    fi
  fi
fi

# Re-fetch PR_BASE_BEFORE if --pr was supplied explicitly (we still need it).
if [ "$PR_NUMBER" != "__NULL__" ] && [ "$PR_BASE_BEFORE" = "__NULL__" ]; then
  if command -v gh >/dev/null 2>&1; then
    PR_BASE_BEFORE=$(gh -R "$REPO" pr view "$PR_NUMBER" --json baseRefName --jq .baseRefName 2>/dev/null || true)
    [ -z "$PR_BASE_BEFORE" ] && PR_BASE_BEFORE="__NULL__"
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: Compute RESOLVED_BASE
# ---------------------------------------------------------------------------

RESOLVED_BASE=""

if [ "$LEGACY_FALLBACK" = "true" ]; then
  if [ "$PR_BASE_BEFORE" = "__NULL__" ] || [ -z "$PR_BASE_BEFORE" ]; then
    log_err "legacy fallback requires PR baseRefName but none found (no task.md, no PR)"
    emit_evidence "$REPO" "__NULL__" "" "conflict" "$PR_NUMBER" \
      "$PR_BASE_BEFORE" "__NULL__" "false" "true"
    exit 1
  fi
  RESOLVED_BASE="$PR_BASE_BEFORE"
else
  if [ ! -f "$RESOLVE_TASK_BASE" ]; then
    log_err "helper missing: $RESOLVE_TASK_BASE"
    exit 1
  fi
  RESOLVED_BASE=$("$RESOLVE_TASK_BASE" "$TASK_MD" 2>/dev/null) && rc=0 || rc=$?
  if [ "$rc" != "0" ] || [ -z "$RESOLVED_BASE" ]; then
    log_err "resolve-task-base.sh failed for $TASK_MD (exit $rc)"
    exit 1
  fi
fi

log_info "repo=$REPO  task_md=${TASK_MD:-<legacy>}  resolved_base=$RESOLVED_BASE  pr=$PR_NUMBER"

# ---------------------------------------------------------------------------
# Step 5: git fetch origin
# ---------------------------------------------------------------------------

if ! git -C "$REPO" fetch origin >/dev/null 2>&1; then
  log_err "git fetch origin failed in $REPO"
  emit_evidence "$REPO" "${TASK_MD:-__NULL__}" "$RESOLVED_BASE" "conflict" \
    "$PR_NUMBER" "$PR_BASE_BEFORE" "__NULL__" "false" \
    "$([ "$LEGACY_FALLBACK" = "true" ] && echo true || echo false)"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 6: Rebase onto origin/<RESOLVED_BASE>
# ---------------------------------------------------------------------------

# Determine rebase target ref. origin/<RESOLVED_BASE> is the convention; if the
# remote branch doesn't exist, fall back to local <RESOLVED_BASE>.
REBASE_TARGET="origin/$RESOLVED_BASE"
if ! git -C "$REPO" rev-parse --verify --quiet "$REBASE_TARGET" >/dev/null 2>&1; then
  if git -C "$REPO" rev-parse --verify --quiet "$RESOLVED_BASE" >/dev/null 2>&1; then
    REBASE_TARGET="$RESOLVED_BASE"
    log_info "origin/$RESOLVED_BASE not found; falling back to local $RESOLVED_BASE"
  else
    log_err "neither origin/$RESOLVED_BASE nor local $RESOLVED_BASE exists in $REPO"
    emit_evidence "$REPO" "${TASK_MD:-__NULL__}" "$RESOLVED_BASE" "conflict" \
      "$PR_NUMBER" "$PR_BASE_BEFORE" "__NULL__" "false" \
      "$([ "$LEGACY_FALLBACK" = "true" ] && echo true || echo false)"
    exit 1
  fi
fi

# Check if rebase is needed: if HEAD already contains the target as ancestor's tip,
# then `git rebase` is a no-op. We classify "not_needed" when the merge-base
# already equals the target's commit (i.e., target is reachable from HEAD).
REBASE_STATUS="clean"
TARGET_SHA=$(git -C "$REPO" rev-parse "$REBASE_TARGET" 2>/dev/null || echo "")
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "")
MERGE_BASE=$(git -C "$REPO" merge-base "$REBASE_TARGET" HEAD 2>/dev/null || echo "")

if [ -n "$TARGET_SHA" ] && [ "$TARGET_SHA" = "$MERGE_BASE" ]; then
  # target is ancestor of HEAD → branch is up-to-date relative to base.
  REBASE_STATUS="not_needed"
  log_info "rebase not needed: HEAD is already on top of $REBASE_TARGET"
else
  # Run rebase.
  if git -C "$REPO" rebase "$REBASE_TARGET" >/dev/null 2>&1; then
    REBASE_STATUS="clean"
    log_info "rebase onto $REBASE_TARGET PASS"
  else
    # Conflict or other error. git is now in rebase-in-progress state.
    REBASE_STATUS="conflict"
    log_err "Conflict during rebase onto $REBASE_TARGET — manual resolution required"
    log_err "(repo is in rebase-in-progress state; run 'git -C $REPO rebase --abort' to back out)"
    emit_evidence "$REPO" "${TASK_MD:-__NULL__}" "$RESOLVED_BASE" "$REBASE_STATUS" \
      "$PR_NUMBER" "$PR_BASE_BEFORE" "__NULL__" "false" \
      "$([ "$LEGACY_FALLBACK" = "true" ] && echo true || echo false)"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 7: PR base sync (only when not in legacy fallback)
# ---------------------------------------------------------------------------

PR_BASE_AFTER="__NULL__"
PR_BASE_SYNCED="false"

if [ "$LEGACY_FALLBACK" = "true" ]; then
  log_info "legacy fallback — skipping PR base sync"
  PR_BASE_AFTER="$PR_BASE_BEFORE"  # unchanged
elif [ "$PR_NUMBER" = "__NULL__" ] || [ "$PR_BASE_BEFORE" = "__NULL__" ]; then
  log_info "no PR for current branch — skipping PR base sync"
  PR_BASE_AFTER="$PR_BASE_BEFORE"
else
  if [ "$PR_BASE_BEFORE" = "$RESOLVED_BASE" ]; then
    log_info "PR #$PR_NUMBER base already aligned ($PR_BASE_BEFORE == $RESOLVED_BASE) — no edit needed"
    PR_BASE_AFTER="$PR_BASE_BEFORE"
    PR_BASE_SYNCED="false"
  else
    log_info "PR #$PR_NUMBER base drift: $PR_BASE_BEFORE → $RESOLVED_BASE (running gh pr edit --base)"
    if gh -R "$REPO" pr edit "$PR_NUMBER" --base "$RESOLVED_BASE" >/dev/null 2>&1; then
      PR_BASE_AFTER="$RESOLVED_BASE"
      PR_BASE_SYNCED="true"
      log_info "PR base sync PASS"
    else
      log_err "gh pr edit --base failed for PR #$PR_NUMBER (target=$RESOLVED_BASE)"
      log_err "(possible causes: pr-base-gate hook block, missing perms, network)"
      emit_evidence "$REPO" "${TASK_MD:-__NULL__}" "$RESOLVED_BASE" "$REBASE_STATUS" \
        "$PR_NUMBER" "$PR_BASE_BEFORE" "__NULL__" "false" "false"
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Step 8: Emit evidence + exit 0
# ---------------------------------------------------------------------------

emit_evidence "$REPO" "${TASK_MD:-__NULL__}" "$RESOLVED_BASE" "$REBASE_STATUS" \
  "$PR_NUMBER" "$PR_BASE_BEFORE" "$PR_BASE_AFTER" "$PR_BASE_SYNCED" \
  "$([ "$LEGACY_FALLBACK" = "true" ] && echo true || echo false)"

exit 0
