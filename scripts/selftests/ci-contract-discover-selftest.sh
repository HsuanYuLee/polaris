#!/usr/bin/env bash
# DP-233-T1: ci-contract-discover husky multiline hook selftest.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/ci-contract-discover.sh"
TMPDIR_SELFTEST="$(mktemp -d -t ci-contract-discover.XXXXXX)"
trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

repo="$TMPDIR_SELFTEST/repo"
mkdir -p "$repo/.husky"
cat > "$repo/.husky/pre-commit" <<'SHELL'
#!/bin/sh
. "$(dirname -- "$0")/_/husky.sh"

TESTS_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.tests\.ts$' || true)
if [ -n "$TESTS_FILES" ]; then
  echo "ERROR: .tests.ts is no longer allowed"
  exit 1
fi

pnpm exec lint-staged
SHELL
chmod +x "$repo/.husky/pre-commit"

out="$TMPDIR_SELFTEST/contract.json"
bash "$SCRIPT" --repo "$repo" > "$out"

python3 - "$out" <<'PY'
import json
import sys
from pathlib import Path

contract = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
hooks = [
    hook
    for hook in contract.get("dev_hooks", [])
    if hook.get("source_file") == ".husky/pre-commit"
]

if len(hooks) != 1:
    raise SystemExit(f"expected exactly one pre-commit hook body, got {len(hooks)}")

command = hooks[0].get("command") or ""
required = [
    'TESTS_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E \'\\.tests\\.ts$\' || true)',
    'if [ -n "$TESTS_FILES" ]; then',
    'echo "ERROR: .tests.ts is no longer allowed"',
    'exit 1',
    'fi',
    'pnpm exec lint-staged',
]
for needle in required:
    if needle not in command:
        raise SystemExit(f"missing expected command body fragment: {needle}")

for token in ("fi", "then", "else"):
    if any((hook.get("command") or "").strip() == token for hook in hooks):
        raise SystemExit(f"bare shell control token emitted as command: {token}")

print("PASS: ci-contract-discover husky multiline hook selftest")
PY
