#!/usr/bin/env bash
# audit-dogfood-evidence.sh — validate DP dogfood evidence schema and consumed mapping.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/audit-dogfood-evidence.sh [--require-consumed] <dogfood-evidence-dir>

Validates YYYY-MM-DD-*.md dogfood evidence entries:
  - Starlight frontmatter: title, description, draft: true, sidebar.hidden: true
  - Required sections: Observed, Judgment, Category, Proposed Fix
  - Category enum: deterministic-gap, llm-judgment-acceptable, dp-207-spec-bug, non-dp-207
  - With --require-consumed, deterministic-gap entries require consumed: true and consumed_by mapping
EOF
  exit 2
}

require_consumed=0
if [[ "${1:-}" == "--require-consumed" ]]; then
  require_consumed=1
  shift
fi

[[ $# -eq 1 ]] || usage
evidence_dir="$1"

python3 - "$evidence_dir" "$require_consumed" <<'PY'
import re
import sys
from pathlib import Path

evidence_dir = Path(sys.argv[1])
require_consumed = sys.argv[2] == "1"

category_values = {
    "deterministic-gap",
    "llm-judgment-acceptable",
    "dp-207-spec-bug",
    "non-dp-207",
}
required_sections = ["Observed", "Judgment", "Category", "Proposed Fix"]
filename_re = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md$")
frontmatter_re = re.compile(r"^---\n(.*?)\n---\n", re.S)
section_re = re.compile(r"^## ([^\n]+)\n(.*?)(?=^## |\Z)", re.S | re.M)


def scalar(frontmatter: str, key: str) -> str | None:
    match = re.search(rf"^{re.escape(key)}:\s*(.*?)\s*$", frontmatter, re.M)
    if not match:
        return None
    return match.group(1).strip().strip('"').strip("'")


def has_consumed_by(frontmatter: str) -> bool:
    inline = re.search(r"^consumed_by:\s*(.+?)\s*$", frontmatter, re.M)
    if inline and inline.group(1).strip() not in {"", "[]"}:
        return True
    block = re.search(r"^consumed_by:\s*\n((?:\s+-\s+\S.*\n?)+)", frontmatter, re.M)
    return bool(block)


def first_meaningful_line(block: str) -> str:
    for raw in block.splitlines():
        line = raw.strip()
        if line and not line.startswith("```"):
            return line.strip("`").strip()
    return ""


errors: list[str] = []

if not evidence_dir.is_dir():
    print(f"dogfood evidence directory not found: {evidence_dir}", file=sys.stderr)
    raise SystemExit(2)

entries = sorted(p for p in evidence_dir.iterdir() if p.is_file() and p.name != "index.md")
entries = [p for p in entries if p.suffix == ".md"]
if not entries:
    errors.append(f"{evidence_dir}: no markdown dogfood evidence entries found")

deterministic_count = 0
unconsumed_count = 0

for path in entries:
    rel = path.name
    if not filename_re.fullmatch(rel):
        errors.append(f"{rel}: filename must match YYYY-MM-DD-{{slug}}.md")
        continue

    text = path.read_text(encoding="utf-8")
    fm_match = frontmatter_re.match(text)
    if not fm_match:
        errors.append(f"{rel}: missing frontmatter")
        continue
    frontmatter = fm_match.group(1)
    body = text[fm_match.end():]

    for key in ("title", "description"):
        if not scalar(frontmatter, key):
            errors.append(f"{rel}: frontmatter {key} is required")
    if scalar(frontmatter, "draft") != "true":
        errors.append(f"{rel}: frontmatter draft must be true")
    if not re.search(r"^sidebar:\s*\n(?:[^\n]*\n)*?\s+hidden:\s*true\s*$", frontmatter, re.M):
        errors.append(f"{rel}: frontmatter sidebar.hidden must be true")

    sections = {name.strip(): content for name, content in section_re.findall(body)}
    for name in required_sections:
        if name not in sections:
            errors.append(f"{rel}: missing required section ## {name}")

    category = first_meaningful_line(sections.get("Category", ""))
    if category not in category_values:
        errors.append(
            f"{rel}: category must be one of {sorted(category_values)} (got: {category or '<empty>'})"
        )
        continue

    if category == "deterministic-gap":
        deterministic_count += 1
        if not first_meaningful_line(sections.get("Proposed Fix", "")):
            errors.append(f"{rel}: deterministic-gap requires non-empty ## Proposed Fix")
        consumed = scalar(frontmatter, "consumed")
        if require_consumed and (consumed != "true" or not has_consumed_by(frontmatter)):
            unconsumed_count += 1
            errors.append(
                f"{rel}: deterministic-gap requires consumed: true and consumed_by mapping"
            )

if errors:
    print("dogfood evidence audit FAILED:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    if require_consumed:
        print(f"unconsumed deterministic-gap count: {unconsumed_count}", file=sys.stderr)
    raise SystemExit(1)

mode = "require-consumed" if require_consumed else "schema"
print(
    f"PASS: dogfood evidence audit ({mode}) entries={len(entries)} deterministic_gap={deterministic_count}"
)
PY
