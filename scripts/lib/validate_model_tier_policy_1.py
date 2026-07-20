"""Structured validator authority extracted from scripts/validate-model-tier-policy.sh."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
pattern = re.compile(
    r'model:[ \t]*"?((haiku)|(sonnet)|(opus)|(claude-[A-Za-z0-9._-]+)|(gpt-[A-Za-z0-9._-]+))"?'
    r"|claude-sonnet-[A-Za-z0-9._-]+"
    r"|gpt-[0-9][A-Za-z0-9._-]*"
    r"|\b(haiku|sonnet|opus)[ \t]+(model|sub-agent|subagent)\b"
    r"|\b(haiku|sonnet|opus)\b[ \t]+for[ \t]+.*(batch|jira|explore|execute|review|implementation|coding)"
)


def rel(path: Path) -> str:
    return os.path.relpath(path, root)


def is_allowed(path: str) -> bool:
    if path == ".claude/skills/references/model-tier-policy.md":
        return True
    if path == "CHANGELOG.md" or path.endswith("/CHANGELOG.md"):
        return True
    if "release-notes" in path or "ReleaseNotes" in path:
        return True
    if "runtime" in path and "example" in path:
        return True
    if "runtime" in path and "adapter" in path:
        return True
    if "model" in path and "adapter" in path:
        return True
    if re.fullmatch(r"specs/[^/]+/artifacts/research-report-.*\.md", path):
        return True
    if re.fullmatch(r"specs/design-plans/[^/]+/artifacts/research-report-.*\.md", path):
        return True
    return False


def candidate_files():
    roots: list[Path] = []
    for path in [root / ".claude/skills", root / ".claude/rules"]:
        if path.is_dir():
            roots.append(path)
    for path in [root / "CLAUDE.md", root / "AGENTS.md"]:
        if path.is_file():
            roots.append(path)

    for scan_root in roots:
        if scan_root.is_file():
            yield scan_root
            continue
        for dirpath, dirnames, filenames in os.walk(scan_root):
            dirnames[:] = [
                name for name in dirnames if name not in {".git", "node_modules"}
            ]
            for name in filenames:
                path = Path(dirpath) / name
                if name == "SKILL.md" or path.suffix in {
                    ".md",
                    ".json",
                    ".yaml",
                    ".yml",
                }:
                    yield path


failed = False
for path in candidate_files():
    relative = rel(path)
    if is_allowed(relative):
        continue
    matches: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        continue
    for line_no, line in enumerate(lines, start=1):
        if pattern.search(line):
            matches.append(f"{line_no}:{line}")
    if matches:
        failed = True
        print(
            f"FAIL: raw provider model policy outside approved mapping location: {relative}",
            file=sys.stderr,
        )
        print("\n".join(matches), file=sys.stderr)

sys.exit(1 if failed else 0)
