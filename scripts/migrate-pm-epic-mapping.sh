#!/usr/bin/env bash
# scripts/migrate-pm-epic-mapping.sh
#
# Migrate `local_role: pm_epic_mapping` company Epic containers into the
# canonical refinement flow:
#
# 1. Discover containers with `local_role: pm_epic_mapping` in frontmatter
#    under `docs-manager/src/content/docs/specs/companies/{company}/{KEY}/`.
# 2. Parse PM child Story rows (markdown table) under the "## PM Child Tickets"
#    section. Falls back to a permissive bullet list parser if no table is
#    present.
# 3. Emit / merge `refinement.md` (handoff markdown) + `refinement.json`
#    (machine artifact). Each PM child Story is written into the JSON
#    `dependencies[]` array with a new `type: pm_child_story` entry carrying
#    `target` (JIRA key), `role`, `status`, `description`.
# 4. Remove `local_role` from the container frontmatter.
# 5. Containers whose child Story list cannot be parsed → exit 2 and append
#    them to a workspace-level manual review list.
# 6. Idempotent: a second apply on the same workspace is a no-op.
#
# CLI:
#   --workspace-root DIR   Workspace root containing docs-manager/... (required)
#   --dry-run              Plan only; do not modify files (default)
#   --apply                Mutate files
#   --include-archive      Also process archive/ containers (default skip)
#   --skip KEY             Skip a specific JIRA key (repeatable)
#
# Exit codes:
#   0 = success
#   2 = fatal (malformed container, parse failure, missing workspace)
#
# DP-228-T13. Covers AC8, AC9, AC-NF3, AC-NEG5.

set -euo pipefail

WORKSPACE_ROOT=""
MODE="dry-run"
INCLUDE_ARCHIVE=0
SKIPS=()

usage() {
  cat <<'EOF' >&2
Usage:
  scripts/migrate-pm-epic-mapping.sh --workspace-root DIR [--dry-run|--apply]
                                     [--include-archive] [--skip KEY ...]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT="$2"; shift 2 ;;
    --dry-run)        MODE="dry-run"; shift ;;
    --apply)          MODE="apply"; shift ;;
    --include-archive) INCLUDE_ARCHIVE=1; shift ;;
    --skip)           SKIPS+=("$2"); shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$WORKSPACE_ROOT" ]]; then
  echo "ERROR: --workspace-root is required" >&2
  exit 2
fi
if [[ ! -d "$WORKSPACE_ROOT" ]]; then
  echo "ERROR: workspace root not found: $WORKSPACE_ROOT" >&2
  exit 2
fi

SPECS_ROOT="$WORKSPACE_ROOT/docs-manager/src/content/docs/specs"
if [[ ! -d "$SPECS_ROOT" ]]; then
  echo "ERROR: specs root not found: $SPECS_ROOT" >&2
  exit 2
fi

SKIP_JOINED="$(IFS=,; echo "${SKIPS[*]:-}")"

# Delegate parse + emit to a single Python step so we can keep table /
# bullet parsing and JSON merge logic structured and testable.
python3 - "$SPECS_ROOT" "$MODE" "$INCLUDE_ARCHIVE" "$SKIP_JOINED" "$WORKSPACE_ROOT" <<'PY'
import datetime as _dt
import json
import os
import re
import sys

SPECS_ROOT = sys.argv[1]
MODE = sys.argv[2]
INCLUDE_ARCHIVE = sys.argv[3] == "1"
SKIPS = {s for s in sys.argv[4].split(",") if s}
WORKSPACE_ROOT = sys.argv[5]

FRONT_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
LOCAL_ROLE_RE = re.compile(r"^local_role:\s*\"?pm_epic_mapping\"?\s*$", re.MULTILINE)
ANY_LOCAL_ROLE_RE = re.compile(r"^local_role:[^\n]*\n", re.MULTILINE)
PM_CHILD_HEADING_RE = re.compile(
    r"^##\s+PM\s+Child\s+Tickets\s*$", re.IGNORECASE | re.MULTILINE
)
NEXT_HEADING_RE = re.compile(r"^##\s+", re.MULTILINE)
JIRA_KEY_RE = re.compile(r"\b([A-Z][A-Z0-9]+-\d+)\b")


def now_iso():
    return (
        _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0, tzinfo=None).isoformat()
        + "Z"
    )


