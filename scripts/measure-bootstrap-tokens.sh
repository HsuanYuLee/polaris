#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="local"
FORMAT="text"
TRANSCRIPT=""
MEMORY_INDEX=""

usage() {
  cat >&2 <<'EOF'
usage: measure-bootstrap-tokens.sh [options]

Options:
  --local                 Measure Polaris-controlled local bootstrap sources (default)
  --transcript <path>     Add an observed transcript/debug dump as supporting evidence
  --root <path>           Workspace root (default: script parent)
  --memory-index <path>   Explicit MEMORY.md path (default derived from root)
  --markdown              Emit Markdown report
  --json                  Emit JSON report
  -h, --help              Show help

Every row includes source, scope, confidence, bytes, and estimated tokens.
The default estimator is conservative bytes / 4 and is labeled bytes_estimated.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) MODE="local"; shift ;;
    --transcript) TRANSCRIPT="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --memory-index) MEMORY_INDEX="${2:-}"; shift 2 ;;
    --markdown) FORMAT="markdown"; shift ;;
    --json) FORMAT="json"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "measure-bootstrap-tokens: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

python3 - "$ROOT" "$MODE" "$FORMAT" "$TRANSCRIPT" "$MEMORY_INDEX" <<'PY'
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).expanduser().resolve()
mode = sys.argv[2]
output_format = sys.argv[3]
transcript_arg = sys.argv[4]
memory_index_arg = sys.argv[5]

if mode != "local":
    print(f"measure-bootstrap-tokens: unsupported mode: {mode}", file=sys.stderr)
    sys.exit(2)

if output_format not in {"text", "markdown", "json"}:
    print(f"measure-bootstrap-tokens: unsupported format: {output_format}", file=sys.stderr)
    sys.exit(2)

if not root.exists():
    print(f"measure-bootstrap-tokens: root not found: {root}", file=sys.stderr)
    sys.exit(2)


def estimate_tokens(byte_count: int) -> int:
    return math.ceil(byte_count / 4)


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return str(path)


def read_bytes(path: Path) -> int:
    try:
        return len(path.read_bytes())
    except OSError:
        return 0


def memory_slug(workspace: Path) -> str:
    return "-" + re.sub(r"[^A-Za-z0-9_-]+", "-", str(workspace).strip("/"))


def frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---", 4)
    return text[4:end] if end != -1 else ""


def frontmatter_description_bytes(skill_file: Path) -> int:
    try:
        text = skill_file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0
    fm = frontmatter(text)
    if not fm:
        return 0
    match = re.search(r"(?ms)^description:\s*(.*?)(?:\n[a-zA-Z_][\w-]*:|\Z)", fm + "\n")
    if not match:
        return 0
    return len(match.group(1).rstrip().encode("utf-8"))


def add_row(rows: list[dict], source: str, scope: str, confidence: str, byte_count: int, paths: list[str], note: str = "") -> None:
    rows.append({
        "source": source,
        "scope": scope,
        "confidence": confidence,
        "bytes": byte_count,
        "estimated_tokens": estimate_tokens(byte_count),
        "paths": paths,
        "note": note,
    })


rows: list[dict] = []

rules_dir = root / ".claude" / "rules"
rule_files = sorted(p for p in rules_dir.glob("*.md") if p.is_file()) if rules_dir.exists() else []
add_row(
    rows,
    ".claude/rules/*.md",
    "shared_polaris",
    "bytes_estimated",
    sum(read_bytes(p) for p in rule_files),
    [rel(p) for p in rule_files],
    "Root auto-load rule surface.",
)

skills_dir = root / ".claude" / "skills"
skill_files = sorted(skills_dir.glob("*/SKILL.md")) if skills_dir.exists() else []
add_row(
    rows,
    ".claude/skills/*/SKILL.md frontmatter descriptions",
    "shared_polaris",
    "bytes_estimated",
    sum(frontmatter_description_bytes(p) for p in skill_files),
    [rel(p) for p in skill_files],
    "Description bytes only; full skill bodies are loaded on demand.",
)

