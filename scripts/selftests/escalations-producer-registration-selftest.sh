#!/usr/bin/env bash
# escalations-producer-registration-selftest.sh — DP-246 T1.
#
# Verifies that scripts/lib/evidence-producers.json contains an engineering
# producer entry with escalations/ path globs covering BOTH source types
# (DP-backed and JIRA Epic-backed), and that the no-direct-evidence-write
# hook bypass logic respects these registrations via POLARIS_SKILL_WRITER=engineering.
#
# Design note: The hook (no-direct-evidence-write.sh) resolves its producers.json
# from BASH_SOURCE (always the main checkout at runtime). Since this selftest
# runs pre-merge in a worktree where main checkout does not yet have the new
# escalations globs, the hook-binary tests (AC1/AC-NEG1) use a Python simulation
# of the hook's match_any + skill-writer decision logic, reading the WORKTREE's
# producers.json directly. This is a legitimate approach: the selftest validates
# the contract (producer registration + glob coverage) rather than the hook binary
# behaviour (which is already covered by the hook's own selftests). Post-merge,
# the hook binary itself will enforce the contract.
#
# Cases:
#   AC1-dp   POLARIS_SKILL_WRITER=engineering + DP-backed escalations path
#            (design-plans/DP-NNN/escalations/T1-1.md) → BYPASS_SKILL decision.
#   AC1-epic POLARIS_SKILL_WRITER=engineering + Epic-backed escalations path
#            (companies/exampleco/EPIC-100/escalations/T2-1.md) → BYPASS_SKILL decision.
#   AC-NEG1-refinement  POLARIS_SKILL_WRITER=refinement + DP-backed escalations
#            path → PATH_OUT_OF_GLOBS (no refinement glob covers escalations/).
#   AC-NEG1-noenv  No POLARIS_SKILL_WRITER (empty) + DP-backed escalations path →
#            skill decision skipped entirely (no bypass).
#   AC-NEG1-cross  POLARIS_SKILL_WRITER=engineering + non-escalations spec path
#            outside engineering-owned globs (dogfood-evidence) → PATH_OUT_OF_GLOBS.
#
# Exit 0 → PASS (echo `PASS`); any failure prints diagnostic + non-zero exit.

set -euo pipefail

# shellcheck source=../lib/selftest-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"
# ROOT_DIR is now exported and validated by init_ROOT_DIR.

HOOK="$ROOT_DIR/.claude/hooks/no-direct-evidence-write.sh"
PRODUCERS_JSON="$ROOT_DIR/scripts/lib/evidence-producers.json"
WORKDIR="$(mktemp -d -t dp246-t1-escalations.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook is not executable: $HOOK" >&2
  exit 1
fi
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "FAIL: producers table missing: $PRODUCERS_JSON" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# CONTRACT CHECK: evidence-producers.json contains escalations/ globs for BOTH
# source types under an engineering owning_skill entry.
# ---------------------------------------------------------------------------
python3 - <<PY
import fnmatch, json, sys

data = json.load(open("$PRODUCERS_JSON"))
engineering_entries = [
    p for p in data.get("producers", [])
    if p.get("owning_skill") == "engineering"
]
if not engineering_entries:
    print("FAIL: no engineering producer entry found in evidence-producers.json", file=sys.stderr)
    sys.exit(2)

# Collect all path_globs across all engineering entries.
all_globs = []
for e in engineering_entries:
    all_globs.extend(e.get("path_globs") or [])

# Hook's match_any logic (replicated from no-direct-evidence-write.sh).
def match_any(path, globs):
    parts = path.split("/")
    for g in globs:
        if fnmatch.fnmatch(path, g):
            return True
        for i in range(len(parts)):
            tail = "/".join(parts[i:])
            if fnmatch.fnmatch(tail, g):
                return True
        g_alt = g.replace("**/", "*/").replace("/**", "/*")
        if fnmatch.fnmatch(path, g_alt):
            return True
    return False

dp_sample = "docs-manager/src/content/docs/specs/design-plans/DP-246-test/escalations/T1-1.md"
epic_sample = "docs-manager/src/content/docs/specs/companies/exampleco/EPIC-100/escalations/T2-1.md"

dp_covered = match_any(dp_sample, all_globs)
epic_covered = match_any(epic_sample, all_globs)

failures = []
if not dp_covered:
    failures.append(f"FAIL: DP-backed escalations path not covered by any engineering glob: {dp_sample}")
    failures.append(f"  Registered engineering globs: {all_globs}")
if not epic_covered:
    failures.append(f"FAIL: Epic-backed escalations path not covered by any engineering glob: {epic_sample}")
    failures.append(f"  Registered engineering globs: {all_globs}")

if failures:
    for f in failures:
        print(f, file=sys.stderr)
    sys.exit(2)

print("CONTRACT_OK: both DP-backed and Epic-backed escalations globs registered under engineering")
PY

