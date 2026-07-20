"""Validate L2 embedding registry paths, anchors, hooks, and layer consistency."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
REGISTRY = REPO_ROOT / ".claude" / "skills" / "references" / "l2-embedding-registry.md"
RECORD_SEPARATOR = "\x1e"
HELP = """#
# Purpose: 驗證 L2 embedding registry 裡每個 entry 對應的 script / SKILL.md embed /
#          hook 都實際存在且字串一致。漏一個就 exit 1。
# Registry: .claude/skills/references/l2-embedding-registry.md
# Exit codes:
#   0 — 全部 entry 驗證通過（或 registry 無 entry）
#   1 — 至少一個 entry 驗證失敗（missing file / missing grep / anchor 不存在）
#   2 — Registry 檔不存在或格式錯誤（meta error）
#
# Usage:
#   scripts/validate-l2-embedding.sh              # human-readable report
#   scripts/validate-l2-embedding.sh --quiet      # 只輸出 FAIL row + summary
#
# Invoked by:
#   - .claude/skills/validate/SKILL.md Mechanisms mode check #11
#   - Local smoke test during DP-030 Phase 2 rollout
"""


def compact_whitespace(value: str) -> str:
    """Match the legacy trim_restore awk whitespace normalization."""
    return " ".join(value.replace(RECORD_SEPARATOR, "|").split())


def registry_rows(text: str) -> list[list[str]]:
    """Extract and split data rows between the registry markers."""
    table: list[str] = []
    inside = False
    for line in text.splitlines():
        if "<!-- registry:start -->" in line:
            inside = True
            continue
        if "<!-- registry:end -->" in line:
            inside = False
            continue
        if inside and line.startswith("|"):
            table.append(line)
    if not table:
        raise ValueError("registry table markers not found or empty")
    rows: list[list[str]] = []
    for row in table[2:]:
        protected = row.replace(r"\|", RECORD_SEPARATOR)
        fields = [compact_whitespace(field) for field in protected.split("|")]
        if len(fields) < 11:
            fields.extend([""] * (11 - len(fields)))
        rows.append(fields)
    return rows


def validate_row(fields: list[str]) -> tuple[str, str, list[str]]:
    """Validate one normalized registry row."""
    (
        _,
        canary,
        script,
        layer,
        l2_skill,
        l2_grep,
        l1_hook,
        _l1_event,
        _l1_matcher,
        l1_grep,
        *_,
    ) = fields
    errors: list[str] = []

    if script and script != "—":
        if not (REPO_ROOT / script).is_file():
            errors.append(f"  - script not found: {script}")
    else:
        errors.append("  - script column empty")

    if l2_skill and l2_skill != "—":
        if "#" in l2_skill:
            skill_file, anchor = l2_skill.split("#", 1)
        else:
            skill_file = anchor = l2_skill
        skill_path = REPO_ROOT / skill_file
        if not skill_file or not skill_path.is_file():
            errors.append(f"  - L2 skill file not found: {skill_file}")
        else:
            skill_text = skill_path.read_text(encoding="utf-8")
            if anchor not in skill_text:
                errors.append(f"  - L2 anchor missing in {skill_file}: {anchor}")
            if l2_grep and l2_grep != "—" and l2_grep not in skill_text:
                errors.append(
                    f"  - L2 expected grep missing in {skill_file}: {l2_grep}"
                )

    if l1_hook and l1_hook != "—":
        hook_path = REPO_ROOT / l1_hook
        if not hook_path.is_file():
            errors.append(f"  - L1 hook file not found: {l1_hook}")
        else:
            hook_text = hook_path.read_text(encoding="utf-8")
            if l1_grep and l1_grep != "—" and l1_grep not in hook_text:
                errors.append(
                    f"  - L1 expected grep missing in {l1_hook}: {l1_grep}"
                )
        settings = REPO_ROOT / ".claude" / "settings.json"
        if settings.is_file():
            settings_text = settings.read_text(encoding="utf-8")
            if Path(l1_hook).name not in settings_text:
                errors.append(
                    f"  - hook not registered in .claude/settings.json: {Path(l1_hook).name}"
                )

    if layer == "L2+L1":
        if not l2_skill or l2_skill == "—":
            errors.append("  - Layer L2+L1 declared but L2 Skill empty")
        if not l1_hook or l1_hook == "—":
            errors.append("  - Layer L2+L1 declared but L1 Hook empty")
    elif layer == "L1-only":
        if l2_skill and l2_skill != "—":
            errors.append("  - Layer L1-only but L2 Skill populated")
        if not l1_hook or l1_hook == "—":
            errors.append("  - Layer L1-only but L1 Hook empty")
    elif layer == "L2-only":
        if not l2_skill or l2_skill == "—":
            errors.append("  - Layer L2-only but L2 Skill empty")
        if l1_hook and l1_hook != "—":
            errors.append("  - Layer L2-only but L1 Hook populated")
    else:
        errors.append(
            f"  - Unknown Layer value: '{layer}' (expected L2+L1 / L1-only / L2-only)"
        )
    return canary, layer, errors


def build_parser() -> argparse.ArgumentParser:
    """Build the compatibility CLI parser."""
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    """Run the L2 embedding registry validator."""
    args, _unknown = build_parser().parse_known_args(argv)
    if args.help:
        print(HELP, end="")
        return 0
    if not REGISTRY.is_file():
        print(f"ERROR: registry missing at {REGISTRY}", file=sys.stderr)
        return 2
    try:
        rows = registry_rows(REGISTRY.read_text(encoding="utf-8"))
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    if not rows:
        if not args.quiet:
            print("Registry has no data entries — nothing to validate.")
        return 0

    total = passed = failed = 0
    for fields in rows:
        canary = fields[1] if len(fields) > 1 else ""
        if not canary or canary == "Canary":
            continue
        total += 1
        canary, layer, errors = validate_row(fields)
        if errors:
            failed += 1
            print(f"🔴 {canary} — {layer}", file=sys.stderr)
            for error in errors:
                print(error, file=sys.stderr)
        else:
            passed += 1
            if not args.quiet:
                print(f"✅ {canary} — {layer}")

    print()
    print(f"L2 embedding validation: {total} total | {passed} ✅ | {failed} 🔴")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
