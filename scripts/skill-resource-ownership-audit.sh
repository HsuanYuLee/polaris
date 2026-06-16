#!/usr/bin/env bash
# Purpose: audit ownership of shared references and root scripts — classify each
#   resource as keep_shared / keep_private / candidate_rehome / needs_manual_review.
#   Root-script infrastructure status reads the authoritative scripts/manifest.json
#   `kind` field, not a filename prefix (DP-325 T4 / AC6).
# Inputs:  --root <path>, --skills-dir <path>, --markdown (optional flags)
# Outputs: stdout ownership table (text or Starlight Markdown); exit 0 on success,
#          2 on bad arguments / missing root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR=""
OUTPUT_FORMAT="text"

usage() {
  cat >&2 <<'EOF'
usage: skill-resource-ownership-audit.sh [options]

Options:
  --root <path>        Workspace root (default: script parent)
  --skills-dir <path>  Explicit skills directory (default: <root>/.claude/skills)
  --markdown           Emit Starlight-compatible Markdown
  -h, --help           Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --skills-dir) SKILLS_DIR="${2:-}"; shift 2 ;;
    --markdown) OUTPUT_FORMAT="markdown"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "skill-resource-ownership-audit: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

python3 - "$ROOT" "$SKILLS_DIR" "$OUTPUT_FORMAT" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).expanduser().resolve()
skills_arg = sys.argv[2]
output_format = sys.argv[3]
skills_dir = Path(skills_arg).expanduser().resolve() if skills_arg else root / ".claude" / "skills"
shared_ref_dir = skills_dir / "references"
root_scripts_dir = root / "scripts"

# Authoritative per-script manifest fields (kind / owner_surface). The root-script
# classifier reads the recorded `kind` rather than inferring infrastructure status
# from a filename prefix (DP-325 T4 / AC6) — the manifest field is the single
# source of truth, so classification follows the field, not the script's name.
# Manifest kinds that mark a root script as framework-shared infrastructure.
SHARED_INFRA_MANIFEST_KINDS = {"gate", "writer", "resolver", "release", "selftest", "support"}


def load_manifest_kinds(workspace_root: Path) -> dict:
    """Load each manifest script row's `kind` field, keyed by repo-relative path.

    Args:
        workspace_root: workspace root holding scripts/manifest.json.

    Returns:
        Mapping of manifest `path` to its `kind` string; empty when the manifest
        is absent or unreadable (classifier then falls back to no-kind handling).
    """
    manifest_path = workspace_root / "scripts" / "manifest.json"
    if not manifest_path.exists():
        return {}
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return {
        str(row["path"]): str(row.get("kind", ""))
        for row in data.get("scripts", [])
        if isinstance(row, dict) and row.get("path")
    }


manifest_kind_by_path = load_manifest_kinds(root)

if output_format not in {"text", "markdown"}:
    print("skill-resource-ownership-audit: invalid output format", file=sys.stderr)
    sys.exit(2)
if not root.exists():
    print(f"skill-resource-ownership-audit: root not found: {root}", file=sys.stderr)
    sys.exit(2)


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return str(path)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def is_text_file(path: Path) -> bool:
    return path.suffix in {".md", ".txt", ".yaml", ".yml", ".json", ".sh", ".py", ".js", ".ts", ".tsx", ".vue"}


skills = sorted(p.parent.name for p in skills_dir.glob("*/SKILL.md")) if skills_dir.exists() else []
skill_set = set(skills)

search_files: list[tuple[str, Path]] = []
if skills_dir.exists():
    for path in sorted(skills_dir.rglob("*")):
        if path.is_file() and is_text_file(path):
            parts = path.relative_to(skills_dir).parts
            owner = parts[0] if parts else ""
            search_files.append((owner, path))

if root_scripts_dir.exists():
    for path in sorted(root_scripts_dir.glob("*.sh")):
        if path.is_file():
            search_files.append(("scripts", path))


def direct_consumers(resource: Path, *, owner_hint: str | None = None) -> set[str]:
    out: set[str] = set()
    r = rel(resource)
    name = resource.name
    stem = resource.stem
    parent = resource.parent.name
    patterns = {
        r,
        f"`{r}`",
        name,
        f"`{name}`",
        f"{parent}/{name}",
        f"`{parent}/{name}`",
    }
    if owner_hint:
        patterns.add(f"{owner_hint}/{parent}/{name}")

    for owner, path in search_files:
        if path.resolve() == resource.resolve():
            continue
        try:
            text = read_text(path)
        except OSError:
            continue
        if any(pattern in text for pattern in patterns):
            if owner in skill_set:
                out.add(owner)
            elif owner == "scripts":
                out.add("scripts")

    # Some references are named after the owning skill flow. Use this only as a
    # weak hint when the filename starts with an exact skill name.
    for skill in skills:
        if stem == skill or stem.startswith(f"{skill}-"):
            out.add(skill)
    return out


def index_consumers(resource: Path) -> set[str]:
    index = shared_ref_dir / "INDEX.md"
    if not index.exists() or resource.parent.resolve() != shared_ref_dir.resolve():
        return set()
    try:
        text = read_text(index)
    except OSError:
        return set()
    found: set[str] = set()
    for line in text.splitlines():
        if resource.name not in line:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        haystack = " ".join(cells[1:]) if len(cells) > 1 else line
        for skill in skills:
            if re.search(rf"(?<![A-Za-z0-9_-]){re.escape(skill)}(?![A-Za-z0-9_-])", haystack):
                found.add(skill)
    return found


CONTRACT_WORDS = {
    "contract",
    "protocol",
    "policy",
    "registry",
    "schema",
    "default",
    "shared",
    "workspace",
    "handoff",
    "task-md",
    "starlight",
    "pipeline",
    "language",
    "branch",
    "config",
}


