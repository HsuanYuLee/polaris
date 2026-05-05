#!/usr/bin/env bash
set -euo pipefail

# check-delivery-completion.sh — Completion-time hard gate for engineering.
# Prevents "mouth-only completion" by requiring the same delivery evidence gates
# before the agent reports task completion to the user.
#
# Usage:
#   bash scripts/check-delivery-completion.sh [--repo <path>] [--ticket <KEY>] [--admin]
#
# Exit: 0 = pass, 2 = block, 64 = usage error

PREFIX="[polaris completion-gate]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
TICKET=""
MODE="auto"

parse_github_pr_url() {
  local pr_url="$1"

  python3 - "$pr_url" <<'PY'
import re
import sys

value = sys.argv[1].strip()
match = re.match(r"^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$", value)
if not match:
    sys.exit(1)

owner, repo, number = match.groups()
print(f"{owner}/{repo}\t{number}")
PY
}

json_field() {
  local file="$1"
  local field="$2"

  python3 - "$file" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

value = data.get(field)
if value is None:
    sys.exit(0)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

write_json_field_to_file() {
  local json_file="$1"
  local field="$2"
  local output_file="$3"

  python3 - "$json_file" "$field" "$output_file" <<'PY'
import json
import sys

json_path, field, output_path = sys.argv[1:4]
with open(json_path, encoding="utf-8") as f:
    data = json.load(f)

value = data.get(field) or ""
with open(output_path, "w", encoding="utf-8") as f:
    f.write(str(value))
PY
}

check_deliverable_pr_remote_truth() {
  local task_md_path="$1"
  local deliverable_head_sha="$2"
  local pr_url=""
  local parsed=""
  local gh_repo=""
  local pr_number=""
  local pr_json=""
  local pr_body_file=""
  local pr_state=""
  local pr_is_draft=""
  local pr_head_oid=""

  pr_url="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md_path" --no-resolve --field deliverable_pr_url)"
  if [[ -z "$pr_url" ]]; then
    echo "$PREFIX PR readiness check failed: deliverable.pr_url missing in ${task_md_path}" >&2
    exit 2
  fi

  if ! parsed="$(parse_github_pr_url "$pr_url")"; then
    echo "$PREFIX PR readiness check failed: deliverable.pr_url is not a GitHub PR URL: ${pr_url}" >&2
    exit 2
  fi

  gh_repo="${parsed%%$'\t'*}"
  pr_number="${parsed##*$'\t'}"

  command -v gh >/dev/null 2>&1 || {
    echo "$PREFIX PR readiness check failed: gh CLI is required to inspect ${pr_url}" >&2
    exit 2
  }

  pr_json="$(mktemp -t polaris-pr-metadata.XXXXXX.json)"
  pr_body_file="$(mktemp -t polaris-pr-body.XXXXXX.md)"
  trap 'rm -f "${pr_json:-}" "${pr_body_file:-}"' RETURN

  if ! gh pr view "$pr_number" --repo "$gh_repo" --json body,isDraft,state,url,headRefName,headRefOid,baseRefName >"$pr_json"; then
    echo "$PREFIX PR readiness check failed: unable to read GitHub PR metadata for ${pr_url}" >&2
    exit 2
  fi

  pr_state="$(json_field "$pr_json" state || true)"
  pr_is_draft="$(json_field "$pr_json" isDraft || true)"
  pr_head_oid="$(json_field "$pr_json" headRefOid || true)"
  write_json_field_to_file "$pr_json" body "$pr_body_file"

  if [[ "$pr_state" != "OPEN" ]]; then
    echo "$PREFIX PR readiness check failed: deliverable PR must be OPEN (got ${pr_state:-<empty>}) for ${pr_url}" >&2
    exit 2
  fi

  if [[ "$pr_is_draft" == "true" ]]; then
    echo "$PREFIX PR readiness check failed: deliverable PR is draft; mark it ready for review before Developer completion: ${pr_url}" >&2
    exit 2
  fi

  if [[ -n "$pr_head_oid" && -n "$deliverable_head_sha" && "$pr_head_oid" != "$deliverable_head_sha" && "$pr_head_oid" != "${deliverable_head_sha}"* ]]; then
    echo "$PREFIX PR freshness check failed: remote headRefOid (${pr_head_oid}) != deliverable.head_sha (${deliverable_head_sha}) for ${pr_url}" >&2
    exit 2
  fi

  bash "${SCRIPT_DIR}/gates/gate-pr-body-template.sh" --repo "$REPO_ROOT" --body-file "$pr_body_file"
  bash "${SCRIPT_DIR}/gates/gate-pr-language.sh" --repo "$REPO_ROOT" --body-file "$pr_body_file"

  local publication_ticket="$TICKET"
  if [[ -z "$publication_ticket" ]]; then
    publication_ticket="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md_path" --no-resolve --field task_jira_key 2>/dev/null || true)"
  fi
  if [[ -n "$publication_ticket" ]]; then
    bash "${SCRIPT_DIR}/publish-delivery-evidence.sh" \
      --mode check \
      --repo "$REPO_ROOT" \
      --ticket "$publication_ticket" \
      --head-sha "$deliverable_head_sha" \
      --pr-url "$pr_url"
  fi

  echo "$PREFIX ✅ PR readiness/body/language/evidence publication gates passed for ${pr_url}" >&2
}

find_workspace_root_for_path() {
  local path="$1"
  local probe=""
  local root=""

  [[ -d "$path" ]] || return 1
  probe="$(cd "$path" && pwd)"

  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -f "$probe/workspace-config.yaml" ]]; then
      root="$probe"
    fi
    probe="$(dirname "$probe")"
  done

  [[ -n "$root" ]] || return 1
  printf '%s\n' "$root"
}