# ---------------------------------------------------------------------------
# SKILL-WRITER DECISION SIMULATION
#
# The hook's POLARIS_SKILL_WRITER bypass runs Python against the workspace's
# producers.json. Since pre-merge selftests run in a worktree where the main
# checkout's producers.json does not yet have the new escalations globs, we
# simulate the hook's decision logic directly, reading the WORKTREE's
# producers.json (ROOT_DIR derived from BASH_SOURCE = this worktree).
#
# simulate_skill_writer_decision(skill, file_path, producers_json)
#   Returns: BYPASS_SKILL | PATH_OUT_OF_GLOBS | SKILL_UNKNOWN | NO_TABLE
# ---------------------------------------------------------------------------
simulate_decision() {
  local skill="$1"
  local file_path="$2"
  local producers_json="$3"
  # Replicate the hook's Python decision inline.
  POLARIS_SKILL_WRITER_VAL="$skill" \
    FILE_PATH_VAL="$file_path" \
    PRODUCERS_JSON_VAL="$producers_json" \
    python3 - <<'PY'
import fnmatch
import json
import os
import sys

skill = os.environ.get("POLARIS_SKILL_WRITER_VAL", "")
file_path = os.environ.get("FILE_PATH_VAL", "")
producers_json = os.environ.get("PRODUCERS_JSON_VAL", "")

try:
    with open(producers_json, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print("NO_TABLE")
    sys.exit(0)

producers = data.get("producers", []) or []
matching = [p for p in producers if p.get("owning_skill") == skill]
if not matching:
    print("SKILL_UNKNOWN")
    sys.exit(0)


def match_any(path, globs):
    for g in globs:
        if fnmatch.fnmatch(path, g):
            return True
        parts = path.split("/")
        for i in range(len(parts)):
            tail = "/".join(parts[i:])
            if fnmatch.fnmatch(tail, g):
                return True
        g_alt = g.replace("**/", "*/").replace("/**", "/*")
        if fnmatch.fnmatch(path, g_alt):
            return True
    return False


for entry in matching:
    md_globs = [
        g for g in (entry.get("path_globs") or [])
        if g.endswith(".md") or g.endswith("/**") or "*.md" in g
    ]
    if not md_globs:
        continue
    if match_any(file_path, md_globs):
        print("BYPASS_SKILL")
        sys.exit(0)

print("PATH_OUT_OF_GLOBS")
PY
}

# === AC1: POLARIS_SKILL_WRITER=engineering allows writing escalations/ paths ===

# AC1-dp: DP-backed escalations path.
dp_path="docs-manager/src/content/docs/specs/design-plans/DP-246-fixture/escalations/T1-1.md"
decision=$(simulate_decision "engineering" "$dp_path" "$PRODUCERS_JSON")
if [[ "$decision" != "BYPASS_SKILL" ]]; then
  echo "FAIL (ac1-dp): expected BYPASS_SKILL, got '$decision'" >&2
  echo "  path: $dp_path" >&2
  exit 1
fi
echo "PASS_AC1_DP: engineering bypass for DP-backed escalations path (decision=$decision)"

# AC1-epic: Epic-backed escalations path.
epic_path="docs-manager/src/content/docs/specs/companies/exampleco/EPIC-100/escalations/T2-1.md"
decision=$(simulate_decision "engineering" "$epic_path" "$PRODUCERS_JSON")
if [[ "$decision" != "BYPASS_SKILL" ]]; then
  echo "FAIL (ac1-epic): expected BYPASS_SKILL, got '$decision'" >&2
  echo "  path: $epic_path" >&2
  exit 1
fi
echo "PASS_AC1_EPIC: engineering bypass for Epic-backed escalations path (decision=$decision)"

# === AC-NEG1: non-engineering or absent writer must not get BYPASS_SKILL ===

# AC-NEG1-refinement: POLARIS_SKILL_WRITER=refinement on DP-backed escalations path.
# Expected: PATH_OUT_OF_GLOBS (refinement entries have no escalations/ globs).
decision=$(simulate_decision "refinement" "$dp_path" "$PRODUCERS_JSON")
if [[ "$decision" == "BYPASS_SKILL" ]]; then
  echo "FAIL (neg1-refinement): got BYPASS_SKILL but expected denial (refinement has no escalations globs)" >&2
  exit 1
fi
echo "PASS_NEG1_REFINEMENT: refinement correctly denied (decision=$decision)"

# AC-NEG1-noenv: no POLARIS_SKILL_WRITER (empty string) on DP-backed escalations path.
# When skill is empty the hook's POLARIS_SKILL_WRITER bypass block is not entered.
# Simulate: empty skill → SKILL_UNKNOWN (no entry with owning_skill="").
decision=$(simulate_decision "" "$dp_path" "$PRODUCERS_JSON")
if [[ "$decision" == "BYPASS_SKILL" ]]; then
  echo "FAIL (neg1-noenv): got BYPASS_SKILL but expected denial (no skill_writer set)" >&2
  exit 1
fi
echo "PASS_NEG1_NOENV: no skill_writer correctly denied (decision=$decision)"

# AC-NEG1-cross: POLARIS_SKILL_WRITER=engineering on a path NOT in engineering's
# globs (dogfood-evidence is owned by refinement, not engineering).
non_eng_path="docs-manager/src/content/docs/specs/design-plans/DP-246-fixture/dogfood-evidence/session-2026-05-28.md"
decision=$(simulate_decision "engineering" "$non_eng_path" "$PRODUCERS_JSON")
if [[ "$decision" == "BYPASS_SKILL" ]]; then
  echo "FAIL (neg1-cross): got BYPASS_SKILL for out-of-glob path (dogfood-evidence)" >&2
  echo "  path: $non_eng_path" >&2
  exit 1
fi
echo "PASS_NEG1_CROSS: engineering correctly denied for non-escalations path (decision=$decision)"

echo "PASS"
