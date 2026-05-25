#!/usr/bin/env bash
# Resolve the active engineering task worktree path for a given source / work item.
#
# Contract (AC33):
#   - Inputs: --source-id <DP-NNN | JIRA-EPIC-KEY> --work-item-id <Tn | DP-NNN-Tn | EPIC-KEY-Tn>
#   - Looks up `git worktree list --porcelain` against canonical task branch
#     pattern `task/{TASK_KEY}-*` where {TASK_KEY} = combined source / work item identity.
#   - Single match → print absolute worktree path, exit 0.
#   - Zero matches → print "NONE", exit 0 (caller may decide blocking).
#   - Multiple matches → fail-stop, stderr `POLARIS_DISPATCH_WORKTREE_AMBIGUOUS`, exit 2.
#
# Used by /auto-pass and /verify-AC dispatch to populate envelope `worktree_resolution`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  resolve-task-worktree.sh --source-id <SOURCE_ID> --work-item-id <WORK_ITEM_ID> [--repo <repo_root>] [--format text|json]
  resolve-task-worktree.sh --selftest

Outputs (text format, default):
  - absolute worktree path on single match
  - literal NONE on zero match

Outputs (json format):
  - {"status": "FOUND",     "path": "<abs>", "task_key": "<key>"}
  - {"status": "NONE",      "path": null,    "task_key": "<key>"}
  - status AMBIGUOUS does not emit json; fail-stop on stderr.
EOF
}

SOURCE_ID=""
WORK_ITEM_ID=""
REPO=""
FORMAT="text"
SELFTEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id)
      SOURCE_ID="${2:-}"
      shift 2
      ;;
    --work-item-id)
      WORK_ITEM_ID="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-text}"
      shift 2
      ;;
    --selftest)
      SELFTEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Derive canonical task key. The work item id can be either fully-qualified
# (`DP-230-T13` / `EXAMPLE-500-T2`) or short-form (`T13`). If short-form, we
# concatenate with the source id.
derive_task_key() {
  local source_id="$1" work_item_id="$2"
  if [[ -z "$work_item_id" ]]; then
    echo ""
    return 0
  fi
  case "$work_item_id" in
    T[0-9]*|V[0-9]*)
      if [[ -z "$source_id" ]]; then
        echo ""
        return 0
      fi
      printf '%s-%s\n' "$source_id" "$work_item_id"
      ;;
    *)
      printf '%s\n' "$work_item_id"
      ;;
  esac
}

resolve_repo_root() {
  local repo="$1"
  if [[ -n "$repo" ]]; then
    # Resolve worktree → real repo top-level so that callers running inside a
    # worktree still find sibling .worktrees/ entries.
    git -C "$repo" rev-parse --show-toplevel 2>/dev/null || {
      echo "ERROR: --repo not inside a git working tree: $repo" >&2
      return 2
    }
  else
    git rev-parse --show-toplevel 2>/dev/null || {
      echo "ERROR: not inside a git working tree (pass --repo)" >&2
      return 2
    }
  fi
}

resolve_main_checkout() {
  # `git worktree list` works against the common_dir, so even when invoked from
  # an engineering worktree we get the full registry. We just need a repo to
  # invoke against.
  local repo="$1"
  local common_dir
  common_dir="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || return 1
  if [[ "$common_dir" != /* ]]; then
    common_dir="$repo/$common_dir"
  fi
  # common_dir is something like /path/to/main/.git. Strip the trailing /.git.
  printf '%s\n' "${common_dir%/.git}"
}

resolve_task_worktree() {
  local source_id="$1" work_item_id="$2" repo_override="$3" format="$4"
  local task_key
  task_key="$(derive_task_key "$source_id" "$work_item_id")"
  if [[ -z "$task_key" ]]; then
    echo "ERROR: --work-item-id required (and --source-id when short-form Tn)" >&2
    return 2
  fi

  local repo
  repo="$(resolve_repo_root "$repo_override")" || return $?

  # `git worktree list --porcelain` is stable across git versions and yields
  # records separated by blank lines:
  #   worktree <abs path>
  #   HEAD <sha>
  #   branch refs/heads/<name>
  local listing
  listing="$(git -C "$repo" worktree list --porcelain 2>/dev/null)" || {
    echo "ERROR: git worktree list failed in $repo" >&2
    return 2
  }

  # Match worktrees whose branch matches `task/{task_key}-*` (canonical task
  # branch shape, see resolve-task-branch.sh). The trailing `-` ensures we do
  # not collide with e.g. `task/DP-230-T1` matching `DP-230-T13`.
  local matches
  matches="$(printf '%s\n' "$listing" | awk -v key="$task_key" '
    BEGIN { wt=""; br="" }
    /^worktree /   { if (wt!="" && br!="") emit(); wt=$2; br="" }
    /^branch /     { br=$2 }
    /^$/           { if (wt!="" && br!="") emit(); wt=""; br="" }
    END            { if (wt!="" && br!="") emit() }
    function emit() {
      # br looks like refs/heads/task/<task_key>-<slug>
      prefix="refs/heads/task/" key "-"
      if (substr(br, 1, length(prefix)) == prefix) {
        print wt
      }
    }
  ')"

  local count
  count="$(printf '%s\n' "$matches" | grep -c . || true)"

  if [[ "$count" -gt 1 ]]; then
    echo "POLARIS_DISPATCH_WORKTREE_AMBIGUOUS: multiple worktrees match task_key=$task_key" >&2
    printf '%s\n' "$matches" >&2
    return 2
  fi

  if [[ "$count" -eq 0 ]]; then
    if [[ "$format" == "json" ]]; then
      printf '{"status":"NONE","path":null,"task_key":"%s"}\n' "$task_key"
    else
      echo "NONE"
    fi
    return 0
  fi

  local path
  path="$(printf '%s\n' "$matches" | head -n 1)"

  if [[ "$format" == "json" ]]; then
    printf '{"status":"FOUND","path":"%s","task_key":"%s"}\n' "$path" "$task_key"
  else
    printf '%s\n' "$path"
  fi
  return 0
}

if [[ "$SELFTEST" -eq 1 ]]; then
  echo "resolve-task-worktree.sh: --selftest is a no-op marker; run scripts/selftests/resolve-task-worktree-selftest.sh" >&2
  exit 0
fi

if [[ -z "$WORK_ITEM_ID" ]]; then
  usage
  exit 2
fi

resolve_task_worktree "$SOURCE_ID" "$WORK_ITEM_ID" "$REPO" "$FORMAT"
