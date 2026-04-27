#!/usr/bin/env bash
# cascade-rebase-chain.sh — rebase a task branch chain upstream → downstream.
#
# Contract:
#   cascade-rebase-chain.sh --repo <repo> --task-md <task.md> [--skip-missing-last]
#
# Reads task.md `Branch chain` through resolve-branch-chain.sh. For a chain like:
#   develop -> feat/GT-478-demo -> task/KB2CW-3711-a -> task/KB2CW-3900-b
# it rebases each downstream branch onto the latest upstream in order:
#   feat/GT-478-demo onto origin/develop
#   task/KB2CW-3711-a onto origin/feat/GT-478-demo
#   task/KB2CW-3900-b onto origin/task/KB2CW-3711-a
#
# Intermediate branches are pushed with --force-with-lease after a clean rebase,
# because later PRs use those remote branches as their GitHub base.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_BRANCH_CHAIN="$SCRIPT_DIR/resolve-branch-chain.sh"

log() {
  printf '[cascade-rebase-chain] %s\n' "$*" >&2
}

usage() {
  cat >&2 <<'USAGE'
usage: cascade-rebase-chain.sh --repo <repo> --task-md <task.md> [--skip-missing-last]

Exit:
  0 chain rebased or already up to date
  1 fetch / rebase / push failure
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

REPO=""
TASK_MD=""
SKIP_MISSING_LAST=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || { log "--repo requires a value"; usage; exit 2; }
      REPO="$2"; shift 2 ;;
    --task-md)
      [ "$#" -ge 2 ] || { log "--task-md requires a value"; usage; exit 2; }
      TASK_MD="$2"; shift 2 ;;
    --skip-missing-last)
      SKIP_MISSING_LAST=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      log "unknown arg: $1"; usage; exit 2 ;;
  esac
done

if [ -z "$REPO" ] || [ -z "$TASK_MD" ]; then
  usage
  exit 2
fi
if ! REPO=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null); then
  log "--repo is not a git repo: $REPO"
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

  target_ref="origin/$upstream"
  if ! git -C "$REPO" rev-parse --verify --quiet "$target_ref" >/dev/null 2>&1; then
    if git -C "$REPO" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1; then
      target_ref="$upstream"
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
    exit 1
  fi

  i=$((i + 1))
done

restore_original_branch
emit_evidence "$REPO" "$TASK_MD" "ok" "$CHAIN_FILE" "$STEPS_FILE"
