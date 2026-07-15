#!/usr/bin/env bash
# Purpose: DP-419 T1 selftest — assert the self-referential DP delivery carve-out
#          reference exists, carries the four required sections + evidence
#          checklist parity items, and is registered in the mechanism registry.
# Inputs:  none (reads tracked reference + registry from repo root).
# Outputs: PASS line on success; non-zero FAIL on contract regression.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REF="$ROOT/.claude/skills/references/self-referential-dp-delivery.md"
REG="$ROOT/.claude/rules/mechanism-registry.md"

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Canonical reference exists (AC2 single source).
test -f "$REF" || fail "missing reference: $REF"

# 2. Four required sections (AC2: 觸發條件 / 自驗步驟 / 繞過邊界 / evidence checklist).
for section in '## 觸發條件' '## 自驗步驟' '## 繞過邊界' '## Evidence Checklist'; do
  grep -qF "$section" "$REF" || fail "reference missing required section: $section"
done

# 3. Evidence checklist parity items (AC3: 手動交付 evidence 與 auto-pass 對等).
for item in 'completion_gate' 'deliverable.head_sha' 'run-aggregate-selftests.sh' 'mark-spec-implemented.sh'; do
  grep -qF "$item" "$REF" || fail "evidence checklist missing parity item: $item"
done

# 4. Bypass boundary must forbid bypass env (繞過邊界: 禁 bypass env).
grep -qF 'POLARIS_*_BYPASS' "$REF" || fail "reference missing bypass-env prohibition"

# 5. Registered in mechanism registry (canary entry).
grep -qF 'self-referential-dp-delivery' "$REG" || fail "mechanism-registry missing self-referential-dp-delivery entry"

echo "PASS: self-referential DP delivery carve-out reference + registry"
