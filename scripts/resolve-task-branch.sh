#!/usr/bin/env bash
# Resolve the implementation branch name from task.md.
#
# Contract:
#   - Prefer Operational Context `Task branch` when present.
#   - Validate explicit branches fail loud instead of silently re-slugifying.
#   - Fallback to task/{delivery_ticket_key}-{summary-slug} only for legacy
#     task.md without `Task branch`.
#   - The branch prefix is the delivery_ticket_key atom (DP-238): Bug/JIRA
#     source = real JIRA key (e.g. PROJ-4190); DP source = work_item_id
#     (e.g. DP-238-T4). The internal task marker work_item_id (e.g.
#     PROJ-4190-T1) must NOT become the product branch prefix, and the legacy
#     task_jira_key alias must not be used to re-admit it (AC-NEG5).

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
  # work_item_id is the internal task marker. For Bug sources it differs from
  # the delivery_ticket_key (task_key); when it does, a branch prefixed with the
  # internal marker (e.g. task/EXCO-4190-T1-*) is an identity leak (AC-NEG5).
  local work_item_id="${3:-}"

  if is_na_value "$branch"; then
    echo "ERROR: task branch resolved to empty" >&2
    return 1
  fi

  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    echo "ERROR: invalid Task branch git ref: $branch" >&2
    return 1
  fi

  if [[ -n "$work_item_id" && "$work_item_id" != "$task_key" ]]; then
    case "$branch" in
      "task/${work_item_id}-"*)
        echo "ERROR: Task branch leaks internal task marker into product branch identity (AC-NEG5)." >&2
        echo "  Internal work_item_id: $work_item_id" >&2
        echo "  Delivery ticket key:   $task_key" >&2
        echo "  Use task/${task_key}-... instead. Actual: $branch" >&2
        return 1
        ;;
    esac
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
  local task_json task_key work_item_id summary explicit_branch slug branch

  if [[ ! -f "$task_md" ]]; then
    echo "ERROR: task_md not found: $task_md" >&2
    return 2
  fi

  task_json="$("$PARSE_TASK_MD" "$task_md" --no-resolve 2>/dev/null)" || {
    echo "ERROR: parse-task-md.sh failed for $task_md" >&2
    return 2
  }

  # delivery_ticket_key is the canonical product-PR-identity atom (DP-238).
  # Do NOT fall back to the legacy operational_context.task_jira_key alias: for
  # Bug sources that alias holds the internal work_item_id (e.g. PROJ-4190-T1)
  # and would leak the internal task marker into the product branch (AC-NEG5).
  task_key="$(printf '%s' "$task_json" | json_field "identity.delivery_ticket_key")"
  work_item_id="$(printf '%s' "$task_json" | json_field "identity.work_item_id")"
  summary="$(printf '%s' "$task_json" | json_field "header.summary")"
  explicit_branch="$(printf '%s' "$task_json" | json_field "operational_context.task_branch")"

  if is_na_value "$task_key"; then
    echo "ERROR: task identity not found in $task_md" >&2
    return 2
  fi

  if ! is_na_value "$explicit_branch"; then
    validate_branch "$explicit_branch" "$task_key" "$work_item_id" || return 1
    printf '%s\n' "$explicit_branch"
    return 0
  fi

  slug="$(slugify "$summary")"
  [[ -n "$slug" ]] || slug="impl"
  branch="task/${task_key}-${slug}"
  validate_branch "$branch" "$task_key" "$work_item_id" || return 1
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

  # DP-238 AC-NEG5: Bug source product branch uses delivery_ticket_key (the real
  # JIRA key), not the internal task marker work_item_id.
  write_bug_task() {
    local file="$1"
    local branch="$2"
    cat >"$file" <<TASK
# T1: bug source identity (3 pt)

> Source: EXCO-4190 | Task: EXCO-4190-T1 | JIRA: EXCO-4190 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-4190 |
| Task ID | EXCO-4190-T1 |
| JIRA key | EXCO-4190 |
| Base branch | develop |
| Task branch | ${branch} |

## Test Environment

- **Level**: static
TASK
  }

  bug_ok="$tmpdir/bug-ok.md"
  write_bug_task "$bug_ok" "task/EXCO-4190-fix-leak"
  out="$(resolve_task_branch "$bug_ok" 2>/dev/null)"
  assert_eq "$out" "task/EXCO-4190-fix-leak" "bug source delivery-ticket branch resolves"

  bug_leak="$tmpdir/bug-leak.md"
  write_bug_task "$bug_leak" "task/EXCO-4190-T1-fix-leak"
  resolve_task_branch "$bug_leak" >/dev/null 2>&1
  assert_rc "$?" "1" "bug source internal task marker branch fails (AC-NEG5)"

  echo "resolve-task-branch.sh selftest: $PASS/$TOTAL passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

resolve_task_branch "$1"
