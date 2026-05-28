#!/usr/bin/env bash
# Selftest for DP-255 AC1 / AC2 / AC-NEG3 routing precision.
#
# This selftest is a Strategist-side fixture checker. It applies the canonical
# disambiguation rules from .claude/rules/skill-routing.md to a list of
# utterances and asserts the expected skill for each.
#
# The matcher is a deterministic Python script — same disambiguation
# heuristics that the Strategist applies in conversation:
#   1. If utterance mentions "大家的 PR" / "掃 PR" / "review inbox" → review-inbox
#   2. If utterance includes a PR URL + 修 / 沒修好 → engineering (revision)
#   3. If utterance has 催 review / 催 PR / 我的 PR / PR 狀態 → check-pr-approvals
#   4. If utterance has "請 <subject> (幫我) review" where subject ∈
#      {同仁, 大家, 人名/角色, 找人, 找誰} → check-pr-approvals
#   5. If utterance has "review" with subject = self / omitted → review-pr
#
# Exit:
#   0 — all rows route to the expected skill
#   2 — at least one row mismatched; stderr lists each mismatch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="${SCRIPT_DIR}/fixtures/skill-routing-utterances.tsv"

if [[ ! -f "$FIXTURE" ]]; then
  echo "FAIL: fixture missing: ${FIXTURE}" >&2
  exit 1
fi

python3 - "$FIXTURE" <<'PY'
import re
import sys

fixture_path = sys.argv[1]

# Patterns: each entry is (regex, skill). Order matters — first match wins.
RULES = [
    # AC-NEG3 sibling skills (most specific first)
    (re.compile(r"review\s*inbox|大家的\s*PR|掃\s*PR"), "review-inbox"),
    # engineering revision: explicit fix intent with PR URL
    (re.compile(r"(修(\s*PR)?|沒修好|fix\s*review|fix\s*PR).*https?://"), "engineering"),
    (re.compile(r"https?://.*(\s|$).*(修|沒修好|CI\s*沒過|CI\s*failed)"), "engineering"),
    # AC1 check-pr-approvals: 催 review keywords
    (re.compile(r"催\s*(review|PR)"), "check-pr-approvals"),
    (re.compile(r"我的\s*PR|PR\s*狀態"), "check-pr-approvals"),
    # AC1 check-pr-approvals: third-party subject before 幫我 review / review
    (re.compile(r"請\s*(同仁|大家|[一-鿿]{1,4})\s*(幫我\s*|幫忙\s*)?(看\s*一下\s*)?(code\s*)?review"), "check-pr-approvals"),
    # Also catch 請<subject>幫忙看一下 PR (no "review" keyword)
    (re.compile(r"請\s*(同仁|大家|[一-鿿]{1,4})\s*幫(我|忙)\s*(看\s*一下|看看)?\s*PR"), "check-pr-approvals"),
    (re.compile(r"找\s*(人|誰)\s*review"), "check-pr-approvals"),
    # AC2 review-pr: self-review (subject omitted or = self) with "review" + PR signal
    (re.compile(r"\b(review|看)\s*(這個|此|該)?\s*PR"), "review-pr"),
    (re.compile(r"幫我\s*review.*https?://"), "review-pr"),
    (re.compile(r"\breview\s+(這|此|該)"), "review-pr"),
    (re.compile(r"\breview\s+PR\b"), "review-pr"),
]

def classify(utterance: str) -> str:
    for pattern, skill in RULES:
        if pattern.search(utterance):
            return skill
    return "UNKNOWN"

failures = []
total = 0
with open(fixture_path, "r", encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
        line = raw.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        if "\t" not in line:
            failures.append((lineno, line, "MALFORMED", "expected tab-separated"))
            continue
        expected, utterance = line.split("\t", 1)
        expected = expected.strip()
        utterance = utterance.strip()
        if not expected or not utterance:
            failures.append((lineno, line, "MALFORMED", "empty field"))
            continue
        total += 1
        actual = classify(utterance)
        if actual != expected:
            failures.append((lineno, utterance, expected, actual))

if failures:
    sys.stderr.write(f"FAIL: skill-routing selftest — {len(failures)}/{total} mismatched:\n")
    for lineno, utt, expected, actual in failures:
        sys.stderr.write(f"  line {lineno}: '{utt}'\n")
        sys.stderr.write(f"    expected={expected} actual={actual}\n")
    sys.exit(2)

print(f"PASS: skill-routing-subject-aware selftest ({total} utterances)")
PY
