"""Static linter for Polaris SKILL.md contract drift."""

from __future__ import annotations

import re
import sys
from pathlib import Path


USAGE = """usage: validate-skill-contracts.sh [--root <skills-dir>] [--strict] [--quiet]

Checks SKILL.md files for common framework contract drift.
"""
CHECKS = (
    (
        "sub-agent-envelope",
        re.compile(r"sub-?agent|dispatch|平行|委派", re.I),
        re.compile(r"Completion Envelope"),
        "sub-agent dispatch text exists without Completion Envelope reference",
    ),
    (
        "post-task-reflection",
        re.compile(r"寫入|更新|create|update|JIRA|Slack|Confluence|PR|commit|產出|Write tool|Edit tool", re.I),
        re.compile(r"Post-Task Reflection"),
        "likely write skill without Post-Task Reflection section",
    ),
    (
        "external-write-language-gate",
        re.compile(r"JIRA comment|Slack|Confluence|github review|review body|inline comment|slack_send_message|addComment|send_message", re.I),
        re.compile(r"validate-language-policy|polaris-external-write-gate|workspace-language-policy"),
        "external write surface without language gate/helper reference",
    ),
    (
        "starlight-authoring",
        re.compile(r"docs-manager/src/content/docs/specs|specs folder|specs/.*\.md|Starlight route"),
        re.compile(r"validate-starlight-authoring|starlight-authoring-contract"),
        "specs markdown producer without Starlight authoring reference",
    ),
)
LEGACY = re.compile(r"(^|[^A-Za-z0-9_])specs/\{EPIC\}|\{workspace_root\}/specs|~/work/", re.M)


def main(argv: list[str]) -> int:
    root = Path(".claude/skills")
    strict = quiet = False
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--root" and index + 1 < len(argv):
            root = Path(argv[index + 1])
            index += 2
            continue
        if arg == "--strict":
            strict = True
        elif arg == "--quiet":
            quiet = True
        elif arg in {"-h", "--help"}:
            print(USAGE, file=sys.stderr, end="")
            return 2
        else:
            print(f"error: unknown argument: {arg}", file=sys.stderr)
            print(USAGE, file=sys.stderr, end="")
            return 2
        index += 1
    if not str(root) or not root.is_dir():
        print(f"error: skills root not found: {root}", file=sys.stderr)
        return 2
    warnings = 0
    errors = 0
    for path in sorted(root.rglob("SKILL.md")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        findings: list[tuple[str, str]] = []
        for name, trigger, required, detail in CHECKS:
            if trigger.search(text) and not required.search(text):
                findings.append((name, detail))
        if LEGACY.search(text):
            findings.append(("legacy-path-pattern", "legacy or user-specific path pattern found"))
        for name, detail in findings:
            warnings += 1
            if not quiet:
                print(f"WARN\t{name}\t{path}\t{detail}")
    if not quiet:
        print(f"summary\terrors={errors}\twarnings={warnings}")
    return 1 if errors or (strict and warnings) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
