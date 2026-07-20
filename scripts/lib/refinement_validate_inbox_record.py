"""驗證 breakdown 產生的 refinement return inbox record。"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path


BODY_CAP_BYTES = 8192
REQUIRED_SECTIONS = ("## Decision", "## Refinement Context", "## Decisions Needed", "## Source Audit")


def split_document(path: Path) -> tuple[dict[str, str], str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        return {}, text
    frontmatter, body = text[4:].split("\n---\n", 1)
    fields: dict[str, str] = {}
    for line in frontmatter.splitlines():
        if line[:1].isspace() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
    return fields, body


def section_body(body: str, heading: str) -> str | None:
    lines = body.splitlines()
    try:
        start = lines.index(heading) + 1
    except ValueError:
        return None
    end = next((index for index in range(start, len(lines)) if lines[index].startswith("## ")), len(lines))
    return "\n".join(lines[start:end])


def validate_file(path: Path) -> int:
    if not path.is_file():
        print(f"error: inbox record not found: {path}", file=sys.stderr)
        return 2
    fields, body = split_document(path)
    errors: list[str] = []
    warnings: list[str] = []
    expected = {
        "skill": "breakdown", "target_skill": "refinement",
        "source": "scope-escalation", "route": "refinement",
    }
    for key, value in expected.items():
        if fields.get(key, "") != value:
            errors.append(f"frontmatter '{key}' must be '{value}' (got '{fields.get(key, '')}')")
    source_type, source_id, epic = (fields.get(key, "") for key in ("source_type", "source_id", "epic"))
    if source_type or source_id:
        if not source_type:
            errors.append("frontmatter 'source_type' is required when 'source_id' is set (must be 'dp' or 'jira')")
        elif source_type not in {"dp", "jira"}:
            errors.append(f"frontmatter 'source_type' must be 'dp' or 'jira' (got '{source_type}')")
        if not source_id:
            errors.append("frontmatter 'source_id' is required when 'source_type' is set")
        elif source_type == "dp" and not re.fullmatch(r"DP-[0-9]+", source_id):
            errors.append(f"frontmatter 'source_id' must match 'DP-<n>' when source_type=dp (got '{source_id}')")
        elif source_type == "jira" and not re.fullmatch(r"[A-Z][A-Z0-9]+-[0-9]+", source_id):
            errors.append(f"frontmatter 'source_id' must match '<PROJECT>-<n>' when source_type=jira (got '{source_id}')")
    elif epic:
        warnings.append("legacy 'epic' field detected without 'source_type'/'source_id'; please migrate to DP-228 source-neutral schema (deprecated read-only compatibility)")
    else:
        errors.append("frontmatter must provide 'source_type' + 'source_id' (DP-228 schema) or legacy 'epic' (deprecated)")
    for key, message in (
        ("source_task", "frontmatter 'source_task' is required"),
        ("source_ticket", "frontmatter 'source_ticket' is required"),
        ("source_sidecar", "frontmatter 'source_sidecar' is required as an audit pointer"),
    ):
        if not fields.get(key):
            errors.append(message)
    if not re.fullmatch(r"[12]", fields.get("escalation_count", "")):
        errors.append(f"frontmatter 'escalation_count' must be 1 or 2 (got '{fields.get('escalation_count', '')}')")
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", fields.get("created_at", "")):
        errors.append(f"frontmatter 'created_at' must be ISO 8601 with Z suffix (got '{fields.get('created_at', '')}')")
    if fields.get("consumed", "") not in {"true", "false"}:
        errors.append(f"frontmatter 'consumed' must be true or false (got '{fields.get('consumed', '')}')")
    for heading in REQUIRED_SECTIONS:
        content = section_body(body, heading)
        if content is None:
            errors.append(f"missing required section '{heading}'")
        elif not re.sub(r"\s", "", content):
            errors.append(f"required section '{heading}' is empty")
    if "## Raw Evidence" in body:
        errors.append("inbox record must not contain '## Raw Evidence'; summarize planner context instead")
    body_size = len(body.encode("utf-8"))
    if body_size > BODY_CAP_BYTES:
        errors.append(f"body size {body_size} bytes exceeds 8KB cap")
    if errors:
        print(f"✗ validate-refinement-inbox-record.sh FAIL — {path}", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    for warning in warnings:
        print(f"⚠ validate-refinement-inbox-record.sh WARN — {warning}", file=sys.stderr)
    print(f"✓ validate-refinement-inbox-record.sh PASS — {path}")
    return 0


def self_test() -> int:
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "record.md"
        path.write_text("""---
skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
source_type: dp
source_id: DP-420
source_task: T10
source_ticket: DP-420-T10
source_sidecar: specs/escalations/T10.md
escalation_count: 1
created_at: 2026-07-20T00:00:00Z
consumed: false
---

## Decision

決策。

## Refinement Context

脈絡。

## Decisions Needed

需要決定。

## Source Audit

稽核。
""", encoding="utf-8")
        print("self-test: validating GOOD inbox record")
        if validate_file(path) != 0:
            return 1
        text = path.read_text(encoding="utf-8").replace("skill: breakdown", "skill: engineering")
        path.write_text(text, encoding="utf-8")
        print("self-test: validating BAD inbox record (expect FAIL)")
        if validate_file(path) == 0:
            print("self-test failed: bad inbox record passed", file=sys.stderr)
            return 1
    print("self-test: ALL PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    cli = os.environ.get("POLARIS_COMPAT_CLI", "validate-refinement-inbox-record.sh")
    if not args or args[0] in {"-h", "--help"}:
        print(f"usage: {cli} <path/to/refinement-inbox/record.md>", file=sys.stderr)
        print(f"       {cli} --self-test", file=sys.stderr)
        return 2
    if args[0] == "--self-test":
        return self_test()
    return validate_file(Path(args[0]))


if __name__ == "__main__":
    raise SystemExit(main())
