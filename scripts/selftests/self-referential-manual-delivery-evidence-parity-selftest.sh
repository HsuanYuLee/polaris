#!/usr/bin/env bash
# Purpose: DP-419 T5 selftest — assert the self-referential DP manual-delivery
#          (D2) evidence path enumerates the FULL marker set at parity with an
#          auto-pass delivery, so a manual bootstrap cannot ship evidence-gapped
#          (the DP-417 all-missing counter-example). Complements T1's sampled
#          reference-shape check by asserting every Evidence Checklist parity item
#          lives in the `## Evidence Checklist` section, plus the no-gap contract
#          and the DP-360 delivery-head authority (no branch-ref fallback).
# Inputs:  none (reads the tracked reference + mechanism registry from repo root).
# Outputs: PASS line on success; non-zero FAIL on parity-contract regression.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REF="$ROOT/.claude/skills/references/self-referential-dp-delivery.md"
REG="$ROOT/.claude/rules/mechanism-registry.md"

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Canonical reference exists.
test -f "$REF" || fail "missing reference: $REF"

# 2. Extract the `## Evidence Checklist` section body (up to the next `## ` heading).
#    Parity items must live inside this section, not merely somewhere in the file —
#    that is the distinct review value over T1's whole-file sample.
section="$(awk '
  /^## Evidence Checklist/ { collecting = 1; next }
  collecting && /^## / { collecting = 0 }
  collecting { print }
' "$REF")"
[ -n "$section" ] || fail "reference missing or empty '## Evidence Checklist' section"

section_has() {
  grep -qF "$1" <<<"$section" || fail "Evidence Checklist section missing parity item: $1"
}

# 3. Full 6-item auto-pass-parity marker set (each asserted inside the section).
section_has 'completion_gate marker'                 # engineering completion gate 對等
section_has '.polaris/evidence/completion-gate/'
section_has 'Layer B verify marker'                  # auto-pass verify 階段對等
section_has 'run-verify-command.sh'
section_has 'pr_freshness marker'                    # delivery backbone base-freshness 對等
section_has 'ci_local marker'                        # ci-local gate 對等（framework repo N/A）
section_has 'deliverable.head_sha'                   # DP-360 唯一交付 head authority
section_has 'closeout evidence'                      # auto-pass closeout chain 對等
section_has 'tasks/pr-release/'
section_has 'mark-spec-implemented.sh'

# 4. No-gap contract: manual delivery must NOT ship evidence-gapped; DP-417 named
#    as the all-missing counter-example.
section_has 'evidence-gapped'
section_has 'DP-417'

# 5. Delivery head must NOT fall back to a mutable branch ref (DP-360 authority).
grep -qF 'branch ref' <<<"$section" || fail "Evidence Checklist section missing no-branch-ref-fallback contract for delivery head"

# 6. Reference names this selftest as the parity asserter (contract ↔ enforcer binding).
grep -qF 'self-referential-manual-delivery-evidence-parity-selftest.sh' "$REF" \
  || fail "reference does not bind parity assertion to this selftest"

# 7. Registered in the mechanism registry (self-referential-dp-delivery canary).
grep -qF 'self-referential-manual-delivery-evidence-parity-selftest.sh' "$REG" \
  || fail "mechanism-registry missing T5 parity selftest reference in self-referential-dp-delivery entry"

echo "PASS: self-referential manual-delivery evidence parity (6-item marker set + no-gap + DP-360 head authority)"
