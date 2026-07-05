#!/usr/bin/env bash
# Purpose: Verify render-refinement-md.sh emits Bug-specific section only for bug sources.
# Inputs:  Repository checkout with refinement fixture library.
# Outputs: PASS line on success; exits non-zero on render drift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/selftests/refinement-dp229-fixture-lib.sh"

tmp="$(mktemp -d -t refinement-render-bug.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

make_refinement_fixture "$tmp/bug"
python3 - "$tmp/bug/refinement.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["source"]["type"] = "bug"
data["source"]["id"] = "BUG-123"
data["source"]["jira_key"] = "BUG-123"
data["reproduction_steps"] = ["open source", "run refinement"]
data["root_cause"] = "Bug source fields were not rendered."
data["source_pr"] = "N/A - fixture"
data["severity"] = "medium"
data["impact_scope"] = "derived refinement view"
data["regression"] = "unknown"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

bash "$ROOT/scripts/render-refinement-md.sh" "$tmp/bug/refinement.json"
grep -Fq "## Bug-specific Fields" "$tmp/bug/refinement.md"
grep -Fq "**Reproduction steps**: open source; run refinement" "$tmp/bug/refinement.md"
grep -Fq "**Root cause**: Bug source fields were not rendered." "$tmp/bug/refinement.md"
bash "$ROOT/scripts/render-refinement-md.sh" "$tmp/bug/refinement.json" --check

make_refinement_fixture "$tmp/nonbug"
bash "$ROOT/scripts/render-refinement-md.sh" "$tmp/nonbug/refinement.json"
if grep -Fq "## Bug-specific Fields" "$tmp/nonbug/refinement.md"; then
  echo "FAIL: non-bug refinement rendered Bug-specific section" >&2
  exit 1
fi

echo "PASS: render refinement md selftest"
