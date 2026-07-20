"""Structured validator authority extracted from scripts/validate-handbook-load-gate.sh."""

import os
import sys

repo = os.path.realpath(sys.argv[1])
target = os.path.realpath(
    sys.argv[2] if os.path.isabs(sys.argv[2]) else os.path.join(repo, sys.argv[2])
)
try:
    relative = os.path.relpath(target, repo)
except ValueError:
    raise SystemExit(0)
if relative == ".." or relative.startswith("../"):
    raise SystemExit(0)
print(relative)
