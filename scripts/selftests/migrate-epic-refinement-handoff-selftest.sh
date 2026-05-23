#!/usr/bin/env bash
# scripts/selftests/migrate-epic-refinement-handoff-selftest.sh — DP-228-T12
#
# Covers AC15 (existing Epic 補 refinement.md 或 non-ready audit) and AC9
# (migration script supports --workspace-root and is idempotent).
#
# Fixtures:
#   - companies/exampleco/EPIC-100  → has refinement.json + index.md, rich enough
#                                     to derive refinement.md (HIGH confidence).
#   - companies/exampleco/EPIC-200  → has refinement.json but only minimal data;
#                                     too thin to derive → expect non-ready audit.
#   - companies/exampleco/EPIC-300  → has refinement.json + refinement.md already
#                                     present → migration must skip (idempotency).
#   - companies/exampleco/archive/EPIC-900 → archived; default scan must ignore.
#   - design-plans/DP-999-something/ → DP-backed source; migration must ignore
#                                       (script scope is companies/*).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/migrate-epic-refinement-handoff.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: migration script missing or not executable: $SCRIPT" >&2
  exit 1
fi

WORKDIR="$(mktemp -d -t migrate-epic-refinement-handoff-selftest.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

SPECS_ROOT="$WORKDIR/docs-manager/src/content/docs/specs"

write_file() {
  local file="$1"
  local body="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s' "$body" >"$file"
}

# ---------------------------------------------------------------------------
# Fixture 1: EPIC-100 — rich enough to derive refinement.md
# ---------------------------------------------------------------------------

write_file "$SPECS_ROOT/companies/exampleco/EPIC-100/index.md" '---
title: "Refinement — EPIC-100: SSR h3 titles"
description: "B2C 商品頁 SSR render h3_titles，作為 SEO 結構訊號。"
status: LOCKED
---

> Tier: 2 | Date: 2026-05-15 | Round: 2

## 本輪決策

- 接 Backend API h3_titles 欄位，SSR render 隱藏 h3。
'

write_file "$SPECS_ROOT/companies/exampleco/EPIC-100/refinement.json" '{
  "epic": "EPIC-100",
  "source": {
    "type": "jira",
    "id": "EPIC-100",
    "container": "/tmp/EPIC-100",
    "plan_path": null,
    "jira_key": "EPIC-100"
  },
  "version": "1.0",
  "tier": 2,
  "created_at": "2026-05-15T00:00:00+08:00",
  "refinement_round": 2,
  "modules": [
    {
      "path": "apps/main/pages/product/index.vue",
      "action": "modify",
      "complexity": "medium",
      "risk": "low",
      "reason": "在 SSR head 區塊渲染 h3_titles"
    },
    {
      "path": "apps/main/server/types/product.ts",
      "action": "modify",
      "complexity": "low",
      "risk": "low",
      "reason": "ProductBasicInfo 補 h3_titles 欄位"
    }
  ],
  "dependencies": [
    {
      "type": "api",
      "target": "GET /v1/products/mid-{prod_mid}",
      "description": "Backend 提供 h3_titles array",
      "blocking": false
    }
  ],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "SSR HTML 中可看到 h3 內含 h3_titles 文字",
      "category": "functional",
      "quantifiable": true,
      "verification": { "method": "curl", "detail": "curl SSR HTML 比對 h3" }
    },
    {
      "id": "NEG1",
      "text": "不依 user-agent 對 crawler 與一般使用者輸出不同 HTML",
      "category": "negative",
      "quantifiable": true,
      "verification": { "method": "code_review", "detail": "確認沒有 UA 分支" }
    }
  ],
  "edge_cases": [
    {
      "scenario": "h3_titles 為 null 或空陣列",
      "handling": "B2C 不 render 空 h3",
      "severity": "medium",
      "source": "backend"
    }
  ]
}'

# ---------------------------------------------------------------------------
# Fixture 2: EPIC-200 — too thin to derive; expect non-ready audit
# ---------------------------------------------------------------------------

write_file "$SPECS_ROOT/companies/exampleco/EPIC-200/index.md" '---
title: "Refinement — EPIC-200: placeholder"
description: "尚未補完"
---

TODO
'

write_file "$SPECS_ROOT/companies/exampleco/EPIC-200/refinement.json" '{
  "epic": "EPIC-200",
  "version": "1.0",
  "created_at": "2026-05-15T00:00:00+08:00",
  "modules": [],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": []
}'

# ---------------------------------------------------------------------------
# Fixture 3: EPIC-300 — already has refinement.md
# ---------------------------------------------------------------------------

