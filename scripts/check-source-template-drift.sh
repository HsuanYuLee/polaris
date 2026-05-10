#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REFINEMENT_JSON=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/check-source-template-drift.sh [--repo <path>] [--refinement-json <path>]

Checks that DP and Epic refinement sources stay aligned with the shared source
template contract and that structured downstream fields are present when a
refinement JSON artifact is provided.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --refinement-json) REFINEMENT_JSON="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-source-template-drift: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -d "$REPO_ROOT" ]] || { echo "check-source-template-drift: repo not found: $REPO_ROOT" >&2; exit 2; }
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

python3 - "$REPO_ROOT" "$REFINEMENT_JSON" <<'PY'
import json
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])
refinement_json = sys.argv[2]
errors = []
section_ids = [
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

source_ref = repo / ".claude/skills/references/refinement-source-template.md"
epic_ref = repo / ".claude/skills/references/epic-template.md"
create_dp = repo / "scripts/create-design-plan.sh"
for path in [source_ref, epic_ref, create_dp]:
    if not path.exists():
        errors.append(f"missing required template surface: {path.relative_to(repo)}")

if source_ref.exists():
    text = source_ref.read_text(encoding="utf-8")
    for sid in section_ids:
        if f"`{sid}`" not in text:
            errors.append(f"shared source template missing canonical section id: {sid}")

if epic_ref.exists():
    text = epic_ref.read_text(encoding="utf-8")
    if "refinement-source-template.md" not in text:
        errors.append("epic-template.md must point to refinement-source-template.md")
    for sid in ["acceptance_criteria", "downstream_breakdown_hints"]:
        if sid not in text:
            errors.append(f"epic-template.md missing downstream canonical mapping: {sid}")

if create_dp.exists():
    with tempfile.TemporaryDirectory(prefix="dp-template-drift.") as tmp:
        specs = Path(tmp) / "docs-manager/src/content/docs/specs"
        proc = subprocess.run(
            ["bash", str(create_dp), "--specs-root", str(specs), "--number", "DP-001", "--status", "LOCKED", "template drift smoke"],
            cwd=repo,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if proc.returncode != 0:
            errors.append("create-design-plan.sh failed template smoke: " + proc.stderr.strip().splitlines()[-1])
        else:
            plan = Path(proc.stdout.strip().splitlines()[-1])
            text = plan.read_text(encoding="utf-8")
            for heading in [
                "## Goal",
                "## Background",
                "## Scope",
                "## Out of Scope",
                "## Acceptance Criteria",
                "## Technical Approach",
                "## Dependencies",
                "## Open Questions",
                "## Downstream Breakdown Hints",
            ]:
                if heading not in text:
                    errors.append(f"DP template missing shared heading: {heading}")

if refinement_json:
    path = Path(refinement_json)
    if not path.is_absolute():
        path = repo / path
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"invalid refinement JSON: {path}: {exc}")
    else:
        if not isinstance(data.get("acceptance_criteria"), list) or not data["acceptance_criteria"]:
            errors.append("refinement JSON missing structured acceptance_criteria[]")
        hints = data.get("downstream", {}).get("breakdown_hints")
        if not isinstance(hints, list) or not hints:
            errors.append("refinement JSON missing structured downstream.breakdown_hints[]")

for error in errors:
    print(f"FAIL: {error}", file=sys.stderr)
raise SystemExit(1 if errors else 0)
PY

echo "PASS: source template drift check"
