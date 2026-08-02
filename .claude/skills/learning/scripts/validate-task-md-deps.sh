#!/usr/bin/env bash
# validate-task-md-deps.sh — cross-file validator for task.md depends_on topology + fixture paths.
#
# Usage:
#   validate-task-md-deps.sh <path/to/specs/{EPIC}/tasks/>
#   validate-task-md-deps.sh --scan <workspace_root>
#
# Supports legacy task files (`tasks/T1.md`, `tasks/V1.md`) and folder-native
# task containers (`tasks/T1/index.md`, `tasks/V1/index.md`). Completed tasks
# under `tasks/pr-release/` are lookup targets but are not schema-scanned.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<EOF
usage: $0 <path/to/specs/{EPIC}/tasks/>
       $0 --scan <workspace_root>
EOF
  exit 2
}

validate_epic_tasks_dir() {
  local tasks_dir="$1"
  if [[ ! -d "$tasks_dir" ]]; then
    echo "error: tasks directory not found: $tasks_dir" >&2
    return 2
  fi

  local epic_dir workspace_root
  epic_dir=$(cd "$tasks_dir/.." 2>/dev/null && pwd)
  workspace_root=$(git -C "$tasks_dir" rev-parse --show-toplevel 2>/dev/null || echo "$epic_dir")

  python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_task_md_deps_1.py" "$tasks_dir" "$epic_dir" "$workspace_root"
}

run_selftest() {
  local tmpdir rc
  tmpdir="$(mktemp -d -t validate-task-md-deps-selftest.XXXXXX)"
  trap "rm -rf '$tmpdir'" EXIT

  mkdir -p "$tmpdir/spec/tasks/T1" "$tmpdir/spec/tasks/T2" "$tmpdir/spec/tasks/pr-release/T3" "$tmpdir/spec/tasks/V1"
  cat > "$tmpdir/spec/tasks/T1/index.md" <<'MD'
---
depends_on: []
---
# T1: One (1 pt)
- **Fixtures**: N/A
MD
  cat > "$tmpdir/spec/tasks/T2/index.md" <<'MD'
---
depends_on: [T1]
---
# T2: Two (1 pt)
- **Fixtures**: N/A
MD
  cat > "$tmpdir/spec/tasks/pr-release/T3/index.md" <<'MD'
# T3: Released (1 pt)
MD
  cat > "$tmpdir/spec/tasks/V1/index.md" <<'MD'
---
depends_on: [T3]
---
# V1: Verify (1 pt)
- **Fixtures**: N/A
MD
  validate_epic_tasks_dir "$tmpdir/spec/tasks"

  mkdir -p "$tmpdir/dup/tasks/T1"
  cat > "$tmpdir/dup/tasks/T1.md" <<'MD'
# T1: Legacy (1 pt)
MD
  cat > "$tmpdir/dup/tasks/T1/index.md" <<'MD'
# T1: Folder (1 pt)
MD
  rc=0
  validate_epic_tasks_dir "$tmpdir/dup/tasks" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "2" ]] || { echo "[selftest] duplicate active source should hard fail"; return 1; }

  mkdir -p "$tmpdir/t-to-v/tasks/V1"
  cat > "$tmpdir/t-to-v/tasks/T1.md" <<'MD'
---
depends_on: [V1]
---
# T1: Bad (1 pt)
MD
  cat > "$tmpdir/t-to-v/tasks/V1/index.md" <<'MD'
# V1: Verify (1 pt)
MD
  rc=0
  validate_epic_tasks_dir "$tmpdir/t-to-v/tasks" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "1" ]] || { echo "[selftest] T→V should fail"; return 1; }

  echo "[selftest] PASS"
}

if [[ "${VALIDATE_TASK_MD_DEPS_SELFTEST:-0}" == "1" ]]; then
  run_selftest
  exit $?
fi

if [[ $# -lt 1 ]]; then
  usage
fi

if [[ "$1" == "--scan" ]]; then
  if [[ $# -ne 2 ]]; then
    usage
  fi
  root="$2"
  if [[ ! -d "$root" ]]; then
    echo "error: scan root not found: $root" >&2
    exit 2
  fi
  specs_root="$(resolve_specs_root "$root")" || {
    echo "error: could not resolve specs root under: $root" >&2
    exit 2
  }

  pass=0
  fail=0
  while IFS= read -r d; do
    case "$d" in
      */.worktrees/*|*/node_modules/*|*/archive/*|*/tasks/pr-release) continue ;;
    esac
    if validate_epic_tasks_dir "$d" >/dev/null 2>&1; then
      printf "PASS  %s\n" "$d"
      pass=$((pass+1))
    else
      printf "FAIL  %s\n" "$d"
      validate_epic_tasks_dir "$d" 2>&1 | sed 's/^/      /' >&2 || true
      fail=$((fail+1))
    fi
  done < <(find "$specs_root" -type d -name 'tasks' -path '*/tasks' 2>/dev/null | sort)

  echo ""
  echo "task.md deps scan: $pass pass, $fail fail (total $((pass+fail)))"
  exit 0
fi

validate_epic_tasks_dir "$1"
