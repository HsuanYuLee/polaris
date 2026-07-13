#!/usr/bin/env bash
# Purpose: DP-417 T11 selftest for validate-spec-check-contract-parity.sh — the
#          bidirectional spec↔check contract parity gate. Exercises the gate against
#          hermetic fixture repos (copies of the real spec + validator files, mutated
#          per case) plus the live workspace:
#            1. live-green (AC14 / AC18) — gate PASSes on the real reconciled repo:
#               every validator hard-required author field is documented AND no
#               spec-required field is validator-forbidden (exit 0, regression guard).
#            2. neg8a (AC-NEG8 a) — a validator-required field (changed_files) removed
#               from the spec → fail-closed exit 2 + POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED.
#            3. neg8a-2 — predecessor_audit removed from both specs → same fail-closed.
#            4. neg8b (AC-NEG8 b) — a validator-FORBIDDEN packaging field (allowed_files)
#               re-declared "required" in the spec tasks[] enumeration → fail-closed
#               exit 2 + POLARIS_SPEC_CHECK_PARITY_CONTRADICTION.
#            5. anchor-stale (non-vacuous) — the live check anchor removed from a
#               validator → fail-closed exit 2 + POLARIS_SPEC_CHECK_PARITY_ANCHOR_STALE
#               (proves the parity manifest is tied to the real checks, not a static
#               grep that can silently drift).
# Inputs:  none (builds hermetic fixtures in a tmpdir; uses --repo-root so no env leak).
# Outputs: PASS/FAIL lines per case; exit 0 if all pass, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/validate-spec-check-contract-parity.sh"

if [[ ! -f "$GATE" ]]; then
  echo "FAIL: gate missing: $GATE" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

# Copy the real spec + validator files into a hermetic fixture root.
setup_fixture() {
  local dst="$1"
  mkdir -p "$dst/scripts" "$dst/.claude/skills/references"
  cp "$ROOT/scripts/validate-refinement-json.sh" "$dst/scripts/"
  cp "$ROOT/scripts/validate-refinement-artifact-parity.sh" "$dst/scripts/"
  cp "$ROOT/scripts/validate-breakdown-ready.sh" "$dst/scripts/"
  cp "$ROOT/.claude/skills/references/refinement-artifact.md" "$dst/.claude/skills/references/"
  cp "$ROOT/.claude/skills/references/pipeline-handoff.md" "$dst/.claude/skills/references/"
}

# run_case <name> <expected_exit> <expected_marker|-> <repo_root>
run_case() {
  local name="$1" expected_exit="$2" expected_marker="$3" repo_root="$4"
  local out rc
  set +e
  out="$(bash "$GATE" --repo-root "$repo_root" 2>&1)"
  rc=$?
  set -e
  local ok=1
  if [[ "$rc" -ne "$expected_exit" ]]; then
    ok=0
    echo "  expected exit $expected_exit, got $rc" >&2
  fi
  if [[ "$expected_marker" != "-" ]] && ! grep -q "$expected_marker" <<<"$out"; then
    ok=0
    echo "  expected marker '$expected_marker' not found in output" >&2
    echo "$out" | sed 's/^/    /' >&2
  fi
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name"
    fail=$((fail + 1))
  fi
}

# --- Case 1: live-green (AC14 / AC18 regression guard) ---
run_case "live-green (AC14/AC18 real repo consistent)" 0 "-" "$ROOT"

# --- Case 2: neg8a — validator-required changed_files missing from spec ---
fx_neg8a="$tmpdir/neg8a"
setup_fixture "$fx_neg8a"
python3 - "$fx_neg8a/.claude/skills/references/refinement-artifact.md" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
kept = [ln for ln in lines if "changed_files" not in ln]
open(p, "w", encoding="utf-8").write("".join(kept))
PY
run_case "neg8a (AC-NEG8a changed_files undocumented)" 2 "POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED" "$fx_neg8a"

# --- Case 3: neg8a-2 — predecessor_audit removed from BOTH specs ---
fx_pred="$tmpdir/pred"
setup_fixture "$fx_pred"
python3 - "$fx_pred/.claude/skills/references/refinement-artifact.md" "$fx_pred/.claude/skills/references/pipeline-handoff.md" <<'PY'
import sys
for p in sys.argv[1:]:
    lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
    kept = [ln for ln in lines if "predecessor_audit" not in ln]
    open(p, "w", encoding="utf-8").write("".join(kept))
PY
run_case "neg8a-2 (AC-NEG8a predecessor_audit undocumented)" 2 "POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED" "$fx_pred"

# --- Case 4: neg8b — spec re-declares allowed_files as required tasks[] field ---
fx_neg8b="$tmpdir/neg8b"
setup_fixture "$fx_neg8b"
python3 - "$fx_neg8b/.claude/skills/references/refinement-artifact.md" <<'PY'
import re
import sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
# Re-inject the DP-341-forbidden packaging field into the tasks[] 必填 enumeration
# (simulates a producer spec that contradicts the validator's PACKAGING_FORBIDDEN gate).
text = re.sub(
    r"(- `tasks\[\]`：每筆必填 `id` / `kind` / `title` / `scope` /)",
    r"\1 `allowed_files` /",
    text,
    count=1,
)
open(p, "w", encoding="utf-8").write(text)
PY
run_case "neg8b (AC-NEG8b allowed_files contradiction)" 2 "POLARIS_SPEC_CHECK_PARITY_CONTRADICTION" "$fx_neg8b"

# --- Case 4b: reverse contradiction #2 — source.base_branch re-marked jira-only ---
# DP-337 graduated source.base_branch to universal (dp == feat/<id>); a spec that
# re-declares it as a jira-only (dp-forbidden) field bullet contradicts the validator.
fx_base="$tmpdir/basebranch"
setup_fixture "$fx_base"
python3 - "$fx_base/.claude/skills/references/refinement-artifact.md" <<'PY'
import re
import sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
# Re-inject a jira-only defining bullet for source.base_branch right after source.repo.
text = re.sub(
    r"(  - `source\.repo`：產品 repo slug[^\n]*\n    `source\.type=jira` 時 \*\*required\*\*（derive jira mode → task\.md `Repo`）。\n)",
    r"\1  - `source.base_branch`：產品 base branch。`source.type=jira` 時 **required**。\n",
    text,
    count=1,
)
open(p, "w", encoding="utf-8").write(text)
PY
run_case "reverse #2 (AC18 source.base_branch jira-only contradiction)" 2 "POLARIS_SPEC_CHECK_PARITY_CONTRADICTION" "$fx_base"

# --- Case 5: anchor-stale — live check anchor removed from a validator ---
fx_anchor="$tmpdir/anchor"
setup_fixture "$fx_anchor"
python3 - "$fx_anchor/scripts/validate-refinement-artifact-parity.sh" <<'PY'
import sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
# Remove the live changed_files parity assertion; the manifest anchor must then fail.
text = text.replace("changed_files != module_paths", "DISABLED_ANCHOR")
open(p, "w", encoding="utf-8").write(text)
PY
run_case "anchor-stale (non-vacuous manifest↔check binding)" 2 "POLARIS_SPEC_CHECK_PARITY_ANCHOR_STALE" "$fx_anchor"

echo ""
echo "spec-check-contract-parity selftest: $pass pass, $fail fail"
[[ "$fail" -eq 0 ]]