write_file "$SPECS_ROOT/companies/exampleco/EPIC-300/index.md" '---
title: "Refinement — EPIC-300: pre-existing handoff"
description: "已經有 refinement.md"
---

content
'

write_file "$SPECS_ROOT/companies/exampleco/EPIC-300/refinement.json" '{
  "epic": "EPIC-300",
  "version": "1.0",
  "created_at": "2026-05-15T00:00:00+08:00",
  "modules": [
    { "path": "src/x.ts", "action": "modify" }
  ],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "existing",
      "verification": { "method": "manual", "detail": "n/a" }
    }
  ]
}'

# Pre-existing refinement.md — must not be touched.
EXISTING_REFINEMENT_BODY='---
title: "Refinement — EPIC-300: pre-existing handoff"
description: "已經有 refinement.md"
status: LOCKED
---

original content — must not be overwritten.
'
write_file "$SPECS_ROOT/companies/exampleco/EPIC-300/refinement.md" "$EXISTING_REFINEMENT_BODY"

# ---------------------------------------------------------------------------
# Fixture 4: archive — must be ignored by default scan
# ---------------------------------------------------------------------------

write_file "$SPECS_ROOT/companies/exampleco/archive/EPIC-900/index.md" '---
title: "Refinement — EPIC-900: archived"
description: "已封存"
---

archived
'

write_file "$SPECS_ROOT/companies/exampleco/archive/EPIC-900/refinement.json" '{
  "epic": "EPIC-900",
  "version": "1.0",
  "created_at": "2026-04-01T00:00:00+08:00",
  "modules": [
    { "path": "old.ts", "action": "modify", "reason": "legacy" }
  ],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "n/a",
      "verification": { "method": "manual", "detail": "n/a" }
    }
  ]
}'

# ---------------------------------------------------------------------------
# Fixture 5: DP-backed source — out of scope for this migration
# ---------------------------------------------------------------------------

write_file "$SPECS_ROOT/design-plans/DP-999-out-of-scope/index.md" '---
title: "DP-999: out of scope"
description: "DP-backed source"
---

n/a
'

write_file "$SPECS_ROOT/design-plans/DP-999-out-of-scope/refinement.json" '{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/DP-999",
    "plan_path": "/tmp/DP-999/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "created_at": "2026-05-15T00:00:00+08:00",
  "modules": [],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": []
}'

# ===========================================================================
# Test 1: dry-run report — no mutation, but classifications surfaced
# ===========================================================================

DRY_REPORT="$WORKDIR/dry-run.txt"
bash "$SCRIPT" --workspace-root "$WORKDIR" --dry-run >"$DRY_REPORT"

grep -q '^total=3$' "$DRY_REPORT" || {
  echo "FAIL: expected total=3 (EPIC-100, EPIC-200, EPIC-300); got:" >&2
  cat "$DRY_REPORT" >&2
  exit 1
}
grep -q '^would_backfill=1$' "$DRY_REPORT" || {
  echo "FAIL: expected would_backfill=1 (EPIC-100)" >&2
  cat "$DRY_REPORT" >&2
  exit 1
}
grep -q '^non_ready=1$' "$DRY_REPORT" || {
  echo "FAIL: expected non_ready=1 (EPIC-200)" >&2
  cat "$DRY_REPORT" >&2
  exit 1
}
grep -q '^already_ok=1$' "$DRY_REPORT" || {
  echo "FAIL: expected already_ok=1 (EPIC-300)" >&2
  cat "$DRY_REPORT" >&2
  exit 1
}

if [[ -f "$SPECS_ROOT/companies/exampleco/EPIC-100/refinement.md" ]]; then
  echo "FAIL: dry-run must not write refinement.md" >&2
  exit 1
fi

# ===========================================================================
# Test 2: apply — backfill EPIC-100 and write non-ready audit
# ===========================================================================

APPLY_REPORT="$WORKDIR/apply.txt"
bash "$SCRIPT" --workspace-root "$WORKDIR" --apply >"$APPLY_REPORT"

grep -q '^backfilled=1$' "$APPLY_REPORT" || {
  echo "FAIL: expected backfilled=1 after --apply" >&2
  cat "$APPLY_REPORT" >&2
  exit 1
}
grep -q '^non_ready=1$' "$APPLY_REPORT" || {
  echo "FAIL: expected non_ready=1 after --apply" >&2
  cat "$APPLY_REPORT" >&2
  exit 1
}

# 2a. refinement.md written for EPIC-100
HANDOFF="$SPECS_ROOT/companies/exampleco/EPIC-100/refinement.md"
[[ -f "$HANDOFF" ]] || {
  echo "FAIL: refinement.md not written for EPIC-100" >&2
  exit 1
}

