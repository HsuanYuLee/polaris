#!/usr/bin/env bash
# resolve-task-md.sh — DP-032 D1 task.md / plan.md entry resolver
#
# Resolves exactly one engineering work order from:
#   - direct task.md / plan.md path
#   - JIRA ticket key
#   - PR URL / PR number
#   - current branch
#   - raw user input

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BY_BRANCH_SCRIPT="${SCRIPT_DIR}/resolve-task-md-by-branch.sh"

usage() {
  cat >&2 <<'USAGE'
usage: resolve-task-md.sh <path|jira-key|pr-url|pr-number>
       resolve-task-md.sh --current
       resolve-task-md.sh --clear-lock
       resolve-task-md.sh --write-lock <path|jira-key|pr-url|pr-number>
       resolve-task-md.sh --write-lock --current
       resolve-task-md.sh --write-lock --from-input "<raw user message>"
       resolve-task-md.sh --from-input "<raw user message>"
       resolve-task-md.sh --scan-root <path> <path|jira-key|pr-url|pr-number>
       resolve-task-md.sh --scan-root <path> --current
       resolve-task-md.sh --scan-root <path> --from-input "<raw user message>"

stdout: absolute path to exactly one task.md / plan.md
exit: 0 = resolved
      1 = not found / ambiguous / dependency missing
      2 = usage error
USAGE
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  fi
}

lock_path_for_root() {
  local root="$1"
  python3 - "$root" <<'PY'
import hashlib
import sys

root = sys.argv[1]
digest = hashlib.sha1(root.encode("utf-8")).hexdigest()[:12]
print(f"/tmp/polaris-work-order-lock-{digest}.json")
PY
}

write_lock() {
  local root="$1"
  local resolved_path="$2"
  local mode="$3"
  local input_value="$4"
  local lock_path=""

  lock_path="$(lock_path_for_root "$root")"
  python3 - "$lock_path" "$root" "$resolved_path" "$mode" "$input_value" <<'PY'
import json
import sys
from datetime import datetime, timezone

lock_path, root, resolved_path, mode, input_value = sys.argv[1:6]
payload = {
    "root": root,
    "resolved_path": resolved_path,
    "mode": mode,
    "input": input_value,
    "writer": "resolve-task-md.sh",
    "at": datetime.now(timezone.utc).isoformat(),
}
with open(lock_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False)
PY
}

clear_lock() {
  local root="$1"
  local lock_path=""
  lock_path="$(lock_path_for_root "$root")"
  rm -f "$lock_path"
}

