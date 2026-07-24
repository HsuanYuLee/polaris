#!/usr/bin/env bash
# refinement-locked-scope-selftest.sh — LOCKED scope guard fixtures, updated
# for DP-298 JSON-only authority and DP-444 explicit current/candidate files.
#
# DP-298 T2 removed the `refinement.md` `## Scope` / heading-diff business-read
# branch. `refinement.json` is the single authoritative source for LOCKED scope.
# The derived `refinement.md` body is no longer read to make a LOCKED-scope
# decision, so amending non-LOCKED JSON fields (e.g. `tasks[].title`) — even
# alongside a derived `## Scope` change in refinement.md — must PASS.
#
# Cases:
#   1. (AC-NF1) Amendment touches only a non-LOCKED JSON field
#      (`technical_approach`)                                  → exit 0 (PASS).
#   2. (AC1) Amendment changes non-LOCKED `tasks[].title` AND the derived
#      `refinement.md` `## Scope` body                          → exit 0 (PASS);
#      no longer mis-flagged by a removed derived-md branch.
#   3. (AC2) Amendment changes refinement.json `acceptance_criteria`
#                                                               → exit 2 violation.
#   4. (AC-NF1) Each JSON LOCKED field
#      (goal/background/decisions/scope/acceptance_criteria)    → exit 2 violation;
#      existing JSON-authority behavior unchanged.
#   5. (AC-NEG1) The guard source contains no executing `refinement.md`
#      body-read path (refinement.md references only appear in comments).
#   6. (DP-444) Explicit current/candidate authority accepts implementation
#      detail and rejects a protected-field rewrite.

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
  "source": {"type": "dp", "id": "DP-999"},
  "goal": "original goal",
  "background": "original background",
  "decisions": ["D1"],
  "scope": ["thing A"],
  "acceptance_criteria": [{"id": "AC1", "text": "original"}],
  "technical_approach": "original approach",
  "tasks": [{"id": "DP-999-T1", "title": "original task title"}]
}
JSON

git -C "$REPO" add .
git -C "$REPO" commit -q -m "initial LOCKED snapshot"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

# === Case 1 (AC-NF1): legitimate amendment of a non-LOCKED JSON field ===
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
  echo "FAIL: case 1 (legitimate non-LOCKED JSON amendment) was incorrectly rejected" >&2
  cat "$TMP/case1.out" >&2
  exit 1
fi

# === Case 2 (AC1): amend non-LOCKED tasks[].title AND derived md ## Scope ===
# This is the DP-298 T2 fix: the derived refinement.md ## Scope change must NOT
# cause a violation because the guard no longer reads the md body.
git -C "$REPO" reset --hard "$BASE_SHA" -q

python3 - "$CONTAINER/refinement.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["tasks"][0]["title"] = "amended task title (non-locked)"
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

# Also mutate the derived refinement.md ## Scope body to prove the md branch is gone.
python3 - "$CONTAINER/refinement.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
text = text.replace("- thing A", "- thing A\n- thing B (derived md scope rerender)")
p.write_text(text, encoding="utf-8")
PY

git -C "$REPO" add .
git -C "$REPO" commit -q -m "amendment: tasks[].title + derived md scope rerender"

if ! "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/case2.out" 2>&1; then
  echo "FAIL: case 2 (tasks[].title + derived md ## Scope) was incorrectly rejected" >&2
  echo "      AC1 regression: guard must not read derived refinement.md body" >&2
  cat "$TMP/case2.out" >&2
  exit 1
fi

# === Case 3 (AC2): violation — change acceptance_criteria in json ===
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
  cat "$TMP/case3.out" >&2
  exit 1
fi

# === Case 4 (AC-NF1): every JSON LOCKED field still triggers exit 2 ===
LOCKED_MUTATIONS=(
  'data["goal"] = "rewritten goal (violation)"'
  'data["background"] = "rewritten background (violation)"'
  'data["decisions"] = ["D1", "D2 (violation)"]'
  'data["scope"] = ["thing A", "thing B (violation)"]'
  'data["acceptance_criteria"] = [{"id": "AC1", "text": "rewritten (violation)"}]'
)
for mutation in "${LOCKED_MUTATIONS[@]}"; do
  git -C "$REPO" reset --hard "$BASE_SHA" -q
  python3 - "$CONTAINER/refinement.json" "$mutation" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
exec(sys.argv[2])
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$REPO" add .
  git -C "$REPO" commit -q -m "amendment: LOCKED field mutation (violation)"
  if "$VALIDATOR" --container "$CONTAINER" --base-ref "$BASE_SHA" --head-ref HEAD >"$TMP/case4.out" 2>&1; then
    echo "FAIL: case 4 LOCKED-field mutation incorrectly accepted: $mutation" >&2
    cat "$TMP/case4.out" >&2
    exit 1
  fi
  if ! grep -q "POLARIS_LOCKED_SCOPE_VIOLATION" "$TMP/case4.out"; then
    echo "FAIL: case 4 missing violation signal for: $mutation" >&2
    cat "$TMP/case4.out" >&2
    exit 1
  fi
done

# === Case 5 (AC-NEG1): no executing refinement.md body-read path in guard ===
# Strip comment lines, then assert the executable body never references
# refinement.md (no `git show ...refinement.md`, no REFINEMENT_MD_REL, no
# heading-diff python block).
EXEC_BODY="$(grep -vE '^[[:space:]]*#' "$VALIDATOR")"
if grep -qE 'refinement\.md|REFINEMENT_MD_REL|LOCKED_HEADINGS' <<< "$EXEC_BODY"; then
  echo "FAIL: case 5 (AC-NEG1) guard still has an executing refinement.md body-read path" >&2
  printf '%s\n' "$EXEC_BODY" | grep -nE 'refinement\.md|REFINEMENT_MD_REL|LOCKED_HEADINGS' >&2
  exit 1
fi

# === Case 6 (DP-444): explicit current/candidate file authority ===
CURRENT_JSON="$TMP/current.json"
CANDIDATE_JSON="$TMP/candidate.json"
git -C "$REPO" show "$BASE_SHA:$CONTAINER_REL/refinement.json" >"$CURRENT_JSON"
cp "$CURRENT_JSON" "$CANDIDATE_JSON"
python3 - "$CANDIDATE_JSON" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["technical_approach"] = "explicit implementation-detail amendment"
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
"$VALIDATOR" --current-file "$CURRENT_JSON" --candidate-file "$CANDIDATE_JSON" >"$TMP/case6-pass.out" 2>&1 || {
  echo "FAIL: case 6 explicit implementation-detail amendment was rejected" >&2
  cat "$TMP/case6-pass.out" >&2
  exit 1
}
python3 - "$CANDIDATE_JSON" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["goal"] = "protected goal rewrite"
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
rc=0
"$VALIDATOR" --current-file "$CURRENT_JSON" --candidate-file "$CANDIDATE_JSON" >"$TMP/case6-fail.out" 2>&1 || rc=$?
if [[ "$rc" -ne 2 ]] || ! grep -q 'POLARIS_LOCKED_SCOPE_VIOLATION' "$TMP/case6-fail.out"; then
  echo "FAIL: case 6 explicit protected-field rewrite did not fail closed" >&2
  cat "$TMP/case6-fail.out" >&2
  exit 1
fi

echo "PASS: refinement LOCKED scope guard selftest (JSON-only + explicit-file authority, 6/6 cases)"
