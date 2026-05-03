#!/usr/bin/env bash
# resolve-task-md.sh — DP-032 D1 task.md entry resolver
#
# Resolves exactly one engineering work order from:
#   - direct task.md path
#   - JIRA ticket key
#   - PR URL / PR number
#   - current branch
#   - raw user input

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BY_BRANCH_SCRIPT="${SCRIPT_DIR}/resolve-task-md-by-branch.sh"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<'USAGE'
usage: resolve-task-md.sh <path|jira-key|pr-url|pr-number>
       resolve-task-md.sh --current
       resolve-task-md.sh --include-archive <path|jira-key|pr-url|pr-number>
       resolve-task-md.sh --clear-lock
       resolve-task-md.sh --write-lock <path|jira-key|pr-url|pr-number>
       resolve-task-md.sh --write-lock --current
       resolve-task-md.sh --write-lock --from-input "<raw user message>"
       resolve-task-md.sh --from-input "<raw user message>"
       resolve-task-md.sh --scan-root <path> <path|jira-key|pr-url|pr-number>
       resolve-task-md.sh --scan-root <path> --current
       resolve-task-md.sh --scan-root <path> --from-input "<raw user message>"

stdout: absolute path to exactly one task.md
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
    # shellcheck source=lib/main-checkout.sh
    . "$(dirname "$0")/lib/main-checkout.sh"
    if main_checkout="$(resolve_main_checkout 2>/dev/null)"; then
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
    specs/*/tasks/T*.md|specs/*/tasks/pr-release/T*.md|*/specs/*/tasks/T*.md|*/specs/*/tasks/pr-release/T*.md) abs_path "$candidate" ;;
    *) return 1 ;;
  esac
}

resolve_by_dp_task() {
  local root="$1"
  local dp_task="$2"
  local include_archive="${3:-0}"
  local dp_id=""
  local task_id=""
  local specs_root=""
  local -a matches=()
  local line=""

  if [[ ! "$dp_task" =~ ^(DP-[0-9]{3})-(T[0-9]+[a-z]*)$ ]]; then
    return 1
  fi
  dp_id="${BASH_REMATCH[1]}"
  task_id="${BASH_REMATCH[2]}"
  specs_root="$(resolve_specs_root "$root")" || return 1

  if [[ "$include_archive" == "1" ]]; then
    while IFS= read -r -d '' line; do
      matches+=("$line")
    done < <(
      find "$specs_root/design-plans" \
        \( -path "$specs_root/design-plans/${dp_id}-*/tasks/${task_id}.md" -print0 \) \
        -o \( -path "$specs_root/design-plans/${dp_id}-*/tasks/pr-release/${task_id}.md" -print0 \) \
        -o \( -path "$specs_root/design-plans/archive/${dp_id}-*/tasks/${task_id}.md" -print0 \) \
        -o \( -path "$specs_root/design-plans/archive/${dp_id}-*/tasks/pr-release/${task_id}.md" -print0 \) \
        2>/dev/null
    )
  else
    while IFS= read -r -d '' line; do
      matches+=("$line")
    done < <(
      find "$specs_root/design-plans" \
        \( -type d -name archive -prune \) \
        -o \( -path "$specs_root/design-plans/${dp_id}-*/tasks/${task_id}.md" -print0 \) \
        -o \( -path "$specs_root/design-plans/${dp_id}-*/tasks/pr-release/${task_id}.md" -print0 \) \
        2>/dev/null
    )
  fi

  if [[ ${#matches[@]} -gt 0 ]]; then
    emit_unique_match "DP task ${dp_task}" "${matches[@]}"
    return $?
  fi

  echo "error: no DP task.md found for ${dp_task}" >&2
  return 1
}

resolve_by_jira() {
  local root="$1"
  local jira_key="$2"
  local include_archive="${3:-0}"
  local specs_root=""
  local -a task_matches=()
  local line=""
  local parsed_jira=""
  specs_root="$(resolve_specs_root "$root")" || return 1

  while IFS= read -r -d '' line; do
    parsed_jira=""
    if [[ -x "$PARSE_TASK_MD" ]]; then
      parsed_jira="$(bash "$PARSE_TASK_MD" "$line" --no-resolve --field jira_key 2>/dev/null || true)"
    fi
    if [[ "$parsed_jira" == "$jira_key" ]]; then
      task_matches+=("$line")
    elif grep -Eq "^>.*\\bJIRA:\\s*${jira_key}\\b" "$line"; then
      task_matches+=("$line")
    fi
  done < <(
    if [[ "$include_archive" == "1" ]]; then
      find "$specs_root" \
        \( -type d \( -name .git -o -name .worktrees -o -name node_modules \) -prune \) \
        -o \
        \( -type f -name 'T*.md' \( -path '*/tasks/*.md' -o -path '*/tasks/pr-release/*.md' \) -print0 \)
    else
      find "$specs_root" \
        \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
        -o \
        \( -type f -name 'T*.md' \( -path '*/tasks/*.md' -o -path '*/tasks/pr-release/*.md' \) -print0 \)
    fi
  )

  if [[ ${#task_matches[@]} -gt 0 ]]; then
    emit_unique_match "JIRA ${jira_key}" "${task_matches[@]}"
    return $?
  fi

  echo "error: no task.md found for JIRA ${jira_key}" >&2
  return 1
}

resolve_by_epic_series_ordinal() {
  local root="$1"
  local epic_key="$2"
  local series="$3"
  local ordinal="${4:-}"
  local include_archive="${5:-0}"
  local specs_root=""
  local -a candidates=()
  local line=""
  local selected=""
  specs_root="$(resolve_specs_root "$root")" || return 1

  while IFS= read -r -d '' line; do
    candidates+=("$line")
  done < <(
    if [[ "$include_archive" == "1" ]]; then
      find "$specs_root" \
        \( -type d \( -name .git -o -name .worktrees -o -name node_modules \) -prune \) \
        -o \
        \( -type f \( -path "*/${epic_key}/tasks/${series}*.md" -o -path "*/${epic_key}/tasks/pr-release/${series}*.md" \) -print0 \)
    else
      find "$specs_root" \
        \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
        -o \
        \( -type f \( -path "*/${epic_key}/tasks/${series}*.md" -o -path "*/${epic_key}/tasks/pr-release/${series}*.md" \) -print0 \)
    fi
  )

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "error: no ${series} series task.md found for ${epic_key}" >&2
    return 1
  fi

  selected="$(python3 - "$ordinal" "${candidates[@]}" <<'PY'
import os
import re
import sys

ordinal = sys.argv[1].strip().lower()
paths = sys.argv[2:]

def task_sort_key(path):
    name = os.path.splitext(os.path.basename(path))[0]
    m = re.fullmatch(r"T(\d+)([a-z]*)", name, re.I)
    canonical = 0 if "/companies/" in path else 1
    if not m:
        return (canonical, 999999, "zzzz", path)
    return (canonical, int(m.group(1)), m.group(2).lower(), path)

paths = sorted(paths, key=task_sort_key)
if ordinal in {"first", "1", "1st", "one", "第一", "第1", "首張", "第一張"}:
    print(paths[0])
elif ordinal in {"second", "2", "2nd", "two", "第二", "第2", "第二張"}:
    if len(paths) < 2:
        raise SystemExit(1)
    print(paths[1])
else:
    print("AMBIGUOUS")
    for path in paths:
        print(path)
PY
)" || {
    echo "error: ordinal ${ordinal:-<none>} is out of range for ${epic_key} ${series} series" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    return 1
  }

  if [[ "$selected" == AMBIGUOUS$'\n'* || "$selected" == "AMBIGUOUS" ]]; then
    echo "error: ${epic_key} ${series} series resolved to multiple work orders; provide an ordinal or exact task id:" >&2
    printf '%s\n' "$selected" | tail -n +2 | sed 's/^/  /' >&2
    return 1
  fi

  abs_path "$selected"
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
  local include_archive="${3:-0}"
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
if re.search(r"\bDP-\d{3}-T\d+[a-z]*\b", raw, re.I):
    raise SystemExit(1)
epic = re.search(r"\b([A-Z][A-Z0-9]+-\d+)\b", raw)
series = re.search(r"\b(T\d+)\s*(?:系列|series)?\b", raw, re.I)
if not (epic and series):
    raise SystemExit(1)
ordinal = ""
lower = raw.lower()
if re.search(r"(第一張|第一|第\s*1|首張|\bfirst\b|\b1st\b)", lower):
    ordinal = "first"
elif re.search(r"(第二張|第二|第\s*2|\bsecond\b|\b2nd\b)", lower):
    ordinal = "second"
print(f"epic_series\t{epic.group(1)}\t{series.group(1).upper()}\t{ordinal}")
PY
)" && {
    IFS=$'\t' read -r kind value series ordinal <<<"$extracted"
    if [[ "$kind" == "epic_series" ]]; then
      resolve_by_epic_series_ordinal "$root" "$value" "$series" "$ordinal" "$include_archive"
      return $?
    fi
  }

  extracted="$(python3 - "$raw" <<'PY'
import re
import sys

raw = sys.argv[1]
patterns = [
    ("dp_task", r"\b(DP-\d{3}-T\d+[a-z]*)\b"),
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
    dp_task)
      resolve_by_dp_task "$root" "$value" "$include_archive"
      ;;
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
      resolve_by_jira "$root" "$value" "$include_archive"
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
  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/GT-478/tasks/pr-release" "$tmpdir/docs-manager/src/content/docs/specs/GT-478/tasks" "$tmpdir/docs-manager/src/content/docs/specs/GT-999" \
           "$tmpdir/docs-manager/src/content/docs/specs/companies/kkday/GT-478/tasks/pr-release" "$tmpdir/docs-manager/src/content/docs/specs/companies/kkday/GT-478/tasks" \
           "$tmpdir/docs-manager/src/content/docs/specs/companies/kkday/archive/GT-999/tasks"

  cat > "$tmpdir/docs-manager/src/content/docs/specs/GT-478/tasks/T3b.md" <<'MD'
# T3b: Example (1 pt)
> Epic: GT-478 | JIRA: GT-480 | Repo: kkday
## Operational Context
| Task branch | task/GT-480-example |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/GT-478/tasks/pr-release/T3a.md" <<'MD'
# T3a: Example (1 pt)
> Epic: GT-478 | JIRA: GT-479 | Repo: kkday
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/kkday/GT-478/tasks/pr-release/T3a.md" <<'MD'
# T3a: Canonical series first (1 pt)
> Source: GT-478 | Task: KB2CW-3711 | JIRA: KB2CW-3711 | Repo: kkday
## Operational Context
| Source type | jira |
| Source ID | GT-478 |
| Task ID | KB2CW-3711 |
| JIRA key | KB2CW-3711 |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/kkday/GT-478/tasks/T3b.md" <<'MD'
# T3b: Canonical series second (1 pt)
> Source: GT-478 | Task: KB2CW-3902 | JIRA: KB2CW-3902 | Repo: kkday
## Operational Context
| Source type | jira |
| Source ID | GT-478 |
| Task ID | KB2CW-3902 |
| JIRA key | KB2CW-3902 |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/GT-478/tasks/T4.md" <<'MD'
# T4: Canonical product task (1 pt)
> Source: GT-478 | Task: GT-481 | JIRA: GT-481 | Repo: kkday
## Operational Context
| Source type | jira |
| Source ID | GT-478 |
| Task ID | GT-481 |
| JIRA key | GT-481 |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/kkday/archive/GT-999/tasks/T1.md" <<'MD'
# T1: Archived task (1 pt)
> Source: GT-999 | Task: GT-999 | JIRA: GT-999 | Repo: kkday
## Operational Context
| Source type | jira |
| Source ID | GT-999 |
| Task ID | GT-999 |
| JIRA key | GT-999 |
MD

  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-047-framework-work-order-bridge/tasks"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-047-framework-work-order-bridge/tasks/T1.md" <<'MD'
# T1: DP task (1 pt)
> Epic: DP-047 | JIRA: DP-047-T1 | Repo: workspace
## Operational Context
| Task JIRA key | DP-047-T1 |
| Task branch | task/DP-047-T1-framework-bridge |
MD

  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/pr-release"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/pr-release/T1.md" <<'MD'
# T1: Canonical DP task (1 pt)
> Source: DP-050 | Task: DP-050-T1 | JIRA: N/A | Repo: workspace
## Operational Context
| Source type | dp |
| Source ID | DP-050 |
| Task ID | DP-050-T1 |
| JIRA key | N/A |
MD

  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" GT-480)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/T3b.md" ]] || { echo "[selftest] jira active FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" GT-479)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/pr-release/T3a.md" ]] || { echo "[selftest] jira complete FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" GT-481)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/T4.md" ]] || { echo "[selftest] canonical jira lookup FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" GT-999)" || rc=$?
  [[ $rc -eq 1 ]] || { echo "[selftest] default archive exclusion FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --include-archive --scan-root "$tmpdir" GT-999)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/companies/kkday/archive/GT-999/tasks/T1.md" ]] || { echo "[selftest] include-archive lookup FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" --from-input '請做 GT-480')" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/GT-478/tasks/T3b.md" ]] || { echo "[selftest] from-input jira FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" DP-047-T1)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/design-plans/DP-047-framework-work-order-bridge/tasks/T1.md" ]] || { echo "[selftest] dp task FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" --from-input 'engineering DP-047-T1')" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/design-plans/DP-047-framework-work-order-bridge/tasks/T1.md" ]] || { echo "[selftest] from-input dp task FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" --from-input '請做 GT-478 T3 系列第一張')" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/companies/kkday/GT-478/tasks/pr-release/T3a.md" ]] || { echo "[selftest] from-input epic series first FAIL"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" --from-input '請做 GT-478 T3 series')" || rc=$?
  [[ $rc -eq 1 ]] || { echo "[selftest] ambiguous epic series should fail"; return 1; }

  rc=0
  out="$(env -u RESOLVE_TASK_MD_SELFTEST bash "$0" --scan-root "$tmpdir" DP-050-T1)" || rc=$?
  [[ $rc -eq 0 && "$out" == *"/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/pr-release/T1.md" ]] || { echo "[selftest] canonical dp pr-release task FAIL"; return 1; }

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
include_archive_flag=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-root)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      scan_root="$2"
      shift 2
      ;;
    --include-archive)
      include_archive_flag=1
      shift
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
    resolved_path="$(resolve_from_input "$root" "$input_value" "$include_archive_flag")"
    ;;
  direct)
    if resolve_direct_path "$input_value" >/dev/null 2>&1; then
      resolved_path="$(resolve_direct_path "$input_value")"
    elif [[ "$input_value" =~ ^DP-[0-9]{3}-T[0-9]+[a-z]*$ ]]; then
      resolved_path="$(resolve_by_dp_task "$root" "$input_value" "$include_archive_flag")"
    elif [[ "$input_value" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
      resolved_path="$(resolve_by_jira "$root" "$input_value" "$include_archive_flag")"
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
