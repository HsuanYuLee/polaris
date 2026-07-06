#!/usr/bin/env bash
# Purpose: Regression selftest for write-deliverable.sh preserving an existing
#          deliverable.verification subtree while refreshing PR metadata.
# Inputs:  none; creates a temporary task.md fixture.
# Outputs: exit 0 + PASS line, or non-zero with a focused diagnostic.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRITER="${ROOT}/scripts/write-deliverable.sh"

tmp="$(mktemp -d -t write-deliverable-preserve.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

task="${tmp}/task.md"
cat >"$task" <<'MD'
---
title: "DP-999 T1 deliverable preservation fixture"
description: "Fixture task for write-deliverable preservation."
status: IN_PROGRESS
task_kind: T
deliverable:
  pr_url: https://github.com/example/repo/pull/1
  pr_state: OPEN
  head_sha: aaaaaaa
  verification:
    status: PASS
    evidence_path: /tmp/original-verify.json
    ac_counts:
      ac_total: 2
      ac_pass: 2
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
---

# T1
MD

bash "$WRITER" "$task" "https://github.com/example/repo/pull/2" OPEN bbbbbbb >/tmp/write-deliverable-preserve.out 2>&1
bash "$WRITER" --verification-aggregate-head "$task" ccccccc >/tmp/write-deliverable-aggregate-head.out 2>&1

python3 - "$task" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
fm = text.split("---", 2)[1]

required = [
    "  pr_url: https://github.com/example/repo/pull/2",
    "  pr_state: OPEN",
    "  head_sha: bbbbbbb",
    "  verification:",
    "    aggregate_head_sha: ccccccc",
    "    status: PASS",
    "    evidence_path: /tmp/original-verify.json",
    "      ac_total: 2",
    "      ac_pass: 2",
]
missing = [item for item in required if item not in fm]
if missing:
    raise SystemExit("FAIL: deliverable block missing preserved fields: " + ", ".join(missing))
if len(re.findall(r"^deliverable:", fm, flags=re.MULTILINE)) != 1:
    raise SystemExit("FAIL: deliverable block duplicated")
if len(re.findall(r"^  verification:", fm, flags=re.MULTILINE)) != 1:
    raise SystemExit("FAIL: deliverable.verification block duplicated")
if "  head_sha: ccccccc" in fm:
    raise SystemExit("FAIL: verification aggregate head leaked into top-level deliverable.head_sha")
PY

echo "[write-deliverable-preserve-verification-selftest] PASS"
