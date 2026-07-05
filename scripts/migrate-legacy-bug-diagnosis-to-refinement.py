#!/usr/bin/env python3
"""Migrate a legacy Bug RCA comment into refinement Bug source artifacts."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


SECTION_RE = re.compile(r"^\[([A-Z_]+)\]\s*$")
JIRA_RE = re.compile(r"^[A-Z][A-Z0-9]+-\d+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket", required=True, help="Bug ticket key, e.g. BUG-4190")
    parser.add_argument("--comment-file", required=True, type=Path)
    parser.add_argument("--target-dir", required=True, type=Path)
    parser.add_argument("--apply", action="store_true", dest="apply_changes")
    return parser.parse_args()


def advisory(message: str) -> None:
    print(f"ADVISORY: {message}")


def parse_sections(text: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        match = SECTION_RE.match(line.strip())
        if match:
            current = match.group(1)
            sections.setdefault(current, [])
            continue
        if current:
            sections[current].append(line)
    return {key: "\n".join(value).strip() for key, value in sections.items()}


def split_steps(raw: str) -> list[str]:
    steps: list[str] = []
    for line in raw.splitlines():
        cleaned = re.sub(r"^\s*(?:[-*]|\d+[.)])\s*", "", line).strip()
        if cleaned:
            steps.append(cleaned)
    return steps


def parse_bool(raw: str) -> bool:
    normalized = raw.strip().lower()
    return normalized in {"true", "yes", "y", "1", "是", "有", "regression"}


def build_artifact(ticket: str, target_dir: Path, sections: dict[str, str]) -> tuple[dict, list[str]]:
    missing: list[str] = []

    def field(name: str, fallback: str) -> str:
        value = sections.get(name, "").strip()
        if value:
            return value
        missing.append(name)
        return fallback

    root_cause = field("ROOT_CAUSE", "N/A - legacy RCA comment missing [ROOT_CAUSE]")
    impact_scope = field("IMPACT", "N/A - legacy RCA comment missing [IMPACT]")
    source_pr = field("SOURCE_PR", "N/A - legacy RCA comment missing [SOURCE_PR]")
    severity = field("SEVERITY", "unknown - legacy RCA comment missing [SEVERITY]")
    steps = split_steps(sections.get("REPRODUCTION_STEPS", ""))
    if not steps:
        missing.append("REPRODUCTION_STEPS")
        steps = ["N/A - legacy RCA comment missing [REPRODUCTION_STEPS]"]

    regression = parse_bool(sections.get("REGRESSION", "false"))
    task_id = f"{ticket}-T1"
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    artifact = {
        "schema_version": "1.0",
        "source": {
            "type": "bug",
            "id": ticket,
            "jira_key": ticket,
            "container": str(target_dir),
            "plan_path": str(target_dir / "index.md"),
        },
        "version": "1.0",
        "created_at": now,
        "modules": [
            {
                "path": "TBD by refinement Bug source mode",
                "action": "investigate",
                "reason": "Migrated from legacy RCA comment for refinement follow-up.",
            }
        ],
        "acceptance_criteria": [
            {
                "id": "AC1",
                "text": "Migrated Bug source artifact preserves RCA, impact, source PR, severity, regression, and reproduction evidence.",
                "verification": {
                    "method": "unit_test",
                    "detail": "bash scripts/selftests/migrate-legacy-bug-diagnosis-to-refinement-selftest.sh",
                },
            }
        ],
        "dependencies": [],
        "edge_cases": [],
        "predecessor_audit": [],
        "adversarial_pass": [
            {
                "ac_id": "AC1",
                "attack": "Legacy RCA migration silently drops partial or malformed fields.",
                "enforce": "Selftest covers well-formed, partial, malformed, target-exists, and dry-run paths.",
            }
        ],
        "tasks": [
            {
                "id": task_id,
                "kind": "T",
                "title": "Refine migrated Bug source",
                "scope": "Review migrated RCA fields and produce implementation-ready Bug task work order.",
                "modules": [
                    {
                        "path": "TBD by refinement Bug source mode",
                        "action": "investigate",
                        "reason": "Migration preserves RCA but does not author final implementation scope.",
                    }
                ],
                "ac_ids": ["AC1"],
                "dependencies": [],
                "verification": {
                    "method": "unit_test",
                    "detail": "bash scripts/selftests/migrate-legacy-bug-diagnosis-to-refinement-selftest.sh",
                },
            }
        ],
        "reproduction_steps": steps,
        "root_cause": root_cause,
        "source_pr": source_pr,
        "severity": severity,
        "impact_scope": impact_scope,
        "regression": regression,
        "migration": {
            "needs_human_review": bool(missing),
            "missing_fields": missing,
            "source": "legacy RCA comment",
        },
    }
    return artifact, missing


def render_md(artifact: dict) -> str:
    source = artifact["source"]
    missing = artifact["migration"]["missing_fields"]
    missing_text = ", ".join(missing) if missing else "N/A"
    steps = "\n".join(f"- {step}" for step in artifact["reproduction_steps"])
    return f"""---
title: "{source['id']} Bug Refinement"
description: "Migrated Bug source refinement artifact."
draft: true
sidebar:
  hidden: true
---

# {source['id']} Bug Refinement

## Bug-specific Fields

| Field | Value |
|-------|-------|
| Root cause | {artifact['root_cause']} |
| Source PR | {artifact['source_pr']} |
| Severity | {artifact['severity']} |
| Impact scope | {artifact['impact_scope']} |
| Regression | {artifact['regression']} |
| Missing fields | {missing_text} |

## Reproduction Steps

{steps}
"""


def main() -> int:
    args = parse_args()
    ticket = args.ticket.strip()
    if not JIRA_RE.match(ticket):
        print(f"ERROR: invalid --ticket: {ticket}", file=sys.stderr)
        return 2

    if not args.comment_file.is_file():
        print(f"ERROR: comment file not found: {args.comment_file}", file=sys.stderr)
        return 2

    text = args.comment_file.read_text(encoding="utf-8")
    sections = parse_sections(text)
    if not sections.get("ROOT_CAUSE", "").strip():
        advisory("malformed RCA comment; missing [ROOT_CAUSE]; no files written")
        return 0

    refinement_json = args.target_dir / "refinement.json"
    refinement_md = args.target_dir / "refinement.md"
    if args.apply_changes and (refinement_json.exists() or refinement_md.exists()):
        advisory("target refinement artifact exists; no files overwritten")
        return 0

    artifact, missing = build_artifact(ticket, args.target_dir, sections)
    if missing:
        advisory(f"partial legacy RCA comment; missing fields: {', '.join(missing)}")

    if not args.apply_changes:
        advisory("dry-run only; no files written")
        print(json.dumps(artifact, ensure_ascii=False, indent=2))
        return 0

    args.target_dir.mkdir(parents=True, exist_ok=True)
    refinement_json.write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    refinement_md.write_text(render_md(artifact), encoding="utf-8")
    print(f"WROTE: {refinement_json}")
    print(f"WROTE: {refinement_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
