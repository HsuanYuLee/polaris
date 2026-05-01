#!/usr/bin/env bash
# validate-task-md-deps.sh — cross-file validator for task.md depends_on topology + fixture paths.
#
# Usage:
#   validate-task-md-deps.sh <path/to/specs/{EPIC}/tasks/>
#   validate-task-md-deps.sh --scan <workspace_root>
#
# Exit:  0 = schema pass (single) / scan complete (scan mode, always 0)
#        1 = schema violations (single mode; details printed to stderr)
#        2 = usage error / directory not found / hard invariant violation (same-key duplicate)
#
# Contract source: skills/references/pipeline-handoff.md § Artifact Schemas —
#                  task.md Cross-File Schema
#           also:  skills/references/task-md-schema.md § 5.2 + § 5.3 + § 5.5 + § 6
#                  (DP-033 Phase A D6 + D8; Phase B 跨類型 V→T / T→V 方向性)
# Called by:       .claude/hooks/pipeline-artifact-gate.sh (PreToolUse hook)
#
# Validates (T*.md AND V*.md, DP-033 Phase B 雙路徑共用):
#   1. `depends_on` (frontmatter) references only existing T{n}/V{n}[suffix].md in the same dir
#      — with active→pr-release fallback (DP-033 D8): if tasks/{id}.md missing, check
#        tasks/pr-release/{id}.md before reporting broken ref.
#   2. `depends_on` graph is a DAG — no cycles (跨 T/V 同圖)
#   3. `Fixtures:` paths in `## Test Environment` exist on filesystem (when non-N/A)
#   4. `depends_on` graph is a linear chain (each task has ≤ 1 dep) — DP-028 is-linear-dag rule
#   5. Same-key uniqueness (DP-033 D6 § 5.5): if the same task key exists in BOTH tasks/
#      and tasks/pr-release/, exit 2 (HARD FAIL — D6 move-first invariant violated).
#   6. **V→T / T→V cross-type direction (DP-033 D4 § 5.3，Phase B 新增)**:
#      - V→T 合法（驗收前提是相關實作完成）
#      - V→V 合法（驗收 chain，仍受線性限制）
#      - T→V 禁止（實作不應卡在驗收，避免 Epic 內 phase 化；exit 1，建議拆 Epic）
#
# Scope: T*.md and V*.md files in the tasks/ top-level directory are scanned for schema.
#   Files under tasks/pr-release/ are never scanned (they retain their historical shape).
#   However, pr-release/ IS searched when resolving depends_on references.

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

