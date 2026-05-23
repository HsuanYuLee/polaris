#!/usr/bin/env bash
# Selftest for scripts/migrate-pm-epic-mapping.sh
#
# Covers DP-228 AC8 (deprecate local_role + dependencies), AC9 (idempotency),
# AC-NF3 (malformed fail-stop + manual review list), AC-NEG5 (archive guard).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MIGRATE="$ROOT/scripts/migrate-pm-epic-mapping.sh"

if [[ ! -x "$MIGRATE" ]]; then
  echo "FAIL: migrate-pm-epic-mapping.sh missing or not executable at $MIGRATE" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t migrate-pm-epic-mapping.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

ws="$tmpdir/workspace"
specs="$ws/docs-manager/src/content/docs/specs"
mkdir -p \
  "$specs/companies/exampleco/EXAMPLE-526" \
  "$specs/companies/exampleco/EXAMPLE-700" \
  "$specs/companies/exampleco/archive/EXAMPLE-800" \
  "$specs/companies/exampleco/EXAMPLE-900"

# --- Fixture 1: EXAMPLE-526-like — PM Epic mapping with markdown table ---
cat >"$specs/companies/exampleco/EXAMPLE-526/index.md" <<'MD'
---
title: "Epic Mapping — EXAMPLE-526: [SEO] URL Architecture 重構"
description: "EXAMPLE-526 PM Epic local mapping container；記錄 PM child Story 與 RD-owned implementation task 的關聯策略。"
status: DISCUSSION
jira_issue_type: "Epic"
local_role: "pm_epic_mapping"

sidebar:
  badge:
    text: "DISCUSSION"
    variant: "note"
---

> Source: DP-146 | JIRA: EXAMPLE-526 | Role: PM Epic mapping container

## Local Posture

EXAMPLE-526 是 PM 開立的 Epic。

## PM Child Tickets

| JIRA key | Issue type | Local role | Summary | RD implementation posture |
|---|---|---|---|---|
| EXAMPLE-527 | Story | PM child scope reference | [SEO] Task 1 — 移除 /category 的 noindex | 另開 RD-owned EXB2C task |
| EXAMPLE-528 | Story | PM child scope reference | [SEO] Task 2 — 補齊 BreadcrumbList JSON-LD | 另開 RD-owned EXB2C task |
| EXAMPLE-529 | Story | PM child scope reference | [Explore] Task 3 — 移除中間層 | 另開 RD-owned EXB2C task |
| EXAMPLE-530 | Story | PM child scope reference | [SEO] Task 4 — 建立新路由 | 另開 RD-owned EXB2C task |

## Mapping Policy

- RD implementation task 需另開 EXB2C key。
MD

# --- Fixture 2: EXAMPLE-700 — already partially migrated (has refinement.json) ---
cat >"$specs/companies/exampleco/EXAMPLE-700/index.md" <<'MD'
---
title: "Epic Mapping — EXAMPLE-700"
description: "Another PM mapping container."
status: DISCUSSION
jira_issue_type: "Epic"
local_role: "pm_epic_mapping"
---

## PM Child Tickets

| JIRA key | Issue type | Local role | Summary | RD implementation posture |
|---|---|---|---|---|
| EXAMPLE-701 | Story | PM child scope reference | Task A | RD-owned task TBD |
MD

# --- Fixture 3: archive — must not be touched by default ---
cat >"$specs/companies/exampleco/archive/EXAMPLE-800/index.md" <<'MD'
---
title: "Archived PM mapping"
description: "Archived container."
status: IMPLEMENTED
jira_issue_type: "Epic"
local_role: "pm_epic_mapping"
---

## PM Child Tickets

| JIRA key | Issue type | Local role | Summary | RD implementation posture |
|---|---|---|---|---|
| EXAMPLE-801 | Story | PM child scope reference | Done task | Done |
MD

# --- Fixture 4: malformed — no recognisable child Story list ---
cat >"$specs/companies/exampleco/EXAMPLE-900/index.md" <<'MD'
---
title: "Malformed PM mapping"
description: "Malformed."
status: DISCUSSION
jira_issue_type: "Epic"
local_role: "pm_epic_mapping"
---

## PM Child Tickets

This container forgot to list child tickets in a recognisable format.
Just freeform prose mentioning random tokens like ABC and 123.
MD

# ---------------------------------------------------------------------------
# 1. --dry-run must not modify any file
# ---------------------------------------------------------------------------

