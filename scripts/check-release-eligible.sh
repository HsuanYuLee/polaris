#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris release-eligible]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"
RESOLVE_RELEASE_SURFACE="${SCRIPT_DIR}/resolve-release-surface.sh"
CHECK_DELIVERY_COMPLETION_BIN="${POLARIS_CHECK_DELIVERY_COMPLETION_BIN:-${SCRIPT_DIR}/check-delivery-completion.sh}"
CHECK_LOCAL_EXTENSION_COMPLETION_BIN="${POLARIS_CHECK_LOCAL_EXTENSION_COMPLETION_BIN:-${SCRIPT_DIR}/check-local-extension-completion.sh}"
POLARIS_CHANGESET_BIN="${POLARIS_CHANGESET_BIN:-${SCRIPT_DIR}/polaris-changeset.sh}"
VERIFY_AGENTS_MIRROR_PORTABLE_BIN="${POLARIS_VERIFY_AGENTS_MIRROR_PORTABLE_BIN:-${SCRIPT_DIR}/verify-agents-mirror-portable.sh}"

TASK_MD=""
REPO_OVERRIDE=""
TEMPLATE_REPO=""
FORMAT="text"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/check-release-eligible.sh --task-md <path> [--repo <path>] [--template-repo <path>] [--format text|json]

Exit:
  0  release not required or release eligible
  2  release required but blocked
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

case "$SURFACE_CLASS" in
  package_release)
    if [[ -x "$VERIFY_AGENTS_MIRROR_PORTABLE_BIN" ]]; then
      bash "$VERIFY_AGENTS_MIRROR_PORTABLE_BIN" >/dev/null 2>&1 || {
        emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "codex_portable_smoke_failed"
        exit 2
      }
    fi
    if bash "$POLARIS_CHANGESET_BIN" check --task-md "$TASK_MD" --repo "$REPO_PATH" >/dev/null 2>&1; then
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "ELIGIBLE" "pass"
      exit 0
    fi
    emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "changeset_missing_or_invalid"
    exit 2
    ;;
  developer_pr)
    TICKET="$(parse_field jira_key)"
    if [[ -z "$TICKET" || "$TICKET" == "N/A" ]]; then
      TICKET="$(parse_field work_item_id)"
    fi
    if [[ -z "$TICKET" || "$TICKET" == "N/A" ]]; then
      TICKET="$(parse_field task_jira_key)"
    fi
    [[ -n "$TICKET" ]] || { echo "$PREFIX could not resolve ticket/work item for developer_pr surface: $TASK_MD" >&2; exit 64; }

    if bash "$CHECK_DELIVERY_COMPLETION_BIN" --repo "$REPO_PATH" --ticket "$TICKET" >/dev/null 2>&1; then
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "ELIGIBLE" "pass"
      exit 0
    fi
    emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "completion_gate_failed"
    exit 2
    ;;
  local_extension)
    TASK_ID="$(parse_field work_item_id)"
    if [[ -z "$TASK_ID" || "$TASK_ID" == "N/A" ]]; then
      TASK_ID="$(parse_field task_jira_key)"
    fi
    EXTENSION_ID="$(parse_field extension_deliverable_extension_id)"
    [[ -n "$TASK_ID" ]] || { echo "$PREFIX could not resolve task/work item id for local_extension surface: $TASK_MD" >&2; exit 64; }
    [[ -n "$EXTENSION_ID" ]] || { echo "$PREFIX extension_deliverable.extension_id missing for local_extension surface: $TASK_MD" >&2; exit 64; }

    local_args=(--repo "$REPO_PATH" --task-md "$TASK_MD" --task-id "$TASK_ID" --extension-id "$EXTENSION_ID")
    if [[ -n "$TEMPLATE_REPO" ]]; then
      local_args+=(--template-repo "$TEMPLATE_REPO")
    fi
    if [[ -x "$VERIFY_AGENTS_MIRROR_PORTABLE_BIN" ]]; then
      bash "$VERIFY_AGENTS_MIRROR_PORTABLE_BIN" >/dev/null 2>&1 || {
        emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "codex_portable_smoke_failed"
        exit 2
      }
    fi
    if bash "$CHECK_LOCAL_EXTENSION_COMPLETION_BIN" "${local_args[@]}" >/dev/null 2>&1; then
      emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "ELIGIBLE" "pass"
      exit 0
    fi
    emit_result "$SOURCE_ID" "$SURFACE_CLASS" "$RELEASE_REQUIRED" "BLOCKED" "local_extension_completion_failed"
    exit 2
    ;;
  *)
    echo "$PREFIX unsupported release surface class: $SURFACE_CLASS" >&2
    exit 64
    ;;
esac
