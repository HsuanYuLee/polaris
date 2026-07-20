"""Require an owning DP reference whenever mise.toml changes."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


USAGE = """usage: validate-mise-dependency-change.sh [--diff <ref>]
                                          [--pr-body <path> | --pr-body-stdin]
                                          [--root <dir>]
                                          [--mise-path <path>]
                                          [--diff-files-override <list>]
"""


def usage(message: str | None = None) -> int:
    if message:
        print(message, file=sys.stderr)
    print(USAGE, file=sys.stderr, end="")
    return 2


def main(argv: list[str]) -> int:
    base = "HEAD"
    body_file = ""
    body_stdin = False
    root = Path.cwd()
    mise_path = "mise.toml"
    diff_override: str | None = None
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg in {"-h", "--help"}:
            print(USAGE, file=sys.stderr, end="")
            return 0
        if arg == "--pr-body-stdin":
            body_stdin = True
            index += 1
            continue
        if arg not in {"--diff", "--pr-body", "--root", "--mise-path", "--diff-files-override"}:
            return usage(f"unknown argument: {arg}")
        if index + 1 >= len(argv) or not argv[index + 1]:
            return usage(f"{arg} requires a value")
        value = argv[index + 1]
        if arg == "--diff":
            base = value
        elif arg == "--pr-body":
            body_file = value
        elif arg == "--root":
            root = Path(value)
        elif arg == "--mise-path":
            mise_path = value
        else:
            diff_override = value
        index += 2

    if diff_override is None:
        result = subprocess.run(
            ["git", "diff", "--name-only", base, "--", "."],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode:
            print(f"POLARIS_MISE_DEPENDENCY_GATE_USAGE: cannot diff against {base}", file=sys.stderr)
            return 2
        diff_files = result.stdout.splitlines()
    else:
        diff_files = diff_override.splitlines()
    if mise_path not in diff_files:
        print("PASS: mise.toml unchanged; skip")
        return 0

    if body_stdin:
        body = sys.stdin.read()
    elif body_file:
        path = Path(body_file)
        if not path.is_file():
            print(f"POLARIS_MISE_DEPENDENCY_GATE_USAGE: PR body file missing: {body_file}", file=sys.stderr)
            return 2
        body = path.read_text(encoding="utf-8")
    else:
        print(f"POLARIS_MISE_DEPENDENCY_DP_MISSING:{mise_path}", file=sys.stderr)
        print("mise.toml changed but no --pr-body / --pr-body-stdin provided", file=sys.stderr)
        return 2
    if re.search(r"\bDP-[0-9]+\b", body):
        print("PASS: mise.toml change references an owning DP")
        return 0
    print(f"POLARIS_MISE_DEPENDENCY_DP_MISSING:{mise_path}", file=sys.stderr)
    print("mise.toml changed but PR body does not reference any DP-NNN", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
