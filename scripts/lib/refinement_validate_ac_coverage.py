"""依 surface handbook 驗證 refinement AC coverage。"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import sys
from pathlib import Path

import yaml


def fail(message: str) -> int:
    print(f"FAIL: {message}", file=sys.stderr)
    return 2


def load_yaml(path: Path, label: str) -> dict | None:
    if not path.is_file():
        fail(f"{label} not found: {path}")
        return None
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        fail(f"{label} invalid YAML: {exc}")
        return None


def main(argv: list[str] | None = None) -> int:
    raw = list(sys.argv[1:] if argv is None else argv)
    usage_text = (
        "usage:\n  scripts/validate-refinement-ac-coverage.sh <refinement.json> "
        "[--handbook PATH] [--company-override PATH]\n\n"
        "Validates refinement.json changed_files against the Polaris framework defaults\n"
        "ac-required-by-surface yaml. Defaults to the tracked reference at\n"
        ".claude/skills/references/ac-required-by-surface-defaults.yaml. If a company\n"
        "override yaml is provided (via --company-override or POLARIS_AC_COMPANY_OVERRIDE\n"
        "env var), its surfaces are merged on top of the defaults; same-id surfaces from\n"
        "the override replace the default entry.\n"
    )
    if not raw:
        print(usage_text, end="", file=sys.stderr)
        return 2
    refinement_path = Path(raw.pop(0))
    handbook_arg = ".claude/skills/references/ac-required-by-surface-defaults.yaml"
    company_override = os.environ.get("POLARIS_AC_COMPANY_OVERRIDE", "")
    i = 0
    while i < len(raw):
        arg = raw[i]
        if arg in {"--handbook", "--company-override"}:
            value = raw[i + 1] if i + 1 < len(raw) else ""
            if arg == "--handbook":
                handbook_arg = value
            else:
                company_override = value
            i += 2
        elif arg in {"--help", "-h"}:
            print(usage_text, end="", file=sys.stderr)
            return 2
        else:
            print(f"ERROR: unknown argument: {arg}", file=sys.stderr)
            print(usage_text, end="", file=sys.stderr)
            return 2
    if not refinement_path.is_file():
        return fail(f"refinement.json not found: {refinement_path}")
    try:
        refinement = json.loads(refinement_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return fail(f"refinement.json invalid JSON: {exc}")
    handbook = load_yaml(Path(handbook_arg), "AC handbook")
    if handbook is None:
        return 2
    override: dict = {}
    if company_override:
        loaded = load_yaml(Path(company_override), "AC handbook company override")
        if loaded is None:
            return 2
        override = loaded

    changed_files = refinement.get("changed_files")
    if not isinstance(changed_files, list) or not changed_files:
        return fail("refinement.json changed_files is required and must be a non-empty array")
    acceptance_criteria = refinement.get("acceptance_criteria")
    if not isinstance(acceptance_criteria, list):
        return fail("refinement.json acceptance_criteria must be an array")
    methods = {
        str(((ac.get("verification") or {}).get("method") or "")).strip()
        for ac in acceptance_criteria if isinstance(ac, dict)
    }
    ac_text = "\n".join(
        f"{ac.get('id', '')} {ac.get('text', '')}" for ac in acceptance_criteria if isinstance(ac, dict)
    )
    defaults = handbook.get("surfaces")
    if not isinstance(defaults, list) or not defaults:
        return fail("AC handbook surfaces must be a non-empty array")
    merged: dict[str, dict] = {}
    order: list[str] = []
    for surface in [*defaults, *((override.get("surfaces") or []) if isinstance(override, dict) else [])]:
        if not isinstance(surface, dict):
            continue
        sid = str(surface.get("id") or "").strip()
        if not sid:
            continue
        if sid not in merged:
            order.append(sid)
        merged[sid] = surface

    errors: list[str] = []
    for surface in (merged[sid] for sid in order):
        surface_id = surface.get("id") or "unknown"
        globs = surface.get("file_globs") or []
        if not isinstance(globs, list):
            errors.append(f"surface {surface_id}: file_globs must be an array")
            continue
        hits = [
            changed for changed in changed_files if isinstance(changed, str)
            for pattern in globs if isinstance(pattern, str) and fnmatch.fnmatch(changed, pattern)
        ]
        if not hits:
            continue
        required = surface.get("required_acceptance") or []
        if not isinstance(required, list) or not required:
            errors.append(f"surface {surface_id}: hit changed_files but has no required_acceptance")
            continue
        for requirement in required:
            if not isinstance(requirement, dict):
                errors.append(f"surface {surface_id}: required_acceptance entry must be an object")
                continue
            req_id = str(requirement.get("id") or "").strip()
            accepted = {str(method).strip() for method in requirement.get("accepted_verification_methods") or []}
            if not (accepted & methods) and not (req_id and req_id in ac_text):
                errors.append(
                    f"surface {surface_id}: changed_files hit {', '.join(sorted(set(hits)))}; "
                    f"missing required AC {req_id or '<missing-id>'} "
                    f"(accepted methods: {', '.join(sorted(accepted)) or 'none'})"
                )
    if errors:
        print("FAIL: refinement AC coverage", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 2
    print(f"PASS: refinement AC coverage ({refinement_path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
