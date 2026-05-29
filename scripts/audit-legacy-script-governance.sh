#!/usr/bin/env bash
# audit-legacy-script-governance.sh — DP-240 T7 (AC7) legacy script governance debt
# aggregator. Combines `validate-script-header-comment.sh --mode audit`,
# `script-ownership-audit.py`, and `scripts/manifest.json` lifecycle metadata to
# produce a single Markdown debt artifact. Used as seed input for future
# backfill DPs; non-blocking (always exits 0 on success).
#
# Purpose: enumerate legacy script governance debt across the framework
# workspace so subsequent backfill / sunset / relocation work can be planned
# against a deterministic snapshot.
#
# Required signals (per task.md DP-240-T7):
#   - root_script_count            : count of scripts/*.{sh,py,mjs}
#   - header_debt_count            : root scripts missing header comment
#   - skill_local_candidates       : root scripts only consumed by a single
#                                    skill (move-to-skill-local candidates)
#   - sunset_orphans               : manifest lifecycle ∈ {sunset_candidate,
#                                    sunset_ready} but still referenced
#   - ownership_candidate_summary  : breakdown by classification
#
# Modes:
#   --emit <path>   Write the Markdown debt artifact to <path>. Parent dir
#                   must exist. Stdout prints a brief summary.
#
# Exit:
#   0 — artifact emitted successfully
#   2 — usage error or upstream tool failure
#
# Examples:
#   bash scripts/audit-legacy-script-governance.sh \
#       --emit docs-manager/.../artifacts/legacy-script-governance-debt-audit.md

set -euo pipefail

EMIT_PATH=""
ROOT_DIR=""

usage() {
  cat >&2 <<'EOF'
usage: audit-legacy-script-governance.sh --emit <path> [--root <dir>]

Options:
  --emit <path>   Write Markdown debt artifact to <path>.
  --root <dir>    Repository root (default: git toplevel from script location).
  -h, --help      Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --emit)
      EMIT_PATH="${2:-}"
      shift 2
      ;;
    --root)
      ROOT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$EMIT_PATH" ]]; then
  printf 'error: --emit <path> is required\n' >&2
  usage
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$ROOT_DIR" ]]; then
  ROOT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null | head -1)"
  if [[ -z "$ROOT_DIR" ]]; then
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  fi
fi

EMIT_DIR="$(dirname "$EMIT_PATH")"
if [[ ! -d "$EMIT_DIR" ]]; then
  printf 'error: parent dir does not exist: %s\n' "$EMIT_DIR" >&2
  exit 2
fi

HEADER_AUDIT_SCRIPT="$ROOT_DIR/scripts/validate-script-header-comment.sh"
OWNERSHIP_AUDIT_SCRIPT="$ROOT_DIR/scripts/script-ownership-audit.py"
MANIFEST_PATH="$ROOT_DIR/scripts/manifest.json"

for required in "$HEADER_AUDIT_SCRIPT" "$OWNERSHIP_AUDIT_SCRIPT" "$MANIFEST_PATH"; do
  if [[ ! -f "$required" ]]; then
    printf 'error: required input not found: %s\n' "$required" >&2
    exit 2
  fi
done

# 1. Run header audit (always exit 0, prints AUDIT: + legacy-debt: lines).
HEADER_AUDIT_OUTPUT="$(bash "$HEADER_AUDIT_SCRIPT" --mode audit --root "$ROOT_DIR" 2>&1)" || {
  printf 'error: header audit failed:\n%s\n' "$HEADER_AUDIT_OUTPUT" >&2
  exit 2
}

# 2. Run ownership audit in JSON mode.
OWNERSHIP_JSON="$(python3 "$OWNERSHIP_AUDIT_SCRIPT" --root "$ROOT_DIR" --format json 2>&1)" || {
  printf 'error: ownership audit failed:\n%s\n' "$OWNERSHIP_JSON" >&2
  exit 2
}

# 3. Compose the Markdown artifact via embedded Python (single-pass JSON parsing
#    keeps the shell glue minimal). Bash 3.2 has a heredoc-inside-$() bug, so
#    we materialize the Python to a tempfile and invoke it normally.
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PY_TMP="$(mktemp -t polaris-audit-legacy-script-governance.XXXXXX.py)"
trap 'rm -f "$PY_TMP"' EXIT INT TERM

cat > "$PY_TMP" <<'PY'
import json
import os
import re
from pathlib import Path

