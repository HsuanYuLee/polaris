#!/usr/bin/env bash
# Infer missing Starlight description frontmatter for legacy specs Markdown.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: infer-starlight-descriptions.sh [--dry-run|--apply] [--report PATH] <file-or-directory>...

Infers descriptions only when a Markdown file already has scalar title frontmatter
but no description. The report records path, strategy, and inferred text.
EOF
  exit 2
}

mode="dry-run"
report=""
paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      mode="dry-run"
      shift
      ;;
    --apply)
      mode="apply"
      shift
      ;;
    --report)
      [[ $# -ge 2 ]] || usage
      report="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage
      ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

[[ ${#paths[@]} -gt 0 ]] || usage

python3 - "$mode" "$report" "${paths[@]}" <<'PY'
import re
import sys
from datetime import date
from pathlib import Path

mode = sys.argv[1]
report_path = Path(sys.argv[2]) if sys.argv[2] else None
inputs = [Path(p) for p in sys.argv[3:]]

if mode not in {"dry-run", "apply"}:
    print(f"error: unsupported mode: {mode}", file=sys.stderr)
    sys.exit(2)

def is_generated_path(path: Path) -> bool:
    parts = path.as_posix().split("/")
    for idx, part in enumerate(parts[:-1]):
        if part == "docs-manager" and parts[idx + 1] == "dist":
            return True
    return "dist" in parts and "docs-manager" in parts

def markdown_files(path: Path):
    if not path.exists():
        print(f"error: path not found: {path}", file=sys.stderr)
        sys.exit(2)
    if is_generated_path(path):
        print(f"error: generated output path is not a source input: {path}", file=sys.stderr)
        sys.exit(2)
    if path.is_file():
        if path.suffix == ".md":
            yield path
        return
    for file in sorted(path.rglob("*.md")):
        if not is_generated_path(file):
            yield file

def strip_quotes(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value

def quote_yaml(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

def parse_frontmatter(lines):
    if not lines or lines[0].strip() != "---":
        return {}, None, None
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return {}, None, None
    data = {}
    title_line = None
    for idx, raw in enumerate(lines[1:end], start=1):
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        key = key.strip()
        if key == "title":
            data["title"] = strip_quotes(value)
            title_line = idx
        elif key == "description":
            data["description"] = strip_quotes(value)
    return data, end, title_line

def clean_inline(text: str) -> str:
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip(" -\t")

def is_bad_paragraph_start(line: str) -> bool:
    stripped = line.strip()
    return (
        not stripped
        or stripped.startswith(("#", "|", ">", "```", "~~~", ":::", "<"))
        or re.match(r"^[-*+]\s+", stripped) is not None
        or re.match(r"^\d+[.)]\s+", stripped) is not None
        or re.match(r"^[A-Za-z0-9_.-]+\s*[:=]\s*", stripped) is not None
    )

def first_paragraph(lines, start):
    idx = start
    in_fence = False
    while idx < len(lines):
        stripped = lines[idx].strip()
        if stripped.startswith(("```", "~~~")):
            in_fence = not in_fence
            idx += 1
            continue
        if in_fence or is_bad_paragraph_start(lines[idx]):
            idx += 1
            continue
        paragraph = []
        while idx < len(lines) and lines[idx].strip():
            if is_bad_paragraph_start(lines[idx]):
                break
            paragraph.append(lines[idx].strip())
            idx += 1
        value = clean_inline(" ".join(paragraph))
        if 12 <= len(value) <= 180:
            return value
        if len(value) > 180:
            return value[:177].rstrip() + "..."
    return ""

def task_title(title: str) -> str:
    return re.sub(r"^Work Order\s*-\s*", "", title).strip()

def infer_description(path: Path, title: str, lines, fm_end: int):
    parts = path.as_posix().split("/")
    name = path.name.lower()
    title = task_title(title)

    para = first_paragraph(lines, fm_end + 1)
    if para and not any(seg in parts for seg in ["tasks", "artifacts", "verification", "escalations", "refinement-inbox"]):
        return "first-paragraph", para

    if "tasks" in parts and re.match(r"^[tv]\d+[a-z]*\.md$", name):
        return "task-title", f"此工單描述 {title} 的實作或驗收範圍。"
    if name == "refinement.md":
        return "refinement-title", f"此文件記錄 {title} 的 refinement 結果與決策脈絡。"
    if name == "breakdown.md":
        return "breakdown-title", f"此文件記錄 {title} 的 breakdown 拆解與交付範圍。"
    if name == "plan.md":
        return "plan-title", f"此文件記錄 {title} 的 design plan 與決策脈絡。"
    if "verification" in parts:
        return "verification-title", f"此文件記錄 {title} 的驗收或驗證結果。"
    if "escalations" in parts:
        return "escalation-title", f"此文件記錄 {title} 的 escalation 背景與處置脈絡。"
    if "refinement-inbox" in parts:
        return "inbox-title", f"此文件記錄 {title} 的 refinement return inbox 脈絡。"
    if "artifacts" in parts:
        return "artifact-title", f"此 artifact 記錄 {title} 的執行脈絡與證據。"
    return "title-fallback", f"此文件記錄 {title} 的相關內容。"

def insert_description(lines, title_line: int, description: str):
    newline = "\n" if lines[title_line].endswith("\n") else ""
    lines.insert(title_line + 1, f"description: {quote_yaml(description)}{newline}")

seen = set()
files = []
for input_path in inputs:
    for file in markdown_files(input_path):
        resolved = file.resolve()
        if resolved not in seen:
            seen.add(resolved)
            files.append(file)

rows = []
for path in files:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines(keepends=True)
    stripped_lines = [line.rstrip("\n\r") for line in lines]
    fm, fm_end, title_line = parse_frontmatter(stripped_lines)
    title = (fm.get("title") or "").strip()
    description = (fm.get("description") or "").strip()
    if not title:
        rows.append(("manual-needed", "missing-title", str(path), "", ""))
        continue
    if description:
        rows.append(("skipped", "has-description", str(path), "", ""))
        continue
    strategy, inferred = infer_description(path, title, stripped_lines, fm_end or 0)
    rows.append(("inferred", strategy, str(path), inferred, ""))
    if mode == "apply" and title_line is not None:
        insert_description(lines, title_line, inferred)
        path.write_text("".join(lines), encoding="utf-8")

print("status\tstrategy\tpath\tdescription")
for status, strategy, path, description, _ in rows:
    print(f"{status}\t{strategy}\t{path}\t{description}")

summary = {}
for status, *_ in rows:
    summary[status] = summary.get(status, 0) + 1
for key in ["inferred", "skipped", "manual-needed"]:
    print(f"summary\t{key}\t-\t{summary.get(key, 0)}")

if report_path:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    inferred_rows = [row for row in rows if row[0] == "inferred"]
    lines = [
        "---\n",
        'title: "DP-067 Legacy Description Inference Report"\n',
        'description: "記錄 DP-067 legacy specs description inference 的來源策略與推斷結果。"\n',
        "---\n\n",
        "## Summary\n\n",
        f"- Date: {date.today().isoformat()}\n",
        f"- Mode: {mode}\n",
        f"- Inferred: {len(inferred_rows)}\n",
        f"- Skipped: {summary.get('skipped', 0)}\n",
        f"- Manual needed: {summary.get('manual-needed', 0)}\n\n",
        "## Inferred Descriptions\n\n",
        "| Path | Strategy | Description |\n",
        "|------|----------|-------------|\n",
    ]
    for _, strategy, path, description, _ in inferred_rows:
        safe_path = path.replace("|", "\\|")
        safe_desc = description.replace("|", "\\|")
        lines.append(f"| `{safe_path}` | `{strategy}` | {safe_desc} |\n")
    report_path.write_text("".join(lines), encoding="utf-8")
PY
