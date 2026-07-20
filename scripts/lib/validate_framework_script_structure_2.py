"""Structured validator authority extracted from scripts/validate-framework-script-structure.sh."""

from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
bad = []
for index, line in enumerate(lines):
    if not line.lstrip().startswith("# shellcheck disable="):
        continue
    window = lines[max(0, index - 2) : index + 1]
    if not any("POLARIS_SHELLCHECK_JUSTIFICATION:" in item for item in window):
        bad.append(index + 1)
if bad:
    print(",".join(str(item) for item in bad))
    raise SystemExit(1)
