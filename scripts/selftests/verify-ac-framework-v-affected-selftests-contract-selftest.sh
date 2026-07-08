#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REF="$ROOT/.claude/skills/references/verify-ac-execution-flow.md"

python3 - "$REF" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

required = {
    "direct AC verification": r"declared direct AC verification",
    "affected runner": r"scripts/selftest-affected-runner\.sh",
    "affected runner run mode": r"--run",
    "full corpus sentinel": r"POLARIS_AFFECTED_FULL_CORPUS",
    "conditional full corpus": r"full corpus escalation",
    "aggregate selftest escalation": r"scripts/run-aggregate-selftests\.sh",
    "release tail backstop": r"release tail / framework PR gate 的 full corpus backstop",
    "no second mapping": r"不新增第二套\s*\n?script↔selftest 綁定表",
}

for label, pattern in required.items():
    if not re.search(pattern, text):
        fail(f"missing contract wording: {label}")

forbidden = [
    r"Framework DP 的 V 單 / umbrella regression 在 implementation tasks 完成後，必須把完整\s*`run-aggregate-selftests\.sh`\s*納入 source-level 整合態驗證",
    r"每張 V 單的預設成本[^。\n]*`run-aggregate-selftests\.sh`",
]

for pattern in forbidden:
    if re.search(pattern, text):
        fail("unconditional full corpus wording remains")

print("PASS: verify-AC framework V affected selftests contract")
PY