append_unique_scan_root() {
  local root="$1"
  local existing=""

  [[ -n "$root" && -d "$root" ]] || return 0
  root="$(cd "$root" && pwd)"

  if declare -p scan_roots >/dev/null 2>&1; then
    for existing in ${scan_roots[@]+"${scan_roots[@]}"}; do
      if [[ "$existing" == "$root" ]]; then
        return 0
      fi
    done
  fi

  scan_roots+=("$root")
}

resolve_task_for_completion_check() {
  if [[ "$MODE" == "admin" ]]; then
    return 1
  fi

  local candidate=""
  local candidates=()
  local main_checkout=""
  local workspace_root=""
  local scan_root=""

  local -a scan_roots
  scan_roots=()

  if [[ -e "${REPO_ROOT}/.git" ]]; then
    # shellcheck source=lib/main-checkout.sh
    . "${SCRIPT_DIR}/lib/main-checkout.sh"
    if main_checkout="$(resolve_main_checkout "$REPO_ROOT" 2>/dev/null)" && [[ -n "$main_checkout" ]]; then
      if [[ "$main_checkout" != "$REPO_ROOT" ]]; then
        append_unique_scan_root "$main_checkout"
      fi
      if workspace_root="$(find_workspace_root_for_path "$main_checkout" 2>/dev/null)" && [[ -n "$workspace_root" ]]; then
        append_unique_scan_root "$workspace_root"
      fi
    fi
  fi

  append_unique_scan_root "$REPO_ROOT"
  if workspace_root="$(find_workspace_root_for_path "$REPO_ROOT" 2>/dev/null)" && [[ -n "$workspace_root" ]]; then
    append_unique_scan_root "$workspace_root"
  fi

  if [[ -n "$TICKET" ]]; then
    for scan_root in ${scan_roots[@]+"${scan_roots[@]}"}; do
      if candidate="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$scan_root" "$TICKET" 2>/dev/null || true)" && [[ -n "$candidate" ]]; then
        candidates+=("$candidate")
        break
      fi
    done
  fi

  for scan_root in ${scan_roots[@]+"${scan_roots[@]}"}; do
    if candidate="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$scan_root" --current 2>/dev/null || true)" && [[ -n "$candidate" ]]; then
      candidates+=("$candidate")
      break
    fi
  done

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --ticket)
      TICKET="${2:-}"
      shift 2
      ;;
    --admin)
      MODE="admin"
      shift
      ;;
    -h|--help)
      echo "Usage: bash scripts/check-delivery-completion.sh [--repo <path>] [--ticket <KEY>] [--admin]"
      echo "  --repo <path>   Target repo (default: git rev-parse --show-toplevel)"
      echo "  --ticket <KEY>  JIRA ticket key for verification evidence gate"
      echo "  --admin         Skip ticket-bound verification evidence gate"
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi

if [[ -z "$REPO_ROOT" ]]; then
  echo "$PREFIX unable to resolve repo root" >&2
  exit 64
fi

if [[ "$MODE" == "auto" && -z "$TICKET" ]]; then
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
    TICKET="${BASH_REMATCH[1]}"
  fi
fi

echo "$PREFIX checking completion gates for ${REPO_ROOT}" >&2

# Layer A: repo-level Local CI Mirror. Existing script must be treated as
# authoritative regardless of git tracking state (tracked/untracked/generated).
# BLOCKED_ENV from Layer A is intentionally still blocking; gate-ci-local owns
# the environment remediation / RETRY_WITH_ESCALATION message.
bash "${SCRIPT_DIR}/gates/gate-ci-local.sh" --repo "$REPO_ROOT"

# Layer B: ticket-bound verify evidence for Developer flows.
if [[ "$MODE" != "admin" && -n "$TICKET" ]]; then
  bash "${SCRIPT_DIR}/gates/gate-evidence.sh" --repo "$REPO_ROOT" --ticket "$TICKET"
fi

# Developer PR metadata/deliverable gates.
if [[ "$MODE" != "admin" ]]; then
  bash "${SCRIPT_DIR}/gates/gate-pr-title.sh" --repo "$REPO_ROOT"
  bash "${SCRIPT_DIR}/gates/gate-changeset.sh" --repo "$REPO_ROOT"

  TASK_MD_PATH=""
  if ! TASK_MD_PATH="$(resolve_task_for_completion_check)"; then
    echo "$PREFIX unable to resolve task.md for completion freshness check (supply --ticket or call from task-bound context)" >&2
    exit 2
  fi

  DELIVERABLE_HEAD_SHA="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$TASK_MD_PATH" --no-resolve --field deliverable_head_sha)"
  if [[ -z "$DELIVERABLE_HEAD_SHA" ]]; then
    echo "$PREFIX completion freshness check failed: deliverable.head_sha missing in ${TASK_MD_PATH}" >&2
    exit 2
  fi

  CURRENT_HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  if [[ "$CURRENT_HEAD_SHA" != "$DELIVERABLE_HEAD_SHA" && "$CURRENT_HEAD_SHA" != "${DELIVERABLE_HEAD_SHA}"* ]]; then
    echo "$PREFIX completion freshness check failed: deliverable.head_sha (${DELIVERABLE_HEAD_SHA}) != HEAD (${CURRENT_HEAD_SHA}) in ${TASK_MD_PATH}" >&2
    exit 2
  fi

  check_deliverable_pr_remote_truth "$TASK_MD_PATH" "$DELIVERABLE_HEAD_SHA"
fi

echo "$PREFIX ✅ completion gates satisfied." >&2
