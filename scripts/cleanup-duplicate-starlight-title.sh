#!/usr/bin/env bash
# Remove deterministic duplicate Starlight page-title H1s from Markdown sources.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: cleanup-duplicate-starlight-title.sh [--dry-run|--apply] <file-or-directory>...

Scans Markdown files for frontmatter title followed by an identical first H1.
--dry-run reports what would change. --apply rewrites only deterministic matches.
EOF
  exit 2
}

mode="dry-run"
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
    -h|--help)
      usage
      ;;
    --)
      shift
      break
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

if [[ ${#paths[@]} -eq 0 ]]; then
  usage
fi

python3 - "$mode" "${paths[@]}" <<'PY'
import re
import sys
from pathlib import Path

mode = sys.argv[1]
inputs = [Path(p) for p in sys.argv[2:]]

if mode not in {"dry-run", "apply"}:
    print(f"error: unsupported mode: {mode}", file=sys.stderr)
    sys.exit(2)

def is_generated_path(path: Path) -> bool:
    parts = path.as_posix().split("/")
    return "dist" in parts

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

def parse_scalar_frontmatter(lines, key):
    if not lines or lines[0].strip() != "---":
        return None, None
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, None
    pattern = re.compile(rf"^{re.escape(key)}\s*:\s*(.*)\s*$")
    for raw in lines[1:end]:
        match = pattern.match(raw)
        if not match:
            continue
        value = match.group(1).strip()
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        return value, end
    return None, end

def normalize(value):
    return re.sub(r"\s+", " ", value).strip()

def first_h1(lines, start_index):
    for idx in range(start_index, len(lines)):
        raw = lines[idx]
        if raw.startswith("# ") and not raw.startswith("## "):
            return idx, raw[2:].strip()
    return None, None

def is_task_work_order(path: Path) -> bool:
    parts = path.as_posix().split("/")
    return "tasks" in parts and re.match(r"^[TV]\d+[a-z]*\.md$", path.name) is not None

def quote_yaml(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

def adjust_title_line(lines, title: str, fm_end: int):
    replacement = f"Work Order - {title}"
    for idx in range(1, fm_end):
        if re.match(r"^title\s*:", lines[idx]):
            newline = "\n" if lines[idx].endswith("\n") else ""
            lines[idx] = f"title: {quote_yaml(replacement)}{newline}"
            return True
    return False

seen = set()
files = []
for input_path in inputs:
    for file in markdown_files(input_path):
        resolved = file.resolve()
        if resolved not in seen:
            seen.add(resolved)
            files.append(file)

print("status\taction\tpath\tdetail")

counts = {"modified": 0, "skipped": 0, "manual-needed": 0}
for file in files:
    text = file.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines(keepends=True)
    title, fm_end = parse_scalar_frontmatter([line.rstrip("\n\r") for line in lines], "title")
    if not title or fm_end is None:
        counts["skipped"] += 1
        print(f"skipped\tmissing-title\t{file}\tno scalar title frontmatter")
        continue

    h1_idx, h1_text = first_h1([line.rstrip("\n\r") for line in lines], fm_end + 1)
    if h1_idx is None:
        counts["skipped"] += 1
        print(f"skipped\tno-h1\t{file}\tno body H1")
        continue

    if normalize(h1_text) != normalize(title):
        counts["skipped"] += 1
        print(f"skipped\tnon-duplicate\t{file}\tfirst H1 differs from title")
        continue

    counts["modified"] += 1
    if is_task_work_order(file):
        action = "would-adjust-task-title" if mode == "dry-run" else "adjusted-task-title"
        print(f"modified\t{action}\t{file}\t{h1_text}")
        if mode == "apply":
            if not adjust_title_line(lines, title, fm_end):
                counts["manual-needed"] += 1
                print(f"manual-needed\ttitle-rewrite-failed\t{file}\tcould not rewrite title line")
                continue
            file.write_text("".join(lines), encoding="utf-8")
    else:
        action = "would-remove-duplicate-h1" if mode == "dry-run" else "removed-duplicate-h1"
        print(f"modified\t{action}\t{file}\t{h1_text}")
        if mode == "apply":
            del lines[h1_idx]
            if h1_idx < len(lines) and lines[h1_idx].strip() == "":
                del lines[h1_idx]
            file.write_text("".join(lines), encoding="utf-8")

print(f"summary\tmodified\t-\t{counts['modified']}")
print(f"summary\tskipped\t-\t{counts['skipped']}")
print(f"summary\tmanual-needed\t-\t{counts['manual-needed']}")
PY
