#!/usr/bin/env bash
set -euo pipefail

FORMAT="text"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) FORMAT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/memory-retention-scan.sh [--format json|text]" >&2
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
import sys
from datetime import date
from pathlib import Path

fmt = sys.argv[1]
roots = [Path(".claude/memory"), Path(".agents/memory"), Path.home() / ".claude" / "memory"]
today = date.today().isoformat()

def frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end == -1:
        return {}
    out = {}
    for line in text[4:end].splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        out[key.strip()] = value.strip().strip('"')
    return out

items = []
for root in roots:
    if not root.exists():
        continue
    for path in sorted(root.rglob("*.md")):
        if path.name == "MEMORY.md":
            continue
        text = path.read_text(errors="ignore")
        meta = frontmatter(text)
        mtype = meta.get("type", "unknown")
        absorbed = meta.get("absorbed_into", "")
        expires = meta.get("expires_at", "")
        if absorbed:
            action = "prune"
        elif expires and expires < today:
            action = "review_for_removal"
        elif mtype == "project" and re.search(r"\bDone\b|已完成|IMPLEMENTED", text):
            action = "archive"
        else:
            action = "keep"
        items.append({
            "memory": str(path),
            "type": mtype,
            "absorbed_into": absorbed or None,
            "expires_at": expires or None,
            "recommended_action": action,
        })

payload = {"schema_version": 1, "scanner": "memory-retention", "items": items}
if fmt == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    for item in items:
        print(f"{item['recommended_action']}\t{item['type']}\t{item['memory']}")
PY
