"""Structured validator authority extracted from scripts/validate-framework-script-structure.sh."""

import json
import os
import sys

payload = json.loads(sys.argv[1])
matches = [
    path
    for path in payload.get("narrative_paths", [])
    if path.endswith("/script-governance.md")
]
if len(matches) != 1:
    raise SystemExit("resolver payload must contain exactly one script-governance.md")
print(os.path.realpath(matches[0]))