header_audit = os.environ["HEADER_AUDIT"]
ownership = json.loads(os.environ["OWNERSHIP_JSON"])
manifest_path = Path(os.environ["MANIFEST_PATH"])
timestamp = os.environ["TIMESTAMP"]
root_dir = os.environ["ROOT_DIR"]

# Parse header-audit output: lines like "AUDIT: ... scanned N script(s); M missing header"
# and "  legacy-debt: <path>"
scanned_match = re.search(r"scanned\s+(\d+)\s+script\(s\);\s+(\d+)\s+missing header", header_audit)
header_scanned = int(scanned_match.group(1)) if scanned_match else 0
header_missing = int(scanned_match.group(2)) if scanned_match else 0
header_debt_paths = []
for line in header_audit.splitlines():
    m = re.match(r"\s*legacy-debt:\s*(.+)$", line)
    if m:
        header_debt_paths.append(m.group(1).strip())

# Filter header debt to root scripts/* only (script-ownership-audit.py also
# scopes root scripts; report both totals separately for clarity).
root_header_debt = [p for p in header_debt_paths if p.startswith("scripts/")]

# Ownership audit summary
summary = ownership.get("summary", {})
scripts_rows = ownership.get("scripts", [])
classification_counts = {}
for row in scripts_rows:
    cls = row.get("classification", "unknown")
    classification_counts[cls] = classification_counts.get(cls, 0) + 1

skill_local_candidates = [row for row in scripts_rows if row.get("classification") == "skill_local"]
sunset_orphans_classified = [row for row in scripts_rows if row.get("classification") == "sunset_orphan"]

# Manifest sunset lifecycle scan (independent of consumer graph): rows marked
# sunset_candidate / sunset_ready that still appear referenced from any text
# file. We re-use the ownership audit's consumer mapping.
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
script_to_row = {r.get("path"): r for r in manifest.get("scripts", []) if isinstance(r, dict)}

sunset_orphans = []  # manifest lifecycle says sunset but still consumed
sunset_unreferenced = []  # manifest lifecycle says sunset and zero consumers
for row in scripts_rows:
    mrow = script_to_row.get(row["path"], {})
    lifecycle = mrow.get("lifecycle", "")
    if lifecycle in {"sunset_candidate", "sunset_ready"}:
        if row.get("consumer_count", 0) > 0:
            sunset_orphans.append({
                "path": row["path"],
                "lifecycle": lifecycle,
                "consumer_count": row["consumer_count"],
            })
        else:
            sunset_unreferenced.append({
                "path": row["path"],
                "lifecycle": lifecycle,
            })

# Render Markdown
lines = []
lines.append("---")
lines.append("title: \"DP-240 T7: Legacy Script Governance Debt Audit\"")
lines.append("description: \"Snapshot of header / ownership / sunset debt under scripts/.\"")
lines.append(f"generated_at: \"{timestamp}\"")
lines.append("sidebar:")
lines.append("  hidden: true")
lines.append("---")
lines.append("")
lines.append("# Legacy Script Governance Debt Audit (DP-240 T7)")
lines.append("")
lines.append("> Generated by `scripts/audit-legacy-script-governance.sh`. Non-blocking;")
lines.append("> consumed as seed input for follow-up backfill / sunset / relocation DPs.")
lines.append("")
lines.append("## Summary")
lines.append("")
lines.append("| Signal | Count |")
lines.append("|--------|------:|")
lines.append(f"| root scripts (`scripts/*.{{sh,py,mjs}}`) | {summary.get('root_scripts', len(scripts_rows))} |")
lines.append(f"| header debt count (root scripts missing header) | {len(root_header_debt)} |")
lines.append(f"| header audit scanned (all hot-path scripts) | {header_scanned} |")
lines.append(f"| header audit total missing (all scopes) | {header_missing} |")
lines.append(f"| skill_local candidates | {summary.get('skill_local_scripts', len(skill_local_candidates))} |")
lines.append(f"| sunset orphans (manifest sunset + still referenced) | {len(sunset_orphans)} |")
lines.append(f"| sunset ready-to-delete (manifest sunset + zero consumers) | {len(sunset_unreferenced)} |")
lines.append(f"| shim candidates | {summary.get('shim_candidates', 0)} |")
lines.append(f"| root contracts | {summary.get('root_contracts', 0)} |")
lines.append("")
lines.append("## Ownership Classification Breakdown")
lines.append("")
lines.append("| Classification | Count |")
lines.append("|----------------|------:|")
for cls in sorted(classification_counts):
    lines.append(f"| {cls} | {classification_counts[cls]} |")
