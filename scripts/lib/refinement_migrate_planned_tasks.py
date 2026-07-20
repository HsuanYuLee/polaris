#!/usr/bin/env python3
"""Migrate legacy planned_tasks into canonical refinement tasks."""
from __future__ import annotations

import sys
from pathlib import Path

USAGE = "usage: migrate-refinement-planned-tasks-to-canonical.sh <refinement.json> [<refinement.json> ...]"


def migrate_one(target: str) -> int:
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
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    status = 0
    for target in argv:
        if not Path(target).is_file():
            print(f"POLARIS_MIGRATE_TARGET_MISSING:{target}", file=sys.stderr)
            status = 1
            continue
        original = sys.argv
        sys.argv = [original[0], target]
        try:
            try:
                rc = migrate_one(target)
            except SystemExit as exc:
                rc = int(exc.code or 0)
        finally:
            sys.argv = original
        if rc:
            status = rc
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
