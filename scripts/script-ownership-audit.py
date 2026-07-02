#!/usr/bin/env python3
"""Purpose: classify framework scripts with placement taxonomy evidence.

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
SCRIPT_SUFFIXES = {".sh", ".py", ".mjs", ".ts"}


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
            # Compute the skip decision relative to the resolved root so
            # that only SKIP_DIRS nested *inside* the scanned tree are
            # skipped. The root itself may live under a .worktrees/ path
            # (an engineering worktree); checking the absolute path.parts
            # against SKIP_DIRS would then match ".worktrees" in the root
            # prefix and blank out every consumer, turning the
            # categorization Verify Command into a false-pass (EC1).
            try:
                rel_parts = path.relative_to(root).parts
            except ValueError:
                rel_parts = path.parts
            if any(part in SKIP_DIRS for part in rel_parts):
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


def candidate_scripts(root: Path):
    scan_roots = [
        root / "scripts",
        root / ".claude" / "hooks",
        root / ".claude" / "skills",
    ]
    scripts = []
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            try:
                rel_parts = path.relative_to(root).parts
            except ValueError:
                rel_parts = path.parts
            if any(part in SKIP_DIRS for part in rel_parts):
                continue
            if path.is_file() and path.suffix in SCRIPT_SUFFIXES:
                scripts.append(rel(root, path))
    return sorted(set(scripts))


def legacy_root_scripts(root: Path):
    scripts = []
    scripts_dir = root / "scripts"
    if not scripts_dir.exists():
        return scripts
    for path in scripts_dir.iterdir():
        if path.is_file() and path.suffix in SCRIPT_SUFFIXES:
            scripts.append(rel(root, path))
    return sorted(scripts)


def skill_owner_for(path: str):
    parts = path.split("/")
    if len(parts) >= 3 and parts[0] == ".claude" and parts[1] == "skills":
        if parts[2] == "references":
            return "shared-references"
        return parts[2]
    return None


def is_own_selftest_or_fixture(path: str) -> bool:
    """Return True when ``path`` is a script's own selftest or fixture.

    Selftests live under ``scripts/selftests/`` and fixtures under
    ``scripts/fixtures/``. A script's own selftest/fixture moves WITH the
    owning skill, so it must not disqualify skill_local classification
    (EC2). Any other non-skill consumer (hook, rule, workflow, another
    root script) still disqualifies skill_local — see ``classify`` for the
    conservative guard.

    Args:
        path: repo-relative consumer path (POSIX-style).

    Returns:
        True if the consumer is a selftest or fixture under scripts/.
    """
    return path.startswith("scripts/selftests/") or path.startswith("scripts/fixtures/")


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

    # EC2: exactly one skill owner, and every non-skill consumer is this
    # script's own selftest/fixture. The script is movable WITH the owning
    # skill (its selftest/fixture moves alongside it), so classify
    # skill_local rather than demoting to keep_root_with_reason.
    # Conservative: a hook / rule / another-skill / another-root-script
    # non-skill consumer still disqualifies (it is not an own
    # selftest/fixture), falling through to the existing branches.
    if (
        len(skill_owners) == 1
        and skill_owners[0] != "shared-references"
        and non_skill
        and all(is_own_selftest_or_fixture(path) for path in non_skill)
    ):
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


def shebang_for(root: Path, script_path: str) -> str | None:
    try:
        with (root / script_path).open("r", encoding="utf-8", errors="ignore") as handle:
            first_line = handle.readline().strip()
    except OSError:
        return None
    if first_line.startswith("#!"):
        return first_line
    return None


def taxonomy_for(script_path, manifest_row, consumers, decision):
    owner_surface = manifest_row.get("owner_surface", "") if manifest_row else ""
    kind = manifest_row.get("kind", "") if manifest_row else ""
    classification = decision["classification"]

    if script_path.startswith("scripts/fixtures/") or "/fixtures/" in script_path:
        return "generated_or_fixture"
    if script_path.startswith("scripts/selftests/") or kind == "selftest":
        return "selftest"
    if script_path.startswith(".claude/hooks/") or owner_surface == "hook":
        return "hook"
    if script_path.startswith("scripts/lib/"):
        return "framework_lib"
    if script_path.startswith(".claude/skills/"):
        return "skill_local"
    if classification in {"skill_local", "root_contract", "shim_candidate", "sunset_orphan"}:
        return classification
    if classification in {"shared_reference_keep", "keep_root_with_reason"}:
        return "framework_orchestration"
    return "framework_orchestration"


def taxonomy_evidence(root, script_path, manifest_row, consumers, taxonomy, decision):
    evidence = [f"path={script_path}", f"taxonomy={taxonomy}"]
    if manifest_row:
        kind = manifest_row.get("kind")
        owner_surface = manifest_row.get("owner_surface")
        relocation = manifest_row.get("relocation")
        if kind:
            evidence.append(f"manifest.kind={kind}")
        if owner_surface:
            evidence.append(f"manifest.owner_surface={owner_surface}")
        if relocation:
            evidence.append(f"manifest.relocation={relocation}")
    shebang = shebang_for(root, script_path)
    if shebang:
        evidence.append(f"shebang={shebang}")
    evidence.append(f"classification={decision['classification']}")
    evidence.append(f"consumer_count={len(consumers)}")
    if decision.get("owner_skill"):
        evidence.append(f"owner_skill={decision['owner_skill']}")
    return evidence


def main():
    parser = argparse.ArgumentParser(allow_abbrev=False)
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
    for script_path in candidate_scripts(root):
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
        taxonomy = taxonomy_for(script_path, row, consumers, decision)
        rows.append(
            {
                "path": script_path,
                "kind": row.get("kind"),
                "owner_surface": row.get("owner_surface"),
                "taxonomy": taxonomy,
                "taxonomy_evidence": taxonomy_evidence(root, script_path, row, consumers, taxonomy, decision),
                "classification": decision["classification"],
                "recommendation": decision["recommendation"],
                "owner_skill": decision["owner_skill"],
                "consumer_count": len(consumers),
                "consumers": consumers,
                "local_leakage": sorted(set(decision["local_leakage"])),
                "bridge_removal_criteria": decision["bridge_removal_criteria"],
            }
        )

    root_only_count = len(legacy_root_scripts(root))
    summary = {
        "root_scripts": root_only_count,
        "total_scripts": len(rows),
        "skill_local_scripts": sum(1 for row in rows if row["classification"] == "skill_local"),
        "root_contracts": sum(1 for row in rows if row["classification"] == "root_contract"),
        "shim_candidates": sum(1 for row in rows if row["classification"] == "shim_candidate"),
        "sunset_orphans": sum(1 for row in rows if row["classification"] == "sunset_orphan"),
        "taxonomy": {
            name: sum(1 for row in rows if row["taxonomy"] == name)
            for name in [
                "root_contract",
                "framework_orchestration",
                "framework_lib",
                "selftest",
                "hook",
                "skill_local",
                "generated_or_fixture",
                "sunset_orphan",
                "shim_candidate",
            ]
        },
    }
    output = {"summary": summary, "scripts": rows}

    if args.format == "json":
        print(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("path\ttaxonomy\tclassification\trecommendation\towner_skill\tconsumers\tlocal_leakage")
    for row in rows:
        print(
            "\t".join(
                [
                    row["path"],
                    row["taxonomy"],
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
