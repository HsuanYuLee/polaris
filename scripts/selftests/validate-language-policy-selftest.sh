#!/usr/bin/env bash
# Purpose: DP-298 T3 selftest for validate-language-policy.sh json-fields mode.
#   Exercises the per-field language gate over refinement.json human-facing prose
#   fields (tasks[].title, tasks[].scope, acceptance_criteria[].text) against
#   hermetic tmpdir fixtures:
#     1. English tasks[].title under zh-TW → fail-closed, names tasks[0].title (AC3)
#     2. English tasks[].scope under zh-TW → fail-closed, names tasks[0].scope (AC3)
#     3. English acceptance_criteria[].text → fail-closed, names field path (AC3)
#     4. all-zh-TW document → PASS (AC4)
#     5. zh-TW prose wrapping backtick-quoted English identifiers → PASS, not
#        misflagged (AC-NEG2, inline-code strip heuristic reused)
#     6. advisory enforcement on an English field → findings printed, exit 0
#     7. non-zh workspace language → no enforcement, exit 0
#     8. invalid JSON → exit 2 usage/parse error
#   Also runs the legacy embedded artifact-mode selftest (LANGUAGE_POLICY_SELFTEST=1)
#   so this dedicated selftest stays the single manifest-declared entry point.
# Inputs:  none (builds fixtures in a tmpdir).
# Outputs: PASS/FAIL lines per case; exit 0 if all pass, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-language-policy.sh"

if [[ ! -f "$VALIDATOR" ]]; then
  echo "FAIL: validator missing: $VALIDATOR" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

# run_validator_jf <fixture> <enforcement> <stderr-file>; echoes exit code so the
# caller can capture it without tripping `set -e` on a non-zero return.
run_validator_jf() {
  local fixture="$1" enforcement="$2" errfile="$3" rc=0
  env -u LANGUAGE_POLICY_SELFTEST bash "$VALIDATOR" \
    "--$enforcement" --language zh-TW --mode json-fields "$fixture" \
    >/dev/null 2>"$errfile" || rc=$?
  printf '%s' "$rc"
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected, got $actual)" >&2
    fail=$((fail + 1))
  fi
}

assert_stderr_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "PASS: $label (stderr contains '$needle')"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (stderr missing '$needle')" >&2
    cat "$file" >&2
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Case 1 — AC3: English tasks[].title under zh-TW policy fails closed and names
# the offending field path.
# ---------------------------------------------------------------------------
cat >"$tmpdir/en-title.json" <<'JSON'
{
  "tasks": [
    {
      "title": "Add JSON field-aware mode to the language policy validator",
      "scope": "在 `validate-language-policy.sh` 新增 json-fields mode"
    }
  ],
  "acceptance_criteria": [
    {"text": "修改後執行驗證 → PASS"}
  ]
}
JSON
err1="$tmpdir/err1"
rc1=$(run_validator_jf "$tmpdir/en-title.json" blocking "$err1")
assert_exit "AC3 English tasks[].title fails closed" 1 "$rc1"
assert_stderr_contains "AC3 names tasks[0].title" "tasks[0].title" "$err1"

# ---------------------------------------------------------------------------
# Case 2 — AC3: English tasks[].scope under zh-TW policy fails closed and names
# the offending field path.
# ---------------------------------------------------------------------------
cat >"$tmpdir/en-scope.json" <<'JSON'
{
  "tasks": [
    {
      "title": "新增 json-fields mode",
      "scope": "Add a new validation mode that walks the json prose fields and reports each violation by its field path"
    }
  ],
  "acceptance_criteria": [
    {"text": "全 zh-TW pass"}
  ]
}
JSON
err2="$tmpdir/err2"
rc2=$(run_validator_jf "$tmpdir/en-scope.json" blocking "$err2")
assert_exit "AC3 English tasks[].scope fails closed" 1 "$rc2"
assert_stderr_contains "AC3 names tasks[0].scope" "tasks[0].scope" "$err2"

# ---------------------------------------------------------------------------
# Case 3 — AC3: English acceptance_criteria[].text under zh-TW policy fails
# closed and names the offending field path.
# ---------------------------------------------------------------------------
cat >"$tmpdir/en-ac.json" <<'JSON'
{
  "tasks": [
    {"title": "新增 mode", "scope": "在 `validate-language-policy.sh` 新增 mode"}
  ],
  "acceptance_criteria": [
    {"text": "編輯 `refinement.json` 後執行驗證流程 → PASS"},
    {"text": "Editing the title field must trigger a fail-closed violation that names the field path"}
  ]
}
JSON
err3="$tmpdir/err3"
rc3=$(run_validator_jf "$tmpdir/en-ac.json" blocking "$err3")
assert_exit "AC3 English acceptance_criteria[].text fails closed" 1 "$rc3"
assert_stderr_contains "AC3 names acceptance_criteria[1].text" "acceptance_criteria[1].text" "$err3"

