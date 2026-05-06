#!/usr/bin/env bash
# Selftest for inspect-pr-section.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inspector="$script_dir/inspect-pr-section.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_dir="$tmp/runs/test-run"
mkdir -p "$run_dir"
diff="$run_dir/pr-42.diff"
{
  echo "diff --git a/a.txt b/a.txt"
  echo "@@ -1,3 +1,3 @@"
  for i in $(seq 1 150); do
    echo "+line $i"
  done
} > "$diff"

range_out="$tmp/range.out"
"$inspector" --runs-dir "$tmp/runs" --run-id test-run --pr 42 --start 1 --end 150 --max-lines 25 > "$range_out"
lines=$(wc -l < "$range_out" | tr -d ' ')
if [[ "$lines" -ne 25 ]]; then
  echo "expected bounded 25 lines, got $lines" >&2
  exit 1
fi

hunks_out="$tmp/hunks.out"
"$inspector" --runs-dir "$tmp/runs" --run-id test-run --pr 42 --hunks > "$hunks_out"
rg -q '^diff --git' "$hunks_out"
rg -q '^@@ ' "$hunks_out"

if "$inspector" --runs-dir "$tmp/runs" --run-id test-run --pr 99 --hunks >/dev/null 2>&1; then
  echo "missing artifact should fail" >&2
  exit 1
fi

echo "inspect-pr-section selftest: PASS"