lines.append("")

lines.append("## Header Debt — Root Scripts Missing Header")
lines.append("")
if root_header_debt:
    lines.append("Root scripts under `scripts/` lacking a non-shebang header comment within the first 20 lines:")
    lines.append("")
    for p in sorted(root_header_debt):
        lines.append(f"- `{p}`")
else:
    lines.append("_None — all root scripts carry a header comment._")
lines.append("")

lines.append("## Skill-Local Candidates")
lines.append("")
lines.append("Root scripts consumed by exactly one skill (move-to-skill-local candidates):")
lines.append("")
if skill_local_candidates:
    lines.append("| Script | Owner Skill | Consumers |")
    lines.append("|--------|-------------|----------:|")
    for row in sorted(skill_local_candidates, key=lambda r: r["path"]):
        lines.append(
            f"| `{row['path']}` | {row.get('owner_skill') or '-'} | {row.get('consumer_count', 0)} |"
        )
else:
    lines.append("_None._")
lines.append("")

lines.append("## Sunset Orphans (Manifest lifecycle = sunset_candidate / sunset_ready + still referenced)")
lines.append("")
if sunset_orphans:
    lines.append("| Script | Lifecycle | Consumers |")
    lines.append("|--------|-----------|----------:|")
    for row in sorted(sunset_orphans, key=lambda r: r["path"]):
        lines.append(f"| `{row['path']}` | {row['lifecycle']} | {row['consumer_count']} |")
else:
    lines.append("_None — no manifest-sunset scripts are still referenced._")
lines.append("")

lines.append("## Sunset Ready-to-Delete (Manifest sunset + zero consumers)")
lines.append("")
if sunset_unreferenced:
    lines.append("| Script | Lifecycle |")
    lines.append("|--------|-----------|")
    for row in sorted(sunset_unreferenced, key=lambda r: r["path"]):
        lines.append(f"| `{row['path']}` | {row['lifecycle']} |")
else:
    lines.append("_None._")
lines.append("")

lines.append("## Classification-Detected Sunset Orphans (zero consumers, no manual flag)")
lines.append("")
if sunset_orphans_classified:
    lines.append("Root scripts classified as `sunset_orphan` by `script-ownership-audit.py` (zero consumers, owner_surface not manual/internal):")
    lines.append("")
    for row in sorted(sunset_orphans_classified, key=lambda r: r["path"]):
        lines.append(f"- `{row['path']}`")
else:
    lines.append("_None._")
lines.append("")

lines.append("## Inputs")
lines.append("")
lines.append("- `scripts/validate-script-header-comment.sh --mode audit`")
lines.append("- `scripts/script-ownership-audit.py --format json`")
lines.append("- `scripts/manifest.json` (lifecycle field)")
lines.append("")
lines.append(f"_Snapshot taken {timestamp}._")

print("\n".join(lines))
PY

REPORT="$(
HEADER_AUDIT="$HEADER_AUDIT_OUTPUT" \
OWNERSHIP_JSON="$OWNERSHIP_JSON" \
MANIFEST_PATH="$MANIFEST_PATH" \
TIMESTAMP="$TIMESTAMP" \
ROOT_DIR="$ROOT_DIR" \
python3 "$PY_TMP"
)"

printf '%s\n' "$REPORT" > "$EMIT_PATH"

# Brief stdout summary
ROOT_COUNT=$(printf '%s' "$REPORT" | grep -E '^\| root scripts' | sed -E 's/.*\| ([0-9]+) \|/\1/' | head -1)
HEADER_DEBT=$(printf '%s' "$REPORT" | grep -E '^\| header debt count' | sed -E 's/.*\| ([0-9]+) \|/\1/' | head -1)
SKILL_LOCAL=$(printf '%s' "$REPORT" | grep -E '^\| skill_local candidates' | sed -E 's/.*\| ([0-9]+) \|/\1/' | head -1)
SUNSET_ORPHANS=$(printf '%s' "$REPORT" | grep -E '^\| sunset orphans' | sed -E 's/.*\| ([0-9]+) \|/\1/' | head -1)

printf 'AUDIT: legacy-script-governance — emitted to %s\n' "$EMIT_PATH"
printf '  root_scripts=%s header_debt=%s skill_local_candidates=%s sunset_orphans=%s\n' \
  "$ROOT_COUNT" "$HEADER_DEBT" "$SKILL_LOCAL" "$SUNSET_ORPHANS"

exit 0
