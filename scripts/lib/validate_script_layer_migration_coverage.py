"""Purpose: validate DP-420 script-layer semantics, coverage, and terminality."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from script_layer_audit import LANGUAGE_BY_SUFFIX, iter_surface_files, load_manifest, surface_for


ALLOWED_DISPOSITIONS = {"migrate", "stay_shell", "stay_python", "stay_node", "resolved_by_owner", "obsolete"}
DP420_OWNERS = {
    "DP-420-T4",
    "DP-420-T5",
    "DP-420-T6",
    "DP-420-T10",
    "DP-420-T11",
    "DP-420-T12",
    "DP-420-T13",
}
FOREIGN_OWNERS = {"DP-422", "DP-423"}
GENERIC_EVIDENCE = {
    "shell orchestration remains owned by the legacy runner until a migration task claims it",
    "structured validator",
    "fixture",
    "n/a",
}


def expected_union(workspace_root: Path) -> set[str]:
    return {path.relative_to(workspace_root).as_posix() for path in iter_surface_files(workspace_root)}


def validate_evidence(prefix: str, path: str, evidence: Any) -> list[str]:
    errors: list[str] = []
    required = {"surface_rule", "disposition_rule", "observed", "rationale"}
    if not isinstance(evidence, dict):
        return [f"{prefix}.evidence must be an object"]
    missing = sorted(required - set(evidence))
    if missing:
        errors.append(f"{prefix}.evidence missing fields: {missing}")
        return errors
    for field in required:
        value = evidence.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{prefix}.evidence.{field} must be non-empty")
    rationale = str(evidence.get("rationale", "")).strip()
    if rationale.lower() in GENERIC_EVIDENCE or path not in rationale:
        errors.append(f"{prefix}.evidence.rationale must be path-specific, not generic")
    return errors


def validate(ledger_path: Path, owner_query: str | None, require_terminal: bool) -> list[str]:
    errors: list[str] = []
    try:
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"ledger is not valid JSON: {exc}"]
    if ledger.get("schema_version") != 2:
        errors.append("ledger schema_version must be 2")
    if ledger.get("source") != "DP-420":
        errors.append("ledger source must be DP-420")
    entries = ledger.get("entries")
    if not isinstance(entries, list) or not entries:
        return errors + ["ledger entries must be a non-empty array"]

    workspace_root = ledger_path.parent.parent
    manifest = load_manifest(workspace_root)
    seen: set[str] = set()
    by_owner: dict[str, list[dict[str, Any]]] = {}
    for index, entry in enumerate(entries):
        prefix = f"entries[{index}]"
        if not isinstance(entry, dict):
            errors.append(f"{prefix} must be an object")
            continue
        required_fields = {"path", "surface", "language", "classification", "disposition", "owner", "terminal", "evidence"}
        missing = sorted(required_fields - set(entry))
        if missing:
            errors.append(f"{prefix} missing semantic fields: {missing}")
            continue
        path = entry["path"]
        if not isinstance(path, str) or not path:
            errors.append(f"{prefix}.path is required")
            continue
        if path in seen:
            errors.append(f"duplicate ledger path: {path}")
        seen.add(path)
        file_path = workspace_root / path
        if not file_path.is_file():
            errors.append(f"{prefix}.path does not exist: {path}")
            continue
        expected_language = LANGUAGE_BY_SUFFIX.get(file_path.suffix)
        if entry["language"] != expected_language:
            errors.append(f"{prefix}.language does not match suffix for {path}")
        expected_surface, _ = surface_for(path, manifest.get(path))
        if entry["surface"] != expected_surface:
            errors.append(f"{prefix}.surface must be {expected_surface} for {path}")
        disposition = entry["disposition"]
        owner = entry["owner"]
        terminal = entry["terminal"]
        if disposition not in ALLOWED_DISPOSITIONS:
            errors.append(f"{prefix}.disposition is unsupported: {disposition}")
        if not isinstance(terminal, bool):
            errors.append(f"{prefix}.terminal must be boolean")
        if disposition == "migrate":
            if owner not in DP420_OWNERS:
                errors.append(f"{prefix}.owner must be one unique DP-420 migration owner")
            if terminal is not False:
                errors.append(f"{prefix}.migrate must be non-terminal")
        elif disposition in {"resolved_by_owner", "obsolete"}:
            if owner not in FOREIGN_OWNERS:
                errors.append(f"{prefix}.{disposition} requires DP-422 or DP-423 owner")
            if terminal is not True:
                errors.append(f"{prefix}.{disposition} must be terminal")
        else:
            if owner is not None:
                errors.append(f"{prefix}.{disposition} must not claim a migration owner")
            if terminal is not True:
                errors.append(f"{prefix}.{disposition} must be terminal")
        if owner is not None:
            by_owner.setdefault(str(owner), []).append(entry)
        errors.extend(validate_evidence(prefix, path, entry["evidence"]))

    missing_paths = sorted(expected_union(workspace_root) - seen)
    extra_paths = sorted(seen - expected_union(workspace_root))
    if missing_paths:
        errors.append(f"ledger missing filesystem paths: {missing_paths}")
    if extra_paths:
        errors.append(f"ledger contains non-union paths: {extra_paths}")

    if require_terminal and not owner_query:
        errors.append("unsupported terminal query: --require-terminal requires --owner")
    if owner_query:
        if not re.fullmatch(r"DP-[0-9]+(?:-T[0-9]+)?", owner_query):
            errors.append(f"unsupported terminal query owner: {owner_query}")
        elif owner_query not in DP420_OWNERS | FOREIGN_OWNERS:
            errors.append(f"unsupported terminal query owner: {owner_query}")
        elif require_terminal:
            active = [
                entry["path"]
                for entry in by_owner.get(owner_query, [])
                if entry.get("terminal") is not True
            ]
            if active:
                errors.append(f"owner {owner_query} is not terminal: {active}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--owner")
    parser.add_argument("--require-terminal", action="store_true")
    args = parser.parse_args()
    errors = validate(Path(args.ledger).resolve(), args.owner, args.require_terminal)
    if errors:
        for error in errors:
            print(f"POLARIS_SCRIPT_LAYER_COVERAGE: {error}")
        return 2
    print("PASS: script-layer semantic coverage")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
