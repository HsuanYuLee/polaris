#!/usr/bin/env bash
# Deterministic Starlight authoring validator for specs Markdown sources.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-starlight-authoring.sh <check|legacy-report> <file-or-directory>...

Modes:
  check          Blocking validation for explicit create/update/move-in paths.
  legacy-report  Non-blocking report for legacy trees; exits 0 after classifying drift.
EOF
  exit 2
}

if [[ $# -lt 2 ]]; then
  usage
fi

mode="$1"
shift

case "$mode" in
  check|legacy-report) ;;
  *) usage ;;
esac

python3 - "$mode" "$@" <<'PY'
import re
import sys
from pathlib import Path

mode = sys.argv[1]
inputs = [Path(p) for p in sys.argv[2:]]

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
        if path.suffix != ".md":
            print(f"error: not a markdown file: {path}", file=sys.stderr)
            sys.exit(2)
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

def parse_frontmatter(lines):
    if not lines or lines[0].strip() != "---":
        return {}, None
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return {}, None
    data = {}
    for raw in lines[1:end]:
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        key = key.strip()
        if key in {"title", "description"}:
            data[key] = strip_quotes(value)
    return data, end

def normalize(value):
    return re.sub(r"\s+", " ", value).strip()

def first_h1(lines, start_index):
    for idx in range(start_index, len(lines)):
        raw = lines[idx]
        if raw.startswith("# ") and not raw.startswith("## "):
            return idx + 1, raw[2:].strip()
    return None, None

def code_fence_language_findings(lines):
    findings = []
    fence_re = re.compile(r"^\s*(```|~~~)\s*([^`\s~]*)\s*$")
    in_fence = False
    marker = None
    for idx, line in enumerate(lines, start=1):
        match = fence_re.match(line)
        if not match:
            continue
        if not in_fence:
            in_fence = True
            marker = match.group(1)
            lang = match.group(2)
            if not lang:
                findings.append((idx, "code fence missing language"))
        elif line.lstrip().startswith(marker):
            in_fence = False
            marker = None
    return findings

def source_link_findings(text):
    findings = []
    generated_path = "docs-manager/" + "dist"
    legacy_source = "docs-viewer/src/content/docs/specs"
    link_targets = re.findall(r"\[[^\]]+\]\(([^)]+)\)", text)
    for target in link_targets:
        if generated_path in target:
            findings.append(("source-link", "link points at generated output"))
        if legacy_source in target:
            findings.append(("source-link", "link points at legacy docs-viewer specs source"))
    return findings

seen = set()
files = []
for input_path in inputs:
    for file in markdown_files(input_path):
        resolved = file.resolve()
        if resolved not in seen:
            seen.add(resolved)
            files.append(file)

if not files:
    print("error: no markdown files found", file=sys.stderr)
    sys.exit(2)

rows = []
blocking = 0

for file in files:
    text = file.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    fm, fm_end = parse_frontmatter(lines)

    def add(category, issue, detail="", line="-"):
        nonlocal_blocking[0] += 1 if mode == "check" else 0
        rows.append((category, issue, str(file), str(line), detail))

    nonlocal_blocking = [0]

    if fm_end is None:
        add("manual-needed", "missing-frontmatter", "add title and description")
    else:
        if not normalize(fm.get("title", "")):
            add("manual-needed", "missing-title", "add scalar title frontmatter")
        if not normalize(fm.get("description", "")):
            add("manual-needed", "missing-description", "description must be authored or safely inferred")

        title = fm.get("title")
        if title:
            h1_line, h1_text = first_h1(lines, fm_end + 1)
            if h1_line and normalize(title) == normalize(h1_text):
                add("deterministic", "duplicate H1", h1_text, h1_line)

    for line, detail in code_fence_language_findings(lines):
        add("deterministic", "code-fence-language", detail, line)

    for issue, detail in source_link_findings(text):
        add("deterministic", issue, detail)

    blocking += nonlocal_blocking[0]

if mode == "legacy-report":
    print("category\tissue\tpath\tline\tdetail")
    for row in rows:
        print("\t".join(row))
    summary = {
        "deterministic": 0,
        "manual-needed": 0,
        "skipped": 0,
        "duplicate": 0,
    }
    for category, issue, *_ in rows:
        if category in summary:
            summary[category] += 1
        if issue == "duplicate H1":
            summary["duplicate"] += 1
    print(f"summary\tdeterministic\t-\t-\t{summary['deterministic']}")
    print(f"summary\tmanual-needed\t-\t-\t{summary['manual-needed']}")
    print(f"summary\tskipped\t-\t-\t{summary['skipped']}")
    print(f"summary\tduplicate\t-\t-\t{summary['duplicate']}")
    sys.exit(0)

if rows:
    print("category\tissue\tpath\tline\tdetail", file=sys.stderr)
    for row in rows:
        print("\t".join(row), file=sys.stderr)
    sys.exit(1)

print(f"PASS: Starlight authoring check ({len(files)} file(s))")
PY
