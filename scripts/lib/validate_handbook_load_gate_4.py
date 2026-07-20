"""Structured validator authority extracted from scripts/validate-handbook-load-gate.sh."""

import json
import os
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(1)
raise SystemExit(
    0
    if data.get("repo") == os.path.realpath(sys.argv[2])
    and data.get("session_id") == sys.argv[3]
    else 1
)
