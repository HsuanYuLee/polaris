#!/usr/bin/env bash
# Purpose: DP-231 T9 regression for the direct gh pr create PreToolUse guard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/scripts/pr-create-guard.sh"
TMP="$(mktemp -d -t pr-create-guard.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

payload() {
  local command="$1"
  python3 - "$command" <<'PY'
import json
import sys

print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
PY
}

# Hermetic: the spine lane keys off a delivery record in the repository the
# command runs in, so both lanes are exercised from throwaway repos rather than
# from whatever state this workspace happens to be in.
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email selftest@example.com
  git -C "$dir" config user.name selftest
  : > "$dir/seed"
  git -C "$dir" add -A
  git -C "$dir" commit -qm seed
}

make_repo "$TMP/plain"
make_repo "$TMP/spine"
mkdir -p "$TMP/spine/sources/DP-000-example/.spine"
python3 - "$TMP/spine" <<'PY'
import json, subprocess, sys
root = sys.argv[1]
head = subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"]).decode().strip()
record = f"{root}/sources/DP-000-example/.spine/delivery.json"
json.dump({"schema_version": 1, "source": "sources/DP-000-example",
           "destination": "template", "head_sha": head}, open(record, "w"))
PY

if (cd "$TMP/plain" && payload "gh pr create --base main --title 測試 --body 測試" | "$GUARD" >/dev/null 2>"$TMP/plain.err"); then
  echo "FAIL: direct gh pr create passed in a repo with no spine delivery record" >&2
  exit 1
fi

(cd "$TMP/spine" && payload "gh pr create --base main --title 測試 --body 測試" | "$GUARD" >/dev/null 2>&1) || {
  echo "FAIL: a spine delivery pinned to HEAD should be allowed to open its own PR" >&2
  exit 1
}

if (cd "$TMP/plain" && payload "gh pr create --base main --title 測試 --body 測試" | POLARIS_PR_WORKFLOW=1 "$GUARD" >/dev/null 2>"$TMP/direct.err"); then
  echo "FAIL: direct gh pr create passed with POLARIS_PR_WORKFLOW=1" >&2
  exit 1
fi
grep -Fq "BLOCKED: Direct gh pr create" "$TMP/direct.err" || {
  echo "FAIL: missing direct-create block message" >&2
  cat "$TMP/direct.err" >&2
  exit 1
}

payload "bash scripts/polaris-pr-create.sh --base main --title 測試 --body 測試" | "$GUARD" >/dev/null
payload "echo gh pr create --base main" | "$GUARD" >/dev/null

if grep -Fq "POLARIS_PR_WORKFLOW" "$GUARD"; then
  echo "FAIL: legacy POLARIS_PR_WORKFLOW bypass remains in guard" >&2
  exit 1
fi

echo "PASS: pr-create guard selftest"