before_hash="$(find "$specs" -type f -print0 | sort -z | xargs -0 shasum | shasum)"
dry_out="$tmpdir/dry.json"
# Exclude the malformed container from the default scope by running with
# --skip EXAMPLE-900 so dry-run can succeed and we can assert the other fixtures.
bash "$MIGRATE" --workspace-root "$ws" --dry-run --skip EXAMPLE-900 >"$dry_out"
after_hash="$(find "$specs" -type f -print0 | sort -z | xargs -0 shasum | shasum)"
[[ "$before_hash" == "$after_hash" ]] || { echo "FAIL: dry-run modified files" >&2; exit 1; }
grep -q '"action": "migrate"' "$dry_out" || { echo "FAIL: dry-run missing migrate action" >&2; exit 1; }
grep -q 'EXAMPLE-526' "$dry_out" || { echo "FAIL: dry-run missing EXAMPLE-526" >&2; exit 1; }
grep -q 'EXAMPLE-700' "$dry_out" || { echo "FAIL: dry-run missing EXAMPLE-700" >&2; exit 1; }
grep -q 'EXAMPLE-800' "$dry_out" && { echo "FAIL: dry-run touched archive without flag" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2. Apply succeeds (skipping malformed); assert structure
# ---------------------------------------------------------------------------

bash "$MIGRATE" --workspace-root "$ws" --apply --skip EXAMPLE-900 >"$tmpdir/apply.json"

# 2a. refinement.md + refinement.json materialised for EXAMPLE-526
[[ -f "$specs/companies/exampleco/EXAMPLE-526/refinement.md" ]] || { echo "FAIL: EXAMPLE-526 refinement.md missing" >&2; exit 1; }
[[ -f "$specs/companies/exampleco/EXAMPLE-526/refinement.json" ]] || { echo "FAIL: EXAMPLE-526 refinement.json missing" >&2; exit 1; }

# 2b. local_role removed from container frontmatter
if grep -q '^local_role:' "$specs/companies/exampleco/EXAMPLE-526/index.md"; then
  echo "FAIL: EXAMPLE-526 index.md still has local_role" >&2
  exit 1
fi

# 2c. dependencies[] populated with type=pm_child_story
python3 - "$specs/companies/exampleco/EXAMPLE-526/refinement.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    data = json.load(fh)

deps = data.get("dependencies") or []
pm_deps = [d for d in deps if d.get("type") == "pm_child_story"]
assert len(pm_deps) == 4, f"expected 4 pm_child_story dependencies, got {len(pm_deps)}: {pm_deps}"
keys = sorted(d.get("target") for d in pm_deps)
assert keys == ["EXAMPLE-527", "EXAMPLE-528", "EXAMPLE-529", "EXAMPLE-530"], f"unexpected keys: {keys}"
for dep in pm_deps:
    assert dep.get("description"), f"missing description: {dep}"
    assert "role" in dep, f"missing role: {dep}"
    assert "status" in dep, f"missing status: {dep}"

assert data.get("source", {}).get("type") == "jira"
assert data.get("source", {}).get("id") == "EXAMPLE-526"
PY

# 2d. archive untouched
if grep -q 'pm_child_story' "$specs/companies/exampleco/archive/EXAMPLE-800/index.md" 2>/dev/null; then
  echo "FAIL: archive container was modified" >&2
  exit 1
fi
[[ ! -f "$specs/companies/exampleco/archive/EXAMPLE-800/refinement.json" ]] || { echo "FAIL: archive refinement.json created" >&2; exit 1; }
[[ ! -f "$specs/companies/exampleco/archive/EXAMPLE-800/refinement.md" ]] || { echo "FAIL: archive refinement.md created" >&2; exit 1; }
grep -q '^local_role:' "$specs/companies/exampleco/archive/EXAMPLE-800/index.md" || { echo "FAIL: archive local_role removed (should be preserved by default)" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 3. Idempotency: second apply has zero diff
# ---------------------------------------------------------------------------

snapshot1="$(find "$specs" -type f -not -path '*/archive/*' -print0 | sort -z | xargs -0 shasum)"
bash "$MIGRATE" --workspace-root "$ws" --apply --skip EXAMPLE-900 >"$tmpdir/apply2.json"
snapshot2="$(find "$specs" -type f -not -path '*/archive/*' -print0 | sort -z | xargs -0 shasum)"
if [[ "$snapshot1" != "$snapshot2" ]]; then
  echo "FAIL: second apply changed files (non-idempotent)" >&2
  diff <(echo "$snapshot1") <(echo "$snapshot2") >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Malformed container: fail-stop exit 2 + manual review list
# ---------------------------------------------------------------------------

set +e
bash "$MIGRATE" --workspace-root "$ws" --apply >"$tmpdir/malformed.json" 2>"$tmpdir/malformed.err"
rc=$?
set -e
if [[ $rc -ne 2 ]]; then
  echo "FAIL: malformed container should fail-stop with exit 2, got $rc" >&2
  cat "$tmpdir/malformed.err" >&2
  exit 1
fi
review_list="$ws/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-900/.migrate-pm-epic-mapping-review.md"
# The manual review list may be written either next to the container or under
# a workspace-level audit path. Accept either.
audit_top="$ws/.polaris/evidence/migrate-pm-epic-mapping/manual-review.md"
if [[ ! -f "$review_list" && ! -f "$audit_top" ]]; then
  # Fall back: scan stderr / json for a manual review list path
  if ! grep -qi 'manual.*review' "$tmpdir/malformed.err" "$tmpdir/malformed.json"; then
    echo "FAIL: malformed run did not write manual review list" >&2
    cat "$tmpdir/malformed.err" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 5. --include-archive opt-in flag still honours idempotency
# ---------------------------------------------------------------------------

bash "$MIGRATE" --workspace-root "$ws" --apply --include-archive --skip EXAMPLE-900 >"$tmpdir/archive-apply.json"
[[ -f "$specs/companies/exampleco/archive/EXAMPLE-800/refinement.json" ]] || { echo "FAIL: --include-archive did not migrate archive" >&2; exit 1; }

snap_a="$(find "$specs/companies/exampleco/archive" -type f -print0 | sort -z | xargs -0 shasum)"
bash "$MIGRATE" --workspace-root "$ws" --apply --include-archive --skip EXAMPLE-900 >"$tmpdir/archive-apply2.json"
snap_b="$(find "$specs/companies/exampleco/archive" -type f -print0 | sort -z | xargs -0 shasum)"
if [[ "$snap_a" != "$snap_b" ]]; then
  echo "FAIL: --include-archive second apply not idempotent" >&2
  exit 1
fi

echo "PASS: migrate pm-epic-mapping selftest"
