#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-refinement-ac-coverage.sh <refinement.json> [--handbook PATH]

Validates refinement.json changed_files against an ac-required-by-surface.yaml handbook.
USAGE
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

REFINEMENT_JSON="$1"
shift
HANDBOOK="polaris-config/polaris/handbook/ac-required-by-surface.yaml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --handbook)
      HANDBOOK="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      ;;
  esac
done

python3 - "$REFINEMENT_JSON" "$HANDBOOK" <<'PY'
import fnmatch
import json
import sys
from pathlib import Path

import yaml

refinement_path = Path(sys.argv[1])
handbook_path = Path(sys.argv[2])


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(2)


if not refinement_path.is_file():
    fail(f"refinement.json not found: {refinement_path}")
if not handbook_path.is_file():
    fail(f"AC handbook not found: {handbook_path}")

try:
    refinement = json.loads(refinement_path.read_text(encoding="utf-8"))
except Exception as exc:
    fail(f"refinement.json invalid JSON: {exc}")
try:
    handbook = yaml.safe_load(handbook_path.read_text(encoding="utf-8")) or {}
except Exception as exc:
    fail(f"AC handbook invalid YAML: {exc}")

changed_files = refinement.get("changed_files")
if not isinstance(changed_files, list) or not changed_files:
    fail("refinement.json changed_files is required and must be a non-empty array")

acceptance_criteria = refinement.get("acceptance_criteria")
if not isinstance(acceptance_criteria, list):
    fail("refinement.json acceptance_criteria must be an array")

methods = {
    str(((ac.get("verification") or {}).get("method") or "")).strip()
    for ac in acceptance_criteria
    if isinstance(ac, dict)
}
ac_ids_and_text = "\n".join(
    f"{ac.get('id', '')} {ac.get('text', '')}" for ac in acceptance_criteria if isinstance(ac, dict)
)

surfaces = handbook.get("surfaces")
if not isinstance(surfaces, list) or not surfaces:
    fail("AC handbook surfaces must be a non-empty array")

errors = []
for surface in surfaces:
    if not isinstance(surface, dict):
        continue
    surface_id = surface.get("id") or "unknown"
    globs = surface.get("file_globs") or []
    if not isinstance(globs, list):
        errors.append(f"surface {surface_id}: file_globs must be an array")
        continue
    hits = [
        changed
        for changed in changed_files
        if isinstance(changed, str)
        for glob in globs
        if isinstance(glob, str) and fnmatch.fnmatch(changed, glob)
    ]
    if not hits:
        continue
    required = surface.get("required_acceptance") or []
    if not isinstance(required, list) or not required:
        errors.append(f"surface {surface_id}: hit changed_files but has no required_acceptance")
        continue
    for req in required:
        if not isinstance(req, dict):
            errors.append(f"surface {surface_id}: required_acceptance entry must be an object")
            continue
        req_id = str(req.get("id") or "").strip()
        accepted_methods = {str(method).strip() for method in (req.get("accepted_verification_methods") or [])}
        method_ok = bool(accepted_methods & methods)
        text_ok = bool(req_id and req_id in ac_ids_and_text)
        if not method_ok and not text_ok:
            errors.append(
                "surface {surface}: changed_files hit {hits}; missing required AC {req} "
                "(accepted methods: {methods})".format(
                    surface=surface_id,
                    hits=", ".join(sorted(set(hits))),
                    req=req_id or "<missing-id>",
                    methods=", ".join(sorted(accepted_methods)) or "none",
                )
            )

if errors:
    print("FAIL: refinement AC coverage", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(2)

print(f"PASS: refinement AC coverage ({refinement_path})")
PY
