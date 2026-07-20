#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-360-T11 — friction→DP intake scanner
#          (scripts/friction-to-dp-intake.sh). Asserts:
#   - CONVERTED ledger（sibling report.follow_up_dp_seed 非 null）的 friction
#     entry 不出現在 intake output。
#   - UN-CONVERTED ledger（report.follow_up_dp_seed: null、或無 sibling report）的
#     friction entry 必出現。
#   - 空 friction_log[] 的 ledger 不貢獻任何 entry。
#   - text header（friction-intake unconverted=N ledgers-scanned=M）+ per-entry
#     line（INTAKE source=... ledger=... ts=... kind=... summary=...）格式。
#   - --json mode shape（unconverted / ledgers_scanned / entries[]）。
#   - archived-DP / archived-company ledger（design-plans/archive/DP-*、
#     companies/*/archive/*）的 UN-CONVERTED friction 仍進入 intake（DP-393 T3 AC4/AC5/
#     AC-NEG3）；archived 且已 seed（EC5）維持 CONVERTED 隱藏；active-DP 行為不變。
#   - idempotency：兩次執行 byte-identical。
#   - fail-closed negative：壞 ledger JSON → POLARIS_LEDGER_MALFORMED + exit 2；
#     --root 與 --ledger 互斥 → exit 2。
# Inputs:  none（CLI args 忽略）。建構 mktemp 內的 DP-* container fixture tree。
# Outputs: stdout pass=N fail=M；exit 0 = 全 PASS，非 0 = 有 fail。
# Side effects: 僅 tmpdir（trap-removed）；不碰 live workspace、不改 git state。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCANNER="$ROOT/scripts/friction-to-dp-intake.sh"

TMPROOT="$(mktemp -d -t friction-to-dp-intake-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
TOTAL=0

_assert_contains() {
  # Args: $1 = haystack  $2 = needle  $3 = label
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$2" <<< "$1"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL %d] %s: substring not found: %q\n' "$TOTAL" "$3" "$2" >&2
    printf '       in: %s\n' "$1" >&2
  fi
}

_assert_not_contains() {
  # Args: $1 = haystack  $2 = needle  $3 = label
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$2" <<< "$1"; then
    FAIL=$((FAIL + 1))
    printf '[FAIL %d] %s: substring should NOT appear: %q\n' "$TOTAL" "$3" "$2" >&2
    printf '       in: %s\n' "$1" >&2
  else
    PASS=$((PASS + 1))
  fi
}

_assert_eq() {
  # Args: $1 = actual  $2 = expected  $3 = label
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL %d] %s: expected=%q got=%q\n' "$TOTAL" "$3" "$2" "$1" >&2
  fi
}

# Args: $1 = ledger path  $2 = friction_log JSON array literal
write_ledger() {
  local path="$1" friction="$2"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
{
  "schema_version": 1,
  "friction_log": $friction
}
EOF
}

# Args: $1 = report path  $2 = follow_up_dp_seed JSON literal (null or object)
write_report() {
  local path="$1" seed="$2"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
{
  "schema_version": 1,
  "terminal_status": "complete",
  "follow_up_dp_seed": $seed
}
EOF
}

# ---------------------------------------------------------------------------
# Build a fixture workspace with the DP-* container layout under
# docs-manager/src/content/docs/specs/design-plans/.
# ---------------------------------------------------------------------------
WS="$TMPROOT/ws"
SPECS="$WS/docs-manager/src/content/docs/specs"
DP="$SPECS/design-plans"

# (a) CONVERTED: friction entries + sibling report with follow_up_dp_seed populated.
write_ledger "$DP/DP-901-converted/artifacts/auto-pass/20260101-000000-ledger.json" \
  '[{"ts":"2026-01-01T00:00:00Z","stage":"engineering","friction_kind":"manual_artifact_patch","summary":"converted-friction-A"}]'
write_report "$DP/DP-901-converted/artifacts/auto-pass/20260101-000000-report.json" \
  '{"path":"docs-manager/src/content/docs/specs/design-plans/DP-901-follow-up/index.md","reason":"manual_items","source_report":"/abs/report.json","framework_gap":false}'

