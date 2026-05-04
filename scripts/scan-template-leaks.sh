#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="$DEFAULT_WORKSPACE"
TEMPLATE=""
SOURCE="workspace"
FORMAT="summary"
BLOCKING=0

usage() {
  cat >&2 <<'EOF'
usage: scan-template-leaks.sh [options]

Options:
  --workspace <path>   Workspace instance root (default: script parent)
  --template <path>    Polaris template root (required for --source template)
  --source <mode>      workspace | template | both (default: workspace)
  --format <mode>      summary | markdown | json (default: summary)
  --blocking           Exit 1 when material leak hits exist
  -h, --help           Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --template) TEMPLATE="${2:-}"; shift 2 ;;
    --source) SOURCE="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --blocking) BLOCKING=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "scan-template-leaks: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

python3 - "$WORKSPACE" "$TEMPLATE" "$SOURCE" "$FORMAT" "$BLOCKING" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"scan-template-leaks: PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(2)

workspace = Path(sys.argv[1]).expanduser().resolve()
template_arg = sys.argv[2]
template = Path(template_arg).expanduser().resolve() if template_arg else None
source_mode = sys.argv[3]
output_format = sys.argv[4]
blocking = sys.argv[5] == "1"

if source_mode not in {"workspace", "template", "both"}:
    print("scan-template-leaks: --source must be workspace, template, or both", file=sys.stderr)
    sys.exit(2)
if output_format not in {"summary", "markdown", "json"}:
    print("scan-template-leaks: --format must be summary, markdown, or json", file=sys.stderr)
    sys.exit(2)
if not workspace.exists():
    print(f"scan-template-leaks: workspace not found: {workspace}", file=sys.stderr)
    sys.exit(2)
if source_mode in {"template", "both"} and (template is None or not template.exists()):
    print("scan-template-leaks: --template is required for template source scan", file=sys.stderr)
    sys.exit(2)


def load_company_configs(root: Path):
    configs = []
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        if child.name.startswith("_"):
            continue
        cfg = child / "workspace-config.yaml"
        if cfg.exists():
            configs.append((child.name, cfg))
    return configs


def collect_patterns(root: Path):
    patterns = []
    companies = []
    for company, cfg_path in load_company_configs(root):
        companies.append(company)
        patterns.append({
            "label": f"company-slug:{company}",
            "regex": rf"(?i)(?<![A-Za-z0-9_]){re.escape(company)}(?![A-Za-z0-9_])",
            "raw": company,
        })
        try:
            data = yaml.safe_load(cfg_path.read_text()) or {}
        except Exception:
            continue

        for project in (data.get("jira") or {}).get("projects") or []:
            key = str(project.get("key") or "").strip()
            if len(key) >= 2:
                patterns.append({
                    "label": f"jira:{key}",
                    "regex": rf"{re.escape(key)}-[0-9]+",
                    "raw": f"{key}-[0-9]+",
                })

        web_urls = data.get("web_urls") or {}
        for value in web_urls.values():
            if not isinstance(value, str) or "." not in value:
                continue
            match = re.search(r"://([^/]+)", value)
            if match:
                domain = match.group(1)
                patterns.append({
                    "label": f"domain:{domain}",
                    "regex": re.escape(domain),
                    "raw": domain,
                })

        jira_instance = str((data.get("jira") or {}).get("instance") or "").strip()
        if jira_instance:
            patterns.append({
                "label": f"jira-instance:{jira_instance}",
                "regex": re.escape(jira_instance),
                "raw": jira_instance,
            })

        channels = (data.get("slack") or {}).get("channels") or {}
        for value in channels.values():
            if isinstance(value, str) and value.startswith("C"):
                patterns.append({
                    "label": f"slack:{value}",
                    "regex": re.escape(value),
                    "raw": value,
                })

        org = str((data.get("github") or {}).get("org") or "").strip()
        if org:
            patterns.append({
                "label": f"github-org:{org}",
                "regex": re.escape(org),
                "raw": org,
            })

    deduped = {}
    for item in patterns:
        deduped[(item["label"], item["regex"])] = item
    return list(deduped.values()), companies


patterns, companies = collect_patterns(workspace)
compiled = [(item, re.compile(item["regex"])) for item in patterns]

TEXT_SUFFIXES = {
    ".md", ".mdx", ".sh", ".py", ".js", ".mjs", ".cjs", ".ts", ".tsx",
    ".json", ".yaml", ".yml", ".txt", ".example", ".toml",
}
TEXT_NAMES = {"CLAUDE.md", "README.md", "README.zh-TW.md", "VERSION", "CHANGELOG.md", "AGENTS.md"}


def is_text_file(path: Path):
    return path.name in TEXT_NAMES or path.suffix in TEXT_SUFFIXES


def is_maintainer_only_skill(root: Path, skill_name: str):
    skill_md = root / ".claude" / "skills" / skill_name / "SKILL.md"
    if not skill_md.exists():
        return False
    try:
        text = skill_md.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return False
    frontmatter = text.split("---", 2)
    if len(frontmatter) < 3:
        return False
    return bool(re.search(r"(?m)^scope:\s*maintainer-only\s*$", frontmatter[1]))


