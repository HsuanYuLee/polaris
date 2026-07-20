"""Enforce production language-fit and monotonic migration debt."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from script_layer_audit import build_ledger


MARKER = "POLARIS_SCRIPT_LANGUAGE_FIT"


def load(path: Path, label: str) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} unreadable: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"{label} must be a JSON object")
    return data


def git_changed(root: Path, base_ref: str | None) -> set[str]:
    if not base_ref:
        return set()
    result = subprocess.run(
        ["git", "-C", str(root), "diff", "--name-only", f"{base_ref}...HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise ValueError(f"cannot derive changed files from {base_ref}: {result.stderr.strip()}")
    return {line for line in result.stdout.splitlines() if line}


def base_entries(root: Path, base_ref: str | None) -> list[dict[str, Any]] | None:
    if not base_ref:
        return None
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{base_ref}:scripts/script-layer-governance-ledger.json"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise ValueError(f"cannot read base ledger from {base_ref}: {result.stderr.strip()}")
    try:
        entries = json.loads(result.stdout)["entries"]
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        raise ValueError(f"base ledger from {base_ref} is malformed: {exc}") from exc
    if not isinstance(entries, list):
        raise ValueError(f"base ledger from {base_ref} entries must be a list")
    return entries


def validate(args: argparse.Namespace) -> list[str]:
    ledger = load(args.ledger, "ledger")
    manifest = load(args.manifest, "manifest")
    governance = manifest.get("script_layer_governance")
    if not isinstance(governance, dict) or not isinstance(governance.get("production_language_fit"), dict):
        return ["manifest missing script_layer_governance.production_language_fit"]
    budget = governance["production_language_fit"]
    owner_max = budget.get("owner_nonterminal_max")
    if not isinstance(owner_max, dict) or "production_nonterminal_max" not in budget:
        return ["production language-fit budget is incomplete"]
    entries = ledger.get("entries")
    if not isinstance(entries, list):
        return ["ledger entries must be a list"]

    errors: list[str] = []
    fresh_entries = {
        entry["path"]: entry for entry in build_ledger(args.root.resolve())["entries"]
    }
    semantic_fields = ("surface", "language", "disposition", "owner", "terminal")
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("surface") != "production":
            continue
        fresh = fresh_entries.get(entry.get("path"))
        if fresh is None:
            errors.append(f"production ledger path is not current: {entry.get('path', '<unknown>')}")
            continue
        if any(entry.get(field) != fresh.get(field) for field in semantic_fields) or (
            (entry.get("evidence") or {}).get("disposition_rule")
            != (fresh.get("evidence") or {}).get("disposition_rule")
        ):
            errors.append(f"production ledger semantics differ from canonical audit: {entry.get('path')}")

    debt = [entry for entry in entries if entry.get("surface") == "production" and entry.get("terminal") is False]
    if len(debt) > int(budget["production_nonterminal_max"]):
        errors.append(
            f"production migration debt increased: {len(debt)} > {budget['production_nonterminal_max']}"
        )
    owners: dict[str, int] = {}
    for entry in debt:
        owner = str(entry.get("owner") or "")
        owners[owner] = owners.get(owner, 0) + 1
    for owner, count in owners.items():
        if owner not in owner_max:
            errors.append(f"production debt has unbudgeted owner: {owner or '<none>'}")
        elif count > int(owner_max[owner]):
            errors.append(f"production debt for {owner} increased: {count} > {owner_max[owner]}")

    prior_entries = base_entries(args.root.resolve(), args.base_ref)
    if prior_entries is not None:
        prior_debt = [
            entry for entry in prior_entries
            if entry.get("surface") == "production" and entry.get("terminal") is False
        ]
        if len(debt) > len(prior_debt):
            errors.append(f"production migration debt regressed from prior wave: {len(debt)} > {len(prior_debt)}")
        prior_owners: dict[str, int] = {}
        for entry in prior_debt:
            owner = str(entry.get("owner") or "")
            prior_owners[owner] = prior_owners.get(owner, 0) + 1
        for owner, count in owners.items():
            if count > prior_owners.get(owner, 0):
                errors.append(
                    f"production debt for {owner or '<none>'} regressed from prior wave: {count} > {prior_owners.get(owner, 0)}"
                )

    changed = git_changed(args.root.resolve(), args.base_ref)
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("surface") != "production":
            continue
        path = str(entry.get("path") or "")
        if path in changed and (entry.get("disposition") == "migrate" or entry.get("terminal") is False):
            errors.append(f"changed production script remains migration debt: {path}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--base-ref")
    args = parser.parse_args()
    try:
        errors = validate(args)
    except ValueError as exc:
        errors = [str(exc)]
    if errors:
        for error in errors:
            print(f"{MARKER}: {error}", file=sys.stderr)
        return 2
    print("PASS: production script language-fit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
