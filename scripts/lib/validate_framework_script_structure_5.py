"""Structured validator authority extracted from scripts/validate-framework-script-structure.sh."""

import json
from pathlib import Path
import sys

violations_file = Path(sys.argv[1])
root = sys.argv[2]
items = []
if violations_file.exists():
    for raw in violations_file.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        path, _, reason = raw.partition("\t")
        items.append({"path": path, "reason": reason})
print(
    json.dumps(
        {
            "schema_version": 1,
            "mode": "audit",
            "root": root,
            "violation_count": len(items),
            "violations": items,
        },
        ensure_ascii=False,
        indent=2,
    )
)
