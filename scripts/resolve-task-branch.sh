#!/usr/bin/env bash
# Resolve the implementation branch name from task.md.
#
# Contract:
#   - Prefer Operational Context `Task branch` when present.
#   - Validate explicit branches fail loud instead of silently re-slugifying.
#   - Fallback to task/{work_item_id}-{summary-slug} only for legacy task.md
#     without `Task branch`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  resolve-task-branch.sh <task.md>
  resolve-task-branch.sh --selftest
EOF
}

slugify() {
  local input="$1"
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c1-40
}

json_field() {
  local expr="$1"
  python3 -c '
import json
import sys

data = json.load(sys.stdin)
expr = sys.argv[1].split(".")
value = data
for part in expr:
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break
print(value or "")
' "$expr"
}

is_na_value() {
  local value
  value="$(printf '%s' "${1:-}" | xargs 2>/dev/null || true)"
  [[ -z "$value" || "$value" == "N/A" || "$value" == "n/a" || "$value" == "-" || "$value" == "none" || "$value" == "None" ]]
}

validate_branch() {
  local branch="$1"
  local task_key="$2"

  if is_na_value "$branch"; then
    echo "ERROR: task branch resolved to empty" >&2
    return 1
  fi

  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    echo "ERROR: invalid Task branch git ref: $branch" >&2
    return 1
  fi

  case "$branch" in
    "task/${task_key}-"*) ;;
    *)
      echo "ERROR: Task branch must start with task/${task_key}-" >&2
      echo "  Actual: $branch" >&2
      return 1
      ;;
  esac
}

resolve_task_branch() {
  local task_md="$1"
  local task_json task_key summary explicit_branch slug branch

  if [[ ! -f "$task_md" ]]; then
    echo "ERROR: task_md not found: $task_md" >&2
    return 2
  fi

  task_json="$("$PARSE_TASK_MD" "$task_md" --no-resolve 2>/dev/null)" || {
    echo "ERROR: parse-task-md.sh failed for $task_md" >&2
    return 2
  }

  task_key="$(printf '%s' "$task_json" | json_field "identity.work_item_id")"
  if is_na_value "$task_key"; then
    task_key="$(printf '%s' "$task_json" | json_field "operational_context.task_jira_key")"
  fi
  summary="$(printf '%s' "$task_json" | json_field "header.summary")"
  explicit_branch="$(printf '%s' "$task_json" | json_field "operational_context.task_branch")"

  if is_na_value "$task_key"; then
    echo "ERROR: task identity not found in $task_md" >&2
    return 2
  fi

  if ! is_na_value "$explicit_branch"; then
    validate_branch "$explicit_branch" "$task_key" || return 1
    printf '%s\n' "$explicit_branch"
    return 0
  fi

  slug="$(slugify "$summary")"
  [[ -n "$slug" ]] || slug="impl"
  branch="task/${task_key}-${slug}"
  validate_branch "$branch" "$task_key" || return 1
  printf '%s\n' "$branch"
}

if [[ "${1:-}" == "--selftest" ]]; then
  PASS=0
  FAIL=0
  TOTAL=0

  assert_eq() {
    TOTAL=$((TOTAL + 1))
    if [[ "$1" == "$2" ]]; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "FAIL [$TOTAL]: expected='$2' got='$1' — $3" >&2
    fi
  }

  assert_rc() {
    TOTAL=$((TOTAL + 1))
    if [[ "$1" == "$2" ]]; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "FAIL [$TOTAL]: expected rc='$2' got='$1' — $3" >&2
    fi
  }

  tmpdir="$(mktemp -d -t resolve-task-branch.XXXXXX)"
  trap 'rm -rf "$tmpdir"' EXIT

  write_task() {
    local file="$1"
    local title="$2"
    local branch="$3"
    cat >"$file" <<TASK
# T1: ${title} (3 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | ${branch} |

## Test Environment

- **Level**: static

## Test Command

\`\`\`bash
echo ok
\`\`\`
TASK
  }

  explicit="$tmpdir/explicit.md"
  write_task "$explicit" "summary slug differs" "task/DP-999-T1-contract-branch"
  out="$(resolve_task_branch "$explicit" 2>/dev/null)"
  assert_eq "$out" "task/DP-999-T1-contract-branch" "explicit Task branch wins"

  legacy="$tmpdir/legacy.md"
  write_task "$legacy" "fallback summary branch" "N/A"
  out="$(resolve_task_branch "$legacy" 2>/dev/null)"
  assert_eq "$out" "task/DP-999-T1-fallback-summary-branch" "legacy fallback slug"

  invalid="$tmpdir/invalid.md"
  write_task "$invalid" "bad branch" "task/DP-999-T1 bad"
  resolve_task_branch "$invalid" >/dev/null 2>&1
  assert_rc "$?" "1" "invalid git ref fails"

  wrong_prefix="$tmpdir/wrong-prefix.md"
  write_task "$wrong_prefix" "wrong prefix" "task/DP-999-T2-wrong"
  resolve_task_branch "$wrong_prefix" >/dev/null 2>&1
  assert_rc "$?" "1" "wrong task prefix fails"

  echo "resolve-task-branch.sh selftest: $PASS/$TOTAL passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

resolve_task_branch "$1"
