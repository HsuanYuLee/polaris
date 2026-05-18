#!/usr/bin/env bash
set -euo pipefail

FORMAT="text"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) FORMAT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/rule-retention-scan.sh [--format json|text]" >&2
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

[[ "$FORMAT" == "json" || "$FORMAT" == "text" ]] || { echo "--format must be json or text" >&2; exit 64; }

python3 - "$FORMAT" <<'PY'
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

fmt = sys.argv[1]
rules = sorted(Path(".claude/rules").glob("*.md"))
items = []
for path in rules:
    text = path.read_text(errors="ignore")
    trigger_count = 0
    for match in re.finditer(r"trigger_count:\s*(\d+)", text):
        trigger_count += int(match.group(1))
    try:
        last_git = subprocess.check_output(
            ["git", "log", "-1", "--format=%cs", "--", str(path)],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        last_git = ""
    if trigger_count > 0:
        action = "keep"
    elif last_git:
        action = "review_for_removal"
    else:
        action = "consolidate"
    items.append({
        "rule": str(path),
        "trigger_count": trigger_count,
        "last_git_mention": last_git or None,
        "recommended_action": action,
    })

try:
    report_raw = subprocess.check_output(
        ["bash", "scripts/lint-reference-line-count.sh", "--report"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    phased_oversized_references = json.loads(report_raw)
except (subprocess.CalledProcessError, json.JSONDecodeError):
    phased_oversized_references = []

payload = {
    "schema_version": 1,
    "scanner": "rule-retention",
    "items": items,
    "phased_oversized_references": phased_oversized_references,
}
if fmt == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    for item in items:
        print(f"{item['recommended_action']}\t{item['trigger_count']}\t{item['rule']}")
    print("phased-oversized")
    for item in phased_oversized_references:
        print(
            f"{item['path']}\t{item['current_lines']}\t"
            f"target={item['target_limit']}\texceed_by={item['exceed_by']}"
        )
PY
