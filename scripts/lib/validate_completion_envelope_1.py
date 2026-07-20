"""Validate Polaris sub-agent Completion Envelope output."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path


USAGE = """Usage:
  scripts/validate-completion-envelope.sh [--blocking] <file>...
  scripts/validate-completion-envelope.sh --self-test

Default mode is advisory: invalid envelopes print warnings and exit 0.
Use --blocking at explicit enforcement callsites.
"""
REQUIRED = (
    "**Artifacts**:",
    "**Detail**:",
    "**Model Class**:",
    "**Runtime Agent**:",
    "**Selected Model**:",
    "**Model Fallback**:",
    "**Summary**:",
)


def validate(path: Path, blocking: bool) -> int:
    if not path.is_file():
        print(f"ERROR: file not found: {path}", file=sys.stderr)
        return 2
    text = path.read_text(encoding="utf-8")
    status = ""
    for line in text.splitlines():
        if line.startswith("## Status:"):
            status = line.removeprefix("## Status:").strip()
            break
    invalid = False
    if status not in {"DONE", "BLOCKED", "PARTIAL"}:
        print(
            f"WARNING: {path}: missing or invalid '## Status: DONE|BLOCKED|PARTIAL'",
            file=sys.stderr,
        )
        invalid = True
    for token in REQUIRED:
        if token not in text:
            print(f"WARNING: {path}: missing required line '{token}'", file=sys.stderr)
            invalid = True
    if status == "BLOCKED" and "**Blocker**:" not in text:
        print(f"WARNING: {path}: BLOCKED status requires '**Blocker**:'", file=sys.stderr)
        invalid = True
    if status == "PARTIAL" and "**Remaining**:" not in text:
        print(f"WARNING: {path}: PARTIAL status requires '**Remaining**:'", file=sys.stderr)
        invalid = True
    if not invalid:
        print(f"PASS: completion envelope valid: {path}")
        return 0
    if blocking:
        return 1
    print(f"WARNING: {path}: advisory mode only; continuing", file=sys.stderr)
    return 0


def self_test() -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        common = """**Artifacts**: none
**Detail**: inline
**Model Class**: standard_coding
**Runtime Agent**: polaris-standard-coding
**Selected Model**: inherit
**Model Fallback**: none
**Summary**: Complete.
"""
        valid = root / "valid.md"
        invalid = root / "invalid.md"
        partial = root / "partial.md"
        valid.write_text("## Status: DONE\n" + common, encoding="utf-8")
        invalid.write_text("## Status: DONE\n**Artifacts**: none\n**Summary**: Missing fields.\n", encoding="utf-8")
        partial.write_text("## Status: PARTIAL\n" + common + "**Remaining**: one follow-up\n", encoding="utf-8")
        if validate(valid, False) != 0 or validate(invalid, False) != 0:
            return 1
        if validate(invalid, True) == 0 or validate(partial, True) != 0:
            print("ERROR: completion envelope self-test failed", file=sys.stderr)
            return 1
    print("validate-completion-envelope self-test PASS")
    return 0


def main(argv: list[str]) -> int:
    blocking = False
    paths: list[Path] = []
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--blocking":
            blocking = True
        elif arg == "--self-test":
            return self_test()
        elif arg in {"--help", "-h"}:
            print(USAGE, end="")
            return 0
        elif arg.startswith("-"):
            print(f"ERROR: unknown option: {arg}", file=sys.stderr)
            print(USAGE, file=sys.stderr, end="")
            return 2
        else:
            paths.append(Path(arg))
        index += 1
    if not paths:
        print(USAGE, file=sys.stderr, end="")
        return 2
    result = 0
    for path in paths:
        current = validate(path, blocking)
        if current:
            result = 1
    return result


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
