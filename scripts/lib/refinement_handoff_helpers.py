#!/usr/bin/env python3
"""refinement handoff shell orchestration 的結構化 helper。"""
from __future__ import annotations

import sys


def filter_downstream(relative_container: str) -> int:
    relative = relative_container.rstrip("/")
    for raw in sys.stdin:
        path = raw.strip()
        if not path or path.startswith((".polaris/", ".git/")):
            continue
        if relative and (path == relative or path.startswith(relative + "/")):
            continue
        print(path)
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "filter-downstream":
        return filter_downstream(argv[1])
    print(
        "usage: refinement_handoff_helpers.py filter-downstream <relative-container>",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
