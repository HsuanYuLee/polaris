#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-specs-bound-write-contract.sh --files PATH [PATH ...]
  scripts/validate-specs-bound-write-contract.sh --diff-range BASE..HEAD [--repo PATH]

Validates specs-bound Markdown against scripts/lib/evidence-producers.json.
USAGE
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PRODUCER_MAP="$ROOT_DIR/scripts/lib/evidence-producers.json"
REPO="$ROOT_DIR"
MODE=""
DIFF_RANGE=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --diff-range) MODE="diff"; DIFF_RANGE="${2:-}"; shift 2 ;;
    --files) MODE="files"; shift; while [[ $# -gt 0 && "$1" != --* ]]; do FILES+=("$1"); shift; done ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$MODE" ]] || usage

if [[ "$MODE" == "diff" ]]; then
  [[ -n "$DIFF_RANGE" ]] || usage
  mapfile -t FILES < <(git -C "$REPO" diff --name-only "$DIFF_RANGE" -- 'docs-manager/src/content/docs/specs/**/*.md')
fi

python3 - "$REPO" "$PRODUCER_MAP" "${FILES[@]}" <<'PY'
import fnmatch
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
producer_map = Path(sys.argv[2])
raw_files = sys.argv[3:]

def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(repo).as_posix()
    except Exception:
        return path.as_posix()

def frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}
    data = {}
    stack = []
    for raw in text[4:end].splitlines():
        if not raw.strip() or raw.strip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        key = raw.strip().split(":", 1)[0].strip()
        value = raw.strip().split(":", 1)[1].strip() if ":" in raw else ""
        while stack and stack[-1][0] >= indent:
            stack.pop()
        full = ".".join([item[1] for item in stack] + [key])
        data[full] = value.strip('"').strip("'")
        if value == "":
            stack.append((indent, key))
    return data

data = json.loads(producer_map.read_text(encoding="utf-8"))
producers = [
    p for p in data.get("producers", [])
    if p.get("artifact_kind") in {"specs_markdown", "verify_evidence_layout", "docs_page", "sidecar", "d2_transport"}
]
errors = []
checked = 0
for raw in raw_files:
    path = Path(raw)
    if not path.is_absolute():
        path = repo / path
    if not path.exists() or path.suffix != ".md":
        continue
    path_rel = rel(path)
    if not fnmatch.fnmatch(path_rel, "docs-manager/src/content/docs/specs/**/*.md"):
        continue
    checked += 1
    producer = next((p for p in producers if any(fnmatch.fnmatch(path_rel, glob) for glob in p.get("path_globs", []))), None)
    if producer is None:
        errors.append(f"{path_rel}: no specs-bound producer registration")
        continue
    fm = frontmatter(path)
    for field in producer.get("required_frontmatter", []):
        if field not in fm or fm[field] in {"", "null"}:
            errors.append(f"{path_rel}: missing required frontmatter {field}")

if errors:
    print("FAIL: specs-bound write contract", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: specs-bound write contract ({checked} markdown file(s))")
PY
