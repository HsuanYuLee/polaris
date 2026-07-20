#!/usr/bin/env python3
"""Remove legacy refinement per-task packaging fields."""
from __future__ import annotations

import sys
from pathlib import Path

USAGE = """usage:
  migrate-refinement-packaging-fields.sh [--workspace-root <workspace-root>] [--dry-run]

Scope:
  docs-manager/src/content/docs/specs/design-plans/**/refinement.json

Out of scope:
  archive/** refinement.json
  product/company refinement.json

Hard exclusions:
  DP-231  concurrent-session deferral
  DP-375  halted-source deferral
"""

def usage(message: str | None = None) -> None:
    if message:
        print(message, file=sys.stderr)
    print(USAGE, end="", file=sys.stderr)
    raise SystemExit(2)

script_root=Path(__file__).resolve().parents[2]
workspace=str(script_root)
dry_run="0"
args=sys.argv[1:]
i=0
while i < len(args):
    arg=args[i]
    if arg == "--workspace-root":
        if i+1 >= len(args): usage()
        workspace=args[i+1]; i += 2
    elif arg == "--dry-run": dry_run="1"; i += 1
    elif arg in {"-h", "--help"}: usage()
    else: usage(f"unknown argument: {arg}")
try:
    workspace=str(Path(workspace).resolve(strict=True))
except OSError:
    raise SystemExit(1)
validator=script_root / "scripts/validate-refinement-json.sh"
sys.argv=[sys.argv[0], workspace, str(validator), dry_run]
import json
import os
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

workspace_root = Path(sys.argv[1]).resolve()
validator = Path(sys.argv[2])
dry_run = sys.argv[3] == "1"

design_plans = workspace_root / "docs-manager/src/content/docs/specs/design-plans"
if not design_plans.is_dir():
    print(f"POLARIS_MIGRATE_DESIGN_PLANS_MISSING:{design_plans}", file=sys.stderr)
    sys.exit(2)

hard_exclusions = {
    "DP-231": "concurrent-session",
    "DP-375": "halted-source",
}
packaging_fields = ("allowed_files", "estimate_points")


def source_id_for(path, data):
    source = data.get("source")
    if isinstance(source, dict):
        sid = source.get("id")
        if isinstance(sid, str) and sid.strip():
            return sid.strip()
    for part in path.parts:
        match = re.match(r"^(DP-\d{3})(?:-|$)", part)
        if match:
            return match.group(1)
    return "UNKNOWN"


def short_task_id(source_id, task_id):
    text = str(task_id or "").strip()
    prefix = f"{source_id}-"
    if text.startswith(prefix):
        return text[len(prefix):]
    match = re.fullmatch(r"[A-Z][A-Z0-9]*-\d+-([TV]\d+[a-z]?)", text)
    if match:
        return match.group(1)
    return text


def find_task_md(container, source_id, task_id):
    short = short_task_id(source_id, task_id)
    if not short:
        return None
    candidates = [
        container / "tasks" / short / "index.md",
        container / "tasks" / "pr-release" / short / "index.md",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    tasks_dir = container / "tasks"
    if tasks_dir.is_dir():
        matches = sorted(tasks_dir.glob(f"**/{short}/index.md"))
        if matches:
            return matches[0]
    return None


def parse_task_md_packaging(path):
    text = path.read_text(encoding="utf-8")
    allowed = []
    in_allowed = False
    for line in text.splitlines():
        if re.match(r"^## Allowed Files\s*$", line):
            in_allowed = True
            continue
        if in_allowed and line.startswith("## "):
            break
        if not in_allowed:
            continue
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        item = stripped[2:].strip()
        if item.startswith("`") and item.endswith("`") and len(item) >= 2:
            item = item[1:-1]
        allowed.append(item)

    point_match = re.search(r"\((\d+(?:\.\d+)?)\s*pt\)", text)
    points = point_match.group(1) if point_match else None
    return allowed, points


def decimal_equal(left, right):
    try:
        return Decimal(str(left)) == Decimal(str(right))
    except (InvalidOperation, TypeError):
        return False


def validate_file(path):
    if not validator.is_file():
        return
    result = subprocess.run(
        ["bash", str(validator), str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(
            f"POLARIS_REFINEMENT_PACKAGING_MIGRATION_VALIDATION_FAILED:{path}",
            file=sys.stderr,
        )
        print(result.stderr, file=sys.stderr, end="")
        sys.exit(result.returncode)


def log_stale(source_id, task_id, field, detail):
    print(
        f"STALE_REFINEMENT_PACKAGING_REMOVED: {source_id}:{task_id}:{field}: {detail}"
    )


def migrate_one(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    source_id = source_id_for(path, data)
    if source_id in hard_exclusions:
        print(f"DEFERRED: {source_id} {path} ({hard_exclusions[source_id]})")
        return False

    tasks = data.get("tasks")
    if not isinstance(tasks, list):
        print(f"NO-OP: {path} (no tasks[])")
        return False

    changed = False
    stale_count = 0
    container = path.parent
    for task in tasks:
        if not isinstance(task, dict):
            continue
        present = [field for field in packaging_fields if field in task]
        if not present:
            continue

        task_id = task.get("id")
        task_md = find_task_md(container, source_id, task_id)
        if task_md is None:
            print(f"REMOVE_DRAFT_PACKAGING: {source_id}:{task_id}: no task.md")
        else:
            md_allowed, md_points = parse_task_md_packaging(task_md)
            if "allowed_files" in task:
                refinement_allowed = task.get("allowed_files")
                if not isinstance(refinement_allowed, list):
                    print(
                        f"POLARIS_REFINEMENT_PACKAGING_INVALID:{source_id}:{task_id}:allowed_files is not a list",
                        file=sys.stderr,
                    )
                    sys.exit(2)
                refinement_allowed = [str(item) for item in refinement_allowed]
                if sorted(md_allowed) != sorted(refinement_allowed):
                    stale_count += 1
                    missing = sorted(set(refinement_allowed) - set(md_allowed))
                    extra = sorted(set(md_allowed) - set(refinement_allowed))
                    log_stale(
                        source_id,
                        task_id,
                        "allowed_files",
                        f"task_md_authority missing_from_taskmd={missing!r} extra_in_taskmd={extra!r}",
                    )
            if "estimate_points" in task and not decimal_equal(md_points, task.get("estimate_points")):
                stale_count += 1
                log_stale(
                    source_id,
                    task_id,
                    "estimate_points",
                    f"task_md_authority task_md={md_points!r} refinement={task.get('estimate_points')!r}",
                )

        for field in present:
            del task[field]
        changed = True

    if not changed:
        print(f"NO-OP: {path} (intent-only)")
        return False

    if dry_run:
        print(f"DRY-RUN: {path} stale={stale_count}")
        return True

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    validate_file(path)
    print(f"MIGRATED: {path} stale={stale_count}")
    return True


all_refinements = sorted(
    path
    for path in design_plans.rglob("refinement.json")
    if "/archive/" not in path.as_posix()
)

changed_count = 0
for refinement in all_refinements:
    if migrate_one(refinement):
        changed_count += 1

print(f"SUMMARY: migrated={changed_count} scanned={len(all_refinements)} dry_run={int(dry_run)}")