if [[ $# -lt 1 ]]; then
  usage
fi

validate_epic_tasks_dir() {
  local tasks_dir="$1"
  if [[ ! -d "$tasks_dir" ]]; then
    echo "error: tasks directory not found: $tasks_dir" >&2
    return 2
  fi

  # Epic folder = parent of tasks/ (used for Fixtures resolution)
  local epic_dir
  epic_dir=$(cd "$tasks_dir/.." 2>/dev/null && pwd)

  # Workspace root = walk up until we find a parent that contains 'specs/'.
  # Fall back to git root if we can't infer cleanly.
  local workspace_root
  workspace_root=$(git -C "$tasks_dir" rev-parse --show-toplevel 2>/dev/null || echo "$epic_dir")

  # Delegate to python3 — YAML frontmatter + graph cycle detection is much cleaner there.
  python3 - "$tasks_dir" "$epic_dir" "$workspace_root" <<'PY'
import os
import re
import sys

tasks_dir, epic_dir, workspace_root = sys.argv[1], sys.argv[2], sys.argv[3]

# pr-release/ subdirectory for reader fallback (DP-033 D8)
pr_release_dir = os.path.join(tasks_dir, "pr-release")

errors = []
hard_errors = []  # exit 2 violations (same-key uniqueness)

# --- Enumerate T*.md / V*.md files (active tasks/ only — pr-release/ is skipped for schema scanning) ---
# DP-033 Phase B: filename pattern 從 T*.md 擴展為 [TV]*.md (T = implementation, V = verification).
TASK_FILE_RE = re.compile(r'^[TV][0-9]+[a-z]*\.md$')

task_files = []
for name in sorted(os.listdir(tasks_dir)):
    if TASK_FILE_RE.match(name):
        task_files.append(name)

if not task_files:
    # Nothing to validate in active dir; not an error.
    # Still check same-key uniqueness if pr-release/ exists.
    pass

# task_id = basename without .md (e.g., "T1", "T8a", "V1", "V2a")
task_ids = {f[:-3] for f in task_files}

# --- DP-033 D6 § 5.5: Same-key uniqueness hard check (T/V 共用) ---
# If the same task key exists in BOTH tasks/ and tasks/pr-release/, that is a
# D6 move-first invariant violation — hard fail (exit 2).
if os.path.isdir(pr_release_dir):
    complete_ids = set()
    for name in os.listdir(pr_release_dir):
        if TASK_FILE_RE.match(name):
            complete_ids.add(name[:-3])
    duplicates = task_ids & complete_ids
    if duplicates:
        for dup in sorted(duplicates):
            hard_errors.append(
                f"D6 move-first invariant violated: task key '{dup}' exists in BOTH "
                f"{tasks_dir}/{dup}.md AND {pr_release_dir}/{dup}.md — "
                f"manual recovery required (rm the stale copy or complete the mv)."
            )

if hard_errors:
    for e in hard_errors:
        print(e)
    sys.exit(2)

# --- Build set of all resolvable task ids (active + pr-release) for depends_on fallback ---
# DP-033 D8: depends_on may reference a task that has been moved to pr-release/.
# We treat any T*.md / V*.md found in either location as a valid reference target.
all_known_ids = set(task_ids)
if os.path.isdir(pr_release_dir):
    for name in os.listdir(pr_release_dir):
        if TASK_FILE_RE.match(name):
            all_known_ids.add(name[:-3])

if not task_files:
    # Nothing active to validate further.
    sys.exit(0)

# --- Parse frontmatter + Test Environment Fixtures line per file ---
FRONTMATTER_RE = re.compile(r'^---\s*\n(.*?)\n---\s*\n', re.DOTALL)
DEPENDS_ON_ARRAY_RE = re.compile(r'^depends_on\s*:\s*\[(.*?)\]\s*$', re.MULTILINE)
DEPENDS_ON_YAML_LIST_RE = re.compile(
    r'^depends_on\s*:\s*\n((?:\s*-\s*\S+.*\n)+)', re.MULTILINE
)
FIXTURES_LINE_RE = re.compile(
    r'^\s*[-*]?\s*\*\*Fixtures\*\*\s*:\s*(.+?)$', re.MULTILINE
)

deps_graph = {}          # task_id -> [dep_task_ids]
fixture_paths = {}       # task_id -> [raw fixture path strings]

def parse_depends_on(front):
    """Return list of dep ids parsed from frontmatter text block."""
    # Array form:  depends_on: [T1, T2]
    m = DEPENDS_ON_ARRAY_RE.search(front)
    if m:
        inner = m.group(1).strip()
        if not inner:
            return []
        items = [i.strip().strip('"').strip("'") for i in inner.split(',')]
        return [i for i in items if i]

    # YAML list form:
    #   depends_on:
    #     - T1
    #     - T2
    m = DEPENDS_ON_YAML_LIST_RE.search(front)
    if m:
        items = []
        for line in m.group(1).splitlines():
            ln = line.strip().lstrip('-').strip().strip('"').strip("'")
            if ln:
                items.append(ln)
        return items

    return []

def parse_fixtures(body):
    """Return list of raw fixture path strings (may be 'N/A', code-fenced, or a real path)."""
    results = []
    for m in FIXTURES_LINE_RE.finditer(body):
        val = m.group(1).strip()
        # Strip trailing commentary like "（Mockoon CLI port 3100）"
        # Take the first token or bracketed path.
        # Be lenient: extract backtick-wrapped content first, else take content up to first space.
        bt = re.search(r'`([^`]+)`', val)
        if bt:
            results.append(bt.group(1).strip())
        else:
            # split on common separators (space, parenthesis, em-dash)
            tok = re.split(r'[\s（）\(\)—]', val, maxsplit=1)[0].strip()
            if tok:
                results.append(tok)
    return results

for fname in task_files:
    tid = fname[:-3]
    fpath = os.path.join(tasks_dir, fname)
    with open(fpath, encoding='utf-8') as f:
        content = f.read()

    front = ''
    fm = FRONTMATTER_RE.match(content)
    if fm:
        front = fm.group(1)

    deps = parse_depends_on(front)
    deps_graph[tid] = deps

    # --- Check broken refs (with active→pr-release fallback per DP-033 D8) ---
    for dep in deps:
        if dep not in all_known_ids:
            errors.append(
                f"{fname}: depends_on references '{dep}' but no such task.md "
                f"in {tasks_dir}/ or {pr_release_dir}/ "
                f"(active tasks: {sorted(task_ids)})"
            )

    # --- Fixture path extraction ---
    fixture_paths[tid] = parse_fixtures(content)

# --- DP-033 D4 § 5.3: V→T / T→V cross-type direction (Phase B) ---
# V→T 合法 (驗收前提是相關實作完成)
# V→V 合法 (驗收 chain，仍受 DP-028 線性限制)
# T→V 禁止 (實作不應卡在驗收，避免 Epic 內 phase 化)
# T→T 合法 (既有規則，§ 5.2)
for tid in sorted(deps_graph):
    if not tid.startswith('T'):
        continue
    for dep in deps_graph[tid]:
        if dep.startswith('V'):
            errors.append(
                f"{tid}.md: T→V depends_on is forbidden — '{tid}' depends on '{dep}'. "
                f"DP-033 D4 § 5.3：實作不應卡在驗收（避免循環依賴 + Epic 內 phase 化）。"
                f"考慮拆 Epic（兩個交付 = 兩個 Epic）或重新排序 task。"
            )

# --- Cycle detection (DFS coloring: 0=unvisited, 1=in-stack, 2=done) ---
color = {tid: 0 for tid in deps_graph}
stack = []

def dfs(node):
    color[node] = 1
    stack.append(node)
    for nxt in deps_graph.get(node, []):
        if nxt not in deps_graph:
            continue  # already reported as broken ref
        if color[nxt] == 1:
            # Cycle — extract chain from stack
            idx = stack.index(nxt)
            cycle = stack[idx:] + [nxt]
            errors.append(
                f"depends_on cycle detected: {' -> '.join(cycle)}"
            )
            return True
        elif color[nxt] == 0:
            if dfs(nxt):
                return True
    color[node] = 2
    stack.pop()
    return False

for tid in deps_graph:
    if color[tid] == 0:
        if dfs(tid):
            break

# --- Linearity check (DP-028 is-linear-dag) ---
# Each task may have ≤ 1 depends_on. Non-linear depends_on (task depends on ≥ 2
# independent tasks) is rejected — breakdown must either linearize the order or split the Epic.
for tid in sorted(deps_graph):
    deps = deps_graph[tid]
    if len(deps) > 1:
        errors.append(
            f"{tid}.md: non-linear depends_on DAG — {tid} depends on {deps}. "
            f"DP-028 requires linear chain. Either linearize the dependency order or split the Epic."
        )

# --- Fixture path existence ---
def resolve_fixture(raw):
    """Return list of candidate absolute paths to check.

    Fixture paths in task.md are commonly written in one of three forms:
      1. Absolute path
      2. Relative to Epic folder (e.g., `tests/mockoon/`)
      3. Relative to company base dir or workspace root (e.g., `specs/GT-478/tests/mockoon/`)
    """
    raw = raw.strip()
    if not raw or raw.lower() == 'n/a':
        return []
    if os.path.isabs(raw):
        return [raw]
    # company_base_dir = parent of specs/{EPIC}/ = parent of epic_dir.parent
    epic_parent = os.path.dirname(epic_dir)           # .../specs
    company_base_dir = os.path.dirname(epic_parent)   # .../kkday
    candidates = [
        os.path.join(epic_dir, raw),
        os.path.join(company_base_dir, raw),
        os.path.join(workspace_root, raw),
    ]
    return candidates

for tid, paths in fixture_paths.items():
    for raw in paths:
        if not raw or raw.lower() == 'n/a':
            continue
        # Skip obvious non-path values (e.g., "TBD", "待定")
        if not any(ch in raw for ch in ('/', '.', '\\')):
            continue
        candidates = resolve_fixture(raw)
        if not any(os.path.exists(c) for c in candidates):
            errors.append(
                f"{tid}.md: Fixtures path '{raw}' does not exist "
                f"(checked: {candidates})"
            )

if errors:
    for e in errors:
        print(e)
    sys.exit(1)

sys.exit(0)
PY
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    return 0
  fi

  # DP-033 D6: exit 2 = hard invariant violation (same-key duplicate).
  # Propagate exit 2 directly — do not re-run diagnostics, the Python already printed to stdout.
  if [[ $rc -eq 2 ]]; then
    echo "✗ HARD FAIL (exit 2): D6 move-first invariant violated in $tasks_dir" >&2
    echo "  Manual recovery required. See output above for details." >&2
    return 2
  fi

  echo "✗ task.md cross-file schema violations in $tasks_dir:" >&2
  # Re-run to surface errors already printed to stdout by python (we captured above with status only).
  # Simpler: just mark failure — python already printed to stdout which got swallowed.
  # Re-run for diagnostic output:
  python3 - "$tasks_dir" "$epic_dir" "$workspace_root" <<'PY' 2>/dev/null | sed 's/^/  - /' >&2 || true
import os, re, sys
tasks_dir, epic_dir, workspace_root = sys.argv[1], sys.argv[2], sys.argv[3]
# DP-033 D8: pr-release/ directory for reader fallback
pr_release_dir = os.path.join(tasks_dir, "pr-release")
errors = []

FRONTMATTER_RE = re.compile(r'^---\s*\n(.*?)\n---\s*\n', re.DOTALL)
DEPENDS_ON_ARRAY_RE = re.compile(r'^depends_on\s*:\s*\[(.*?)\]\s*$', re.MULTILINE)
DEPENDS_ON_YAML_LIST_RE = re.compile(r'^depends_on\s*:\s*\n((?:\s*-\s*\S+.*\n)+)', re.MULTILINE)
FIXTURES_LINE_RE = re.compile(r'^\s*[-*]?\s*\*\*Fixtures\*\*\s*:\s*(.+?)$', re.MULTILINE)

TASK_FILE_RE = re.compile(r'^[TV][0-9]+[a-z]*\.md$')
task_files = sorted([n for n in os.listdir(tasks_dir) if TASK_FILE_RE.match(n)])
task_ids = {f[:-3] for f in task_files}
# All known ids = active + pr-release (for fallback resolution)
all_known_ids = set(task_ids)
if os.path.isdir(pr_release_dir):
    for name in os.listdir(pr_release_dir):
        if TASK_FILE_RE.match(name):
            all_known_ids.add(name[:-3])
deps_graph = {}
fixture_paths = {}

def parse_depends_on(front):
    m = DEPENDS_ON_ARRAY_RE.search(front)
    if m:
        inner = m.group(1).strip()
        if not inner: return []
        return [i.strip().strip('"').strip("'") for i in inner.split(',') if i.strip()]
    m = DEPENDS_ON_YAML_LIST_RE.search(front)
    if m:
        items = []
        for line in m.group(1).splitlines():
            ln = line.strip().lstrip('-').strip().strip('"').strip("'")
            if ln: items.append(ln)
        return items
    return []

def parse_fixtures(body):
    results = []
    for m in FIXTURES_LINE_RE.finditer(body):
        val = m.group(1).strip()
        bt = re.search(r'`([^`]+)`', val)
        if bt: results.append(bt.group(1).strip())
        else:
            tok = re.split(r'[\s（）\(\)—]', val, maxsplit=1)[0].strip()
            if tok: results.append(tok)
    return results

for fname in task_files:
    tid = fname[:-3]
    with open(os.path.join(tasks_dir, fname), encoding='utf-8') as f:
        content = f.read()
    front = ''
    fm = FRONTMATTER_RE.match(content)
    if fm: front = fm.group(1)
    deps = parse_depends_on(front)
    deps_graph[tid] = deps
    for dep in deps:
        if dep not in all_known_ids:
            errors.append(f"{fname}: depends_on references '{dep}' but no such task.md in {tasks_dir}/ or {pr_release_dir}/ (active tasks: {sorted(task_ids)})")
    fixture_paths[tid] = parse_fixtures(content)

# DP-033 D4 § 5.3: V→T pass / T→V fail (Phase B)
for tid in sorted(deps_graph):
    if not tid.startswith('T'): continue
    for dep in deps_graph[tid]:
        if dep.startswith('V'):
            errors.append(f"{tid}.md: T→V depends_on is forbidden — '{tid}' depends on '{dep}'. DP-033 D4 § 5.3：實作不應卡在驗收（避免循環依賴 + Epic 內 phase 化）。考慮拆 Epic（兩個交付 = 兩個 Epic）或重新排序 task。")

color = {tid: 0 for tid in deps_graph}
stack = []
def dfs(node):
    color[node] = 1; stack.append(node)
    for nxt in deps_graph.get(node, []):
        if nxt not in deps_graph: continue
        if color[nxt] == 1:
            idx = stack.index(nxt)
            cycle = stack[idx:] + [nxt]
            errors.append(f"depends_on cycle detected: {' -> '.join(cycle)}")
            return True
        elif color[nxt] == 0:
            if dfs(nxt): return True
    color[node] = 2; stack.pop(); return False

for tid in deps_graph:
    if color[tid] == 0:
        if dfs(tid): break

# DP-028 is-linear-dag
for tid in sorted(deps_graph):
    deps = deps_graph[tid]
    if len(deps) > 1:
        errors.append(f"{tid}.md: non-linear depends_on DAG — {tid} depends on {deps}. DP-028 requires linear chain. Either linearize the dependency order or split the Epic.")

def resolve_fixture(raw):
    raw = raw.strip()
    if not raw or raw.lower() == 'n/a': return []
    if os.path.isabs(raw): return [raw]
    epic_parent = os.path.dirname(epic_dir)
    company_base_dir = os.path.dirname(epic_parent)
    return [
        os.path.join(epic_dir, raw),
        os.path.join(company_base_dir, raw),
        os.path.join(workspace_root, raw),
    ]

for tid, paths in fixture_paths.items():
    for raw in paths:
        if not raw or raw.lower() == 'n/a': continue
        if not any(ch in raw for ch in ('/', '.', '\\')): continue
        cands = resolve_fixture(raw)
        if not any(os.path.exists(c) for c in cands):
            errors.append(f"{tid}.md: Fixtures path '{raw}' does not exist (checked: {cands})")

for e in errors: print(e)
PY
  echo "" >&2
  echo "Contract: skills/references/pipeline-handoff.md § Artifact Schemas — task.md Cross-File Schema" >&2
  echo "         skills/references/task-md-schema.md § 5.5 + § 6 (DP-033 D6 + D8)" >&2
  return 1
}

# --- Scan mode ---
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
      */.worktrees/*|*/node_modules/*|*/archive/*) continue ;;
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

# --- Single-dir mode ---
validate_epic_tasks_dir "$1"
exit $?