def list_containers():
    results = []
    base = os.path.join(SPECS_ROOT, "companies")
    if not os.path.isdir(base):
        return results
    for company in sorted(os.listdir(base)):
        company_dir = os.path.join(base, company)
        if not os.path.isdir(company_dir):
            continue
        for entry in sorted(os.listdir(company_dir)):
            entry_path = os.path.join(company_dir, entry)
            if not os.path.isdir(entry_path):
                continue
            if entry == "archive":
                if not INCLUDE_ARCHIVE:
                    continue
                for arc in sorted(os.listdir(entry_path)):
                    arc_path = os.path.join(entry_path, arc)
                    if not os.path.isdir(arc_path):
                        continue
                    results.append((company, arc, arc_path, True))
                continue
            results.append((company, entry, entry_path, False))
    return results


def read_index(container):
    p = os.path.join(container, "index.md")
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def has_pm_epic_mapping(text):
    if text is None:
        return False
    m = FRONT_RE.match(text)
    if not m:
        return False
    return LOCAL_ROLE_RE.search(m.group(1)) is not None


def extract_section(text, heading_re):
    m = heading_re.search(text)
    if not m:
        return None
    start = m.end()
    nm = NEXT_HEADING_RE.search(text, start)
    end = nm.start() if nm else len(text)
    return text[start:end]


def parse_child_table(section):
    """Parse a markdown table. Returns list[dict] or None."""
    if section is None:
        return None
    rows = []
    lines = [ln.rstrip() for ln in section.splitlines() if ln.strip()]
    table_lines = [ln for ln in lines if ln.startswith("|")]
    if len(table_lines) < 2:
        return None
    # First row is header, second is alignment separator.
    headers = [c.strip().lower() for c in table_lines[0].strip("|").split("|")]
    if not any("jira" in h or "key" in h for h in headers):
        return None
    if len(table_lines) < 3:
        # Header + separator but no data → treat as empty table; not malformed.
        return []
    # Try to identify column positions.
    def col(name_hints):
        for idx, h in enumerate(headers):
            for hint in name_hints:
                if hint in h:
                    return idx
        return None

    key_idx = col(["jira key", "key"])
    type_idx = col(["issue type", "type"])
    role_idx = col(["local role", "role"])
    summary_idx = col(["summary", "title"])
    posture_idx = col(["posture", "implementation", "status"])
    if key_idx is None:
        return None
    for ln in table_lines[2:]:
        cells = [c.strip() for c in ln.strip("|").split("|")]
        if not cells or len(cells) <= key_idx:
            continue
        key_cell = cells[key_idx]
        m = JIRA_KEY_RE.search(key_cell)
        if not m:
            continue
        rows.append(
            {
                "target": m.group(1),
                "issue_type": cells[type_idx] if type_idx is not None and type_idx < len(cells) else "",
                "role": cells[role_idx] if role_idx is not None and role_idx < len(cells) else "",
                "summary": cells[summary_idx] if summary_idx is not None and summary_idx < len(cells) else "",
                "posture": cells[posture_idx] if posture_idx is not None and posture_idx < len(cells) else "",
            }
        )
    return rows


def parse_child_bullets(section):
    """Permissive fallback: any bullet line that starts with a JIRA key."""
    if section is None:
        return None
    rows = []
    for ln in section.splitlines():
        s = ln.strip()
        if not s or not (s.startswith("-") or s.startswith("*")):
            continue
        body = s.lstrip("-*").strip()
        m = JIRA_KEY_RE.match(body)
        if not m:
            continue
        rows.append(
            {
                "target": m.group(1),
                "issue_type": "",
                "role": "",
                "summary": body[m.end():].lstrip(" -:|").strip(),
                "posture": "",
            }
        )
    return rows if rows else None


def remove_local_role(text):
    m = FRONT_RE.match(text)
    if not m:
        return text
    raw = m.group(1)
    cleaned = ANY_LOCAL_ROLE_RE.sub("", raw + "\n").rstrip() + "\n"
    return f"---\n{cleaned}---\n" + text[m.end():]


def normalise_dep(row):
    issue_type = row.get("issue_type") or "Story"
    role = row.get("role") or "scope_reference"
    status = row.get("posture") or "open"
    summary = row.get("summary") or ""
    description = summary if summary else f"PM child {issue_type}"
    return {
        "type": "pm_child_story",
        "target": row["target"],
        "issue_type": issue_type,
        "role": role,
        "status": status,
        "description": description,
        "blocking": False,
    }


