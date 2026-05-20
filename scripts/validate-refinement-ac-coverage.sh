#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-refinement-ac-coverage.sh <refinement.json> [--handbook PATH] [--company-override PATH]

Validates refinement.json changed_files against the Polaris framework defaults
ac-required-by-surface yaml. Defaults to the tracked reference at
.claude/skills/references/ac-required-by-surface-defaults.yaml. If a company
override yaml is provided (via --company-override or POLARIS_AC_COMPANY_OVERRIDE
env var), its surfaces are merged on top of the defaults; same-id surfaces from
the override replace the default entry.
USAGE
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

REFINEMENT_JSON="$1"
shift
HANDBOOK=".claude/skills/references/ac-required-by-surface-defaults.yaml"
COMPANY_OVERRIDE="${POLARIS_AC_COMPANY_OVERRIDE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --handbook)
      HANDBOOK="${2:-}"
      shift 2
      ;;
    --company-override)
      COMPANY_OVERRIDE="${2:-}"
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

python3 - "$REFINEMENT_JSON" "$HANDBOOK" "$COMPANY_OVERRIDE" <<'PY'
import fnmatch
import json
import sys
from pathlib import Path

import yaml

refinement_path = Path(sys.argv[1])
handbook_path = Path(sys.argv[2])
override_arg = sys.argv[3] if len(sys.argv) > 3 else ""
override_path = Path(override_arg) if override_arg else None


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

override = {}
if override_path is not None and str(override_path):
    if not override_path.is_file():
        fail(f"AC handbook company override not found: {override_path}")
    try:
        override = yaml.safe_load(override_path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        fail(f"AC handbook company override invalid YAML: {exc}")

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

default_surfaces = handbook.get("surfaces")
if not isinstance(default_surfaces, list) or not default_surfaces:
    fail("AC handbook surfaces must be a non-empty array")

# Merge: defaults first; override surfaces with same `id` replace; new ids append.
merged = {}
order = []
for surface in default_surfaces:
    if not isinstance(surface, dict):
        continue
    sid = str(surface.get("id") or "").strip()
    if not sid:
        continue
    if sid not in merged:
        order.append(sid)
    merged[sid] = surface

override_surfaces = override.get("surfaces") if isinstance(override, dict) else None
if isinstance(override_surfaces, list):
    for surface in override_surfaces:
        if not isinstance(surface, dict):
            continue
        sid = str(surface.get("id") or "").strip()
        if not sid:
            continue
        if sid not in merged:
            order.append(sid)
        merged[sid] = surface

surfaces = [merged[sid] for sid in order]

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
