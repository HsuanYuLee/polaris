"""Structured validator authority extracted from scripts/validate-framework-script-structure.sh."""

from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
path = Path(sys.argv[2]).resolve()
try:
    print(path.relative_to(root))
except ValueError:
    print(path.name)