# Must contain expected sections (handoff-grade refinement.md schema)
for section in 'title:' '## Scope' '## Technical Approach' '## Modules' '## Acceptance Criteria' '## Edge Cases' '## Downstream Hints'; do
  grep -q "$section" "$HANDOFF" || {
    echo "FAIL: refinement.md missing section: $section" >&2
    cat "$HANDOFF" >&2
    exit 1
  }
done

# Must surface module path from refinement.json
grep -q 'apps/main/pages/product/index.vue' "$HANDOFF" || {
  echo "FAIL: refinement.md does not surface module path" >&2
  cat "$HANDOFF" >&2
  exit 1
}

# Must surface AC1 text
grep -q 'SSR HTML' "$HANDOFF" || {
  echo "FAIL: refinement.md missing AC1 text" >&2
  cat "$HANDOFF" >&2
  exit 1
}

# 2b. non-ready audit written
AUDIT="$SPECS_ROOT/refinement-handoff-audit/non-ready.md"
[[ -f "$AUDIT" ]] || {
  echo "FAIL: non-ready audit file not written: $AUDIT" >&2
  exit 1
}
grep -q 'EPIC-200' "$AUDIT" || {
  echo "FAIL: audit missing EPIC-200 entry" >&2
  cat "$AUDIT" >&2
  exit 1
}
grep -q 'EPIC-100' "$AUDIT" && {
  echo "FAIL: audit must not list backfilled EPIC-100" >&2
  cat "$AUDIT" >&2
  exit 1
}

# Machine-parseable JSON sidecar must exist too
AUDIT_JSON="$SPECS_ROOT/refinement-handoff-audit/non-ready.json"
[[ -f "$AUDIT_JSON" ]] || {
  echo "FAIL: non-ready audit JSON sidecar missing: $AUDIT_JSON" >&2
  exit 1
}
python3 - "$AUDIT_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert isinstance(data, dict), "audit JSON must be an object"
entries = data.get("entries", [])
assert isinstance(entries, list), "entries must be a list"
ids = [item.get("source_id") for item in entries]
assert "EPIC-200" in ids, f"EPIC-200 must appear in audit entries; got {ids}"
assert "EPIC-100" not in ids, "EPIC-100 must not appear (it was backfilled)"
PY

# 2c. EPIC-300 untouched (already had refinement.md)
EXISTING_AFTER="$(cat "$SPECS_ROOT/companies/exampleco/EPIC-300/refinement.md")"
if [[ "$EXISTING_AFTER" != *"original content — must not be overwritten."* ]]; then
  echo "FAIL: existing EPIC-300 refinement.md was overwritten" >&2
  exit 1
fi

# 2d. archive untouched
if [[ -f "$SPECS_ROOT/companies/exampleco/archive/EPIC-900/refinement.md" ]]; then
  echo "FAIL: archive EPIC-900 must not be written" >&2
  exit 1
fi

# 2e. DP source untouched
if [[ -f "$SPECS_ROOT/design-plans/DP-999-out-of-scope/refinement.md" ]]; then
  echo "FAIL: DP-999 must be out of scope" >&2
  exit 1
fi

# ===========================================================================
# Test 3: idempotency — re-run apply should backfill=0
# ===========================================================================

# Snapshot mtime of EPIC-100 refinement.md before second apply
BEFORE_HASH="$(shasum "$HANDOFF" | awk '{print $1}')"

REAPPLY_REPORT="$WORKDIR/reapply.txt"
bash "$SCRIPT" --workspace-root "$WORKDIR" --apply >"$REAPPLY_REPORT"

grep -q '^backfilled=0$' "$REAPPLY_REPORT" || {
  echo "FAIL: second --apply should be no-op (backfilled=0)" >&2
  cat "$REAPPLY_REPORT" >&2
  exit 1
}

AFTER_HASH="$(shasum "$HANDOFF" | awk '{print $1}')"
[[ "$BEFORE_HASH" == "$AFTER_HASH" ]] || {
  echo "FAIL: refinement.md content changed on re-apply (not idempotent)" >&2
  exit 1
}

# ===========================================================================
# Test 4: --include-archive scans archive containers
# ===========================================================================

ARCHIVE_REPORT="$WORKDIR/archive.txt"
bash "$SCRIPT" --workspace-root "$WORKDIR" --dry-run --include-archive >"$ARCHIVE_REPORT"
grep -q '^total=4$' "$ARCHIVE_REPORT" || {
  echo "FAIL: --include-archive expected total=4 (adds EPIC-900)" >&2
  cat "$ARCHIVE_REPORT" >&2
  exit 1
}

echo "PASS"