detect_workspace_root() {
  local explicit_root="${1:-}"
  local root=""
  local probe=""
  local gc=""
  local gc_abs=""
  local main_checkout=""

  if [[ -n "$explicit_root" ]]; then
    [[ -d "$explicit_root" ]] || { echo "error: --scan-root not a directory: $explicit_root" >&2; return 2; }
    abs_path "$explicit_root"
    return 0
  fi

  probe="$(pwd)"
  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -f "$probe/workspace-config.yaml" ]]; then
      root="$probe"
    fi
    probe="$(dirname "$probe")"
  done

  if [[ -z "$root" ]] && command -v git >/dev/null 2>&1; then
    if gc="$(git rev-parse --git-common-dir 2>/dev/null)" && [[ -n "$gc" ]]; then
      [[ "$gc" = /* ]] || gc="$(pwd)/$gc"
      gc_abs="$(cd "$gc" 2>/dev/null && pwd || true)"
      if [[ -n "$gc_abs" ]]; then
        main_checkout="$(dirname "$gc_abs")"
        probe="$main_checkout"
        while [[ "$probe" != "/" && -n "$probe" ]]; do
          if [[ -f "$probe/workspace-config.yaml" ]]; then
            root="$probe"
            break
          fi
          probe="$(dirname "$probe")"
        done
      fi
    fi
  fi

  if [[ -z "$root" ]]; then
    probe="$(pwd)"
    while [[ "$probe" != "/" && -n "$probe" ]]; do
      if [[ -d "$probe/.git" || -f "$probe/.git" ]]; then
        root="$probe"
        break
      fi
      probe="$(dirname "$probe")"
    done
  fi

  [[ -n "$root" ]] || { echo "error: could not locate workspace root" >&2; return 1; }
  printf '%s\n' "$root"
}

emit_unique_match() {
  local label="$1"
  shift
  local -a matches=("$@")
  if [[ ${#matches[@]} -eq 0 ]]; then
    return 1
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "error: ${label} resolved to multiple work orders:" >&2
    printf '  %s\n' "${matches[@]}" >&2
    return 1
  fi
  abs_path "${matches[0]}"
}

resolve_direct_path() {
  local candidate="$1"
  [[ -f "$candidate" ]] || return 1
  case "$candidate" in
    *.md) abs_path "$candidate" ;;
    *) return 1 ;;
  esac
}

resolve_by_jira() {
  local root="$1"
  local jira_key="$2"
  local -a task_matches=()
  local -a legacy_plan_matches=()
  local line=""

  while IFS= read -r -d '' line; do
    if grep -Eq "^>.*\\bJIRA:\\s*${jira_key}\\b" "$line"; then
      task_matches+=("$line")
    fi
  done < <(
    find "$root" \
      \( -type d \( -name .git -o -name .worktrees -o -name node_modules \) -prune \) \
      -o \
      \( -type f -name 'T*.md' \( -path '*/specs/*/tasks/*.md' -o -path '*/specs/*/tasks/complete/*.md' \) -print0 \)
  )

  if [[ ${#task_matches[@]} -gt 0 ]]; then
    emit_unique_match "JIRA ${jira_key}" "${task_matches[@]}"
    return $?
  fi

  while IFS= read -r -d '' line; do
    legacy_plan_matches+=("$line")
  done < <(
    find "$root" \
      \( -type d \( -name .git -o -name .worktrees -o -name node_modules \) -prune \) \
      -o \
      \( -type f -path "*/specs/${jira_key}/plan.md" -print0 \)
  )

  if [[ ${#legacy_plan_matches[@]} -gt 0 ]]; then
    emit_unique_match "legacy plan ${jira_key}" "${legacy_plan_matches[@]}"
    return $?
  fi

  echo "error: no task.md / plan.md found for JIRA ${jira_key}" >&2
  return 1
}

resolve_by_branch() {
  local root="$1"
  local branch="$2"
  [[ -f "$BY_BRANCH_SCRIPT" ]] || { echo "error: missing dependency: $BY_BRANCH_SCRIPT" >&2; return 1; }
  bash "$BY_BRANCH_SCRIPT" --scan-root "$root" "$branch" | head -n 1
}

resolve_by_pr() {
  local root="$1"
  local pr_ref="$2"
  local branch=""

  command -v gh >/dev/null 2>&1 || { echo "error: gh is required to resolve PR input: $pr_ref" >&2; return 1; }
  branch="$(gh pr view "$pr_ref" --json headRefName --jq .headRefName 2>/dev/null || true)"
  [[ -n "$branch" && "$branch" != "null" ]] || { echo "error: failed to resolve PR head branch from: $pr_ref" >&2; return 1; }
  resolve_by_branch "$root" "$branch"
}

resolve_from_input() {
  local root="$1"
  local raw="$2"
  local extracted=""
  local kind=""
  local value=""
  local cwd_root=""

  [[ -n "${raw//[[:space:]]/}" ]] || { echo "error: --from-input requires non-empty text" >&2; return 2; }

  if resolve_direct_path "$raw" >/dev/null 2>&1; then
    resolve_direct_path "$raw"
    return 0
  fi

  extracted="$(python3 - "$raw" <<'PY'
import re
import sys

raw = sys.argv[1]
patterns = [
    ("path", r"((?:\.\.?/|~/|/)?[^\s'\"]+\.md)\b"),
    ("pr_url", r"(https?://github\.com/[^/\s]+/[^/\s]+/pull/\d+)"),
    ("jira", r"\b([A-Z][A-Z0-9]+-\d+)\b"),
]
for kind, pattern in patterns:
    m = re.search(pattern, raw)
    if m:
        print(f"{kind}\t{m.group(1)}")
        raise SystemExit(0)
m = re.fullmatch(r'\s*#?(\d+)\s*', raw)
if m:
    print(f"pr_number\t{m.group(1)}")
else:
    print("unknown\t")
PY
)"

  kind="${extracted%%$'\t'*}"
  value="${extracted#*$'\t'}"
  case "$kind" in
    path)
      value="${value/#\~/$HOME}"
      if [[ -f "$value" ]]; then
        abs_path "$value"
        return 0
      fi
      cwd_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
      if [[ -f "$cwd_root/$value" ]]; then
        abs_path "$cwd_root/$value"
        return 0
      fi
      echo "error: markdown path mentioned in input does not exist: $value" >&2
      return 1
      ;;
    pr_url)
      resolve_by_pr "$root" "$value"
      ;;
    pr_number)
      resolve_by_pr "$root" "$value"
      ;;
    jira)
      resolve_by_jira "$root" "$value"
      ;;
    *)
      echo "error: could not resolve work order from raw input" >&2
      return 1
      ;;
  esac
}

