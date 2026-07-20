#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris release-completed]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"
RESOLVE_RELEASE_SURFACE="${SCRIPT_DIR}/resolve-release-surface.sh"
CHECK_LOCAL_EXTENSION_COMPLETION_BIN="${POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN:-${SCRIPT_DIR}/check-local-extension-completion.sh}"
POLARIS_CHANGESET_BIN="${POLARIS_CHANGESET_BIN:-${SCRIPT_DIR}/polaris-changeset.sh}"

TASK_MD=""
REPO_OVERRIDE=""
TEMPLATE_REPO=""
FORMAT="text"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/check-release-completed.sh --task-md <path> [--repo <path>] [--template-repo <path>] [--format text|json]

Exit:
  0  release not required or release closeout completed
  2  release required but not terminally completed
  64 invalid usage / resolver failure
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --repo) REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --template-repo) TEMPLATE_REPO="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ -n "$TASK_MD" ]] || { echo "$PREFIX --task-md is required" >&2; usage; exit 64; }
[[ -f "$TASK_MD" ]] || { echo "$PREFIX task.md not found: $TASK_MD" >&2; exit 64; }
[[ -z "$REPO_OVERRIDE" || -d "$REPO_OVERRIDE" ]] || { echo "$PREFIX --repo path not found: $REPO_OVERRIDE" >&2; exit 64; }
[[ -z "$TEMPLATE_REPO" || -d "$TEMPLATE_REPO" ]] || { echo "$PREFIX --template-repo path not found: $TEMPLATE_REPO" >&2; exit 64; }
[[ "$FORMAT" == "text" || "$FORMAT" == "json" ]] || { echo "$PREFIX --format must be text or json" >&2; exit 64; }

TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
if [[ -n "$REPO_OVERRIDE" ]]; then
  REPO_OVERRIDE="$(cd "$REPO_OVERRIDE" && pwd)"
fi
if [[ -n "$TEMPLATE_REPO" ]]; then
  TEMPLATE_REPO="$(cd "$TEMPLATE_REPO" && pwd)"
fi

parse_field() {
  bash "$PARSE_TASK_MD" "$TASK_MD" --no-resolve --field "$1" 2>/dev/null || true
}

json_field() {
  local payload="$1"
  local field="$2"
  python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" json-field "$payload" "$field"
}

emit_result() {
  local source_id="$1"
  local surface_class="$2"
  local release_required="$3"
  local status="$4"
  local reason="$5"

  if [[ "$FORMAT" == "json" ]]; then
    python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" emit-result \
      "$source_id" "$surface_class" "$release_required" "$status" "$reason"
  else
    if [[ "$reason" == "pass" ]]; then
      printf 'PASS source=%s surface=%s release_required=%s status=%s\n' \
        "$source_id" "$surface_class" "$release_required" "$status"
    else
      printf 'BLOCKED source=%s surface=%s release_required=%s status=%s reason=%s\n' \
        "$source_id" "$surface_class" "$release_required" "$status" "$reason"
    fi
  fi
}

emit_worktree_cleanup_remediation() {
  local repo_path="$1"
  local identity="$2"
  local helper="${SCRIPT_DIR}/engineering-worktree-cleanup.sh"

  echo "$PREFIX residual worktree cleanup remediation:" >&2
  echo "$PREFIX   bash ${helper} --repo ${repo_path} --identity ${identity} --dry-run" >&2
  echo "$PREFIX   bash ${helper} --repo ${repo_path} --identity ${identity} --apply" >&2
}

resolve_repo_path() {
  local repo_name="$1"
  if [[ -n "$REPO_OVERRIDE" ]]; then
    printf '%s\n' "$REPO_OVERRIDE"
    return 0
  fi
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi

  local td probe
  td="$(cd "$(dirname "$TASK_MD")" && pwd)"
  while [[ "$td" != "/" ]]; do
    probe="$td/$repo_name"
    if [[ -d "$probe/.git" || -f "$probe/.git" || -d "$probe" ]]; then
      printf '%s\n' "$probe"
      return 0
    fi
    td="$(dirname "$td")"
  done
  return 1
}