# ---------------------------------------------------------------------------
# Case 4 — AC4: an all-zh-TW refinement.json document passes.
# ---------------------------------------------------------------------------
cat >"$tmpdir/all-zh.json" <<'JSON'
{
  "tasks": [
    {
      "title": "canonical 契約落地與 derived-md reader 盤點守門",
      "scope": "在 `canonical-contract-governance.md` 寫入 business gate 不得讀 derived view 的條文，並盤點所有讀取點"
    },
    {
      "title": "語言不變式前移：refinement.json prose 欄位 write-time 驗證",
      "scope": "對 `tasks[].title`、`tasks[].scope`、`acceptance_criteria[].text` 逐欄位驗 config 語言"
    }
  ],
  "acceptance_criteria": [
    {"text": "修改 `refinement.json` 的 `tasks[].title` 後執行驗證 → PASS"},
    {"text": "英文 `tasks[].title` fail-closed 並指名違規欄位路徑"}
  ]
}
JSON
err4="$tmpdir/err4"
rc4=$(run_validator_jf "$tmpdir/all-zh.json" blocking "$err4")
assert_exit "AC4 all-zh-TW document passes" 0 "$rc4"

# ---------------------------------------------------------------------------
# Case 5 — AC-NEG2: zh-TW prose that wraps multiple English technical
# identifiers in backticks must NOT be misflagged. Reuses the inline-code /
# code-token strip heuristic.
# ---------------------------------------------------------------------------
cat >"$tmpdir/inline-code.json" <<'JSON'
{
  "tasks": [
    {
      "title": "為 `validate-language-policy.sh` 加上 `--mode json-fields`",
      "scope": "逐欄位驗 `tasks[].title`、`tasks[].scope`、`acceptance_criteria[].text`，沿用 `INLINE_CODE_RE` strip heuristic 避免誤擋 `is_full_english_natural_language`"
    }
  ],
  "acceptance_criteria": [
    {"text": "英文 `tasks[].title` fail-closed 指名欄位；全 zh-TW pass；含 `inline-code` title 不誤擋（`AC-NEG2`）"}
  ]
}
JSON
err5="$tmpdir/err5"
rc5=$(run_validator_jf "$tmpdir/inline-code.json" blocking "$err5")
assert_exit "AC-NEG2 inline-code zh-TW prose not misflagged" 0 "$rc5"

# ---------------------------------------------------------------------------
# Case 6 — advisory enforcement on an English field: findings printed, exit 0.
# ---------------------------------------------------------------------------
err6="$tmpdir/err6"
rc6=$(run_validator_jf "$tmpdir/en-title.json" advisory "$err6")
assert_exit "advisory English field exits 0" 0 "$rc6"
assert_stderr_contains "advisory still reports the field" "tasks[0].title" "$err6"

# ---------------------------------------------------------------------------
# Case 7 — non-zh workspace language: json-fields mode does not enforce.
# ---------------------------------------------------------------------------
err7="$tmpdir/err7"
rc7=0
env -u LANGUAGE_POLICY_SELFTEST bash "$VALIDATOR" \
  --blocking --language en --mode json-fields "$tmpdir/en-title.json" \
  >/dev/null 2>"$err7" || rc7=$?
assert_exit "non-zh language disables json-fields enforcement" 0 "$rc7"

# ---------------------------------------------------------------------------
# Case 8 — invalid JSON: contract violation / parse error exits 2.
# ---------------------------------------------------------------------------
printf '{bad json' >"$tmpdir/broken.json"
err8="$tmpdir/err8"
rc8=0
env -u LANGUAGE_POLICY_SELFTEST bash "$VALIDATOR" \
  --blocking --language zh-TW --mode json-fields "$tmpdir/broken.json" \
  >/dev/null 2>"$err8" || rc8=$?
assert_exit "invalid JSON exits 2" 2 "$rc8"

# ---------------------------------------------------------------------------
# Case 9 — legacy artifact-mode selftest still passes (regression guard for the
# existing paragraph-based policy that this DP extends, not replaces).
# ---------------------------------------------------------------------------
err9="$tmpdir/err9"
rc9=0
LANGUAGE_POLICY_SELFTEST=1 bash "$VALIDATOR" >/dev/null 2>"$err9" || rc9=$?
assert_exit "legacy artifact-mode embedded selftest passes" 0 "$rc9"

echo "---"
echo "validate-language-policy json-fields selftest: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
