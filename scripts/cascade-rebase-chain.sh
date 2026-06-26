#!/usr/bin/env bash
# Purpose: rebase a task branch chain (chain mode) OR rebase the current owner
#   branch onto an upstream ref and run the re-verify delivery-flow step (--onto
#   mode), so that "rebase" is never an isolated git mutation but a complete
#   rebase -> re-verify -> rewrite-task.md-head/block delivery step.
# Inputs:
#   chain mode: --repo <repo> --task-md <task.md> [--skip-missing-last]
#   --onto mode: --repo <repo> --onto <ref> [--task-md <task.md> ...]
# Outputs: stdout JSON evidence; exit 0 PASS / 1 generic failure / 2 usage error.
#
# Chain mode (unchanged; engineering-branch-setup + revision-rebase depend on it):
#   Reads task.md `Branch chain` through resolve-branch-chain.sh. For a chain like:
#     develop -> feat/EPIC-478-demo -> task/TASK-3711-a -> task/TASK-3900-b
#   it rebases each downstream branch onto the latest upstream in order:
#     feat/EPIC-478-demo onto origin/develop
#     task/TASK-3711-a onto origin/feat/EPIC-478-demo
#     task/TASK-3900-b onto origin/task/TASK-3711-a
#   Intermediate branches are pushed with --force-with-lease after a clean
#   rebase, because later PRs use those remote branches as their GitHub base.
#
# --onto mode (DP-360 D5 / AC5, aligned with framework-release SKILL.md):
#   Rebases the repo's CURRENT branch (the feat/DP-NNN owner branch the caller
#   has checked out) onto <ref> (feat -> main). After a clean rebase it executes
#   the re-verify delivery-flow step for every task.md whose recorded
#   deliverable.head_sha is reachable from the pre-rebase head:
#     1. re-run the verify gate at the new head (run-verify-command.sh)
#     2. rewrite that task.md `deliverable` head_sha + state to the new head
#        (write-deliverable.sh)
#   Because the rebase rewrites SHAs, the pre-rebase head's delivery evidence
#   would otherwise be orphaned (root bug #6: local_extension_completion_failed).
#   Rebuilding the task.md head/block keeps the delivered head fresh; with the
#   head-sha-keyed completion-gate marker retired (DP-360 T7) there is no frozen
#   marker left to orphan, so root bug #6 is structurally absent (AC4 RED->GREEN).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_BRANCH_CHAIN="$SCRIPT_DIR/resolve-branch-chain.sh"
RUN_VERIFY_COMMAND="$SCRIPT_DIR/run-verify-command.sh"
WRITE_DELIVERABLE="$SCRIPT_DIR/write-deliverable.sh"
REVERIFY_FILE=""

log() {
  printf '[cascade-rebase-chain] %s\n' "$*" >&2
}

