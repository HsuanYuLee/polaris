#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR=""
OUTPUT_FORMAT="text"

usage() {
  cat >&2 <<'EOF'
usage: skill-progressive-disclosure-audit.sh [options]

Options:
  --root <path>        Workspace root (default: script parent)
  --skills-dir <path>  Explicit skills directory (default: <root>/.claude/skills)
  --markdown           Emit Starlight-compatible Markdown
  -h, --help           Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --skills-dir) SKILLS_DIR="${2:-}"; shift 2 ;;
    --markdown) OUTPUT_FORMAT="markdown"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "skill-progressive-disclosure-audit: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

python3 - "$ROOT" "$SKILLS_DIR" "$OUTPUT_FORMAT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).expanduser().resolve()
skills_arg = sys.argv[2]
output_format = sys.argv[3]
skills_dir = Path(skills_arg).expanduser().resolve() if skills_arg else root / ".claude" / "skills"

if output_format not in {"text", "markdown"}:
    print("skill-progressive-disclosure-audit: invalid output format", file=sys.stderr)
    sys.exit(2)

if not root.exists():
    print(f"skill-progressive-disclosure-audit: root not found: {root}", file=sys.stderr)
    sys.exit(2)


def strip_frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---", 4)
    if end == -1:
        return text
    rest = text.find("\n", end + 4)
    return text[rest + 1 :] if rest != -1 else ""


def frontmatter_text(text: str) -> str:
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---", 4)
    return text[4:end].strip("\n") if end != -1 else ""


def frontmatter_description(text: str) -> str:
    fm = frontmatter_text(text)
    if not fm:
        return ""
    lines = fm.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^description:\s*(.*)$", line)
        if not match:
            continue
        value = match.group(1).strip()
        if value in {">", "|", ">-", "|-"}:
            collected = []
            for next_line in lines[index + 1 :]:
                if re.match(r"^[A-Za-z0-9_-]+:\s*", next_line):
                    break
                collected.append(next_line.strip())
            return " ".join(part for part in collected if part)
        return value.strip("\"'")
    return ""


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z0-9_][A-Za-z0-9_'-]*", text))


def severity(words: int) -> str:
    if words > 1000:
        return "P0"
    if 750 <= words <= 1000:
        return "P1"
    if 500 <= words <= 749:
        return "P2"
    return "INFO"


def sections(body: str):
    items = []
    current = None
    current_lines = []
    for line in body.splitlines():
        match = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if match:
            if current is not None:
                items.append((current, "\n".join(current_lines)))
            current = match.group(2).strip()
            current_lines = []
        else:
            current_lines.append(line)
    if current is not None:
        items.append((current, "\n".join(current_lines)))
    return items


def fenced_code_blocks(body: str):
    blocks = []
    in_fence = False
    marker = ""
    lang = ""
    lines = []
    for line in body.splitlines():
        match = re.match(r"^\s*(```|~~~)\s*([^`\s~]*)\s*$", line)
        if not match:
            if in_fence:
                lines.append(line)
            continue
        if not in_fence:
            in_fence = True
            marker = match.group(1)
            lang = match.group(2).strip().lower()
            lines = []
        elif line.lstrip().startswith(marker):
            blocks.append((lang, "\n".join(lines)))
            in_fence = False
            marker = ""
            lang = ""
            lines = []
    return blocks


def flags_for(body: str) -> list[str]:
    flags = []
    section_items = sections(body)
    mode_headings = [
        title for title, _ in section_items
        if re.search(r"\b(mode|phase|workflow|flow|entry|route)\b", title, re.IGNORECASE)
    ]
    if len(mode_headings) >= 2:
        flags.append("multi-mode")

    long_sections = [
        title for title, content in section_items
        if word_count(content) >= 350
    ]
    if long_sections:
        flags.append("long-section")

    script_blocks = [
        block for lang, block in fenced_code_blocks(body)
        if lang in {"bash", "sh", "python", "py", "javascript", "js", "typescript", "ts"}
        or re.search(r"\b(for|while|python3|node|jq|gh|curl|find|rg)\b", block)
    ]
    if script_blocks:
        flags.append("script-candidate")

    return flags


rows = []
if skills_dir.exists():
    for skill_file in sorted(skills_dir.glob("*/SKILL.md")):
        skill = skill_file.parent.name
        text = skill_file.read_text(encoding="utf-8", errors="replace")
        body = strip_frontmatter(text)
        description = frontmatter_description(text)
        description_bytes = len(description.encode("utf-8"))
        words = word_count(body)
        rows.append({
            "skill": skill,
            "severity": severity(words),
            "words": words,
            "description_bytes": description_bytes,
            "description_estimated_tokens": (description_bytes + 3) // 4,
            "flags": flags_for(body),
            "path": skill_file.relative_to(root).as_posix() if skill_file.is_relative_to(root) else str(skill_file),
        })

order = {"P0": 0, "P1": 1, "P2": 2, "INFO": 3}
rows.sort(key=lambda row: (order[row["severity"]], -row["words"], row["skill"]))
counts = {key: 0 for key in order}
for row in rows:
    counts[row["severity"]] += 1
description_bytes_total = sum(row["description_bytes"] for row in rows)
description_tokens_total = sum(row["description_estimated_tokens"] for row in rows)

if output_format == "markdown":
    print("---")
    print('title: "DP-085 Skill Disclosure Baseline"')
    print('description: "Advisory scanner output for Polaris skill progressive disclosure follow-up."')
    print("---")
    print()
    print("# Skill Progressive Disclosure Audit")
    print()
    print("## Summary")
    print()
    print(f"- Total skills: {len(rows)}")
    print(f"- P0: {counts['P0']}")
    print(f"- P1: {counts['P1']}")
    print(f"- P2: {counts['P2']}")
    print(f"- INFO: {counts['INFO']}")
    print(f"- Description bytes: {description_bytes_total}")
    print(f"- Description estimated tokens: {description_tokens_total}")
    print()
    print("## Findings")
    print()
    print("| Skill | Severity | Body words | Description bytes | Description estimated tokens | Signals | Path |")
    print("|-------|----------|------------|-------------------|------------------------------|---------|------|")
    for row in rows:
        signals = ", ".join(row["flags"]) if row["flags"] else "-"
        print(f"| {row['skill']} | {row['severity']} | {row['words']} | {row['description_bytes']} | {row['description_estimated_tokens']} | {signals} | `{row['path']}` |")
else:
    print("Skill Progressive Disclosure Audit")
    print(f"skills={len(rows)} P0={counts['P0']} P1={counts['P1']} P2={counts['P2']} INFO={counts['INFO']} description_bytes={description_bytes_total} description_estimated_tokens={description_tokens_total}")
    print()
    print("skill\tseverity\twords\tdescription_bytes\tdescription_estimated_tokens\tsignals\tpath")
    for row in rows:
        signals = ",".join(row["flags"]) if row["flags"] else "-"
        print(f"{row['skill']}\t{row['severity']}\t{row['words']}\t{row['description_bytes']}\t{row['description_estimated_tokens']}\t{signals}\t{row['path']}")
PY
