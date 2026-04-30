#!/usr/bin/env bash
set -euo pipefail

# close-parent-spec-if-complete.sh
#
# Best-effort parent lifecycle closer for task-based specs.
#
# Usage:
#   bash scripts/close-parent-spec-if-complete.sh --task-md <task.md> [--workspace <path>] [--dry-run]
#   CLOSE_PARENT_SPEC_SELFTEST=1 bash scripts/close-parent-spec-if-complete.sh
#
# Behavior:
#   - Given a task under specs/**/tasks/ or specs/**/tasks/pr-release/, find the
#     parent refinement.md / plan.md.
#   - If any active sibling task remains under tasks/, NOOP.
#   - If any pr-release sibling task is not status: IMPLEMENTED, NOOP.
#   - If all sibling tasks are implemented, check off task checklist items,
#     rewrite moved task links to tasks/pr-release/*.md, and mark the parent
#     spec IMPLEMENTED.
#   - Design plans use codex-mark-design-plan-implemented.sh so checklist
#     governance still applies.
#   - Product/company specs use mark-spec-implemented.sh against the parent key.

PREFIX="[polaris parent-closeout]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TASK_MD=""
DRY_RUN=0

usage() {
  sed -n '3,21p' "$0" >&2
}

run_selftest() {
  local tmpdir dp_dir company_dir
  tmpdir="$(mktemp -d -t parent-closeout-selftest.XXXXXX)"
  trap "rm -rf '$tmpdir'" EXIT

  dp_dir="$tmpdir/specs/design-plans/DP-999-parent-closeout"
  mkdir -p "$dp_dir/tasks/pr-release"
  cat >"$dp_dir/plan.md" <<'MD'
---
topic: parent closeout smoke
created: 2026-04-30
status: LOCKED
locked_at: 2026-04-30
---

# DP-999

## Implementation Checklist

- [ ] T1: First task — `tasks/T1.md`
- [ ] T2: Second task — `tasks/T2.md`

## Work Orders

| Task | Work order |
|------|------------|
| T1 | `tasks/T1.md` |
| T2 | `tasks/T2.md` |
MD
  for task in T1 T2; do
    cat >"$dp_dir/tasks/pr-release/${task}.md" <<MD
---
status: IMPLEMENTED
---
# ${task}

> Source: DP-999 | Task: DP-999-${task} | JIRA: N/A | Repo: polaris-framework
MD
  done

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T2.md" --workspace "$tmpdir" >/dev/null
  grep -q '^status: IMPLEMENTED$' "$dp_dir/plan.md" || {
    echo "[selftest] DP parent was not marked IMPLEMENTED" >&2
    return 1
  }
  grep -q 'tasks/pr-release/T1.md' "$dp_dir/plan.md" || {
    echo "[selftest] DP task links were not rewritten" >&2
    return 1
  }

  company_dir="$tmpdir/specs/companies/kkday/GT-999"
  mkdir -p "$company_dir/tasks/pr-release"
  cat >"$company_dir/refinement.md" <<'MD'
---
status: LOCKED
---
# GT-999 — Parent closeout smoke

## Implementation Checklist

- [ ] T1: Product task — `tasks/T1.md`
MD
  cat >"$company_dir/tasks/pr-release/T1.md" <<'MD'
---
status: IMPLEMENTED
---
# T1

> Source: GT-999 | Task: KB2CW-9999 | JIRA: KB2CW-9999 | Repo: kkday-b2c-web
MD

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$company_dir/tasks/pr-release/T1.md" --workspace "$tmpdir" >/dev/null
  grep -q '^status: IMPLEMENTED$' "$company_dir/refinement.md" || {
    echo "[selftest] product parent was not marked IMPLEMENTED" >&2
    return 1
  }

  echo "[selftest] PASS"
}

if [[ "${CLOSE_PARENT_SPEC_SELFTEST:-0}" == "1" ]]; then
  run_selftest
  exit $?
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md)
      TASK_MD="${2:-}"
      shift 2
      ;;
    --workspace)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

[[ -n "$TASK_MD" ]] || {
  echo "$PREFIX --task-md is required" >&2
  usage
  exit 64
}
[[ -f "$TASK_MD" ]] || { echo "$PREFIX task.md not found: $TASK_MD" >&2; exit 64; }
[[ -d "$WORKSPACE_ROOT" ]] || { echo "$PREFIX workspace not found: $WORKSPACE_ROOT" >&2; exit 64; }

WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"
TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"

info_file="$(mktemp)"
trap 'rm -f "$info_file"' EXIT

python3 - "$TASK_MD" "$WORKSPACE_ROOT" "$DRY_RUN" >"$info_file" <<'PY'
import json
import re
import sys
from pathlib import Path

task_md = Path(sys.argv[1]).resolve()
workspace = Path(sys.argv[2]).resolve()
dry_run = sys.argv[3] == "1"

def emit(**kwargs):
    print(json.dumps(kwargs, ensure_ascii=False))

