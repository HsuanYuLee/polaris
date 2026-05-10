#!/usr/bin/env bash
# check-sunset-candidates.sh — inventory reference/script/skill cleanup candidates.

set -euo pipefail

root="."
format="table"
verify_ledger=""

usage() {
  cat >&2 <<'EOF'
usage: check-sunset-candidates.sh [--root <repo>] [--json]
       check-sunset-candidates.sh --verify-ledger [<ledger.json>] [--root <repo>]

Produces a deterministic cleanup ledger for Polaris references, scripts, and
skills. The ledger is advisory: only rows with posture=sunset_ready are eligible
for removal, and broken-reference checks must still pass after removal.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      root="${2:-}"
      shift 2
      ;;
    --json)
      format="json"
      shift
      ;;
    --verify-ledger)
      verify_ledger="${2:-}"
      if [[ -n "$verify_ledger" && "$verify_ledger" != --* ]]; then
        shift 2
      else
        verify_ledger=".polaris/sunset-ledger.json"
        shift
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$root" || ! -d "$root" ]]; then
  echo "error: repo root not found: $root" >&2
  exit 2
fi

python3 - "$root" "$format" "$verify_ledger" <<'PY'
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
fmt = sys.argv[2]
verify_ledger = sys.argv[3]

SEARCH_DIRS = [
    ".claude/skills",
    ".claude/rules",
    "scripts",
    "docs-manager/src/content/docs",
]

ONE_OFF_SCRIPT_PREFIXES = (
    "backfill-",
    "cleanup-",
    "dp033-",
    "infer-",
    "migrate-",
    "scan-template-leaks",
)

CORE_SCRIPT_HINTS = (
    "check-",
    "validate-",
    "resolve-",
    "run-",
    "gate-",
    "framework-release",
    "compile-runtime-instructions",
    "create-design-plan",
)

CORE_SKILLS = {
    "refinement",
    "breakdown",
    "engineering",
    "verify-AC",
    "validate",
    "framework-release",
}


def rel(path: Path) -> str:
    return path.relative_to(root).as_posix()


