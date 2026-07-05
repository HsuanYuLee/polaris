#!/usr/bin/env bash
# Verify the legacy Bug diagnosis skill surface has been removed from active framework surfaces.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for path in \
  ".claude/skills/bug-triage" \
  ".agents/skills/bug-triage" \
  ".claude/skills/references/bug-triage-entry-flow.md" \
  ".claude/skills/references/bug-triage-root-cause-flow.md" \
  ".claude/skills/references/bug-triage-confirm-handoff-flow.md" \
  ".claude/skills/references/bug-triage-acfail-flow.md"
do
  [[ ! -e "$path" ]] || fail "removed Bug diagnosis surface still exists: $path"
done

active_surfaces=()
for path in .claude/skills .claude/rules .agents/skills CLAUDE.md AGENTS.md MEMORY.md .claude/polaris-backlog.md scripts; do
  [[ -e "$path" ]] && active_surfaces+=("$path")
done

scan_out="$(mktemp -t dp231-bug-diagnosis-scan.XXXXXX)"
trap 'rm -f "$scan_out"' EXIT

if rg -n "bug-triage|/bug-triage" \
  -g "!scripts/selftests/bug-triage-removal-selftest.sh" \
  "${active_surfaces[@]}" >"$scan_out" 2>/dev/null; then
  cat "$scan_out" >&2
  fail "active legacy Bug diagnosis references remain"
fi

deleted_refs=(
  "bug-triage-entry-flow.md"
  "bug-triage-root-cause-flow.md"
  "bug-triage-confirm-handoff-flow.md"
  "bug-triage-acfail-flow.md"
)
for ref in "${deleted_refs[@]}"; do
  if rg -n "$ref" \
    -g "!scripts/selftests/bug-triage-removal-selftest.sh" \
    "${active_surfaces[@]}" >"$scan_out" 2>/dev/null; then
    cat "$scan_out" >&2
    fail "deleted reference still has active referrers: $ref"
  fi
done

echo "referrer scan: 0 hits"
echo "PASS: bug diagnosis removal selftest"