def frontmatter_status(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return ""
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---\n", 4)
    if end == -1:
        return ""
    for line in text[4:end].splitlines():
        if line.startswith("status:"):
            return line.split(":", 1)[1].strip()
    return ""

parts = task_md.parts
if "tasks" not in parts:
    emit(action="noop", reason="task path is not under tasks/", task_md=str(task_md))
    sys.exit(0)

tasks_index = len(parts) - 1 - list(reversed(parts)).index("tasks")
tasks_dir = Path(*parts[: tasks_index + 1])
parent_dir = tasks_dir.parent

if not parent_dir.exists():
    emit(action="noop", reason="parent dir not found", task_md=str(task_md))
    sys.exit(0)

is_design_plan = "/specs/design-plans/" in str(parent_dir)
if is_design_plan:
    parent_file = parent_dir / "plan.md"
    parent_key = next((p for p in parent_dir.name.split("-")[:2] if p.startswith("DP")), "")
else:
    parent_file = parent_dir / "refinement.md"
    if not parent_file.exists():
        parent_file = parent_dir / "plan.md"
    parent_key = parent_dir.name

if not parent_file.exists():
    emit(action="noop", reason="parent refinement.md/plan.md not found", parent_dir=str(parent_dir))
    sys.exit(0)

active_tasks = sorted(
    p for p in tasks_dir.iterdir()
    if p.is_file() and re.fullmatch(r"[TV]\d+[a-z]*\.md", p.name)
)
if active_tasks:
    emit(
        action="noop",
        reason="active sibling tasks remain",
        parent=str(parent_file),
        active=[str(p) for p in active_tasks],
    )
    sys.exit(0)

pr_release = tasks_dir / "pr-release"
completed_tasks = sorted(
    p for p in pr_release.iterdir()
    if p.is_file() and re.fullmatch(r"[TV]\d+[a-z]*\.md", p.name)
) if pr_release.exists() else []

if not completed_tasks:
    emit(action="noop", reason="no pr-release sibling tasks found", parent=str(parent_file))
    sys.exit(0)

unfinished = [
    str(p) for p in completed_tasks
    if frontmatter_status(p) != "IMPLEMENTED"
]
if unfinished:
    emit(
        action="noop",
        reason="pr-release sibling tasks are not all IMPLEMENTED",
        parent=str(parent_file),
        unfinished=unfinished,
    )
    sys.exit(0)

completed_stems = {p.stem for p in completed_tasks}
text = parent_file.read_text(encoding="utf-8")

def rewrite_links(value: str) -> str:
    return re.sub(r"tasks/(?!pr-release/)([TV]\d+[a-z]*\.md)", r"tasks/pr-release/\1", value)

lines = text.splitlines()
out = []
in_checklist = False
remaining_unchecked = 0
for line in lines:
    if line.startswith("## "):
        in_checklist = line.strip() == "## Implementation Checklist"
        out.append(line)
        continue

    new_line = rewrite_links(line)
    if in_checklist and re.search(r"- \[ \]", new_line):
        refs = set(re.findall(r"tasks/(?:pr-release/)?([TV]\d+[a-z]*)\.md", new_line))
        prefix = re.match(r"\s*- \[ \]\s*([TV]\d+[a-z]*)(?=[:\s])", new_line)
        if prefix:
            refs.add(prefix.group(1))
        if refs and refs.issubset(completed_stems):
            new_line = new_line.replace("- [ ]", "- [x]", 1)
        else:
            remaining_unchecked += 1
    out.append(new_line)

new_text = "\n".join(out)
if text.endswith("\n"):
    new_text += "\n"

if remaining_unchecked:
    if new_text != text and not dry_run:
        parent_file.write_text(new_text, encoding="utf-8")
    emit(
        action="noop",
        reason="parent checklist still has unchecked non-task items",
        parent=str(parent_file),
        remaining_unchecked=remaining_unchecked,
    )
    sys.exit(0)

if new_text != text and not dry_run:
    parent_file.write_text(new_text, encoding="utf-8")

emit(
    action="close",
    parent=str(parent_file),
    parent_key=parent_key,
    parent_type="design-plan" if is_design_plan else "spec",
    task_count=len(completed_tasks),
    dry_run=dry_run,
)
PY

action="$(python3 - "$info_file" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("action", "noop"))
PY
)"

if [[ "$action" != "close" ]]; then
  python3 - "$info_file" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
reason = data.get("reason", "not complete")
parent = data.get("parent", "")
suffix = f" ({parent})" if parent else ""
print(f"[polaris parent-closeout] NOOP: {reason}{suffix}")
PY
  exit 0
fi

parent_file="$(python3 - "$info_file" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["parent"])
PY
)"
parent_key="$(python3 - "$info_file" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["parent_key"])
PY
)"
parent_type="$(python3 - "$info_file" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["parent_type"])
PY
)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "$PREFIX DRY-RUN: would mark ${parent_type} parent IMPLEMENTED: ${parent_file}"
  exit 0
fi

if [[ "$parent_type" == "design-plan" ]]; then
  bash "${SCRIPT_DIR}/codex-mark-design-plan-implemented.sh" "$parent_file"
else
  bash "${SCRIPT_DIR}/mark-spec-implemented.sh" "$parent_key" --workspace "$WORKSPACE_ROOT"
fi

echo "$PREFIX ✅ parent implemented: ${parent_file}"