def build_refinement_md(epic_key, rows):
    today = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
    lines = []
    lines.append("---")
    lines.append(f'title: "Refinement — {epic_key}: PM Epic mapping handoff"')
    lines.append(
        'description: "PM child Story mapping promoted from local_role: pm_epic_mapping container."'
    )
    lines.append("status: DISCUSSION")
    lines.append('jira_issue_type: "Epic"')
    lines.append("---")
    lines.append("")
    lines.append(f"> Source: DP-146 / DP-228 | JIRA: {epic_key} | Date: {today}")
    lines.append("")
    lines.append("## PM Child Story Dependencies")
    lines.append("")
    if rows:
        lines.append("| JIRA key | Issue type | Role | Summary | Status |")
        lines.append("|---|---|---|---|---|")
        for r in rows:
            lines.append(
                "| {target} | {it} | {role} | {summary} | {status} |".format(
                    target=r["target"],
                    it=r.get("issue_type") or "Story",
                    role=r.get("role") or "scope_reference",
                    summary=r.get("summary") or "",
                    status=r.get("posture") or "open",
                )
            )
    else:
        lines.append("_(no child Story rows discovered)_")
    lines.append("")
    lines.append("## Mapping Policy")
    lines.append("")
    lines.append("- PM child Story 視為 scope reference，不直接當 RD work order。")
    lines.append("- RD implementation 另開 RD-owned task，並回連對應 PM ticket。")
    lines.append("")
    return "\n".join(lines)


def build_refinement_json(epic_key, container, rows, existing):
    base = {
        "epic": epic_key,
        "source": {
            "type": "jira",
            "id": epic_key,
            "container": container,
            "plan_path": None,
            "jira_key": epic_key,
        },
        "version": "1.0",
        "tier": 1,
        "tier_signals": ["pm_epic_mapping container migrated to standard refinement"],
        "created_at": now_iso(),
        "refinement_round": 1,
        "completeness": {"score": "0/8", "items": []},
        "modules": [],
        "dependencies": [],
        "edge_cases": [],
        "acceptance_criteria": [],
        "gaps": {"pm_questions": [], "rd_risks": []},
        "research": [],
        "research_gate": {
            "status": "none",
            "deferred": False,
            "defer_reason": None,
            "missing_research": [],
        },
        "predecessor_audit": [],
        "downstream": {
            "suggested_subtask_count": 0,
            "estimated_total_points": "0",
            "breakdown_hints": [],
        },
    }
    if existing is not None:
        merged = existing
        # Preserve original created_at and refinement_round if present.
    else:
        merged = base

    # Always overwrite source + dependencies (canonical PM child Story set).
    merged.setdefault("source", base["source"])
    merged["source"]["type"] = "jira"
    merged["source"]["id"] = epic_key
    merged["source"]["container"] = container
    merged["source"]["plan_path"] = None
    merged["source"]["jira_key"] = epic_key

    other_deps = [
        d for d in (merged.get("dependencies") or []) if d.get("type") != "pm_child_story"
    ]
    pm_deps = [normalise_dep(r) for r in rows]
    merged["dependencies"] = other_deps + pm_deps

    # Ensure required scaffolding keys exist (without clobbering authored content).
    for k, v in base.items():
        if k not in merged:
            merged[k] = v

    return merged


def load_existing_json(path):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        try:
            return json.load(fh)
        except json.JSONDecodeError:
            return None


def write_text(path, content):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=False)
        fh.write("\n")


def already_migrated(container):
    """A container is considered fully migrated when:
       - index.md has no local_role: pm_epic_mapping AND
       - refinement.md exists AND
       - refinement.json exists with pm_child_story dependencies.
    """
    idx = os.path.join(container, "index.md")
    if not os.path.isfile(idx):
        return False
    with open(idx, encoding="utf-8") as fh:
        idx_text = fh.read()
    if has_pm_epic_mapping(idx_text):
        return False
    rj = os.path.join(container, "refinement.json")
    rm = os.path.join(container, "refinement.md")
    if not (os.path.isfile(rj) and os.path.isfile(rm)):
        return False
    return True