usage() {
  cat >&2 <<'USAGE'
usage:
  cascade-rebase-chain.sh --repo <repo> --task-md <task.md> [--skip-missing-last]
  cascade-rebase-chain.sh --repo <repo> --onto <ref> [--task-md <task.md> ...]

Modes:
  chain mode (--task-md, no --onto): rebase the task.md Branch chain upstream->down.
  --onto mode (--onto <ref>): rebase the current branch onto <ref> (feat->main)
    and run the re-verify delivery-flow step (re-run gate + rewrite task.md
    deliverable head/block) at the rebased head.

Exit:
  0 chain rebased / onto rebased + re-verify clean (or already up to date)
  1 fetch / rebase / push / re-verify failure
  2 usage error
USAGE
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

emit_evidence() {
  local repo="$1" task_md="$2" status="$3" chain_file="$4" steps_file="$5"
  python3 - "$repo" "$task_md" "$status" "$chain_file" "$steps_file" <<'PY'
import json, sys
repo, task_md, status, chain_file, steps_file = sys.argv[1:]
with open(chain_file, "r", encoding="utf-8") as f:
    chain = [line.strip() for line in f if line.strip()]
steps = []
try:
    with open(steps_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                steps.append(json.loads(line))
except FileNotFoundError:
    pass
print(json.dumps({
    "repo": repo,
    "task_md": task_md,
    "branch_chain": chain,
    "status": status,
    "steps": steps,
    "writer": "cascade-rebase-chain.sh",
}, separators=(",", ":")))
PY
}

# Emit --onto mode evidence: rebased branch + re-verified task.md head/block list.
emit_onto_evidence() {
  local repo="$1" onto_ref="$2" branch="$3" status="$4" reverify_file="$5"
  python3 - "$repo" "$onto_ref" "$branch" "$status" "$reverify_file" <<'PY'
import json, sys
repo, onto_ref, branch, status, reverify_file = sys.argv[1:]
reverified = []
try:
    with open(reverify_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                reverified.append(json.loads(line))
except FileNotFoundError:
    pass
print(json.dumps({
    "repo": repo,
    "mode": "onto",
    "onto_ref": onto_ref,
    "branch": branch,
    "status": status,
    "reverified": reverified,
    "writer": "cascade-rebase-chain.sh",
}, separators=(",", ":")))
PY
}

# Resolve the task.md files whose deliverable.head_sha is reachable from a given
# pre-rebase head. Caller-supplied --task-md paths take precedence (explicit
# scope); otherwise scan the repo's design-plan specs tree for task.md files
# whose recorded deliverable.head_sha is an ancestor of the pre-rebase head.
resolve_onto_task_mds() {
  local repo="$1" pre_head="$2"
  if [ "${#ONTO_TASK_MDS[@]}" -gt 0 ]; then
    local p
    for p in "${ONTO_TASK_MDS[@]}"; do
      [ -f "$p" ] && printf '%s\n' "$p"
    done
    return 0
  fi
  local specs_root="$repo/docs-manager/src/content/docs/specs/design-plans"
  [ -d "$specs_root" ] || return 0
  local candidate head
  while IFS= read -r candidate; do
    head=$(awk '
      /^deliverable:/ { in_blk = 1; next }
      in_blk && /^[^[:space:]]/ { in_blk = 0 }
      in_blk && /^[[:space:]]+head_sha:/ {
        v = $0
        sub(/^[[:space:]]+head_sha:[[:space:]]*/, "", v)
        gsub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    ' "$candidate")
    [ -n "$head" ] || continue
    # Only re-verify task.md whose recorded delivered head is reachable from the
    # pre-rebase head (i.e. belongs to the branch being rebased).
    if git -C "$repo" merge-base --is-ancestor "$head" "$pre_head" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
    fi
  done < <(find "$specs_root" -type f -name 'index.md' 2>/dev/null; find "$specs_root" -type f -name 'T*.md' 2>/dev/null)
}

# --onto mode: rebase the current branch onto <ref>, then run the re-verify
# delivery-flow step (re-run gate + rewrite task.md deliverable head/block) at
# the new head for every in-scope task.md.
run_onto_mode() {
  local pre_head branch pr_state
  branch=$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [ -z "$branch" ]; then
    log "--onto mode requires the repo to be on a named branch (detached HEAD)"
    exit 1
  fi
  if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
    log "working tree is dirty; refusing to rebase --onto"
    exit 1
  fi
  # REVERIFY_FILE is global so the EXIT trap (which runs in global scope after
  # `exit $?` returns from this function) can resolve it under `set -u`.
  REVERIFY_FILE=$(mktemp -t polaris-onto-reverify.XXXXXX)
  trap 'rm -f "${REVERIFY_FILE:-}"' EXIT
  local reverify_file="$REVERIFY_FILE"

  git -C "$REPO" fetch origin >/dev/null 2>&1 || true

  if ! git -C "$REPO" rev-parse --verify --quiet "$ONTO_REF" >/dev/null 2>&1; then
    log "--onto ref not found: $ONTO_REF"
    emit_onto_evidence "$REPO" "$ONTO_REF" "$branch" "missing_onto_ref" "$reverify_file"
    exit 1
  fi

  pre_head=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)
  if [ -z "$pre_head" ]; then
    log "git rev-parse HEAD failed in $REPO"
    exit 1
  fi

  local onto_sha merge_base
  onto_sha=$(git -C "$REPO" rev-parse "$ONTO_REF" 2>/dev/null || true)
  merge_base=$(git -C "$REPO" merge-base "$ONTO_REF" "$branch" 2>/dev/null || true)
  if [ -z "$onto_sha" ] || [ "$onto_sha" != "$merge_base" ]; then
    log "rebasing $branch onto $ONTO_REF"
    if ! git -C "$REPO" rebase "$ONTO_REF" "$branch" >/dev/null 2>&1; then
      log "conflict while rebasing $branch onto $ONTO_REF"
      emit_onto_evidence "$REPO" "$ONTO_REF" "$branch" "conflict" "$reverify_file"
      git -C "$REPO" rebase --abort >/dev/null 2>&1 || true
      exit 1
    fi
  fi

  # Re-verify delivery-flow step at the new (rebased) head.
  local new_head task_md task_pr_url
  new_head=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)
  while IFS= read -r task_md; do
    [ -n "$task_md" ] || continue
    log "re-verify at new head $new_head for $task_md"
    if ! bash "$RUN_VERIFY_COMMAND" --task-md "$task_md" --repo "$REPO" >&2; then
      log "re-verify gate failed at new head for $task_md"
      emit_onto_evidence "$REPO" "$ONTO_REF" "$branch" "reverify_failed" "$reverify_file"
      exit 1
    fi
    # Preserve the existing PR url/state from the deliverable block; only the
    # head_sha must move to the rebased head.
    task_pr_url=$(awk '
      /^deliverable:/ { in_blk = 1; next }
      in_blk && /^[^[:space:]]/ { in_blk = 0 }
      in_blk && /^[[:space:]]+pr_url:/ {
        v = $0; sub(/^[[:space:]]+pr_url:[[:space:]]*/, "", v)
        gsub(/[[:space:]]+$/, "", v); print v; exit
      }
    ' "$task_md")
    pr_state=$(awk '
      /^deliverable:/ { in_blk = 1; next }
      in_blk && /^[^[:space:]]/ { in_blk = 0 }
      in_blk && /^[[:space:]]+pr_state:/ {
        v = $0; sub(/^[[:space:]]+pr_state:[[:space:]]*/, "", v)
        gsub(/[[:space:]]+$/, "", v); print v; exit
      }
    ' "$task_md")
    [ -n "$pr_state" ] || pr_state="OPEN"
    if [ -z "$task_pr_url" ]; then
      log "task.md has no deliverable.pr_url to preserve: $task_md"
      emit_onto_evidence "$REPO" "$ONTO_REF" "$branch" "missing_pr_url" "$reverify_file"
      exit 1
    fi
    if ! bash "$WRITE_DELIVERABLE" "$task_md" "$task_pr_url" "$pr_state" "$new_head" >&2; then
      log "write-deliverable failed rewriting head/block for $task_md"
      emit_onto_evidence "$REPO" "$ONTO_REF" "$branch" "write_deliverable_failed" "$reverify_file"
      exit 1
    fi
    printf '{"task_md":%s,"head_sha":%s,"pr_url":%s,"pr_state":%s}\n' \
      "$(json_escape "$task_md")" "$(json_escape "$new_head")" \
      "$(json_escape "$task_pr_url")" "$(json_escape "$pr_state")" >> "$reverify_file"
  done < <(resolve_onto_task_mds "$REPO" "$pre_head")

  emit_onto_evidence "$REPO" "$ONTO_REF" "$branch" "ok" "$reverify_file"
  return 0
}

REPO=""
TASK_MD=""
ONTO_REF=""
SKIP_MISSING_LAST=false
ONTO_TASK_MDS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || { log "--repo requires a value"; usage; exit 2; }
      REPO="$2"; shift 2 ;;
    --task-md)
      [ "$#" -ge 2 ] || { log "--task-md requires a value"; usage; exit 2; }
      TASK_MD="$2"; ONTO_TASK_MDS+=("$2"); shift 2 ;;
    --onto)
      [ "$#" -ge 2 ] || { log "--onto requires a value"; usage; exit 2; }
      ONTO_REF="$2"; shift 2 ;;
    --skip-missing-last)
      SKIP_MISSING_LAST=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      log "unknown arg: $1"; usage; exit 2 ;;
  esac
done

if [ -z "$REPO" ]; then
  usage
  exit 2
fi
if ! REPO=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null); then
  log "--repo is not a git repo: $REPO"
  exit 2
fi

# --onto and chain mode are mutually exclusive on the chain-resolving --task-md:
# --onto rebases the current branch; chain mode resolves a Branch chain from a
# single --task-md. With --onto, --task-md is optional and may repeat to scope
# which deliverable blocks get re-verified.
if [ -n "$ONTO_REF" ]; then
  run_onto_mode
  exit $?
fi

if [ -z "$TASK_MD" ]; then
  usage
  exit 2
fi
if [ ! -f "$TASK_MD" ]; then
  log "task_md not found: $TASK_MD"
  exit 2
fi
if [ ! -x "$RESOLVE_BRANCH_CHAIN" ]; then
  # apply_patch creates the file without executable bit in some environments.
  if [ -f "$RESOLVE_BRANCH_CHAIN" ]; then
    :
  else
    log "helper missing: $RESOLVE_BRANCH_CHAIN"
    exit 1
  fi
fi

CHAIN_FILE=$(mktemp -t polaris-branch-chain.XXXXXX)
STEPS_FILE=$(mktemp -t polaris-branch-chain-steps.XXXXXX)
trap 'rm -f "$CHAIN_FILE" "$STEPS_FILE"' EXIT

if ! bash "$RESOLVE_BRANCH_CHAIN" "$TASK_MD" >"$CHAIN_FILE"; then
  log "resolve-branch-chain failed"
  exit 1
fi

CHAIN_LEN=$(wc -l < "$CHAIN_FILE" | tr -d ' ')
if [ "$CHAIN_LEN" -lt 2 ]; then
  log "branch chain must have at least two entries"
  exit 1
fi

ORIG_BRANCH=$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || true)

