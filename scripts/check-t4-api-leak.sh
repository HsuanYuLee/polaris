#!/usr/bin/env bash
# Guard DP-194-T4 docs from naming future T1 APIs before they exist.

set -euo pipefail

base="${POLARIS_T4_BASE:-}"
if [[ -z "$base" ]]; then
  base="$(git merge-base HEAD origin/task/DP-194-T0-tool-contract-schema 2>/dev/null || true)"
fi
if [[ -z "$base" ]]; then
  base="$(git merge-base HEAD main 2>/dev/null || true)"
fi
if [[ -z "$base" ]]; then
  echo "[FAIL] could not resolve DP-194-T4 diff base" >&2
  exit 1
fi

files=(
  ".claude/skills/refinement/SKILL.md"
  ".claude/skills/breakdown/SKILL.md"
  ".claude/skills/engineering/SKILL.md"
  ".claude/skills/references/breakdown-task-packaging.md"
  ".claude/skills/references/engineer-delivery-flow-index-context.md"
)

tmp="$(mktemp -t polaris-t4-api-leak-XXXXXX.diff)"
trap 'rm -f "$tmp"' EXIT

git diff --unified=0 "$base"...HEAD -- "${files[@]}" > "$tmp"

python3 - "$tmp" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
pattern = re.compile(r"\bpolaris_[a-z_]+\b")
violations = []

for line in path.read_text(encoding="utf-8").splitlines():
    if not line.startswith("+") or line.startswith("+++"):
        continue
    if "Available after DP-194-T1" in line:
        continue
    if pattern.search(line):
        violations.append(line[1:])

if violations:
    print("[FAIL] DP-194-T4 introduced future T1 API names without the deferral phrase:", file=sys.stderr)
    for violation in violations:
        print(f"- {violation}", file=sys.stderr)
    raise SystemExit(1)

print("[PASS] DP-194-T4 API leak guard")
PY