# (b) UN-CONVERTED: friction entries + sibling report with follow_up_dp_seed: null.
write_ledger "$DP/DP-902-unconverted/artifacts/auto-pass/20260202-000000-ledger.json" \
  '[{"ts":"2026-02-02T00:00:00Z","stage":"breakdown","friction_kind":"deterministic_gap","summary":"unconverted-friction-B which is a fairly long summary string designed to exceed the eighty character truncation boundary for sure"}]'
write_report "$DP/DP-902-unconverted/artifacts/auto-pass/20260202-000000-report.json" \
  'null'

# (b2) UN-CONVERTED: friction entries with NO sibling report at all.
write_ledger "$DP/DP-903-noreport/artifacts/auto-pass/20260303-000000-ledger.json" \
  '[{"ts":"2026-03-03T00:00:00Z","stage":"verify-AC","friction_kind":"env_bypass","summary":"unconverted-friction-C"}]'

# (c) EMPTY friction_log: contributes nothing.
write_ledger "$DP/DP-904-empty/artifacts/auto-pass/20260404-000000-ledger.json" '[]'
write_report "$DP/DP-904-empty/artifacts/auto-pass/20260404-000000-report.json" 'null'

# ===========================================================================
# Case 1 — text mode: CONVERTED hidden, UN-CONVERTED shown, empty contributes 0.
# ===========================================================================
TEXT_OUT="$(bash "$SCANNER" --root "$WS" 2>&1)" && T_EXIT=0 || T_EXIT=$?
_assert_eq "$T_EXIT" "0" "text mode exits 0 (reporter, not gate)"

# 4 ledgers scanned (901,902,903,904); unconverted entries = B + C = 2.
_assert_contains "$TEXT_OUT" "friction-intake unconverted=2 ledgers-scanned=4" \
  "text header reports unconverted=2 ledgers-scanned=4"
_assert_contains "$TEXT_OUT" "INTAKE source=DP-902-unconverted ledger=20260202-000000-ledger.json ts=2026-02-02T00:00:00Z kind=deterministic_gap summary=" \
  "UN-CONVERTED entry B appears with full per-entry shape"
_assert_contains "$TEXT_OUT" "INTAKE source=DP-903-noreport" \
  "UN-CONVERTED entry C (no sibling report) appears"
_assert_not_contains "$TEXT_OUT" "converted-friction-A" \
  "CONVERTED ledger friction does NOT appear"
_assert_not_contains "$TEXT_OUT" "DP-904-empty" \
  "empty friction_log contributes no intake line"

# summary truncated to 80 chars: the long B summary's tail must be absent.
_assert_not_contains "$TEXT_OUT" "eighty character truncation boundary for sure" \
  "summary truncated at 80 chars (tail dropped)"
_assert_contains "$TEXT_OUT" "summary=unconverted-friction-B which is a fairly long summary string designed to exc" \
  "summary head retained up to 80 chars"

# ===========================================================================
# Case 2 — --json mode shape.
# ===========================================================================
JSON_OUT="$(bash "$SCANNER" --root "$WS" --json 2>&1)" && J_EXIT=0 || J_EXIT=$?
_assert_eq "$J_EXIT" "0" "json mode exits 0"

J_UNCONV="$(printf '%s' "$JSON_OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin)["unconverted"])')"
J_SCANNED="$(printf '%s' "$JSON_OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ledgers_scanned"])')"
J_FIRST_SRC="$(printf '%s' "$JSON_OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin)["entries"][0]["source"])')"
J_FIRST_KIND="$(printf '%s' "$JSON_OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin)["entries"][0]["kind"])')"
_assert_eq "$J_UNCONV" "2" "json unconverted=2"
_assert_eq "$J_SCANNED" "4" "json ledgers_scanned=4"
_assert_eq "$J_FIRST_SRC" "DP-902-unconverted" "json entries sorted by source id (DP-902 first)"
_assert_eq "$J_FIRST_KIND" "deterministic_gap" "json entry carries friction_kind"
# CONVERTED friction must not leak into json entries either.
_assert_not_contains "$JSON_OUT" "converted-friction-A" "json mode also hides CONVERTED friction"

