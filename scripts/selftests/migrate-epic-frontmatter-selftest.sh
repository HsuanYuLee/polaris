#!/usr/bin/env bash
# Selftest for migrate-epic-frontmatter.sh
#
# Coverage：
#   AC6      補 priority / topic / created
#   AC9      --workspace-root + idempotent
#   AC-NEG5  預設不修改 archive/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIGRATE="$SCRIPT_DIR/migrate-epic-frontmatter.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

if [[ ! -x "$MIGRATE" && ! -f "$MIGRATE" ]]; then
  fail "migrate-epic-frontmatter.sh not found at $MIGRATE"
fi

tmpdir="$(mktemp -d -t migrate-epic-frontmatter.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Build fixture workspace
specs="$tmpdir/docs-manager/src/content/docs/specs"
mkdir -p \
  "$specs/companies/exampleco/DEMO-100" \
  "$specs/companies/exampleco/DEMO-200" \
  "$specs/companies/exampleco/DEMO-300" \
  "$specs/companies/exampleco/archive/DEMO-900"

# DEMO-100：缺所有三個欄位（index.md + refinement.md）
cat >"$specs/companies/exampleco/DEMO-100/index.md" <<'MD'
---
title: "Refinement — DEMO-100: 商品頁載入優化"
description: "縮短首屏 TTFB"
status: LOCKED
---

> Tier: 2 | Date: 2026-04-10 | Round: 2

## Background

略。
MD

cat >"$specs/companies/exampleco/DEMO-100/refinement.md" <<'MD'
---
title: "Refinement — DEMO-100: 商品頁載入優化"
description: "縮短首屏 TTFB"
status: LOCKED
---

## Refinement summary
MD

# DEMO-200：已有 priority + topic，缺 created
cat >"$specs/companies/exampleco/DEMO-200/index.md" <<'MD'
---
title: "Refinement — DEMO-200: 結帳流程整理"
description: "簡化 checkout flow"
status: IMPLEMENTING
priority: P2
topic: checkout-flow
---

> Tier: 2 | Date: 2026-03-20 | Round: 1

略。
MD

# DEMO-300：完整三欄位（idempotency baseline）
cat >"$specs/companies/exampleco/DEMO-300/index.md" <<'MD'
---
title: "Refinement — DEMO-300: 已完整"
description: "完整 frontmatter"
status: IMPLEMENTED
priority: P3
topic: complete-epic
created: 2026-02-15
---

略。
MD

# Archive：預設不應動到
cat >"$specs/companies/exampleco/archive/DEMO-900/index.md" <<'MD'
---
title: "Refinement — DEMO-900: 已封存"
description: "archived"
status: ARCHIVED
---

略。
MD

archive_before="$(shasum "$specs/companies/exampleco/archive/DEMO-900/index.md" | awk '{print $1}')"

# Phase 1：dry-run 不可改檔
demo100_before="$(shasum "$specs/companies/exampleco/DEMO-100/index.md" | awk '{print $1}')"
bash "$MIGRATE" --workspace-root "$tmpdir" --dry-run >/dev/null
demo100_after="$(shasum "$specs/companies/exampleco/DEMO-100/index.md" | awk '{print $1}')"
[[ "$demo100_before" == "$demo100_after" ]] || fail "dry-run modified DEMO-100/index.md"

# Phase 2：apply
bash "$MIGRATE" --workspace-root "$tmpdir" --apply >/dev/null

# AC6：DEMO-100 補上三欄位（priority / topic / created），fallback path 帶 priority_source
grep -q '^priority: P3$' "$specs/companies/exampleco/DEMO-100/index.md" \
  || fail "DEMO-100/index.md missing priority"
grep -q '^priority_source: fallback-p3$' "$specs/companies/exampleco/DEMO-100/index.md" \
  || fail "DEMO-100/index.md missing priority_source (MCP unreachable fallback)"
grep -qE '^topic: [a-z0-9][a-z0-9-]*$' "$specs/companies/exampleco/DEMO-100/index.md" \
  || fail "DEMO-100/index.md missing or invalid topic"
grep -qE '^created: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$specs/companies/exampleco/DEMO-100/index.md" \
  || fail "DEMO-100/index.md missing or invalid created"

# refinement.md 也要被掃到
grep -q '^priority: P3$' "$specs/companies/exampleco/DEMO-100/refinement.md" \
  || fail "DEMO-100/refinement.md missing priority"
grep -qE '^created: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$specs/companies/exampleco/DEMO-100/refinement.md" \
  || fail "DEMO-100/refinement.md missing created"

# DEMO-200：既有 priority/topic 不可覆蓋，只補 created
grep -q '^priority: P2$' "$specs/companies/exampleco/DEMO-200/index.md" \
  || fail "DEMO-200 priority overwritten (should keep P2)"
grep -q '^topic: checkout-flow$' "$specs/companies/exampleco/DEMO-200/index.md" \
  || fail "DEMO-200 topic overwritten (should keep checkout-flow)"
if grep -q '^priority_source:' "$specs/companies/exampleco/DEMO-200/index.md"; then
  fail "DEMO-200 should not gain priority_source when priority already present"
fi
grep -qE '^created: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$specs/companies/exampleco/DEMO-200/index.md" \
  || fail "DEMO-200 missing created"

# AC-NEG5：archive 預設不修改
archive_after="$(shasum "$specs/companies/exampleco/archive/DEMO-900/index.md" | awk '{print $1}')"
[[ "$archive_before" == "$archive_after" ]] \
  || fail "archive/DEMO-900/index.md was modified (AC-NEG5 violation)"

# AC9：idempotency — 再跑一次 apply，diff 必須為空
before="$(find "$specs" -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum)"
bash "$MIGRATE" --workspace-root "$tmpdir" --apply >/dev/null
after="$(find "$specs" -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum)"
[[ "$before" == "$after" ]] || fail "migration is not idempotent on second --apply"

# DEMO-300：已有完整欄位，不可被修改
grep -q '^priority: P3$' "$specs/companies/exampleco/DEMO-300/index.md" \
  || fail "DEMO-300 priority changed"
grep -q '^topic: complete-epic$' "$specs/companies/exampleco/DEMO-300/index.md" \
  || fail "DEMO-300 topic changed"
grep -q '^created: 2026-02-15$' "$specs/companies/exampleco/DEMO-300/index.md" \
  || fail "DEMO-300 created changed"
if grep -q '^priority_source:' "$specs/companies/exampleco/DEMO-300/index.md"; then
  fail "DEMO-300 should not gain priority_source when priority already present"
fi

# Phase 3：--include-archive 才會處理 archive
bash "$MIGRATE" --workspace-root "$tmpdir" --apply --include-archive >/dev/null
grep -q '^priority: P3$' "$specs/companies/exampleco/archive/DEMO-900/index.md" \
  || fail "DEMO-900 should be migrated with --include-archive"

echo "[selftest] PASS"
