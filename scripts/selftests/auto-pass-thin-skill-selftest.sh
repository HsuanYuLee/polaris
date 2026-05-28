#!/usr/bin/env bash
# scripts/selftests/auto-pass-thin-skill-selftest.sh — DP-237 T2/T4 thin SKILL selftest.
#
# 驗證 .claude/skills/auto-pass/SKILL.md 已精簡為 runner-first contract：
#   AC1   — SKILL 只保留 trigger、source gate、stage order、dispatch boundary、
#           legal terminal、forbidden actions、runner command。
#   AC3   — ledger / report / friction / proof / consent / resume schema 不重複
#           出現在 SKILL；schema 僅由 canonical references 維護。
#   AC5   — INDEX.md 仍登錄四個 canonical reference + runner script pointer，
#           SKILL 內含 runner script 與 reference pointer，downstream agent 可
#           直接從 INDEX.md 或 SKILL.md 找到 runner 與 canonical schema。
#   AC-NF1 — SKILL line count 相對原始 464 行至少縮減 60%（≤ 185 行）。
#   AC-NEG1 — (T4 docs-health) thin SKILL 不得讓 ledger / report / friction /
#           proof / resume schema 或 validator 消失：四個 canonical reference
#           檔案、runner script、五個 auto-pass validator script 都必須存在
#           且非空，否則 thin SKILL 把 guardrail 拆掉視為違規。
#
# Usage:
#   bash scripts/selftests/auto-pass-thin-skill-selftest.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/.claude/skills/auto-pass/SKILL.md"
INDEX="$ROOT/.claude/skills/references/INDEX.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if [[ ! -f "$SKILL" ]]; then
  fail "SKILL.md not found: $SKILL"
fi
if [[ ! -f "$INDEX" ]]; then
  fail "INDEX.md not found: $INDEX"
fi

# --- AC-NF1 — line count budget (≥60% reduction from 464). ----------------
ORIGINAL_LINES=464
MAX_LINES=$(( ORIGINAL_LINES * 40 / 100 )) # 185
ACTUAL_LINES="$(wc -l < "$SKILL" | tr -d ' ')"

if (( ACTUAL_LINES > MAX_LINES )); then
  fail "AC-NF1: SKILL.md has $ACTUAL_LINES lines, exceeds budget $MAX_LINES (60% reduction from $ORIGINAL_LINES)"
fi

# --- AC1 — required runner-first sections retained. -----------------------
required_sections=(
  "Source Gate"
  "Dispatch Boundary"
  "Runner Command"
  "Legal Terminal"
  "Forbidden Actions"
)

for section in "${required_sections[@]}"; do
  if ! grep -q "^## .*${section}" "$SKILL"; then
    fail "AC1: SKILL.md missing required section: ## ${section}"
  fi
done

# --- AC3 — schema duplication scan. ---------------------------------------
# SKILL must not embed canonical schemas (ledger JSON shape, friction enum table,
# probe matrix table, resume schema enumeration). These belong to references.

# Pattern 1: ledger JSON minimal-shape block (DP-backed snippet starts with
# `"schema_version"`).
if grep -q '"schema_version"' "$SKILL"; then
  fail "AC3: SKILL.md still contains ledger schema JSON ('\"schema_version\"' literal)"
fi

# Pattern 2: friction kind enum table (matches "Kind" header column with
# >=4 enum kinds listed inline).
friction_kinds=("inner_skill_halt_bypass" "manual_artifact_patch" "deterministic_gap" "validator_contract_conflict" "missing_helper_script" "language_drift_repair")
matched_kinds=0
for kind in "${friction_kinds[@]}"; do
  if grep -q "\`${kind}\`" "$SKILL"; then
    matched_kinds=$(( matched_kinds + 1 ))
  fi
done
if (( matched_kinds >= 4 )); then
  fail "AC3: SKILL.md still enumerates friction kind enum ($matched_kinds kinds inline; expected pointer to friction-capture-contract.md)"
fi

# Pattern 3: probe matrix table (Stage|PASS probe|Blocked headers).
if grep -q "PASS probe" "$SKILL" && grep -q "Blocked / route-back" "$SKILL"; then
  fail "AC3: SKILL.md still embeds probe matrix table (belongs to auto-pass-execution-flow.md)"
fi

# Pattern 4: consent_excludes enum list (multiple enum members inline).
consent_excludes=("base_branch_force_push" "force_push_without_lease" "history_rewrite" "production_write" "jira_child_write")
matched_consent=0
for member in "${consent_excludes[@]}"; do
  if grep -q "\`${member}\`" "$SKILL" || grep -q "\"${member}\"" "$SKILL"; then
    matched_consent=$(( matched_consent + 1 ))
  fi
done
if (( matched_consent >= 3 )); then
  fail "AC3: SKILL.md still enumerates consent_excludes ($matched_consent members inline; expected pointer to auto-pass-ledger.md)"
fi

# Pattern 5: auto-friction trigger table with all 5 signal rows.
auto_friction_signals=("gate_failure" "workaround_taken" "stage_retry" "probe_unknown" "context_pressure")
matched_signals=0
for sig in "${auto_friction_signals[@]}"; do
  if grep -q "\`${sig}\`" "$SKILL"; then
    matched_signals=$(( matched_signals + 1 ))
  fi