if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
  log "working tree is dirty; refusing to checkout/rebase branch chain"
  exit 1
fi

if ! git -C "$REPO" fetch origin >/dev/null 2>&1; then
  log "git fetch origin failed"
  emit_evidence "$REPO" "$TASK_MD" "fetch_failed" "$CHAIN_FILE" "$STEPS_FILE"
  exit 1
fi

line_at() {
  sed -n "${1}p" "$CHAIN_FILE"
}

parse_table_field() {
  local field="$1"
  local file="$2"
  awk -F '|' -v key="$field" '
    {
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*-+/) next
      if (NF < 3) next
      f = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (f == key) {
        v = $3
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file"
}

branch_ticket_key() {
  local branch="$1"
  case "$branch" in
    task/*)
      printf '%s' "$branch" | sed -nE 's#^task/([A-Z][A-Z0-9]*-[0-9]+)-.*#\1#p'
      ;;
    *)
      return 1
      ;;
  esac
}

task_dir_contains_key() {
  local key="$1"
  local tasks_dir
  tasks_dir=$(dirname "$TASK_MD")
  local candidate value
  for candidate in "$tasks_dir"/T*.md "$tasks_dir"/pr-release/T*.md; do
    [ -f "$candidate" ] || continue
    value=$(parse_table_field "Task JIRA key" "$candidate")
    if [ "$value" = "$key" ]; then
      return 0
    fi
  done
  return 1
}

is_external_task_anchor() {
  local branch="$1"
  local key
  key=$(branch_ticket_key "$branch" || true)
  [ -n "$key" ] || return 1
  if task_dir_contains_key "$key"; then
    return 1
  fi
  return 0
}

ensure_local_branch() {
  local branch="$1"
  if git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch"; then
    return 0
  fi
  if git -C "$REPO" rev-parse --verify --quiet "origin/$branch" >/dev/null 2>&1; then
    git -C "$REPO" branch "$branch" "origin/$branch" >/dev/null 2>&1
    return $?
  fi
  return 1
}

restore_original_branch() {
  if [ -n "$ORIG_BRANCH" ]; then
    git -C "$REPO" checkout -q "$ORIG_BRANCH" >/dev/null 2>&1 || true
  fi
}

i=2
while [ "$i" -le "$CHAIN_LEN" ]; do
  upstream=$(line_at $((i - 1)))
  branch=$(line_at "$i")
  is_last=false
  [ "$i" -eq "$CHAIN_LEN" ] && is_last=true

  if [ "$is_last" != "true" ] && is_external_task_anchor "$branch"; then
    if git -C "$REPO" rev-parse --verify --quiet "origin/$branch" >/dev/null 2>&1; then
      printf '{"branch":%s,"upstream":%s,"status":"skipped_external_anchor","reason":"task branch is not owned by this task set"}\n' \
        "$(json_escape "$branch")" "$(json_escape "$upstream")" >> "$STEPS_FILE"
      i=$((i + 1))
      continue
    fi
    if git -C "$REPO" rev-parse --verify --quiet "$branch" >/dev/null 2>&1; then
      printf '{"branch":%s,"upstream":%s,"status":"skipped_external_anchor","reason":"task branch is not owned by this task set"}\n' \
        "$(json_escape "$branch")" "$(json_escape "$upstream")" >> "$STEPS_FILE"
      i=$((i + 1))
      continue
    fi
    log "external anchor branch not found locally or on origin: $branch"
    emit_evidence "$REPO" "$TASK_MD" "missing_external_anchor" "$CHAIN_FILE" "$STEPS_FILE"
    restore_original_branch
    exit 1
  fi

  target_ref="origin/$upstream"
  if ! git -C "$REPO" rev-parse --verify --quiet "$target_ref" >/dev/null 2>&1; then
    if git -C "$REPO" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1; then
      # Fail-closed: refuse to silently fall back to the LOCAL upstream branch.
      # A local-only upstream may carry another session's un-pushed WIP; rebasing
      # onto it would silently absorb unrelated commits into the task branch.
      log "POLARIS_REBASE_LOCAL_FALLBACK: origin/$upstream missing; refusing to rebase onto local branch $upstream"
      emit_evidence "$REPO" "$TASK_MD" "local_fallback_refused" "$CHAIN_FILE" "$STEPS_FILE"
      restore_original_branch
      exit 1
    else
      log "upstream branch not found: $upstream"
      emit_evidence "$REPO" "$TASK_MD" "missing_upstream" "$CHAIN_FILE" "$STEPS_FILE"
      restore_original_branch
      exit 1
    fi
  fi

  if ! ensure_local_branch "$branch"; then
    if [ "$is_last" = "true" ] && [ "$SKIP_MISSING_LAST" = "true" ]; then
      printf '{"branch":%s,"upstream":%s,"status":"skipped_missing_last"}\n' \
        "$(json_escape "$branch")" "$(json_escape "$upstream")" >> "$STEPS_FILE"
      break
    fi
    log "branch not found locally or on origin: $branch"
    emit_evidence "$REPO" "$TASK_MD" "missing_branch" "$CHAIN_FILE" "$STEPS_FILE"
    restore_original_branch
    exit 1
  fi

  target_sha=$(git -C "$REPO" rev-parse "$target_ref" 2>/dev/null || true)
  merge_base=$(git -C "$REPO" merge-base "$target_ref" "$branch" 2>/dev/null || true)
  if [ -n "$target_sha" ] && [ "$target_sha" = "$merge_base" ]; then
    printf '{"branch":%s,"upstream":%s,"target_ref":%s,"status":"not_needed"}\n' \
      "$(json_escape "$branch")" "$(json_escape "$upstream")" "$(json_escape "$target_ref")" >> "$STEPS_FILE"
    i=$((i + 1))
    continue
  fi

  log "rebasing $branch onto $target_ref"
  if git -C "$REPO" rebase "$target_ref" "$branch" >/dev/null 2>&1; then
    printf '{"branch":%s,"upstream":%s,"target_ref":%s,"status":"clean"}\n' \
      "$(json_escape "$branch")" "$(json_escape "$upstream")" "$(json_escape "$target_ref")" >> "$STEPS_FILE"
    if [ "$is_last" != "true" ]; then
      log "pushing intermediate base $branch"
      if ! git -C "$REPO" push --force-with-lease origin "$branch" >/dev/null 2>&1; then
        log "push --force-with-lease failed for intermediate branch: $branch"
        emit_evidence "$REPO" "$TASK_MD" "push_failed" "$CHAIN_FILE" "$STEPS_FILE"
        restore_original_branch
        exit 1
      fi
      git -C "$REPO" update-ref "refs/remotes/origin/$branch" "refs/heads/$branch" >/dev/null 2>&1 || true
    fi
  else
    log "conflict while rebasing $branch onto $target_ref"
    printf '{"branch":%s,"upstream":%s,"target_ref":%s,"status":"conflict"}\n' \
      "$(json_escape "$branch")" "$(json_escape "$upstream")" "$(json_escape "$target_ref")" >> "$STEPS_FILE"
    emit_evidence "$REPO" "$TASK_MD" "conflict" "$CHAIN_FILE" "$STEPS_FILE"
    # Bug #3: a conflicting rebase leaves the checkout mid-rebase and detached.
    # Abort the in-progress rebase and restore the original branch (mirroring the
    # push_failed path) so the caller's working tree is clean, then still fail
    # loud (exit 1) with the conflict evidence already emitted above.
    git -C "$REPO" rebase --abort >/dev/null 2>&1 || true
    restore_original_branch
    exit 1
  fi

  i=$((i + 1))
done

restore_original_branch
emit_evidence "$REPO" "$TASK_MD" "ok" "$CHAIN_FILE" "$STEPS_FILE"