resolve_terminal_task_path() {
  local task_md="$1"
  if [[ "$task_md" == */tasks/pr-release/* ]]; then
    printf '%s\n' "$task_md"
    return 0
  fi

  local candidate=""
  if [[ "$(basename "$task_md")" == "index.md" ]]; then
    local task_dir tasks_dir task_name
    task_dir="$(dirname "$task_md")"
    tasks_dir="$(dirname "$task_dir")"
    task_name="$(basename "$task_dir")"
    candidate="${tasks_dir}/pr-release/${task_name}/index.md"
  else
    candidate="$(dirname "$task_md")/pr-release/$(basename "$task_md")"
  fi

  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
  else
    printf '%s\n' "$task_md"
  fi
}

parent_verification_closeout_invalid() {
  local task_md="$1"
  python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" parent-verification-invalid "$task_md"
}

registered_worktree_for_branch() {
  local repo="$1"
  local branch="$2"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v branch="refs/heads/${branch}" '
    /^worktree / { wt = substr($0, 10); next }
    /^branch / {
      if (substr($0, 8) == branch) {
        print wt
      }
    }
  '
}

SOURCE_ID="$(parse_field work_item_id)"
if [[ -z "$SOURCE_ID" || "$SOURCE_ID" == "N/A" ]]; then
  SOURCE_ID="$(parse_field jira_key)"
fi
if [[ -z "$SOURCE_ID" || "$SOURCE_ID" == "N/A" ]]; then
  SOURCE_ID="$(parse_field task_jira_key)"
fi
if [[ -z "$SOURCE_ID" ]]; then
  SOURCE_ID="$(basename "$(dirname "$TASK_MD")")"
fi

surface_json="$(bash "$RESOLVE_RELEASE_SURFACE" --task-md "$TASK_MD" --format json 2>/dev/null)" || {
  echo "$PREFIX failed to resolve release surface: $TASK_MD" >&2
  exit 64
}
SURFACE_CLASS="$(json_field "$surface_json" class)"
RELEASE_REQUIRED="$(json_field "$surface_json" release_required)"

case "$SURFACE_CLASS" in
  none)
    emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "NOT_REQUIRED" "pass"
    exit 0
    ;;
  ambiguous)
    emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "ambiguous_surface"
    exit 2
    ;;
esac

REPO_NAME="$(parse_field repo)"
REPO_PATH="$(resolve_repo_path "$REPO_NAME" || true)"
[[ -n "$REPO_PATH" && -d "$REPO_PATH" ]] || {
  echo "$PREFIX could not resolve repo for release gate: $TASK_MD" >&2
  exit 64
}

if [[ "$SURFACE_CLASS" != "local_extension" ]]; then
  if [[ "$SURFACE_CLASS" == "package_release" ]]; then
    TASK_BRANCH="$(parse_field task_branch)"
    [[ -n "$TASK_BRANCH" ]] || { echo "$PREFIX task branch missing for package_release surface: $TASK_MD" >&2; exit 64; }

    if ! bash "$POLARIS_CHANGESET_BIN" check --task-md "$TASK_MD" --repo "$REPO_PATH" >/dev/null 2>&1; then
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "changeset_missing_or_invalid"
      exit 2
    fi

    TERMINAL_TASK_MD="$(resolve_terminal_task_path "$TASK_MD")"
    [[ "$TERMINAL_TASK_MD" == */tasks/pr-release/* ]] || {
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "task_not_moved_to_pr_release"
      exit 2
    }
    [[ -f "$TERMINAL_TASK_MD" ]] || {
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "terminal_task_missing"
      exit 2
    }

    TERMINAL_STATUS="$(bash "$PARSE_TASK_MD" "$TERMINAL_TASK_MD" --no-resolve --field status 2>/dev/null || true)"
    if [[ "$TERMINAL_STATUS" != "IMPLEMENTED" ]]; then
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "task_not_implemented"
      exit 2
    fi

    REGISTERED_WT="$(registered_worktree_for_branch "$REPO_PATH" "$TASK_BRANCH" || true)"
    if [[ -n "$REGISTERED_WT" && -d "$REGISTERED_WT" ]]; then
      emit_worktree_cleanup_remediation "$REPO_PATH" "$SOURCE_ID"
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "worktree_not_cleaned"
      exit 2
    fi

    emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "COMPLETED" "pass"
    exit 0
  fi

  if [[ "$SURFACE_CLASS" == "developer_pr" ]]; then
    TASK_BRANCH="$(parse_field task_branch)"
    [[ -n "$TASK_BRANCH" ]] || { echo "$PREFIX task branch missing for developer_pr surface: $TASK_MD" >&2; exit 64; }

    TERMINAL_TASK_MD="$(resolve_terminal_task_path "$TASK_MD")"
    [[ "$TERMINAL_TASK_MD" == */tasks/pr-release/* ]] || {
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "task_not_moved_to_pr_release"
      exit 2
    }
    [[ -f "$TERMINAL_TASK_MD" ]] || {
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "terminal_task_missing"
      exit 2
    }

    TERMINAL_STATUS="$(bash "$PARSE_TASK_MD" "$TERMINAL_TASK_MD" --no-resolve --field status 2>/dev/null || true)"
    if [[ "$TERMINAL_STATUS" != "IMPLEMENTED" ]]; then
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "task_not_implemented"
      exit 2
    fi

    REGISTERED_WT="$(registered_worktree_for_branch "$REPO_PATH" "$TASK_BRANCH" || true)"
    if [[ -n "$REGISTERED_WT" && -d "$REGISTERED_WT" ]]; then
      emit_worktree_cleanup_remediation "$REPO_PATH" "$SOURCE_ID"
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "worktree_not_cleaned"
      exit 2
    fi

    emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "COMPLETED" "pass"
    exit 0
  fi

  echo "$PREFIX unsupported release surface class: $SURFACE_CLASS" >&2
  exit 64
fi

TASK_ID="$(parse_field work_item_id)"
if [[ -z "$TASK_ID" || "$TASK_ID" == "N/A" ]]; then
  TASK_ID="$(parse_field task_jira_key)"
fi
EXTENSION_ID="$(parse_field extension_deliverable_extension_id)"
TASK_BRANCH="$(parse_field task_branch)"
[[ -n "$TASK_ID" ]] || { echo "$PREFIX could not resolve task/work item id for local_extension surface: $TASK_MD" >&2; exit 64; }
[[ -n "$EXTENSION_ID" ]] || { echo "$PREFIX extension_deliverable.extension_id missing for local_extension surface: $TASK_MD" >&2; exit 64; }
[[ -n "$TASK_BRANCH" ]] || { echo "$PREFIX task branch missing for local_extension surface: $TASK_MD" >&2; exit 64; }

local_args=(--repo "$REPO_PATH" --task-md "$TASK_MD" --task-id "$TASK_ID" --extension-id "$EXTENSION_ID")
if [[ -n "$TEMPLATE_REPO" ]]; then
  local_args+=(--template-repo "$TEMPLATE_REPO")
fi
if ! bash "$CHECK_LOCAL_EXTENSION_COMPLETION_BIN" "${local_args[@]}" >/dev/null 2>&1; then
  emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "local_extension_completion_failed"
  exit 2
fi

TERMINAL_TASK_MD="$(resolve_terminal_task_path "$TASK_MD")"
[[ "$TERMINAL_TASK_MD" == */tasks/pr-release/* ]] || {
  emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "task_not_moved_to_pr_release"
  exit 2
}
[[ -f "$TERMINAL_TASK_MD" ]] || {
  emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "terminal_task_missing"
  exit 2
}

TERMINAL_STATUS="$(bash "$PARSE_TASK_MD" "$TERMINAL_TASK_MD" --no-resolve --field status 2>/dev/null || true)"
if [[ "$TERMINAL_STATUS" != "IMPLEMENTED" ]]; then
  emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "task_not_implemented"
  exit 2
fi

if parent_verification_closeout_invalid "$TERMINAL_TASK_MD"; then
  :
else
  emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "verification_closeout_incomplete"
  exit 2
fi

REGISTERED_WT="$(registered_worktree_for_branch "$REPO_PATH" "$TASK_BRANCH" || true)"
if [[ -n "$REGISTERED_WT" && -d "$REGISTERED_WT" ]]; then
  emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "worktree_not_cleaned"
  exit 2
fi

emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "COMPLETED" "pass"
exit 0
