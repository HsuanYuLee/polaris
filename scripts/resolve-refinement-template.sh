#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
COMPANY=""
PROJECT=""
FORMAT="text"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/resolve-refinement-template.sh [--repo <path>] [--company <name>] [--project <name>] [--format text|json]

Resolves the additive refinement template manifest. Company/project templates
may add sections but may not override framework-owned sections.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo|--workspace-root) REPO_ROOT="${2:-}"; shift 2 ;;
    --company) COMPANY="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "resolve-refinement-template: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -d "$REPO_ROOT" ]] || { echo "resolve-refinement-template: repo not found: $REPO_ROOT" >&2; exit 2; }
[[ "$FORMAT" == "text" || "$FORMAT" == "json" ]] || { echo "resolve-refinement-template: --format must be text or json" >&2; exit 2; }
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

python3 - "$REPO_ROOT" "$COMPANY" "$PROJECT" "$FORMAT" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

repo = Path(sys.argv[1])
company = sys.argv[2]
project = sys.argv[3]
fmt = sys.argv[4]

framework_sections = [
    "goal_background",
    "scope",
    "out_of_scope",
    "acceptance_criteria",
    "verification_methods",
    "technical_approach",
    "dependencies",
    "gaps_questions",
    "downstream_breakdown_hints",
]
forbidden = ["framework_sections", "remove_framework_sections", "override_framework_sections"]
framework_path = repo / ".claude/skills/references/refinement-source-template.md"

def rel(path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)

def first_yaml(directory: Path):
    if not directory.is_dir():
        return None
    candidates = sorted(list(directory.glob("*.yaml")) + list(directory.glob("*.yml")))
    return candidates[0] if candidates else None

selected = None
source = "framework"
if company and project:
    selected = first_yaml(repo / company / "polaris-config" / project / "refinement/templates")
    if selected:
        source = "project"
if selected is None and company:
    selected = first_yaml(repo / company / "polaris-config/refinement/templates")
    if selected:
        source = "company"
if selected is None:
    selected = framework_path

if not selected.exists():
    print(f"resolve-refinement-template: template not found: {selected}", file=sys.stderr)
    raise SystemExit(1)

text = selected.read_text(encoding="utf-8")
template_id = selected.stem if source != "framework" else "framework-default"
company_sections = []

if source != "framework":
    for key in forbidden:
        if re.search(rf"(?m)^\s*{re.escape(key)}\s*:", text):
            print(f"resolve-refinement-template: forbidden override key in {rel(selected)}: {key}", file=sys.stderr)
            raise SystemExit(1)
    match = re.search(r"(?m)^\s*template_id\s*:\s*[\"']?([^\"'\n#]+)", text)
    if match:
        template_id = match.group(1).strip()
    in_sections = False
    base_indent = 0
    for raw in text.splitlines():
        if re.match(r"^\s*company_sections\s*:\s*$", raw):
            in_sections = True
            base_indent = len(raw) - len(raw.lstrip())
            continue
        if in_sections:
            if raw.strip() == "" or raw.lstrip().startswith("#"):
                continue
            indent = len(raw) - len(raw.lstrip())
            if indent <= base_indent and not raw.lstrip().startswith("-"):
                break
            item = re.match(r"^\s*-\s*[\"']?([^\"'#]+)", raw)
            if item:
                company_sections.append(item.group(1).strip())

manifest = {
    "schema_version": 1,
    "source": source,
    "template_id": template_id,
    "path": rel(selected),
    "framework_sections": framework_sections,
    "company_sections": company_sections,
    "forbidden_overrides": forbidden,
    "selected_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}

if fmt == "json":
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
else:
    print(f"{manifest['source']}:{manifest['template_id']}:{manifest['path']}")
PY