done
if (( matched_signals >= 4 )); then
  fail "AC3: SKILL.md still embeds auto-friction trigger table ($matched_signals signals inline; expected pointer to friction-capture-contract.md)"
fi

# --- AC5 — runner + canonical reference pointers present. -----------------
required_pointers=(
  "scripts/auto-pass-runner.sh"
  "auto-pass-execution-flow.md"
  "auto-pass-ledger.md"
  "auto-pass-report.md"
  "friction-capture-contract.md"
)

for ptr in "${required_pointers[@]}"; do
  if ! grep -q -F "$ptr" "$SKILL"; then
    fail "AC5: SKILL.md missing pointer: $ptr"
  fi
done

# --- AC5 — INDEX.md still lists the four canonical references. ------------
index_entries=(
  "auto-pass-execution-flow.md"
  "auto-pass-ledger.md"
  "auto-pass-report.md"
  "friction-capture-contract.md"
)

for entry in "${index_entries[@]}"; do
  if ! grep -q -F "$entry" "$INDEX"; then
    fail "AC5: INDEX.md missing canonical reference entry: $entry"
  fi
done

# --- AC5 (T4 wiring) — INDEX.md must surface the runner script. -----------
# downstream agents reading INDEX.md should be able to locate the canonical
# orchestrator runner without first having to read SKILL.md.
if ! grep -q -F "scripts/auto-pass-runner.sh" "$INDEX"; then
  fail "AC5 (T4): INDEX.md does not mention scripts/auto-pass-runner.sh"
fi

# --- AC-NEG1 (T4 docs-health) — schemas / validators not removed. ---------
# Thin SKILL must not silently drop the canonical schema files or the
# validators that enforce them. We enumerate the surfaces that DP-218 /
# DP-220 / DP-230 / DP-231 introduced and require each to exist + be
# non-empty in the worktree.
required_canonical_refs=(
  ".claude/skills/references/auto-pass-execution-flow.md"
  ".claude/skills/references/auto-pass-ledger.md"
  ".claude/skills/references/auto-pass-report.md"
  ".claude/skills/references/friction-capture-contract.md"
  ".claude/skills/references/auto-pass-proof-of-work.md"
)
for ref in "${required_canonical_refs[@]}"; do
  if [[ ! -s "$ROOT/$ref" ]]; then
    fail "AC-NEG1: canonical reference missing or empty: $ref"
  fi
done

required_runner_scripts=(
  "scripts/auto-pass-runner.sh"
  "scripts/auto-pass-probe.sh"
  "scripts/append-auto-pass-friction.sh"
  "scripts/auto-pass-increment-counter.sh"
)
for s in "${required_runner_scripts[@]}"; do
  if [[ ! -x "$ROOT/$s" ]]; then
    fail "AC-NEG1: runner / friction helper missing or non-executable: $s"
  fi
done

required_validators=(
  "scripts/validate-auto-pass-ledger.sh"
  "scripts/validate-auto-pass-report.sh"
  "scripts/validate-auto-pass-proof.sh"
  "scripts/validate-auto-pass-resume.sh"
)
for v in "${required_validators[@]}"; do
  if [[ ! -x "$ROOT/$v" ]]; then
    fail "AC-NEG1: auto-pass validator missing or non-executable: $v"
  fi
done

# --- AC-NEG1 (T4 docs-health) — canonical refs still carry their contracts.
# Spot-check that the load-bearing reference sections are still present, so
# thin SKILL didn't accidentally move authority to ad-hoc prose. Use
# parallel arrays (bash 3.2 compatible — macOS default).
anchor_refs=(
  ".claude/skills/references/auto-pass-ledger.md"
  ".claude/skills/references/auto-pass-report.md"
  ".claude/skills/references/friction-capture-contract.md"
  ".claude/skills/references/auto-pass-execution-flow.md"
  ".claude/skills/references/auto-pass-proof-of-work.md"
)
anchor_tokens=(
  "schema_version"
  "schema_version"
  "deterministic_gap"
  "Dispatch Envelope Worktree Resolution"
  "marker_kind"
)
for idx in "${!anchor_refs[@]}"; do
  ref="${anchor_refs[$idx]}"
  anchor="${anchor_tokens[$idx]}"
  if ! grep -q -F "$anchor" "$ROOT/$ref"; then
    fail "AC-NEG1: $ref missing load-bearing anchor token '$anchor' (thin SKILL appears to have orphaned the schema)"
  fi
done

# --- AC-NEG1 (T4 docs-health) — runner script remains pure aggregator. ----
# A regression where the runner silently grows mutation capability (e.g.
# someone adds gh-pr-merge or sync-to-polaris callsites) would defeat the
# runner-first thin contract by smuggling authority back into the runner.
RUNNER_SH="$ROOT/scripts/auto-pass-runner.sh"
runner_forbidden=(
  "sync-to-polaris.sh"
  "mark-spec-implemented.sh"
  "polaris-pr-create.sh"
)
for token in "${runner_forbidden[@]}"; do
  if grep -q -F "$token" "$RUNNER_SH"; then
    fail "AC-NEG1: runner script references mutation helper '$token' — runner must stay a pure aggregator"
  fi
done

printf 'PASS: auto-pass thin-skill selftest (%s lines, budget %s, docs-health OK)\n' \
  "$ACTUAL_LINES" "$MAX_LINES"
