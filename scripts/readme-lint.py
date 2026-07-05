#!/usr/bin/env python3
"""
Docs lint: checks that skill references across all documentation files match
the actual skill catalog (.claude/skills/*/SKILL.md).

Checks:
1. Skill count — "N workflow skills" matches actual SKILL.md count
2. Undocumented skills — SKILL.md exists but not mentioned in any doc
3. Phantom skills — doc references a skill name that has no SKILL.md
4. chinese-triggers table — skill names in table rows vs catalog
5. Mermaid diagram nodes — node labels in flowchart blocks vs catalog

Usage:
  python3 scripts/readme-lint.py              # check only
  python3 scripts/readme-lint.py --fix        # auto-fix skill counts
  python3 scripts/readme-lint.py --verbose    # show all details

Exit codes: 0 = clean, 1 = drift found, 2 = error
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("POLARIS_README_LINT_ROOT", Path(__file__).resolve().parent.parent)).resolve()
SKILLS_DIR = ROOT / ".claude" / "skills"
README_FILES = [ROOT / "README.md", ROOT / "README.zh-TW.md"]
DOCS_DIR = ROOT / "docs"
CHINESE_TRIGGERS = DOCS_DIR / "chinese-triggers.md"
PUBLIC_ONBOARDING_DOCS = [
    ROOT / "README.md",
    ROOT / "README.zh-TW.md",
    DOCS_DIR / "quick-start-zh.md",
    DOCS_DIR / "codex-quick-start.md",
    DOCS_DIR / "codex-quick-start.zh-TW.md",
    DOCS_DIR / "pm-setup-checklist.md",
    DOCS_DIR / "pm-setup-checklist.zh-TW.md",
]
WORKFLOW_GUIDES = [
    DOCS_DIR / "workflow-guide.md",
    DOCS_DIR / "workflow-guide.zh-TW.md",
]

# Skills that are intentionally not user-facing (don't require doc mention)
INTERNAL_SKILLS = {
    "example",         # template only
}

DEPRECATED_SKILL_ALIASES = {
    "init": "onboard",
}


def get_maintainer_only_skills() -> set[str]:
    """Read SKILL.md frontmatter for `scope: maintainer-only` — same mechanism as sync-to-polaris.sh."""
    maintainer = set()
    for p in SKILLS_DIR.glob("*/SKILL.md"):
        rel = p.relative_to(SKILLS_DIR)
        if len(rel.parts) != 2:
            continue
        try:
            text = p.read_text(encoding="utf-8")
            if "scope:" in text and "maintainer-only" in text:
                # Narrow check: both substrings appear in frontmatter
                maintainer.add(p.parent.name)
        except Exception:
            pass
    return maintainer

# Known non-skill backtick terms that look like skill names (reduce false positives)
KNOWN_NON_SKILLS = {
    # Claude official features (not our SKILL.md)
    "skill-creator",
    # Reference files (skills/references/*.md, not standalone skills)
    "engineer-delivery-flow",
    "pr-body-builder",
    "skill-routing",
    # Modes within existing skills (not standalone)
    "scope-challenge",
    "sub-tasks",
    # Old names (merged/renamed)
    "epic-breakdown",      # → breakdown
    "epic-status",         # → converge
    "end-of-day",          # → standup
    "worklog-report",      # → jira-worklog
    "validate-isolation",  # → validate
    "validate-mechanisms", # → validate
    "which-company",       # → use-company
    "unit-test-review",    # → unit-test
    "tdd",                 # → unit-test
    "work-on",             # → engineering
    # Non-skill terms
    "review-lessons",      # directory, not a skill
    "pre-commit",          # git concept
    "co-authored-by",      # git trailer
    "telemetry-sync",      # mentioned in security section as "no telemetry"
}


def get_actual_skills() -> set[str]:
    """Get all shared skill names from SKILL.md directories (exclude company-specific)."""
    skills = set()
    for p in SKILLS_DIR.glob("*/SKILL.md"):
        # Skip company-specific skills (nested under company dirs)
        rel = p.relative_to(SKILLS_DIR)
        if len(rel.parts) == 2:  # direct child: skills/{name}/SKILL.md
            skills.add(p.parent.name)
    return skills


def get_skill_names_in_text(text: str, actual_skills: set[str]) -> set[str]:
    """Find skill names mentioned in text by matching against actual skill names."""
    found = set()
    for skill in actual_skills:
        patterns = [
            rf"`{re.escape(skill)}`",
            rf'"{re.escape(skill)}"',
            rf"(?<![a-z\-]){re.escape(skill)}(?![a-z\-])",
        ]
        for pattern in patterns:
            if re.search(pattern, text):
                found.add(skill)
                break
    return found


def check_skill_count(text: str, actual: int) -> list[dict]:
    """Find 'N workflow skills' or 'N 個工作流技能' patterns and check against actual count."""
    findings = []
    for m in re.finditer(r"(\d+)\s+(?:workflow\s+)?skills", text):
        stated = int(m.group(1))
        if stated != actual:
            findings.append({
                "type": "skill_count",
                "stated": stated,
                "actual": actual,
                "match": m.group(0),
                "pos": m.start(),
            })
    for m in re.finditer(r"(\d+)\s*個(?:工作流)?技能", text):
        stated = int(m.group(1))
        if stated != actual:
            findings.append({
                "type": "skill_count",
                "stated": stated,
                "actual": actual,
                "match": m.group(0),
                "pos": m.start(),
            })
    return findings


def fix_skill_count(text: str, actual: int) -> str:
    """Replace stale skill counts with actual count."""
    text = re.sub(
        r"(\d+)(\s+(?:workflow\s+)?skills)",
        lambda m: f"{actual}{m.group(2)}",
        text,
    )
    text = re.sub(
        r"(\d+)(\s*個(?:工作流)?技能)",
        lambda m: f"{actual}{m.group(2)}",
        text,
    )
    return text


def check_phantom_skills(text: str, actual_skills: set[str]) -> list[dict]:
    """Find backtick-quoted names that look like skill references but don't exist."""
    findings = []
    for m in re.finditer(r"`([a-z][a-z0-9-]+)`", text):
        candidate = m.group(1)
        if (
            candidate not in actual_skills
            and candidate not in KNOWN_NON_SKILLS
            and len(candidate) > 3
            and candidate.count("-") >= 1
            # Must appear near skill-related context
            and any(
                ctx in text[max(0, m.start() - 300):m.end() + 300].lower()
                for ctx in [
                    "skill", "trigger", "invoke", "技能", "觸發",
                    "pillar", "支柱", "路由", "route",
                ]
            )
        ):
            findings.append({
                "type": "phantom_skill",
                "name": candidate,
                "pos": m.start(),
            })
    return findings