run_selftest() {
  local tmpdir=""
  local out=""
  local rc=0

  tmpdir="$(mktemp -d -t resolve-task-md-selftest.XXXXXX)"
  trap "rm -rf '$tmpdir'" EXIT
  mkdir -p "$tmpdir/specs/GT-478/tasks/complete" "$tmpdir/specs/GT-478/tasks" "$tmpdir/specs/GT-999"

  cat > "$tmpdir/specs/GT-478/tasks/T3b.md" <<'MD'
# T3b: Example (1 pt)
> Epic: GT-478 | JIRA: GT-480 | Repo: kkday
## Operational Context
| Task branch | task/GT-480-example |
MD

  cat > "$tmpdir/specs/GT-478/tasks/complete/T3a.md" <<'MD'
# T3a: Example (1 pt)
> Epic: GT-478 | JIRA: GT-479 | Repo: kkday
MD

  cat > "$tmpdir/specs/GT-999/plan.md" <<'MD'
# Legacy plan
MD

  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" GT-480)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/T3b.md" ]] || { echo "[selftest] jira active FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" GT-479)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/complete/T3a.md" ]] || { echo "[selftest] jira complete FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" GT-999)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-999/plan.md" ]] || { echo "[selftest] legacy plan FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" --from-input '請做 GT-480')" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/T3b.md" ]] || { echo "[selftest] from-input jira FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" --write-lock GT-480)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/T3b.md" ]] || { echo "[selftest] write-lock FAIL"; return 1; }
  [[ -f "$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" --print-lock-path GT-480 2>/dev/null)" ]] || { echo "[selftest] lock file missing"; return 1; }

  echo "[selftest] PASS"
}

if [[ "${RESOLVE_TASK_MD_SELFTEST:-0}" == "1" ]]; then
  run_selftest
  exit $?
fi

scan_root=""
mode=""
input_value=""
write_lock_flag=0
print_lock_path_flag=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-root)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      scan_root="$2"
      shift 2
      ;;
    --write-lock)
      write_lock_flag=1
      shift
      ;;
    --print-lock-path)
      print_lock_path_flag=1
      shift
      ;;
    --clear-lock)
      mode="clear-lock"
      shift
      ;;
    --current)
      mode="current"
      shift
      ;;
    --from-input)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      mode="from-input"
      input_value="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 2
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      [[ -z "$mode" ]] || { echo "error: unexpected extra argument: $1" >&2; usage; exit 2; }
      mode="direct"
      input_value="$1"
      shift
      ;;
  esac
done

[[ -n "$mode" ]] || { usage; exit 2; }

root="$(detect_workspace_root "$scan_root")" || exit $?

if [[ "$mode" == "clear-lock" ]]; then
  clear_lock "$root"
  exit 0
fi

if [[ "$print_lock_path_flag" == "1" ]]; then
  lock_path_for_root "$root"
  exit 0
fi

resolved_path=""

case "$mode" in
  current)
    command -v git >/dev/null 2>&1 || { echo "error: --current requires git in PATH" >&2; exit 2; }
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [[ -n "$branch" && "$branch" != "HEAD" ]] || { echo "error: --current: could not resolve current branch" >&2; exit 1; }
    resolved_path="$(resolve_by_branch "$root" "$branch")"
    ;;
  from-input)
    resolved_path="$(resolve_from_input "$root" "$input_value")"
    ;;
  direct)
    if resolve_direct_path "$input_value" >/dev/null 2>&1; then
      resolved_path="$(resolve_direct_path "$input_value")"
    elif [[ "$input_value" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
      resolved_path="$(resolve_by_jira "$root" "$input_value")"
    elif [[ "$input_value" =~ ^https?://github\.com/.+/pull/[0-9]+$ || "$input_value" =~ ^#?[0-9]+$ ]]; then
      resolved_path="$(resolve_by_pr "$root" "${input_value#\#}")"
    else
      echo "error: unsupported input: $input_value" >&2
      echo "supported: path, JIRA key, PR URL, PR number, --current, --from-input" >&2
      exit 1
    fi
    ;;
esac

if [[ "$write_lock_flag" == "1" ]]; then
  write_lock "$root" "$resolved_path" "$mode" "${input_value:-}"
fi

printf '%s\n' "$resolved_path"