def looks_shared_contract(path: Path) -> bool:
    name = path.stem.lower()
    if any(word in name for word in CONTRACT_WORDS):
        return True
    try:
        head = "\n".join(read_text(path).splitlines()[:30]).lower()
    except OSError:
        return False
    return any(word in head for word in ("contract", "protocol", "policy", "shared", "schema"))


def classify_shared_reference(path: Path) -> tuple[set[str], str, str, str]:
    direct = direct_consumers(path)
    indexed = index_consumers(path)
    consumers = direct | indexed
    owner = "-"
    if len(consumers) == 1:
        owner = next(iter(consumers))
    if path.name == "INDEX.md":
        return consumers, "shared", "keep_shared", "shared index"
    if len(consumers) == 0:
        return consumers, "-", "needs_manual_review", "no consumer detected"
    if len(consumers) >= 2:
        return consumers, "shared", "keep_shared", "multi-consumer resource"
    if looks_shared_contract(path):
        return consumers, owner, "needs_manual_review", "single consumer but contract-like content"
    if not direct and indexed:
        return consumers, owner, "needs_manual_review", "index-only ownership signal"
    return consumers, owner, "candidate_rehome", "single direct consumer"


def classify_private_resource(path: Path, owner: str) -> tuple[set[str], str, str, str]:
    consumers = direct_consumers(path, owner_hint=owner)
    external = sorted(c for c in consumers if c not in {owner})
    if external:
        return consumers, owner, "needs_manual_review", f"owner mismatch: referenced by {', '.join(external)}"
    return consumers or {owner}, owner, "keep_private", "skill-private resource"


def classify_root_script(path: Path) -> tuple[set[str], str, str, str]:
    consumers = direct_consumers(path)
    # DP-325 T4 / AC6: infrastructure status follows the authoritative manifest
    # `kind` field, not a filename prefix. A root script whose manifest kind is a
    # framework-shared role (gate / writer / resolver / release / selftest /
    # support) is shared infrastructure regardless of how it is named.
    manifest_kind = manifest_kind_by_path.get(rel(path), "")
    if manifest_kind in SHARED_INFRA_MANIFEST_KINDS:
        return consumers, "shared", "keep_shared", f"root infrastructure script (manifest kind={manifest_kind})"
    skill_consumers = sorted(c for c in consumers if c in skill_set)
    if len(skill_consumers) == 1 and len(consumers) == 1:
        return consumers, skill_consumers[0], "needs_manual_review", "single skill consumer root script"
    if len(consumers) >= 2:
        return consumers, "shared", "keep_shared", "multi-consumer root script"
    return consumers, "-", "needs_manual_review", "no consumer detected"


rows: list[dict[str, str]] = []

if shared_ref_dir.exists():
    for path in sorted(shared_ref_dir.glob("*.md")):
        consumers, owner, action, reason = classify_shared_reference(path)
        rows.append({
            "resource_path": rel(path),
            "kind": "shared_reference",
            "consumers": ", ".join(sorted(consumers)) if consumers else "-",
            "suggested_owner": owner,
            "action": action,
            "reason": reason,
        })

if skills_dir.exists():
    for skill in skills:
        for subdir, kind in (("references", "skill_private_reference"), ("scripts", "skill_private_script")):
            base = skills_dir / skill / subdir
            if not base.exists():
                continue
            for path in sorted(p for p in base.rglob("*") if p.is_file()):
                consumers, owner, action, reason = classify_private_resource(path, skill)
                rows.append({
                    "resource_path": rel(path),
                    "kind": kind,
                    "consumers": ", ".join(sorted(consumers)) if consumers else "-",
                    "suggested_owner": owner,
                    "action": action,
                    "reason": reason,
                })

if root_scripts_dir.exists():
    for path in sorted(root_scripts_dir.glob("*.sh")):
        consumers, owner, action, reason = classify_root_script(path)
        rows.append({
            "resource_path": rel(path),
            "kind": "root_script",
            "consumers": ", ".join(sorted(consumers)) if consumers else "-",
            "suggested_owner": owner,
            "action": action,
            "reason": reason,
        })

action_order = {"candidate_rehome": 0, "needs_manual_review": 1, "keep_shared": 2, "keep_private": 3}
rows.sort(key=lambda row: (action_order.get(row["action"], 9), row["kind"], row["resource_path"]))


def esc(value: str) -> str:
    return value.replace("|", "\\|")


if output_format == "markdown":
    print("---")
    print('title: "Skill Resource Ownership Audit"')
    print('description: "Advisory audit for skill-private versus shared reference/script ownership."')
    print("---")
    print()
    print("## Summary")
    print()
    for action in ("candidate_rehome", "needs_manual_review", "keep_shared", "keep_private"):
        print(f"- {action}: {sum(1 for row in rows if row['action'] == action)}")
    print()
    print("## Findings")
    print()
    print("| resource_path | kind | consumers | suggested_owner | action | reason |")
    print("|---------------|------|-----------|-----------------|--------|--------|")
    for row in rows:
        print(
            f"| `{esc(row['resource_path'])}` | {esc(row['kind'])} | {esc(row['consumers'])} | "
            f"{esc(row['suggested_owner'])} | {esc(row['action'])} | {esc(row['reason'])} |"
        )
else:
    print("resource_path\tkind\tconsumers\tsuggested_owner\taction\treason")
    for row in rows:
        print(
            f"{row['resource_path']}\t{row['kind']}\t{row['consumers']}\t"
            f"{row['suggested_owner']}\t{row['action']}\t{row['reason']}"
        )
PY