def check_chinese_triggers(actual_skills: set[str]) -> list[dict]:
    """Validate chinese-triggers.md table entries against skill catalog."""
    if not CHINESE_TRIGGERS.exists():
        return []

    text = CHINESE_TRIGGERS.read_text(encoding="utf-8")
    findings = []

    # Extract skill names from table rows: | **skill-name** — description |
    table_skills = set()
    for m in re.finditer(r"\|\s*\*\*([a-zA-Z][a-zA-Z0-9-]*)\*\*", text):
        name = m.group(1)
        table_skills.add(DEPRECATED_SKILL_ALIASES.get(name, name))

    # Skills in table but not in catalog
    for name in sorted(table_skills - actual_skills):
        if name not in KNOWN_NON_SKILLS:
            findings.append({
                "type": "triggers_phantom",
                "name": name,
                "file": "docs/chinese-triggers.md",
            })

    # Skills in catalog but not in table (excluding internal)
    user_facing = actual_skills - INTERNAL_SKILLS
    for name in sorted(user_facing - table_skills):
        findings.append({
            "type": "triggers_missing",
            "name": name,
            "file": "docs/chinese-triggers.md",
        })

    return findings


def check_mermaid_diagrams(actual_skills: set[str]) -> list[dict]:
    """Validate skill names in mermaid flowchart node labels."""
    findings = []

    # Labels that are references/concepts, not standalone skills
    non_skill_labels = {
        "engineer-delivery-flow",  # reference file, not a skill
    }

    for wf in WORKFLOW_GUIDES:
        if not wf.exists():
            continue

        text = wf.read_text(encoding="utf-8")
        rel = str(wf.relative_to(ROOT))

        # Extract mermaid blocks
        for block_m in re.finditer(r"```mermaid\n(.*?)```", text, re.DOTALL):
            block = block_m.group(1)

            # Extract node labels: ID["label-text<br/>..."]
            for node_m in re.finditer(r'(\w+)\["([^"]+)"\]', block):
                label = node_m.group(2)
                # Clean HTML: remove <br/>, <code>...</code> wrappers
                clean = re.sub(r"<br/>.*", "", label)
                clean = re.sub(r"</?code>", "", clean)
                clean = clean.strip()

                # Check if it looks like a skill name
                if (
                    re.match(r"^[a-z][a-z0-9-]+$", clean)
                    and clean not in actual_skills
                    and clean not in non_skill_labels
                    and clean not in KNOWN_NON_SKILLS
                    and len(clean) > 3
                ):
                    findings.append({
                        "type": "diagram_phantom",
                        "name": clean,
                        "file": rel,
                        "node_id": node_m.group(1),
                    })

    return findings


