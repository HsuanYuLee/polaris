#!/usr/bin/env bash
# refinement-locked-scope-selftest.sh — DP-212 LOCKED scope guard fixtures.
#
# Cases:
#   1. Amendment touches only Technical Approach / Dependencies / tasks
#      → validator exits 0 (PASS).
#   2. Amendment changes ## Goal heading body         → exit 2 violation.
#   3. Amendment changes refinement.json acceptance_criteria → exit 2 violation.
#   4. Amendment renames ## Decisions heading         → exit 2 violation.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-refinement-locked-scope.sh"

TMP="$(mktemp -d -t refinement-locked-scope-XXXX)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "selftest@polaris.dev"
git -C "$REPO" config user.name "selftest"

CONTAINER_REL="docs-manager/src/content/docs/specs/design-plans/DP-999-locked-scope-fixture"
CONTAINER="$REPO/$CONTAINER_REL"
mkdir -p "$CONTAINER"

cat >"$CONTAINER/refinement.md" <<'MD'
---
title: "DP-999 refinement"
description: "locked scope fixture"
---

## Goal

Original goal sentence.

## Background

Background body.

## Decisions

- D1: original decision

## Scope

- thing A

## Acceptance Criteria

- AC1: original

## Technical Approach

- Original approach.

## Dependencies

- DP-X
MD

cat >"$CONTAINER/refinement.json" <<'JSON'
{
  "version": "1",
  "goal": "original goal",
  "background": "original background",
  "decisions": ["D1"],
  "scope": ["thing A"],
  "acceptance_criteria": [{"id": "AC1", "text": "original"}],
  "technical_approach": "original approach"
}
JSON

git -C "$REPO" add .
git -C "$REPO" commit -q -m "initial LOCKED snapshot"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

# === Case 1: legitimate amendment (Technical Approach + Dependencies) ===
cat >"$CONTAINER/refinement.md" <<'MD'
---
title: "DP-999 refinement"
description: "locked scope fixture"
---

## Goal

Original goal sentence.

## Background

Background body.

## Decisions

- D1: original decision

## Scope

- thing A

## Acceptance Criteria

- AC1: original

## Technical Approach

- Original approach.
- Added implementation detail discovered by dogfood.

## Dependencies

- DP-X
- DP-Y (new)
MD

# Update json only in non-locked field
python3 - "$CONTAINER/refinement.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["technical_approach"] = "updated approach"
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

git -C "$REPO" add .
git -C "$REPO" commit -q -m "amendment: technical approach refinement"

if ! "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/case1.out" 2>&1; then
  echo "FAIL: case 1 (legitimate amendment) was incorrectly rejected" >&2
  cat "$TMP/case1.out" >&2
  exit 1
fi

# === Case 2: violation — change Goal body ===
git -C "$REPO" reset --hard "$BASE_SHA" -q

python3 - "$CONTAINER/refinement.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
text = text.replace("Original goal sentence.", "Rewritten goal sentence (violation).")
p.write_text(text, encoding="utf-8")
PY

git -C "$REPO" add .
git -C "$REPO" commit -q -m "amendment: change Goal body (violation)"

if "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/case2.out" 2>&1; then
  echo "FAIL: case 2 (Goal body violation) was incorrectly accepted" >&2
  cat "$TMP/case2.out" >&2
  exit 1
fi
if ! grep -q "POLARIS_LOCKED_SCOPE_VIOLATION" "$TMP/case2.out"; then
  echo "FAIL: case 2 missing POLARIS_LOCKED_SCOPE_VIOLATION stderr signal" >&2
  cat "$TMP/case2.out" >&2
  exit 1
fi

# === Case 3: violation — change acceptance_criteria in json ===
git -C "$REPO" reset --hard "$BASE_SHA" -q

python3 - "$CONTAINER/refinement.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["acceptance_criteria"] = [{"id": "AC1", "text": "rewritten AC (violation)"}]
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

git -C "$REPO" add .
git -C "$REPO" commit -q -m "amendment: change AC in json (violation)"

if "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/case3.out" 2>&1; then
  echo "FAIL: case 3 (AC json violation) was incorrectly accepted" >&2
  cat "$TMP/case3.out" >&2
  exit 1
fi
if ! grep -q "POLARIS_LOCKED_SCOPE_VIOLATION" "$TMP/case3.out"; then
  echo "FAIL: case 3 missing POLARIS_LOCKED_SCOPE_VIOLATION stderr signal" >&2
  exit 1
fi

# === Case 4: violation — rename ## Decisions heading ===
git -C "$REPO" reset --hard "$BASE_SHA" -q

python3 - "$CONTAINER/refinement.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
text = text.replace("## Decisions", "## Architectural decisions")
p.write_text(text, encoding="utf-8")
PY

git -C "$REPO" add .
git -C "$REPO" commit -q -m "amendment: rename Decisions heading (violation)"

if "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/case4.out" 2>&1; then
  echo "FAIL: case 4 (Decisions heading rename) was incorrectly accepted" >&2
  cat "$TMP/case4.out" >&2
  exit 1
fi
if ! grep -q "POLARIS_LOCKED_SCOPE_VIOLATION" "$TMP/case4.out"; then
  echo "FAIL: case 4 missing POLARIS_LOCKED_SCOPE_VIOLATION stderr signal" >&2
  exit 1
fi

echo "PASS: DP-212 refinement LOCKED scope guard selftest (4/4 cases)"