def skip_path(root: Path, path: Path, source_name: str):
    rel = path.relative_to(root).as_posix()
    parts = rel.split("/")
    if any(part in {".git", "node_modules", "dist", ".astro", "e2e-results", "test-results"} for part in parts):
        return True
    if rel in {".claude/settings.local.json", ".claude/polaris-backlog.md"} or rel.startswith(".claude/checkpoints/"):
        return True
    if ".claude/worktrees/" in rel or rel.startswith(".claude/worktrees/"):
        return True
    if rel.startswith(".agents/skills"):
        return True
    if rel.startswith(".claude/skills/"):
        skill_name = parts[2] if len(parts) > 2 else ""
        if skill_name in companies or is_maintainer_only_skill(root, skill_name):
            return True
    if rel.startswith(".claude/rules/"):
        rule_scope = parts[2] if len(parts) > 2 else ""
        if rule_scope in companies or len(parts) > 3:
            return True
    if rel.startswith("docs-manager/src/content/docs/specs/"):
        return True
    return False


def scan_roots(root: Path, source_name: str):
    candidates = [
        ".claude",
        ".codex",
        ".github",
        "scripts",
        "docs",
        "docs-manager",
        "_template",
        "CLAUDE.md",
        "AGENTS.md",
        "README.md",
        "README.zh-TW.md",
        "CHANGELOG.md",
    ]
    files = []
    for rel in candidates:
        item = root / rel
        if not item.exists():
            continue
        if item.is_file():
            if is_text_file(item) and not skip_path(root, item, source_name):
                files.append(item)
            continue
        for path in item.rglob("*"):
            if path.is_file() and is_text_file(path) and not skip_path(root, path, source_name):
                files.append(path)
    return sorted(set(files))


def classify(rel: str, line: str, labels):
    if "cross-session-learnings" in rel or "review-lesson" in line or '"company"' in line:
        return "real-company-lesson", "anonymize-or-move-to-company-surface"
    if "genericize" in rel:
        return "company-config-leak", "replace-source-or-map"
    if "regex" in line.lower() or "pattern" in line.lower() or "grep" in line.lower():
        return "false-positive-candidate", "prefer-abstract-regex-or-allowlist"
    return "example-placeholder", "replace-with-neutral-placeholder"


def scan_source(root: Path, source_name: str):
    hits = []
    for file_path in scan_roots(root, source_name):
        rel = file_path.relative_to(root).as_posix()
        path_labels = [item["label"] for item, regex in compiled if regex.search(rel)]
        if path_labels:
            classification, action = classify(rel, rel, path_labels)
            hits.append({
                "source": source_name,
                "file": rel,
                "line": 0,
                "patterns": sorted(set(path_labels)),
                "classification": classification,
                "action": "rename-path-or-move-out-of-template",
                "text": rel,
            })
        try:
            text = file_path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for line_no, line in enumerate(text.splitlines(), 1):
            labels = [item["label"] for item, regex in compiled if regex.search(line)]
            if not labels:
                continue
            classification, action = classify(rel, line, labels)
            hits.append({
                "source": source_name,
                "file": rel,
                "line": line_no,
                "patterns": sorted(set(labels)),
                "classification": classification,
                "action": action,
                "text": line.strip(),
            })
    return hits


hits = []
if source_mode in {"workspace", "both"}:
    hits.extend(scan_source(workspace, "workspace"))
if source_mode in {"template", "both"}:
    hits.extend(scan_source(template, "template"))


def emit_summary():
    print("Template leak scan")
    print(f"source: {source_mode}")
    print(f"workspace: {workspace}")
    if template:
        print(f"template: {template}")
    print(f"companies: {', '.join(companies) if companies else 'none'}")
    print(f"patterns: {', '.join(item['raw'] for item in patterns) if patterns else 'none'}")
    print(f"hits: {len(hits)}")
    if hits:
        by_pattern = {}
        by_file = {}
        by_class = {}
        for hit in hits:
            by_file[f"{hit['source']}:{hit['file']}"] = by_file.get(f"{hit['source']}:{hit['file']}", 0) + 1
            by_class[hit["classification"]] = by_class.get(hit["classification"], 0) + 1
            for label in hit["patterns"]:
                by_pattern[label] = by_pattern.get(label, 0) + 1
        print("\nby pattern:")
        for key, count in sorted(by_pattern.items(), key=lambda item: (-item[1], item[0])):
            print(f"  {count:4} {key}")
        print("\nby classification:")
        for key, count in sorted(by_class.items(), key=lambda item: (-item[1], item[0])):
            print(f"  {count:4} {key}")
        print("\ntop files:")
        for key, count in sorted(by_file.items(), key=lambda item: (-item[1], item[0]))[:20]:
            print(f"  {count:4} {key}")
        print("\nexamples:")
        for hit in hits[:20]:
            print(f"  {hit['source']}:{hit['file']}:{hit['line']} [{','.join(hit['patterns'])}] {hit['text'][:160]}")


def emit_markdown():
    print("# Template Leak Scan")
    print()
    print(f"- Source: `{source_mode}`")
    print(f"- Workspace: `{workspace}`")
    if template:
        print(f"- Template: `{template}`")
    print(f"- Companies: `{', '.join(companies) if companies else 'none'}`")
    print(f"- Hits: `{len(hits)}`")
    print()
    print("| Source | File | Line | Patterns | Class | Action | Text |")
    print("|--------|------|------|----------|-------|--------|------|")
    for hit in hits:
        text = hit["text"].replace("|", "\\|")
        print(f"| {hit['source']} | `{hit['file']}` | {hit['line']} | `{', '.join(hit['patterns'])}` | `{hit['classification']}` | `{hit['action']}` | {text} |")


if output_format == "json":
    print(json.dumps({"patterns": patterns, "companies": companies, "hits": hits}, indent=2, ensure_ascii=False))
elif output_format == "markdown":
    emit_markdown()
else:
    emit_summary()

if blocking and hits:
    print(f"scan-template-leaks: BLOCKED: {len(hits)} material leak hit(s)", file=sys.stderr)
    sys.exit(1)
PY
