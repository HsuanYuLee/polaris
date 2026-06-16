#!/usr/bin/env python3
"""Purpose: classify each root script as skill_local / root_contract / shim_candidate
/ sunset_orphan by cross-referencing its consumers with scripts/manifest.json.

Inputs:  --root <path>, --format {table,json}.
Outputs: stdout classification table or JSON; exit 0 on success.
Side effects: none (read-only scan).

root_contract status reads the authoritative manifest `kind` / `owner_surface`
fields, not a path/filename prefix (DP-325 T4 / AC6).
"""
import argparse
import json
import os
from pathlib import Path


TEXT_SUFFIXES = {
    ".md",
    ".sh",
    ".py",
    ".mjs",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".ts",
    ".js",
}

SKIP_DIRS = {".git", "node_modules", ".worktrees", ".astro", "dist", "build", "__pycache__"}

# Manifest `kind` values that mark a root script as a framework infrastructure
# contract (it stays at the root, owned by the framework, not a single skill).
# Classification reads this authoritative field rather than a path/filename prefix
# (DP-325 T4 / AC6).
ROOT_CONTRACT_MANIFEST_KINDS = {"gate", "writer", "resolver", "release"}


def iter_text_files(root: Path):
    scan_roots = [
        root / ".claude" / "skills",
        root / ".claude" / "rules",
        root / ".claude" / "hooks",
        root / ".github" / "workflows",
        root / "scripts",
    ]
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            if path.is_file() and path.suffix in TEXT_SUFFIXES:
                yield path


def rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def load_manifest(root: Path):
    path = root / "scripts" / "manifest.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {row["path"]: row for row in data.get("scripts", []) if isinstance(row, dict) and "path" in row}


def root_scripts(root: Path):
    scripts = []
    for path in (root / "scripts").iterdir():
        if path.is_file() and path.suffix in {".sh", ".py", ".mjs"}:
            scripts.append(rel(root, path))
    return sorted(scripts)


def skill_owner_for(path: str):
    parts = path.split("/")
    if len(parts) >= 3 and parts[0] == ".claude" and parts[1] == "skills":
        if parts[2] == "references":
            return "shared-references"
        return parts[2]
    return None


def classify(script_path, manifest_row, consumers):
    skill_owners = sorted({owner for path in consumers if (owner := skill_owner_for(path))})
    non_skill = sorted(path for path in consumers if not skill_owner_for(path))
    owner_surface = manifest_row.get("owner_surface", "") if manifest_row else ""
    kind = manifest_row.get("kind", "") if manifest_row else ""
    relocation = manifest_row.get("relocation", "") if manifest_row else ""

    local_leakage = []
    for path in consumers:
        if path.startswith(".claude/hooks/"):
            local_leakage.append("hook_consumer")
    if manifest_row and "manual" in owner_surface:
        local_leakage.append("manual_surface")

    bridge_removal = manifest_row.get("wrapper_removal_criteria") or manifest_row.get("bridge_removal_criteria")

    if script_path == "scripts/resolve-pr-pickup-input.sh":
        return {
            "classification": "skill_local",
            "recommendation": "skill_local",
            "owner_skill": "pr-pickup",
            "bridge_removal_criteria": None,
            "local_leakage": local_leakage,
        }

    if owner_surface in {"hook", "release_flow", "github_workflow"}:
        return {
            "classification": "root_contract",
            "recommendation": "stay",
            "owner_skill": None,
            "bridge_removal_criteria": bridge_removal,
            "local_leakage": local_leakage,
        }

    # DP-325 T4 / AC6: a script whose authoritative manifest kind is a framework
    # infrastructure role (gate / writer / resolver / release) is a root contract
    # regardless of path, filename, or text-search consumer count. Reading the
    # recorded kind field — not a path/filename prefix — stops live framework
    # infrastructure (e.g. a PR gate with no detectable textual consumer) from
    # being mislabeled sunset_orphan.
    if kind in ROOT_CONTRACT_MANIFEST_KINDS:
        return {
            "classification": "root_contract",
            "recommendation": "stay",
            "owner_skill": None,
            "bridge_removal_criteria": bridge_removal,
            "local_leakage": local_leakage,
        }

    if relocation == "move_with_wrapper":
        return {
            "classification": "shim_candidate",
            "recommendation": "keep_bridge",
            "owner_skill": skill_owners[0] if len(skill_owners) == 1 else None,
            "bridge_removal_criteria": bridge_removal,
            "local_leakage": local_leakage,
        }

    if not consumers and owner_surface not in {"manual_maintainer", "script_internal"}:
        return {
            "classification": "sunset_orphan",
            "recommendation": "review_delete",
            "owner_skill": None,
            "bridge_removal_criteria": bridge_removal,
            "local_leakage": local_leakage,
        }

    if len(skill_owners) == 1 and not non_skill and skill_owners[0] != "shared-references":
        return {
            "classification": "skill_local",
            "recommendation": "skill_local",
            "owner_skill": skill_owners[0],
            "bridge_removal_criteria": None,
            "local_leakage": local_leakage,
        }

    if "shared-references" in skill_owners or len(skill_owners) > 1:
        return {
            "classification": "shared_reference_keep",
            "recommendation": "stay_with_reason",
            "owner_skill": None,
            "bridge_removal_criteria": bridge_removal,
            "local_leakage": local_leakage,
        }

    return {
        "classification": "keep_root_with_reason",
        "recommendation": "stay_with_reason",
        "owner_skill": None,
        "bridge_removal_criteria": bridge_removal,
        "local_leakage": local_leakage,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--format", choices=["table", "json"], default="table")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    manifest = load_manifest(root)
    files = list(iter_text_files(root))
    texts = {}
    for path in files:
        try:
            texts[rel(root, path)] = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

    rows = []
    for script_path in root_scripts(root):
        basename = os.path.basename(script_path)
        consumers = []
        for consumer_path, text in texts.items():
            if consumer_path == script_path or consumer_path == "scripts/manifest.json":
                continue
            if script_path in text or f"scripts/{basename}" in text:
                consumers.append(consumer_path)
        consumers = sorted(set(consumers))
        row = manifest.get(script_path, {})
        decision = classify(script_path, row, consumers)
        rows.append(
            {
                "path": script_path,
                "kind": row.get("kind"),
                "owner_surface": row.get("owner_surface"),
                "classification": decision["classification"],
                "recommendation": decision["recommendation"],
                "owner_skill": decision["owner_skill"],
                "consumer_count": len(consumers),
                "consumers": consumers,
                "local_leakage": sorted(set(decision["local_leakage"])),
                "bridge_removal_criteria": decision["bridge_removal_criteria"],
            }
        )

    summary = {
        "root_scripts": len(rows),
        "skill_local_scripts": sum(1 for row in rows if row["classification"] == "skill_local"),
        "root_contracts": sum(1 for row in rows if row["classification"] == "root_contract"),
        "shim_candidates": sum(1 for row in rows if row["classification"] == "shim_candidate"),
        "sunset_orphans": sum(1 for row in rows if row["classification"] == "sunset_orphan"),
    }
    output = {"summary": summary, "scripts": rows}

    if args.format == "json":
        print(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("path\tclassification\trecommendation\towner_skill\tconsumers\tlocal_leakage")
    for row in rows:
        print(
            "\t".join(
                [
                    row["path"],
                    row["classification"],
                    row["recommendation"],
                    row.get("owner_skill") or "-",
                    str(row["consumer_count"]),
                    ",".join(row["local_leakage"]) or "-",
                ]
            )
        )


if __name__ == "__main__":
    main()
