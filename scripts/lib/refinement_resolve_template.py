"""解析 additive refinement template manifest。"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def default_repo() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False
    )
    return result.stdout.strip() if result.returncode == 0 else str(Path.cwd())


def first_yaml(directory: Path) -> Path | None:
    if not directory.is_dir():
        return None
    candidates = sorted([*directory.glob("*.yaml"), *directory.glob("*.yml")])
    return candidates[0] if candidates else None


USAGE = """Usage:
  bash scripts/resolve-refinement-template.sh [--repo <path>] [--company <name>] [--project <name>] [--format text|json]

Resolves the additive refinement template manifest. Company/project templates
may add sections but may not override framework-owned sections.
"""


def main(argv: list[str] | None = None) -> int:
    raw = list(sys.argv[1:] if argv is None else argv)
    repo_arg, company, project, output_format = default_repo(), "", "", "text"
    i = 0
    while i < len(raw):
        arg = raw[i]
        if arg in {"--repo", "--workspace-root", "--company", "--project", "--format"}:
            value = raw[i + 1] if i + 1 < len(raw) else ""
            if arg in {"--repo", "--workspace-root"}:
                repo_arg = value
            elif arg == "--company":
                company = value
            elif arg == "--project":
                project = value
            else:
                output_format = value
            i += 2
        elif arg in {"-h", "--help"}:
            print(USAGE, end="", file=sys.stderr)
            return 0
        else:
            print(f"resolve-refinement-template: unknown argument: {arg}", file=sys.stderr)
            print(USAGE, end="", file=sys.stderr)
            return 2
    repo = Path(repo_arg)
    if not repo.is_dir():
        print(f"resolve-refinement-template: repo not found: {repo}", file=sys.stderr)
        return 2
    if output_format not in {"text", "json"}:
        print("resolve-refinement-template: --format must be text or json", file=sys.stderr)
        return 2
    repo = repo.resolve()
    framework_sections = [
        "goal_background", "scope", "out_of_scope", "acceptance_criteria",
        "verification_methods", "technical_approach", "dependencies", "gaps_questions",
        "downstream_breakdown_hints",
    ]
    forbidden = ["framework_sections", "remove_framework_sections", "override_framework_sections"]
    selected = None
    source = "framework"
    if company and project:
        selected = first_yaml(repo / company / "polaris-config" / project / "refinement/templates")
        if selected:
            source = "project"
    if selected is None and company:
        selected = first_yaml(repo / company / "polaris-config/refinement/templates")
        if selected:
            source = "company"
    selected = selected or repo / ".claude/skills/references/refinement-source-template.md"
    if not selected.exists():
        print(f"resolve-refinement-template: template not found: {selected}", file=sys.stderr)
        return 1

    text = selected.read_text(encoding="utf-8")
    template_id = selected.stem if source != "framework" else "framework-default"
    company_sections: list[str] = []
    relative = str(selected.relative_to(repo)) if selected.is_relative_to(repo) else str(selected)
    if source != "framework":
        for key in forbidden:
            if re.search(rf"(?m)^\s*{re.escape(key)}\s*:", text):
                print(f"resolve-refinement-template: forbidden override key in {relative}: {key}", file=sys.stderr)
                return 1
        match = re.search(r"(?m)^\s*template_id\s*:\s*[\"']?([^\"'\n#]+)", text)
        if match:
            template_id = match.group(1).strip()
        in_sections = False
        base_indent = 0
        for raw in text.splitlines():
            if re.match(r"^\s*company_sections\s*:\s*$", raw):
                in_sections = True
                base_indent = len(raw) - len(raw.lstrip())
                continue
            if in_sections:
                if not raw.strip() or raw.lstrip().startswith("#"):
                    continue
                indent = len(raw) - len(raw.lstrip())
                if indent <= base_indent and not raw.lstrip().startswith("-"):
                    break
                item = re.match(r"^\s*-\s*[\"']?([^\"'#]+)", raw)
                if item:
                    company_sections.append(item.group(1).strip())
    manifest = {
        "schema_version": 1,
        "source": source,
        "template_id": template_id,
        "path": relative,
        "framework_sections": framework_sections,
        "company_sections": company_sections,
        "forbidden_overrides": forbidden,
        "selected_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    print(json.dumps(manifest, ensure_ascii=False, indent=2) if output_format == "json" else f"{source}:{template_id}:{relative}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
