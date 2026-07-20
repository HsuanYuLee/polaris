"""Fail closed when a branch name contains a non-ASCII byte."""

from __future__ import annotations

import re
import sys
from pathlib import Path


USAGE = """usage: validate-branch-name-ascii.sh <branch-name>
       validate-branch-name-ascii.sh <task.md>
       validate-branch-name-ascii.sh --task-md <task.md>

Fail-closed branch-name ASCII gate (DP-307 D3): exits 2 with
POLARIS_BRANCH_NAME_NON_ASCII:{branch} when the branch name contains any
non-ASCII byte. ASCII-only names pass untouched.
"""
MISSING_VALUES = {"", "n/a", "na", "-", "--", "none"}


def usage() -> None:
    print(USAGE, file=sys.stderr, end="")


def task_branch(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\|\s*Task branch\s*\|\s*(.*?)\s*\|\s*$", line)
        if match:
            return match.group(1).strip().strip("`")
    return ""


def main(argv: list[str]) -> int:
    if argv and argv[0] in {"-h", "--help"}:
        usage()
        return 0
    if not argv:
        usage()
        return 2

    task_md: Path | None = None
    if argv[0] == "--task-md":
        if len(argv) < 2 or not argv[1]:
            usage()
            return 2
        task_md = Path(argv[1])
    elif Path(argv[0]).is_file() and argv[0].endswith(".md"):
        task_md = Path(argv[0])

    branch = argv[0]
    if task_md is not None:
        if not task_md.is_file():
            print(f"validate-branch-name-ascii: task.md not found: {task_md}", file=sys.stderr)
            print(f"POLARIS_BRANCH_NAME_FIELD_MISSING:{task_md}", file=sys.stderr)
            return 2
        branch = task_branch(task_md)
        if branch.lower() in MISSING_VALUES:
            print(
                f"validate-branch-name-ascii: no usable 'Task branch' field in {task_md}",
                file=sys.stderr,
            )
            print(f"POLARIS_BRANCH_NAME_FIELD_MISSING:{task_md}", file=sys.stderr)
            return 2

    try:
        branch.encode("ascii")
    except UnicodeEncodeError:
        print(
            f"validate-branch-name-ascii: branch name contains non-ASCII bytes: {branch}",
            file=sys.stderr,
        )
        print(f"POLARIS_BRANCH_NAME_NON_ASCII:{branch}", file=sys.stderr)
        return 2
    print(f"validate-branch-name-ascii PASS - {branch}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