runtime_targets = [root / "CLAUDE.md", root / "AGENTS.md", root / ".codex" / "AGENTS.md"]
existing_runtime_targets = [p for p in runtime_targets if p.is_file()]
add_row(
    rows,
    "compiled runtime targets",
    "shared_polaris",
    "bytes_estimated",
    sum(read_bytes(p) for p in existing_runtime_targets),
    [rel(p) for p in existing_runtime_targets],
    "Generated runtime entry files for supported agents.",
)

memory_index = Path(memory_index_arg).expanduser() if memory_index_arg else Path.home() / ".claude" / "projects" / memory_slug(root) / "memory" / "MEMORY.md"
memory_paths = [memory_index] if memory_index.is_file() else []
add_row(
    rows,
    "MEMORY.md index",
    "shared_polaris",
    "bytes_estimated",
    sum(read_bytes(p) for p in memory_paths),
    [str(p) for p in memory_paths],
    "Hot memory index only; Warm folders are pulled on demand.",
)

local_overlays = [root / "workspace-config.yaml"]
existing_overlays = [p for p in local_overlays if p.is_file()]
add_row(
    rows,
    "local overlays",
    "shared_polaris",
    "bytes_estimated",
    sum(read_bytes(p) for p in existing_overlays),
    [rel(p) for p in existing_overlays],
    "Local workspace overlays when present.",
)

if transcript_arg:
    transcript = Path(transcript_arg).expanduser()
    if not transcript.is_file():
        print(f"measure-bootstrap-tokens: transcript not found: {transcript}", file=sys.stderr)
        sys.exit(2)
    add_row(
        rows,
        "observed transcript sample",
        "adapter_specific",
        "manual_observed",
        read_bytes(transcript),
        [str(transcript)],
        "Supporting evidence only; not part of the shared blocking gate.",
    )

shared_total = sum(row["estimated_tokens"] for row in rows if row["scope"] == "shared_polaris")
adapter_total = sum(row["estimated_tokens"] for row in rows if row["scope"] == "adapter_specific")
result = {
    "root": str(root),
    "estimator": "ceil(bytes / 4)",
    "shared_polaris_estimated_tokens": shared_total,
    "adapter_specific_estimated_tokens": adapter_total,
    "rows": rows,
}

if output_format == "json":
    print(json.dumps(result, indent=2, ensure_ascii=False))
elif output_format == "markdown":
    print("---")
    print('title: "DP-102 Bootstrap Token Baseline"')
    print('description: "Local bootstrap token budget measurement for Polaris-controlled context."')
    print("---")
    print()
    print("# Bootstrap Token Budget")
    print()
    print(f"- Root: `{root}`")
    print("- Estimator: `ceil(bytes / 4)`")
    print(f"- Shared Polaris estimated tokens: `{shared_total}`")
    print(f"- Adapter-specific estimated tokens: `{adapter_total}`")
    print()
    print("| Source | Scope | Confidence | Bytes | Estimated tokens | Paths | Note |")
    print("|--------|-------|------------|-------|------------------|-------|------|")
    for row in rows:
        paths = "<br>".join(f"`{p}`" for p in row["paths"]) if row["paths"] else "-"
        print(
            f"| {row['source']} | {row['scope']} | {row['confidence']} | "
            f"{row['bytes']} | {row['estimated_tokens']} | {paths} | {row['note']} |"
        )
else:
    print("Bootstrap Token Budget")
    print(f"root={root}")
    print("estimator=ceil(bytes / 4)")
    print(f"shared_polaris_estimated_tokens={shared_total}")
    print(f"adapter_specific_estimated_tokens={adapter_total}")
    print()
    print("source\tscope\tconfidence\tbytes\testimated_tokens\tpaths")
    for row in rows:
        paths = ",".join(row["paths"]) if row["paths"] else "-"
        print(
            f"{row['source']}\t{row['scope']}\t{row['confidence']}\t"
            f"{row['bytes']}\t{row['estimated_tokens']}\t{paths}"
        )
PY
