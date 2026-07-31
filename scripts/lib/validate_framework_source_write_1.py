"""Structured validator authority extracted from scripts/validate-framework-source-write.sh.

Wiring self-check: framework source write authority must stay reachable from every
runtime through the same script. The per-write PreToolUse / Codex hook adapters were
retired with the B-bucket bookkeeping mesh; what remains is one runtime-neutral
execution surface (PR gate W17) plus the Codex bash wrapper. Both call
validate-framework-source-write.sh directly, so there is no runtime-specific
allow/deny path left to keep in parity.
"""

from pathlib import Path
import sys

repo = Path(sys.argv[1])
required = {
    "scripts/codex-guarded-bash.sh": "validate-framework-source-write.sh",
    "scripts/check-framework-pr-gate.sh": "W17 framework source write authority",
}
missing = []
for rel, needle in required.items():
    path = repo / rel
    if not path.is_file():
        missing.append(f"{rel}: missing")
        continue
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        missing.append(f"{rel}: missing {needle}")
if missing:
    print("POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:self-check-wiring", file=sys.stderr)
    for item in missing:
        print(f"  - {item}", file=sys.stderr)
    sys.exit(2)
print(
    "PASS: framework source write wiring delegates to validate-framework-source-write.sh"
)
