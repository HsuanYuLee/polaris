"""Structured validator authority extracted from scripts/validate-safe-cli-introspection.sh."""

import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
begin_marker = "# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN"
end_marker = "# POLARIS_SAFE_CLI_INTROSPECTION_END"


def fail(detail: str) -> None:
    print(
        f"POLARIS_SAFE_CLI_INTROSPECTION_UNSAFE_PREFIX:{path.name}:{detail}",
        file=sys.stderr,
    )
    raise SystemExit(2)


if lines.count(begin_marker) != 1 or lines.count(end_marker) != 1:
    fail("canonical markers must each appear exactly once")
begin = lines.index(begin_marker)
end = lines.index(end_marker)
if end <= begin:
    fail("end marker must follow begin marker")
if not lines or lines[0] != "#!/usr/bin/env bash":
    fail("first line must be the canonical bash shebang")

executable_prefix = [
    line.strip()
    for line in lines[1:begin]
    if line.strip() and not line.lstrip().startswith("#")
]
if executable_prefix != ["set -euo pipefail"]:
    fail("only set -euo pipefail may execute before the canonical help block")

block = lines[begin + 1 : end]
expected_if = 'if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then'
if len(block) < 4 or block[0] != expected_if or block[-2:] != ["  exit 0", "fi"]:
    fail("help block must use the canonical condition and terminal exit 0")
printf_lines = block[1:-2]
if not printf_lines:
    fail("help block must emit at least one literal line")
literal_printf = re.compile(r"  command printf '%s\\n' '[^']*'")
for line in printf_lines:
    if not literal_printf.fullmatch(line):
        fail(f"non-literal or side-effecting help statement: {line}")