def check_public_onboarding_no_init() -> list[dict]:
    """Public first-run docs should teach onboard, not init slash commands."""
    findings = []
    banned_patterns = [
        re.compile(r"/init"),
        re.compile(r"Run\s+`/init`", re.IGNORECASE),
        re.compile(r"執行\s+`/init`"),
        re.compile(r"slash command.*init", re.IGNORECASE),
    ]

    for doc_path in PUBLIC_ONBOARDING_DOCS:
        if not doc_path.exists():
            continue
        text = doc_path.read_text(encoding="utf-8")
        rel = str(doc_path.relative_to(ROOT))
        for pattern in banned_patterns:
            for m in pattern.finditer(text):
                findings.append({
                    "type": "public_onboarding_init",
                    "file": rel,
                    "line": line_number_at(text, m.start()),
                    "match": m.group(0),
                })

    return findings


def check_public_onboarding_toolchain_contract() -> list[dict]:
    """Public onboarding docs must expose the root toolchain contract."""
    script = ROOT / "scripts" / "validate-public-onboarding-contract.sh"
    if not script.exists():
        return []

    result = subprocess.run(
        ["bash", str(script)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode == 0:
        return []
    return [{
        "type": "public_onboarding_toolchain_contract",
        "file": "public onboarding docs",
        "line": 0,
        "output": result.stdout.strip(),
    }]


def line_number_at(text: str, pos: int) -> int:
    """Convert character position to line number."""
    return text[:pos].count("\n") + 1


def main():
    parser = argparse.ArgumentParser(description="Docs lint")
    parser.add_argument("--fix", action="store_true", help="Auto-fix stale counts")
    parser.add_argument("--verbose", action="store_true", help="Show all details")
    args = parser.parse_args()

    actual_skills = get_actual_skills()
    actual_count = len(actual_skills)
    maintainer_only = get_maintainer_only_skills()
    # Treat maintainer-only skills as internal for doc-mention purposes
    actual_skills = actual_skills - maintainer_only
    actual_count = len(actual_skills)
    all_findings = []
    fixed_files = []

    # Collect all skill mentions across all README + docs files
    all_mentioned: set[str] = set()
    scan_files = list(README_FILES)
    if DOCS_DIR.exists():
        scan_files += list(DOCS_DIR.glob("*.md"))

    for doc_path in scan_files:
        if not doc_path.exists():
            continue

        text = doc_path.read_text(encoding="utf-8")
        rel = str(doc_path.relative_to(ROOT))

        # Check 1: Skill count
        count_findings = check_skill_count(text, actual_count)
        for f in count_findings:
            f["file"] = rel
            f["line"] = line_number_at(text, f["pos"])
            all_findings.append(f)

        if args.fix and count_findings:
            new_text = fix_skill_count(text, actual_count)
            if new_text != text:
                doc_path.write_text(new_text, encoding="utf-8")
                fixed_files.append(rel)

        # Collect mentioned skills
        mentioned = get_skill_names_in_text(text, actual_skills)
        all_mentioned |= mentioned

        # Check 3: Phantom skills in prose
        phantom_findings = check_phantom_skills(text, actual_skills)
        for f in phantom_findings:
            f["file"] = rel
            f["line"] = line_number_at(text, f["pos"])
            all_findings.append(f)

    # Check 2: Undocumented skills
    user_facing = actual_skills - INTERNAL_SKILLS
    undocumented = user_facing - all_mentioned
    for skill in sorted(undocumented):
        all_findings.append({
            "type": "undocumented_skill",
            "skill": skill,
            "file": "(none)",
            "line": 0,
        })

    # Check 4: chinese-triggers table validation
    all_findings.extend(check_chinese_triggers(actual_skills))

    # Check 5: Mermaid diagram validation
    all_findings.extend(check_mermaid_diagrams(actual_skills))

    # Check 6: public onboarding docs must not teach init slash command
    all_findings.extend(check_public_onboarding_no_init())

    # Check 7: public onboarding docs must expose required toolchain contract
    all_findings.extend(check_public_onboarding_toolchain_contract())

    # === Report ===
    count_issues = [f for f in all_findings if f["type"] == "skill_count"]
    undoc_issues = [f for f in all_findings if f["type"] == "undocumented_skill"]
    phantom_issues = [f for f in all_findings if f["type"] == "phantom_skill"]
    triggers_phantom = [f for f in all_findings if f["type"] == "triggers_phantom"]
    triggers_missing = [f for f in all_findings if f["type"] == "triggers_missing"]
    diagram_issues = [f for f in all_findings if f["type"] == "diagram_phantom"]
    onboarding_init_issues = [f for f in all_findings if f["type"] == "public_onboarding_init"]
    onboarding_toolchain_issues = [f for f in all_findings if f["type"] == "public_onboarding_toolchain_contract"]

    if not all_findings:
        print(f"Docs lint: OK ({actual_count} skills, all documented)")
        return 0

    exit_code = 0

    if count_issues:
        print(f"Skill count drift ({len(count_issues)}):\n")
        for f in count_issues:
            print(
                f"  {f['file']}:{f['line']} — "
                f'"{f["match"]}" says {f["stated"]}, actual is {f["actual"]}'
            )
        exit_code = 1

    if phantom_issues:
        print(f"\nPhantom skills in docs ({len(phantom_issues)}):")
        print("  These look like skill references but have no SKILL.md:\n")
        for f in phantom_issues:
            print(f"  {f['file']}:{f['line']} — `{f['name']}`")
        print(
            "\n  Action: update the doc to use the correct skill name, "
            "or add to KNOWN_NON_SKILLS if not a skill."
        )
        exit_code = 1

    if triggers_phantom:
        print(f"\nPhantom skills in chinese-triggers ({len(triggers_phantom)}):")
        for f in triggers_phantom:
            print(f"  {f['file']} — **{f['name']}** (no SKILL.md)")
        exit_code = 1

    if triggers_missing:
        print(f"\nSkills missing from chinese-triggers ({len(triggers_missing)}):")
        for f in triggers_missing:
            print(f"  {f['file']} — {f['name']}")
        exit_code = 1

    if diagram_issues:
        print(f"\nPhantom skills in mermaid diagrams ({len(diagram_issues)}):")
        for f in diagram_issues:
            print(f"  {f['file']} — node {f['node_id']} label `{f['name']}`")
        exit_code = 1

    if onboarding_init_issues:
        print(f"\nPublic onboarding docs still mention init slash command ({len(onboarding_init_issues)}):")
        for f in onboarding_init_issues:
            print(f"  {f['file']}:{f['line']} — {f['match']}")
        print("\n  Action: use an onboard natural-language prompt in public first-run docs.")
        exit_code = 1

    if onboarding_toolchain_issues:
        print(f"\nPublic onboarding docs drift from toolchain contract ({len(onboarding_toolchain_issues)}):")
        for f in onboarding_toolchain_issues:
            print(f"\n{f['output']}")
        exit_code = 1

    if undoc_issues:
        print(f"\nUndocumented skills ({len(undoc_issues)}):")
        print("  These skills exist but are not mentioned in any README or docs/ file:\n")
        for f in undoc_issues:
            print(f"  - {f['skill']}")
        print(
            "\n  Action: add to README.md skill lists, or add to INTERNAL_SKILLS "
            "in this script if intentionally internal."
        )
        exit_code = 1

    if args.verbose:
        documented = user_facing & all_mentioned
        print(f"\nDocumented skills ({len(documented)}/{len(user_facing)}):")
        for s in sorted(documented):
            print(f"  ✓ {s}")
        if INTERNAL_SKILLS & actual_skills:
            print("\nInternal skills (excluded from check):")
            for s in sorted(INTERNAL_SKILLS & actual_skills):
                print(f"  ⊘ {s}")

    if args.fix and fixed_files:
        print(f"\nFixed counts in: {', '.join(fixed_files)}")
        if not undoc_issues and not phantom_issues:
            return 0

    if count_issues and not args.fix:
        print("\nRun with --fix to auto-correct counts.")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