def rg_consumers(token: str, target: str) -> list[str]:
    paths = [str(root / d) for d in SEARCH_DIRS if (root / d).exists()]
    if not paths:
        return []
    proc = subprocess.run(
        ["rg", "-l", "--fixed-strings", token, *paths],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    consumers: list[str] = []
    for line in proc.stdout.splitlines():
        path = Path(line)
        try:
            rp = path.resolve().relative_to(root).as_posix()
        except ValueError:
            rp = path.as_posix()
        if rp == target:
            continue
        if rp.endswith("-selftest.sh") and target.endswith(rp.replace("-selftest.sh", ".sh")):
            continue
        consumers.append(rp)
    return sorted(set(consumers))


def replacement_for(target: str, kind: str, consumers: list[str]) -> str:
    if consumers:
        return "active consumers retain ownership"
    if kind == "script":
        return "no active consumer; removal requires adjacent broken-reference check"
    if kind == "reference":
        return "no active consumer outside index; remove index row or consolidate pointer"
    if kind == "skill":
        return "no active trigger/consumer evidence; runtime compile must confirm"
    return "N/A"


def action_for(posture: str) -> str:
    return {
        "core_chain": "keep",
        "supporting_gate": "keep",
        "noncore_owned": "keep",
        "archive_only": "keep",
        "sunset_candidate": "demote_or_consolidate",
        "sunset_ready": "remove",
    }.get(posture, "keep")


def script_posture(path: Path, consumers: list[str]) -> str:
    name = path.name
    if consumers:
        return "supporting_gate"
    if name.endswith("-selftest.sh"):
        paired = root / "scripts" / name.replace("-selftest.sh", ".sh")
        if paired.exists():
            return "supporting_gate"
    if name.startswith(ONE_OFF_SCRIPT_PREFIXES):
        return "sunset_ready"
    if name.startswith(CORE_SCRIPT_HINTS):
        return "supporting_gate"
    return "sunset_candidate"


def reference_posture(path: Path, consumers: list[str]) -> str:
    name = path.name
    if name in {"INDEX.md", "task-md-schema.md", "refinement-source-template.md"}:
        return "core_chain"
    non_index = [c for c in consumers if c != ".claude/skills/references/INDEX.md"]
    if non_index:
        return "noncore_owned"
    return "sunset_candidate"


def skill_posture(path: Path, consumers: list[str]) -> str:
    skill = path.parent.name
    if skill in CORE_SKILLS:
        return "core_chain"
    if consumers:
        return "noncore_owned"
    return "sunset_candidate"


def build_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []

    scripts_dir = root / "scripts"
    if scripts_dir.exists():
        for path in sorted(scripts_dir.iterdir()):
            if not path.is_file() or path.name.startswith("."):
                continue
            target = rel(path)
            consumers = rg_consumers(path.name, target)
            posture = script_posture(path, consumers)
            rows.append(
                {
                    "target": target,
                    "type": "script",
                    "posture": posture,
                    "replacement_authority": replacement_for(target, "script", consumers),
                    "active_consumers": consumers,
                    "action": action_for(posture),
                    "verification": "check-sunset-broken-refs.sh plus adjacent selftests",
                }
            )

    refs_dir = root / ".claude/skills/references"
    if refs_dir.exists():
        for path in sorted(refs_dir.glob("*.md")):
            target = rel(path)
            consumers = rg_consumers(path.name, target)
            posture = reference_posture(path, consumers)
            rows.append(
                {
                    "target": target,
                    "type": "reference",
                    "posture": posture,
                    "replacement_authority": replacement_for(target, "reference", consumers),
                    "active_consumers": consumers,
                    "action": action_for(posture),
                    "verification": "reference index consistency and runtime compile",
                }
            )

    skills_dir = root / ".claude/skills"
    if skills_dir.exists():
        for path in sorted(skills_dir.glob("*/SKILL.md")):
            target = rel(path)
            skill = path.parent.name
            consumers = rg_consumers(skill, target)
            posture = skill_posture(path, consumers)
            rows.append(
                {
                    "target": target,
                    "type": "skill",
                    "posture": posture,
                    "replacement_authority": replacement_for(target, "skill", consumers),
                    "active_consumers": consumers,
                    "action": action_for(posture),
                    "verification": "skill routing review and runtime compile",
                }
            )

    return rows


def validate_rows(rows: list[dict[str, object]]) -> list[str]:
    errors: list[str] = []
    required = {
        "target",
        "type",
        "posture",
        "replacement_authority",
        "active_consumers",
        "action",
        "verification",
    }
    valid_types = {"script", "reference", "skill"}
    valid_postures = {
        "core_chain",
        "supporting_gate",
        "noncore_owned",
        "archive_only",
        "sunset_candidate",
        "sunset_ready",
    }
    for idx, row in enumerate(rows):
        missing = sorted(required - row.keys())
        if missing:
            errors.append(f"row {idx}: missing fields: {', '.join(missing)}")
            continue
        if row["type"] not in valid_types:
            errors.append(f"row {idx}: invalid type: {row['type']}")
        if row["posture"] not in valid_postures:
            errors.append(f"row {idx}: invalid posture: {row['posture']}")
        if not isinstance(row["active_consumers"], list):
            errors.append(f"row {idx}: active_consumers must be an array")
        if row["posture"] == "sunset_ready" and row["active_consumers"]:
            errors.append(f"row {idx}: sunset_ready target still has active consumers")
    return errors


if verify_ledger:
    path = root / verify_ledger
    if path.exists():
        rows = json.loads(path.read_text())
        if not isinstance(rows, list):
            print(f"FAIL: ledger root must be an array: {path}", file=sys.stderr)
            raise SystemExit(1)
    else:
        rows = build_rows()
    errors = validate_rows(rows)
    if errors:
        print("FAIL: sunset ledger validation failed", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"PASS: sunset ledger valid ({len(rows)} rows)")
    raise SystemExit(0)

rows = build_rows()

if fmt == "json":
    print(json.dumps(rows, ensure_ascii=False, indent=2))
else:
    print("type\tposture\taction\ttarget\tconsumers")
    for row in rows:
        consumers = row["active_consumers"]
        assert isinstance(consumers, list)
        print(
            f"{row['type']}\t{row['posture']}\t{row['action']}\t"
            f"{row['target']}\t{len(consumers)}"
        )
PY