def main():
    plan = []
    malformed = []
    for company, key, container, archived in list_containers():
        if key in SKIPS:
            continue
        text = read_index(container)
        if text is None:
            continue
        is_target = has_pm_epic_mapping(text)
        is_migrated = already_migrated(container)
        if not is_target and not is_migrated:
            continue
        if is_migrated and not is_target:
            # Idempotency: already migrated, no action.
            plan.append(
                {
                    "company": company,
                    "key": key,
                    "container": container,
                    "archived": archived,
                    "action": "noop",
                    "reason": "already_migrated",
                }
            )
            continue
        section = extract_section(text, PM_CHILD_HEADING_RE)
        rows = parse_child_table(section)
        if rows is None:
            rows = parse_child_bullets(section)
        if rows is None:
            malformed.append(
                {
                    "company": company,
                    "key": key,
                    "container": container,
                    "archived": archived,
                    "reason": "child Story list could not be parsed",
                }
            )
            continue
        plan.append(
            {
                "company": company,
                "key": key,
                "container": container,
                "archived": archived,
                "action": "migrate",
                "child_count": len(rows),
                "rows": rows,
            }
        )

    if malformed:
        # Always write the manual review list so engineers can audit even
        # on dry-run; emit JSON plan first, then surface the failure.
        audit_dir = os.path.join(WORKSPACE_ROOT, ".polaris", "evidence", "migrate-pm-epic-mapping")
        os.makedirs(audit_dir, exist_ok=True)
        audit_path = os.path.join(audit_dir, "manual-review.md")
        lines = [
            "# migrate-pm-epic-mapping — manual review list",
            "",
            f"_Generated: {now_iso()}_",
            "",
            "These containers carry `local_role: pm_epic_mapping` but the PM child",
            "Story list could not be parsed as a table or recognisable bullet list.",
            "Resolve each entry manually (fix the table, or rename `local_role` to a",
            "different role) before re-running the migration.",
            "",
        ]
        for m in malformed:
            lines.append(f"- `{m['container']}` ({m['key']}): {m['reason']}")
        write_text(audit_path, "\n".join(lines) + "\n")
        # Also drop a sibling marker next to each malformed container so
        # callers can discover them without scanning the workspace.
        for m in malformed:
            side = os.path.join(m["container"], ".migrate-pm-epic-mapping-review.md")
            write_text(side, f"# {m['key']} — manual review required\n\n{m['reason']}\n")

        sys.stdout.write(
            json.dumps(
                {
                    "mode": MODE,
                    "plan": plan,
                    "malformed": malformed,
                    "manual_review_list": audit_path,
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n"
        )
        sys.stderr.write(
            f"ERROR: {len(malformed)} container(s) have unparseable PM child Story lists. "
            f"See manual review list: {audit_path}\n"
        )
        sys.exit(2)

    if MODE == "apply":
        for item in plan:
            if item["action"] != "migrate":
                continue
            container = item["container"]
            # Refresh frontmatter (drop local_role).
            idx_path = os.path.join(container, "index.md")
            with open(idx_path, encoding="utf-8") as fh:
                old = fh.read()
            new_idx = remove_local_role(old)
            if new_idx != old:
                write_text(idx_path, new_idx)
            # Build refinement.md
            refinement_md = build_refinement_md(item["key"], item["rows"])
            md_path = os.path.join(container, "refinement.md")
            if not os.path.isfile(md_path):
                write_text(md_path, refinement_md)
            # Build refinement.json (merge with existing)
            json_path = os.path.join(container, "refinement.json")
            existing = load_existing_json(json_path)
            merged = build_refinement_json(
                item["key"], container, item["rows"], existing
            )
            # Idempotency: if existing JSON already matches what we'd write,
            # skip rewriting so file mtime / hash stays stable.
            if existing is not None:
                merged["created_at"] = existing.get("created_at", merged["created_at"])
                merged["refinement_round"] = existing.get(
                    "refinement_round", merged["refinement_round"]
                )
            # Compare normalised JSON to existing for stable idempotency.
            new_blob = json.dumps(merged, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
            if os.path.isfile(json_path):
                with open(json_path, encoding="utf-8") as fh:
                    if fh.read() == new_blob:
                        continue
            write_text(json_path, new_blob)

    sys.stdout.write(
        json.dumps(
            {"mode": MODE, "plan": plan, "malformed": []},
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )


main()
PY
