#!/usr/bin/env bash
# Purpose: Deterministically migrate a refinement.json from the legacy top-level
#          planned_tasks[] shape to the canonical tasks[] first-class shape (DP-296 T1).
#          Each planned_tasks[] entry is folded by task_id into the matching
#          tasks[].task_shape / tasks[].tracked_deliverable_hint, then the
#          top-level planned_tasks[] block is deleted. The migration is
#          behavior-preserving: folded values come straight from planned_tasks[],
#          missing fields default per refinement-artifact.md
#          (task_shape=implementation, tracked_deliverable_hint=tracked).
# Inputs:  one or more refinement.json file paths as positional arguments.
# Outputs: rewrites each file in place; prints a per-file MIGRATED / NO-OP line to
#          stdout. Exit 0 on success, non-zero (fail-loud) when a planned_tasks[]
#          entry has no matching tasks[] entry (the file is left untouched).
# Side effects: in-place rewrite of the supplied refinement.json file(s).
#
# Idempotency: a file already in canonical shape (no top-level planned_tasks[]) is
# a clean byte-identical no-op.
#
# task_id matching: planned_tasks[].task_id and tasks[].id are both accepted in
# short form (T1 / V1) or full form (DP-NNN-T1). Matching normalizes both to the
# short suffix so a full-form planned task_id folds into a short-form tasks[].id.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 2
fi

if [[ "$#" -lt 1 ]]; then
  echo "usage: migrate-refinement-planned-tasks-to-canonical.sh <refinement.json> [<refinement.json> ...]" >&2
  exit 2
fi

status=0
for target in "$@"; do
  if [[ ! -f "$target" ]]; then
    echo "POLARIS_MIGRATE_TARGET_MISSING:$target" >&2
    status=1
    continue
  fi

  python3 - "$target" <<'PY'
import json
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

planned = data.get("planned_tasks")

# Already canonical -> clean no-op (do not rewrite, preserve bytes).
if planned is None:
    print(f"NO-OP: {path} (no planned_tasks[])")
    sys.exit(0)

if not isinstance(planned, list):
    print(f"POLARIS_MIGRATE_PLANNED_TASKS_NOT_LIST:{path}", file=sys.stderr)
    sys.exit(2)

tasks = data.get("tasks")
if not isinstance(tasks, list):
    # planned_tasks[] present but no tasks[] to fold into -> fail-loud unless
    # planned_tasks[] is empty (then it is just a stale empty block to drop).
    if planned:
        print(f"POLARIS_MIGRATE_NO_TASKS_ARRAY:{path}", file=sys.stderr)
        sys.exit(2)
    del data["planned_tasks"]
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"MIGRATED: {path} (dropped empty planned_tasks[])")
    sys.exit(0)


def short_id(value):
    """Normalize a task id to its short suffix (T1/V1) from short or full form."""
    text = str(value or "")
    full = re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+-([TV][0-9]+[a-z]?)", text)
    if full:
        return full.group(1)
    return text


# Index tasks by short id for folding.
by_short = {}
for task in tasks:
    if not isinstance(task, dict):
        continue
    sid = short_id(task.get("id"))
    if sid:
        by_short[sid] = task

for entry in planned:
    if not isinstance(entry, dict):
        print(f"POLARIS_MIGRATE_PLANNED_ENTRY_NOT_OBJECT:{path}", file=sys.stderr)
        sys.exit(2)
    pid = short_id(entry.get("task_id"))
    target_task = by_short.get(pid)
    if target_task is None:
        # No matching tasks[] entry -> fail-loud, do NOT silently drop the field.
        print(
            f"POLARIS_MIGRATE_ORPHAN_PLANNED_TASK:{path}:{entry.get('task_id')}",
            file=sys.stderr,
        )
        sys.exit(2)
    # Behavior-preserving fold with refinement-artifact.md defaults.
    shape = entry.get("task_shape")
    if shape is None:
        shape = "implementation"
    hint = entry.get("tracked_deliverable_hint")
    if hint is None:
        hint = "tracked"
    target_task["task_shape"] = shape
    target_task["tracked_deliverable_hint"] = hint

del data["planned_tasks"]

with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

print(f"MIGRATED: {path} ({len(planned)} planned_tasks[] folded into tasks[])")
PY
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    status="$rc"
  fi
done

exit "$status"
