"""Structured validator authority extracted from scripts/validate-route-safe-spec-paths.sh."""

import re
import sys
from pathlib import Path

inputs = [Path(p) for p in sys.argv[1:]]
SAFE_SEGMENT = re.compile(r"^[A-Za-z0-9_-]+$")


def fail(message: str, code: int = 1):
    print(message, file=sys.stderr)
    sys.exit(code)


def markdown_files(path: Path):
    if not path.exists():
        fail(f"error: path not found: {path}", 2)
    if path.is_file():
        if path.suffix != ".md":
            fail(f"error: not a markdown file: {path}", 2)
        yield path
        return
    yield from sorted(path.rglob("*.md"))


def route_segments(path: Path):
    parts = list(path.parts)
    if "specs" in parts:
        parts = parts[parts.index("specs") + 1 :]
    for idx, part in enumerate(parts):
        if idx == len(parts) - 1 and part.endswith(".md"):
            yield part[:-3], part
        else:
            yield part, part


seen = set()
rows = []
for input_path in inputs:
    for file in markdown_files(input_path):
        resolved = file.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        for segment, raw in route_segments(file):
            if not SAFE_SEGMENT.fullmatch(segment):
                suggestion = re.sub(r"[^A-Za-z0-9_-]+", "-", segment).strip("-").lower()
                rows.append(
                    (str(file), raw, suggestion or "rename-to-route-safe-segment")
                )

if rows:
    print("path\tunsafe-segment\tsuggested-segment", file=sys.stderr)
    for row in rows:
        print("\t".join(row), file=sys.stderr)
    sys.exit(1)

print(f"PASS: route-safe specs paths ({len(seen)} file(s))")