# ===========================================================================
# Case 3 — idempotency: two text runs byte-identical.
# ===========================================================================
RUN1="$(bash "$SCANNER" --root "$WS" 2>&1)"
RUN2="$(bash "$SCANNER" --root "$WS" 2>&1)"
_assert_eq "$RUN1" "$RUN2" "two consecutive runs are byte-identical (idempotent)"

# ===========================================================================
# Case 4 — --ledger single-ledger mode targets one file only.
# ===========================================================================
SINGLE_OUT="$(bash "$SCANNER" --ledger "$DP/DP-903-noreport/artifacts/auto-pass/20260303-000000-ledger.json" 2>&1)" && S_EXIT=0 || S_EXIT=$?
_assert_eq "$S_EXIT" "0" "--ledger mode exits 0"
_assert_contains "$SINGLE_OUT" "friction-intake unconverted=1 ledgers-scanned=1" \
  "--ledger scans exactly one ledger"
_assert_contains "$SINGLE_OUT" "INTAKE source=DP-903-noreport" "--ledger emits its entry"

# ===========================================================================
# Case 5 (fail-closed NEG) — malformed ledger JSON → POLARIS_LEDGER_MALFORMED + exit 2.
# ===========================================================================
BAD_WS="$TMPROOT/bad-ws"
BAD_LEDGER="$BAD_WS/docs-manager/src/content/docs/specs/design-plans/DP-905-bad/artifacts/auto-pass/20260505-000000-ledger.json"
mkdir -p "$(dirname "$BAD_LEDGER")"
printf '{ this is not valid json' >"$BAD_LEDGER"
BAD_OUT="$(bash "$SCANNER" --root "$BAD_WS" 2>&1)" && B_EXIT=0 || B_EXIT=$?
_assert_eq "$([[ "$B_EXIT" -eq 2 ]] && echo two || echo "$B_EXIT")" "two" \
  "malformed ledger fail-closed exit 2"
_assert_contains "$BAD_OUT" "POLARIS_LEDGER_MALFORMED" "malformed ledger emits POLARIS_LEDGER_MALFORMED"

# ===========================================================================
# Case 6 (fail-closed NEG) — --root and --ledger mutually exclusive → exit 2.
# ===========================================================================
EXCL_OUT="$(bash "$SCANNER" --root "$WS" --ledger "$BAD_LEDGER" 2>&1)" && E_EXIT=0 || E_EXIT=$?
_assert_eq "$([[ "$E_EXIT" -eq 2 ]] && echo two || echo "$E_EXIT")" "two" \
  "--root + --ledger fail-closed exit 2"
_assert_contains "$EXCL_OUT" "POLARIS_USAGE" "mutually-exclusive flags emit POLARIS_USAGE"

# ===========================================================================
# Case 7 (fail-closed NEG) — missing python3 surrogate → POLARIS_TOOL_MISSING.
# Run the scanner with a PATH that excludes python3 to exercise the fail-stop.
# ===========================================================================
EMPTY_BIN="$TMPROOT/empty-bin"
mkdir -p "$EMPTY_BIN"
# Provide the coreutils the scanner needs before the python3 check, but NOT python3.
for tool in bash sed command pwd dirname grep; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$EMPTY_BIN/$tool"
done
NOPY_OUT="$(PATH="$EMPTY_BIN" bash "$SCANNER" --root "$WS" 2>&1)" && N_EXIT=0 || N_EXIT=$?
_assert_eq "$([[ "$N_EXIT" -eq 2 ]] && echo two || echo "$N_EXIT")" "two" \
  "missing python3 fail-closed exit 2"
_assert_contains "$NOPY_OUT" "POLARIS_TOOL_MISSING:python3" \
  "missing python3 emits POLARIS_TOOL_MISSING with repair hint"

# ===========================================================================
# Case 8 (DP-393 T3) — archived-DP / archived-company ledgers still enter intake.
# A fresh fixture tree keeps the earlier exact-count assertions untouched. It mixes
# active + archived containers to prove the archive globs are additive (active-DP
# discovery unchanged) and source-symmetric (DP-backed + JIRA-Epic-backed archive).
# ===========================================================================
WS2="$TMPROOT/ws2"
SPECS2="$WS2/docs-manager/src/content/docs/specs"
DP2="$SPECS2/design-plans"
CO2="$SPECS2/companies"

