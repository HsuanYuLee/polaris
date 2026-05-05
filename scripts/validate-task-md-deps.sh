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

  python3 - "$tasks_dir" "$epic_dir" "$workspace_root" <<'PY'
import os
import re
import sys

tasks_dir, epic_dir, workspace_root = sys.argv[1], sys.argv[2], sys.argv[3]
pr_release_dir = os.path.join(tasks_dir, "pr-release")

TASK_ID_RE = re.compile(r"^[TV][0-9]+[a-z]*$")
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
DEPENDS_ON_ARRAY_RE = re.compile(r"^depends_on\s*:\s*\[(.*?)\]\s*$", re.MULTILINE)
DEPENDS_ON_YAML_LIST_RE = re.compile(r"^depends_on\s*:\s*\n((?:\s*-\s*\S+.*\n)+)", re.MULTILINE)
FIXTURES_LINE_RE = re.compile(r"^\s*[-*]?\s*\*\*Fixtures\*\*\s*:\s*(.+?)$", re.MULTILINE)

errors = []
hard_errors = []

def task_id_from_path(path: str):
    rel = os.path.relpath(path, tasks_dir)
    parts = rel.split(os.sep)
    if len(parts) == 1 and parts[0].endswith(".md"):
        task_id = parts[0][:-3]
        return task_id if TASK_ID_RE.fullmatch(task_id) else None
    if len(parts) == 2 and parts[1] == "index.md":
        return parts[0] if TASK_ID_RE.fullmatch(parts[0]) else None
    if len(parts) == 2 and parts[0] == "pr-release" and parts[1].endswith(".md"):
        task_id = parts[1][:-3]
        return task_id if TASK_ID_RE.fullmatch(task_id) else None
    if len(parts) == 3 and parts[0] == "pr-release" and parts[2] == "index.md":
        return parts[1] if TASK_ID_RE.fullmatch(parts[1]) else None
    return None

def collect_task_files():
    active = {}
    released = {}
    for root, dirs, files in os.walk(tasks_dir):
        dirs[:] = [d for d in dirs if d not in {".git", ".worktrees", "node_modules"}]
        for filename in files:
            if filename != "index.md" and not filename.endswith(".md"):
                continue
            path = os.path.join(root, filename)
            task_id = task_id_from_path(path)
            if not task_id:
                continue
            rel = os.path.relpath(path, tasks_dir)
            bucket = released if rel.startswith(f"pr-release{os.sep}") else active
            bucket.setdefault(task_id, []).append(path)
    return active, released

active, released = collect_task_files()

for task_id, paths in sorted(active.items()):
    if len(paths) > 1:
        hard_errors.append(
            f"folder-native uniqueness violated: active task key '{task_id}' has multiple sources: "
            + ", ".join(sorted(paths))
        )

for task_id, paths in sorted(released.items()):
    if len(paths) > 1:
        hard_errors.append(
            f"folder-native uniqueness violated: pr-release task key '{task_id}' has multiple sources: "
            + ", ".join(sorted(paths))
        )

for task_id in sorted(set(active) & set(released)):
    hard_errors.append(
        f"D6 move-first invariant violated: task key '{task_id}' exists in BOTH active tasks/ and tasks/pr-release/ — "
        f"manual recovery required."
    )

if hard_errors:
    for item in hard_errors:
        print(item, file=sys.stderr)
    sys.exit(2)

all_known_ids = set(active) | set(released)
if not active:
    sys.exit(0)

def parse_depends_on(front: str):
    m = DEPENDS_ON_ARRAY_RE.search(front)
    if m:
        inner = m.group(1).strip()
        if not inner:
            return []
        return [item.strip().strip('"').strip("'") for item in inner.split(",") if item.strip()]
    m = DEPENDS_ON_YAML_LIST_RE.search(front)
    if m:
        items = []
        for line in m.group(1).splitlines():
            item = line.strip().lstrip("-").strip().strip('"').strip("'")
            if item:
                items.append(item)
        return items
    return []

def parse_fixtures(body: str):
    results = []
    for m in FIXTURES_LINE_RE.finditer(body):
        val = m.group(1).strip()
        bt = re.search(r"`([^`]+)`", val)
        if bt:
            results.append(bt.group(1).strip())
        else:
            tok = re.split(r"[\s（）\(\)—]", val, maxsplit=1)[0].strip()
            if tok:
                results.append(tok)
    return results

deps_graph = {}
fixture_paths = {}

for task_id, paths in sorted(active.items()):
    path = paths[0]
    with open(path, encoding="utf-8") as f:
        content = f.read()
    fm = FRONTMATTER_RE.match(content)
    front = fm.group(1) if fm else ""
    deps = parse_depends_on(front)
    deps_graph[task_id] = deps
    fixture_paths[task_id] = parse_fixtures(content)

    for dep in deps:
        if dep not in all_known_ids:
            errors.append(
                f"{os.path.relpath(path, tasks_dir)}: depends_on references '{dep}' but no such task.md "
                f"or folder-native index.md in {tasks_dir}/ or {pr_release_dir}/ "
                f"(active tasks: {sorted(active)})"
            )

for task_id, deps in sorted(deps_graph.items()):
    if task_id.startswith("T"):
        for dep in deps:
            if dep.startswith("V"):
                errors.append(
                    f"{task_id}: T→V depends_on is forbidden — '{task_id}' depends on '{dep}'. "
                    "DP-033 D4 § 5.3：實作不應卡在驗收（避免循環依賴 + Epic 內 phase 化）。"
                )
    if len(deps) > 1:
        errors.append(
            f"{task_id}: non-linear depends_on DAG — {task_id} depends on {deps}. "
            "DP-028 requires linear chain."
        )

color = {task_id: 0 for task_id in deps_graph}
stack = []

def dfs(node):
    color[node] = 1
    stack.append(node)
    for nxt in deps_graph.get(node, []):
        if nxt not in deps_graph:
            continue
        if color[nxt] == 1:
            idx = stack.index(nxt)
            errors.append(f"depends_on cycle detected: {' -> '.join(stack[idx:] + [nxt])}")
            return True
        if color[nxt] == 0 and dfs(nxt):
            return True
    stack.pop()
    color[node] = 2
    return False

for task_id in deps_graph:
    if color[task_id] == 0 and dfs(task_id):
        break

def resolve_fixture(raw: str):
    raw = raw.strip()
    if not raw or raw.lower() == "n/a":
        return []
    if os.path.isabs(raw):
        return [raw]
    epic_parent = os.path.dirname(epic_dir)
    company_base_dir = os.path.dirname(epic_parent)
    return [
        os.path.join(epic_dir, raw),
        os.path.join(company_base_dir, raw),
        os.path.join(workspace_root, raw),
    ]

for task_id, paths in fixture_paths.items():
    for raw in paths:
        if not raw or raw.lower() == "n/a":
            continue
        if not any(ch in raw for ch in ("/", ".", "\\")):
            continue
        candidates = resolve_fixture(raw)
        if not any(os.path.exists(candidate) for candidate in candidates):
            errors.append(
                f"{task_id}: Fixtures path '{raw}' does not exist (checked: {candidates})"
            )

if errors:
    for item in errors:
        print(item, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
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
