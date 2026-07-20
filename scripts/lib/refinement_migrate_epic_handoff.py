#!/usr/bin/env python3
"""Migrate Epic refinement handoff artifacts."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

USAGE = """Usage:
  scripts/migrate-epic-refinement-handoff.sh --workspace-root <path>
                                              [--dry-run | --apply]
                                              [--include-archive]

Defaults: --dry-run (no mutations). Pass --apply to write refinement.md and
the non-ready audit list.
"""

def usage(message: str | None = None) -> None:
    if message:
        print(message, file=sys.stderr)
    print(USAGE, end="", file=sys.stderr)

def main_checkout(start: Path) -> Path | None:
    proc=subprocess.run(["git", "-C", str(start), "rev-parse", "--git-common-dir"], capture_output=True, text=True)
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    common=Path(proc.stdout.strip())
    if not common.is_absolute():
        common=(start / common).resolve()
    return common.parent

def specs_root_for(start: str) -> Path:
    explicit=os.environ.get("POLARIS_SPECS_ROOT")
    if explicit:
        path=Path(explicit).resolve()
        if path.is_symlink() or not path.is_dir():
            print(f"resolve-specs-root: missing explicit specs source: {path}; pass --specs-source or run from the main checkout with canonical specs available", file=sys.stderr)
            raise SystemExit(1)
        return path
    override=os.environ.get("POLARIS_WORKSPACE_ROOT")
    workspace=Path(override or start).resolve()
    main=main_checkout(workspace)
    if main is not None:
        workspace=main
    path=workspace / "docs-manager/src/content/docs/specs"
    if path.is_symlink() or not path.is_dir():
        print(f"resolve-specs-root: missing workspace specs root: {path}; pass --specs-source or run from the main checkout with canonical specs available", file=sys.stderr)
        raise SystemExit(1)
    return path

args=sys.argv[1:]
workspace=""
mode="dry-run"
include_archive="0"
i=0
while i < len(args):
    arg=args[i]
    if arg == "--workspace-root":
        workspace=args[i+1] if i+1 < len(args) else ""
        if not workspace:
            usage(); raise SystemExit(2)
        i += 2
    elif arg == "--dry-run": mode="dry-run"; i += 1
    elif arg == "--apply": mode="apply"; i += 1
    elif arg == "--include-archive": include_archive="1"; i += 1
    elif arg in {"-h", "--help"}: usage(); raise SystemExit(0)
    else: usage(f"unknown argument: {arg}"); raise SystemExit(2)
if not workspace:
    usage(); raise SystemExit(2)
sys.argv=[sys.argv[0], str(specs_root_for(workspace)), mode, include_archive]

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

specs_root = Path(sys.argv[1])
mode = sys.argv[2]
include_archive = sys.argv[3] == "1"


EPIC_KEY_RE = re.compile(r"^[A-Z][A-Z0-9]*-[0-9]+$")


def is_archive(path: Path) -> bool:
    return "archive" in path.parts


def find_company_epic_containers() -> list[Path]:
    """Return Path objects for companies/<company>/<KEY>/ containers."""
    out: list[Path] = []
    companies_root = specs_root / "companies"
    if not companies_root.is_dir():
        return out
    for company_dir in sorted(p for p in companies_root.iterdir() if p.is_dir()):
        for child in sorted(company_dir.rglob("refinement.json")):
            if not include_archive and is_archive(child):
                continue
            container = child.parent
            # container name should match Epic key pattern
            if not EPIC_KEY_RE.match(container.name):
                continue
            out.append(container)
    return out


def load_json(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    return data


def read_index_frontmatter(path: Path) -> dict:
    """Parse simple YAML-ish frontmatter (key: value lines) from an index.md."""
    out: dict = {}
    if not path.is_file():
        return out
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return out
    for line in lines[1:]:
        if line.strip() == "---":
            break
        match = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*?)\s*$', line)
        if not match:
            continue
        key, raw_value = match.group(1), match.group(2)
        value = raw_value.strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        out[key] = value
    return out


def assess_confidence(refinement: dict, frontmatter: dict) -> tuple[str, list[str]]:
    """Return (confidence, reasons).

    HIGH iff refinement.json has at least one module and at least one
    acceptance_criteria entry, AND index.md frontmatter title is non-empty.
    """
    reasons: list[str] = []
    modules = refinement.get("modules") if isinstance(refinement, dict) else None
    acs = refinement.get("acceptance_criteria") if isinstance(refinement, dict) else None

    if not isinstance(modules, list) or len(modules) == 0:
        reasons.append("refinement.json modules[] is empty or missing")
    if not isinstance(acs, list) or len(acs) == 0:
        reasons.append("refinement.json acceptance_criteria[] is empty or missing")
    title = frontmatter.get("title", "").strip()
    if not title:
        reasons.append("index.md frontmatter title is empty or missing")

    confidence = "HIGH" if not reasons else "LOW"
    return confidence, reasons


def derive_source_id(container: Path, refinement: dict) -> str:
    source = refinement.get("source") if isinstance(refinement, dict) else None
    if isinstance(source, dict):
        sid = source.get("id")
        if isinstance(sid, str) and sid.strip():
            return sid.strip()
    epic = refinement.get("epic")
    if isinstance(epic, str) and epic.strip():
        return epic.strip()
    return container.name


def normalize_text(value, default: str = "") -> str:
    if isinstance(value, str):
        return value.strip()
    return default


def render_handoff_markdown(
    source_id: str,
    frontmatter: dict,
    refinement: dict,
) -> str:
    title = frontmatter.get("title") or f"Refinement — {source_id}"
    description = frontmatter.get("description") or (
        f"Handoff-grade refinement generated by migrate-epic-refinement-handoff "
        f"for {source_id}."
    )

    modules = refinement.get("modules") or []
    acs = refinement.get("acceptance_criteria") or []
    edge_cases = refinement.get("edge_cases") or []
    dependencies = refinement.get("dependencies") or []
    downstream = refinement.get("downstream") if isinstance(refinement, dict) else None

    lines: list[str] = []
    lines.append("---")
    lines.append(f'title: "{title}"')
    lines.append(f'description: "{description}"')
    lines.append('status: LOCKED')
    lines.append('migrated_from: "refinement.json + index.md"')
    today = datetime.now(timezone.utc).date().isoformat()
    lines.append(f'migration_date: "{today}"')
    lines.append("---")
    lines.append("")
    lines.append(
        "> Auto-generated by `scripts/migrate-epic-refinement-handoff.sh` "
        "from `refinement.json` + `index.md`. Treat as handoff-grade artifact; "
        "review for nuance before next refinement round."
    )
    lines.append("")

    # Scope
    lines.append("## Scope")
    lines.append("")
    scope_text = (
        f"由 migration 從既有 `refinement.json` 推導：{source_id} 既有 "
        f"refinement.json 提供 {len(modules)} 個模組與 {len(acs)} 條 AC。"
    )
    if isinstance(refinement.get("tier"), int):
        scope_text += f" Detected tier: {refinement['tier']}."
    lines.append(scope_text)
    lines.append("")

    # Technical Approach
    lines.append("## Technical Approach")
    lines.append("")
    tier_signals = refinement.get("tier_signals") if isinstance(refinement, dict) else None
    if isinstance(tier_signals, list) and tier_signals:
        for signal in tier_signals:
            lines.append(f"- {normalize_text(signal)}")
    else:
        lines.append(
            "- 依 refinement.json modules[] 與 acceptance_criteria[] 推導；"
            "詳細實作方式請對照原 index.md 與 JIRA Epic 描述。"
        )
    lines.append("")

    # Modules
    lines.append("## Modules")
    lines.append("")
    if modules:
        lines.append("| Path | Action | Reason |")
        lines.append("|---|---|---|")
        for mod in modules:
            if not isinstance(mod, dict):
                continue
            path = normalize_text(mod.get("path"), "(unknown)")
            action = normalize_text(mod.get("action"), "modify")
            reason = normalize_text(mod.get("reason"), "")
            reason = reason.replace("|", "\\|").replace("\n", " ")
            lines.append(f"| `{path}` | {action} | {reason} |")
    else:
        lines.append("(refinement.json modules[] 為空)")
    lines.append("")

    # Acceptance Criteria
    lines.append("## Acceptance Criteria")
    lines.append("")
    if acs:
        lines.append("| ID | 內容 | 驗證方式 |")
        lines.append("|---|---|---|")
        for ac in acs:
            if not isinstance(ac, dict):
                continue
            ac_id = normalize_text(ac.get("id"), "AC?")
            text = normalize_text(ac.get("text"), "")
            text = text.replace("|", "\\|").replace("\n", " ")
            verification = ac.get("verification") or {}
            if isinstance(verification, dict):
                method = normalize_text(verification.get("method"), "manual")
                detail = normalize_text(verification.get("detail"), "")
                detail = detail.replace("|", "\\|").replace("\n", " ")
                verify_cell = f"`{method}`"
                if detail:
                    verify_cell = f"`{method}` — {detail}"
            else:
                verify_cell = "manual"
            lines.append(f"| {ac_id} | {text} | {verify_cell} |")
    else:
        lines.append("(refinement.json acceptance_criteria[] 為空)")
    lines.append("")

    # Edge Cases
    lines.append("## Edge Cases")
    lines.append("")
    if isinstance(edge_cases, list) and edge_cases:
        lines.append("| Scenario | Handling | Severity |")
        lines.append("|---|---|---|")
        for ec in edge_cases:
            if not isinstance(ec, dict):
                continue
            scenario = normalize_text(ec.get("scenario"))
            scenario = scenario.replace("|", "\\|").replace("\n", " ")
            handling = normalize_text(ec.get("handling"))
            handling = handling.replace("|", "\\|").replace("\n", " ")
            severity = normalize_text(ec.get("severity"), "n/a")
            lines.append(f"| {scenario} | {handling} | {severity} |")
    else:
        lines.append("(refinement.json edge_cases[] 為空)")
    lines.append("")

    # Dependencies (optional section)
    if isinstance(dependencies, list) and dependencies:
        lines.append("## Dependencies")
        lines.append("")
        lines.append("| Type | Target | Blocking | 說明 |")
        lines.append("|---|---|---|---|")
        for dep in dependencies:
            if not isinstance(dep, dict):
                continue
            dtype = normalize_text(dep.get("type"), "unknown")
            target = normalize_text(dep.get("target"), "")
            blocking = "yes" if dep.get("blocking") else "no"
            description = normalize_text(dep.get("description"), "")
            description = description.replace("|", "\\|").replace("\n", " ")
            lines.append(f"| {dtype} | {target} | {blocking} | {description} |")
        lines.append("")

    # Downstream Hints
    lines.append("## Downstream Hints")
    lines.append("")
    if isinstance(downstream, dict) and downstream:
        hints = downstream.get("breakdown_hints")
        if isinstance(hints, list) and hints:
            for h in hints:
                lines.append(f"- {normalize_text(h)}")
        else:
            lines.append(
                "- 依 refinement.json downstream 區塊推導；"
                "若 breakdown 想拆 sub-task，請先確認 JIRA Epic 最新需求。"
            )
    else:
        lines.append(
            "- refinement.json 沒有 downstream hints；"
            "breakdown 前請確認 JIRA Epic 是否已更新。"
        )
    lines.append("")

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Scan and classify
# ---------------------------------------------------------------------------

records: list[dict] = []
non_ready: list[dict] = []
already_ok = 0
would_backfill = 0
backfilled = 0

for container in find_company_epic_containers():
    refinement_json = container / "refinement.json"
    refinement_md = container / "refinement.md"
    index_md = container / "index.md"

    rel = container.relative_to(specs_root).as_posix()

    if refinement_md.is_file():
        already_ok += 1
        records.append(
            {
                "container": rel,
                "status": "already_ok",
            }
        )
        continue

    refinement_data = load_json(refinement_json)
    if refinement_data is None:
        non_ready.append(
            {
                "source_id": container.name,
                "container": rel,
                "reasons": ["refinement.json is unparseable"],
            }
        )
        records.append({"container": rel, "status": "non_ready"})
        continue

    frontmatter = read_index_frontmatter(index_md)
    confidence, reasons = assess_confidence(refinement_data, frontmatter)
    source_id = derive_source_id(container, refinement_data)

    if confidence == "LOW":
        non_ready.append(
            {
                "source_id": source_id,
                "container": rel,
                "reasons": reasons,
            }
        )
        records.append({"container": rel, "status": "non_ready"})
        continue

    would_backfill += 1
    if mode == "apply":
        markdown = render_handoff_markdown(source_id, frontmatter, refinement_data)
        refinement_md.write_text(markdown, encoding="utf-8")
        backfilled += 1
    records.append({"container": rel, "status": "would_backfill"})


# ---------------------------------------------------------------------------
# Write non-ready audit (apply mode only)
# ---------------------------------------------------------------------------

audit_dir = specs_root / "refinement-handoff-audit"

if mode == "apply":
    if non_ready:
        audit_dir.mkdir(parents=True, exist_ok=True)
        # Markdown audit
        md_lines = [
            "# Refinement Handoff Migration — Non-Ready Audit",
            "",
            "> Generated by `scripts/migrate-epic-refinement-handoff.sh`. "
            "These Epic containers have a `refinement.json` but missing or "
            "insufficient context to safely derive a handoff-grade "
            "`refinement.md`. Each entry must be reviewed manually.",
            "",
            f"_Last apply: {datetime.now(timezone.utc).isoformat()}_",
            "",
            "| Source | Container | Reasons |",
            "|---|---|---|",
        ]
        for item in non_ready:
            reasons_str = "; ".join(item["reasons"]).replace("|", "\\|")
            md_lines.append(
                f"| {item['source_id']} | `{item['container']}` | {reasons_str} |"
            )
        md_lines.append("")
        (audit_dir / "non-ready.md").write_text(
            "\n".join(md_lines), encoding="utf-8"
        )

        # JSON audit
        payload = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "generator": "migrate-epic-refinement-handoff.sh",
            "entries": non_ready,
        }
        (audit_dir / "non-ready.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    else:
        # Empty result: remove stale audit so re-run reflects reality.
        for fname in ("non-ready.md", "non-ready.json"):
            stale = audit_dir / fname
            if stale.is_file():
                stale.unlink()

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

total = len(records)
print(f"mode={mode}")
print(f"specs_root={specs_root}")
print(f"include_archive={'1' if include_archive else '0'}")
print(f"total={total}")
print(f"already_ok={already_ok}")
print(f"would_backfill={would_backfill}")
print(f"backfilled={backfilled}")
print(f"non_ready={len(non_ready)}")
for item in records:
    print(f"[{item['status']}] {item['container']}")
for entry in non_ready:
    reasons = "; ".join(entry["reasons"])
    print(f"  non-ready: {entry['source_id']} :: {reasons}")
