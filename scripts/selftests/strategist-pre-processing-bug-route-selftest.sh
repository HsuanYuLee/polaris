#!/usr/bin/env bash
# Verify Bug fix-intent strategist routing points to refinement Bug source mode.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROUTING="$ROOT/.claude/rules/skill-routing.md"

python3 - "$ROUTING" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
legacy = "bug" + "-triage"

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)

if legacy in text or f"/{legacy}" in text:
    fail("legacy Bug diagnosis route token remains")

def section(title: str, next_heading_level: str = "##") -> str:
    marker = f"{next_heading_level} {title}"
    start = text.find(marker)
    if start == -1:
        fail(f"missing section: {title}")
    next_match = re.search(rf"\n{re.escape(next_heading_level)}\s+", text[start + 1 :])
    end = start + 1 + next_match.start() if next_match else len(text)
    return text[start:end]

hotfix = section("Pre-Processing: Hotfix Without JIRA Ticket", "###")
if "Route to `/refinement {BUG_KEY}`" not in hotfix:
    fail("hotfix pre-processing does not route to /refinement")
if "source_kind=bug" not in hotfix:
    fail("hotfix pre-processing does not preserve source_kind=bug")

quick = section("Routing Quick Reference")
plan_row = re.search(r"\| Triage/plan a bug \|.*\| (?P<skill>.*?) \|", quick)
if not plan_row or "`refinement` Bug source mode" not in plan_row.group("skill"):
    fail("Triage/plan a bug row does not target refinement Bug source mode")

no_ticket_row = re.search(r"\| Triage a bug \(no ticket\) \|.*\| (?P<skill>.*?) \|", quick)
if not no_ticket_row or "create Bug ticket" not in no_ticket_row.group("skill") or "`refinement` Bug source mode" not in no_ticket_row.group("skill"):
    fail("Triage a bug (no ticket) row does not create Bug then route refinement")

negative = section("Negative-Tone Trigger Recognition")
if not re.search(r"Ticket key \+ negative tone（Bug）→ `refinement` Bug source mode（若尚無 plan）或 `engineering`", negative):
    fail("negative-tone Bug route does not target refinement before engineering")

print("PASS: strategist pre-processing Bug route selftest")
PY