# (a) ACTIVE DP, UN-CONVERTED — regression: adding archive globs must not drop active.
write_ledger "$DP2/DP-393-active/artifacts/auto-pass/20260601-000000-ledger.json" \
  '[{"ts":"2026-06-01T00:00:00Z","stage":"engineering","friction_kind":"manual_artifact_patch","summary":"active-dp-friction-K"}]'

# (b) ARCHIVED DP (DP-392-like), UN-CONVERTED — must appear in intake (AC4/AC5/AC-NEG3).
#     No sibling report → not converted; models release-cleanup friction stranded in
#     an archived ledger.
write_ledger "$DP2/archive/DP-392-release-cleanup/artifacts/auto-pass/20260602-000000-ledger.json" \
  '[{"ts":"2026-06-02T00:00:00Z","stage":"framework-release","friction_kind":"deterministic_gap","summary":"archived-dp392-cleanup-friction-L"}]'

# (c) ARCHIVED DP already seeded (EC5) — sibling report.follow_up_dp_seed non-null →
#     stays CONVERTED and hidden even inside archive/.
write_ledger "$DP2/archive/DP-392-seeded/artifacts/auto-pass/20260603-000000-ledger.json" \
  '[{"ts":"2026-06-03T00:00:00Z","stage":"framework-release","friction_kind":"deterministic_gap","summary":"archived-dp392-seeded-friction-M"}]'
write_report "$DP2/archive/DP-392-seeded/artifacts/auto-pass/20260603-000000-report.json" \
  '{"path":"docs-manager/src/content/docs/specs/design-plans/DP-393-follow-up/index.md","reason":"manual_items","source_report":"/abs/report.json","framework_gap":true}'

# (d) ARCHIVED company (JIRA-Epic-backed) ledger, UN-CONVERTED — source-parity: the
#     archive glob must catch companies/*/archive/* too, not just DP-backed archive.
write_ledger "$CO2/exampleco/archive/EXAMPLE-999/artifacts/auto-pass/20260604-000000-ledger.json" \
  '[{"ts":"2026-06-04T00:00:00Z","stage":"verify-AC","friction_kind":"env_bypass","summary":"archived-company-friction-N"}]'

ARC_OUT="$(bash "$SCANNER" --root "$WS2" 2>&1)" && A_EXIT=0 || A_EXIT=$?
_assert_eq "$A_EXIT" "0" "archived-fixture scan exits 0"

# 4 ledgers scanned (active DP + 2 archived DP + 1 archived company); unconverted = K+L+N.
_assert_contains "$ARC_OUT" "friction-intake unconverted=3 ledgers-scanned=4" \
  "archived globs additive: 4 scanned, 3 unconverted"
_assert_contains "$ARC_OUT" "INTAKE source=DP-392-release-cleanup" \
  "archived-DP UN-CONVERTED friction enters intake (AC4/AC5/AC-NEG3)"
_assert_contains "$ARC_OUT" "archived-dp392-cleanup-friction-L" \
  "archived-DP friction summary present in intake output"
_assert_contains "$ARC_OUT" "INTAKE source=EXAMPLE-999" \
  "archived-company (JIRA-Epic) friction enters intake (source parity)"
_assert_contains "$ARC_OUT" "INTAKE source=DP-393-active" \
  "active-DP discovery unchanged by archive globs (regression)"
_assert_not_contains "$ARC_OUT" "archived-dp392-seeded-friction-M" \
  "archived + seeded (EC5) stays CONVERTED, hidden from intake"

# json mode over the same archived tree keeps the seeded friction hidden as well.
ARC_JSON="$(bash "$SCANNER" --root "$WS2" --json 2>&1)" && AJ_EXIT=0 || AJ_EXIT=$?
_assert_eq "$AJ_EXIT" "0" "archived-fixture json mode exits 0"
_assert_not_contains "$ARC_JSON" "archived-dp392-seeded-friction-M" \
  "json mode also hides archived + seeded CONVERTED friction"

# ---------------------------------------------------------------------------
printf '\npass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
