#!/usr/bin/env bash
# validate-script-categorization-selftest.sh — DP-240 D26 categorization
# gate selftest.
#
# Covers:
#   AC4   — shared callsite PASS; single-skill misplaced FAIL with marker
#           POLARIS_SCRIPT_MISPLACED:{path} -> {skill}/scripts/
#   AC7   — --mode diff blocks; --mode audit emits debt and exits 0
#   AC-NEG2 — generated targets (CLAUDE.md / AGENTS.md / .codex/AGENTS.md /
#           .github/copilot-instructions.md) are never flagged
#   EC3   — dynamic-invoke fixture in the exception allowlist is NOT
#           blocked, but only when the allowlist entry carries an owning
#           skill + reason (AC4 adversarial pass)
#
# Each case spins up a synthetic mini-repo under $tmpdir/caseN with the
# minimum surface area required by scripts/script-ownership-audit.py:
#   - scripts/manifest.json declaring the fixture under test
#   - scripts/<fixture>.sh (the candidate script)
#   - script-ownership-audit.py / .sh copied from the live repo (we just
#     point --root at the synthetic tree, so the audit walks scan roots
#     under that tree only).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/validate-script-categorization.sh"
AUDIT_PY="$ROOT/scripts/script-ownership-audit.py"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: validator missing: $SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$AUDIT_PY" ]]; then
  echo "FAIL: ownership audit script missing: $AUDIT_PY" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Helper: build a synthetic repo with the standard layout the audit
# scanner expects (scripts/, .claude/skills/, .claude/rules/).
build_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts" \
           "$repo/scripts/lib" \
           "$repo/.claude/skills" \
           "$repo/.claude/rules" \
           "$repo/.claude/hooks"
  cp "$AUDIT_PY" "$repo/scripts/script-ownership-audit.py"
  # The exception file is optional; cases that need it write their own.
}

write_manifest() {
  local repo="$1"
  shift
  # Remaining args are JSON rows separated by literal "%%".
  local rows=""
  for row in "$@"; do
    if [[ -n "$rows" ]]; then
      rows+=","
    fi
    rows+=$'\n    '"$row"
  done
  cat >"$repo/scripts/manifest.json" <<JSON
{
  "version": 1,
  "scripts": [${rows}
  ]
}
JSON
}

# ------------------------------------------------------------------
# Case 1 (AC4 / AC7): shared callsite PASSES in diff mode.
# ------------------------------------------------------------------
case1="$tmpdir/case1"
build_repo "$case1"
cp "$ROOT/scripts/fixtures/script-categorization/shared-callsite-sample.sh" \
   "$case1/scripts/shared.sh"
write_manifest "$case1" \
  '{"path": "scripts/shared.sh", "kind": "support", "runner": "bash", "owner_surface": "skill_or_reference", "selftest": "N/A", "selftest_reason": "fixture", "lifecycle": "support_path", "relocation": "stay"}'
mkdir -p "$case1/.claude/skills/alpha" "$case1/.claude/skills/beta"
printf 'See scripts/shared.sh\n' > "$case1/.claude/skills/alpha/SKILL.md"
printf 'See scripts/shared.sh\n' > "$case1/.claude/skills/beta/SKILL.md"
out1="$tmpdir/out1"
if ! bash "$SCRIPT" --root "$case1" --mode diff --file "scripts/shared.sh" \
    >"$out1" 2>&1; then
  echo "FAIL: case 1 — shared callsite (two skills) rejected" >&2
  cat "$out1" >&2
  exit 1
fi
if grep -q "POLARIS_SCRIPT_MISPLACED:" "$out1"; then
  echo "FAIL: case 1 — shared callsite produced unexpected misplaced marker" >&2
  cat "$out1" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 2 (AC4 / AC7 primary): single-skill misplaced FAILS diff mode
# with POLARIS_SCRIPT_MISPLACED marker pointing at .claude/skills/{skill}/scripts/.
# ------------------------------------------------------------------
case2="$tmpdir/case2"
build_repo "$case2"
cp "$ROOT/scripts/fixtures/script-categorization/single-skill-misplaced-sample.sh" \
   "$case2/scripts/misplaced.sh"
write_manifest "$case2" \
  '{"path": "scripts/misplaced.sh", "kind": "support", "runner": "bash", "owner_surface": "skill_or_reference", "selftest": "N/A", "selftest_reason": "fixture", "lifecycle": "support_path", "relocation": "stay"}'
mkdir -p "$case2/.claude/skills/onlyskill"
printf 'See scripts/misplaced.sh\n' > "$case2/.claude/skills/onlyskill/SKILL.md"
out2="$tmpdir/out2"
if bash "$SCRIPT" --root "$case2" --mode diff --file "scripts/misplaced.sh" \
    >"$out2" 2>&1; then
  echo "FAIL: case 2 — single-skill misplaced fixture incorrectly passed" >&2
  cat "$out2" >&2
  exit 1
fi
if ! grep -q "POLARIS_SCRIPT_MISPLACED:scripts/misplaced.sh -> .claude/skills/onlyskill/scripts/" \
    "$out2"; then
  echo "FAIL: case 2 — missing migration hint marker" >&2
  cat "$out2" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 3 (AC7): audit mode reports debt but exits 0.
# ------------------------------------------------------------------
case3="$tmpdir/case3"
build_repo "$case3"
cp "$ROOT/scripts/fixtures/script-categorization/single-skill-misplaced-sample.sh" \
   "$case3/scripts/legacy-misplaced.sh"
write_manifest "$case3" \
  '{"path": "scripts/legacy-misplaced.sh", "kind": "support", "runner": "bash", "owner_surface": "skill_or_reference", "selftest": "N/A", "selftest_reason": "fixture", "lifecycle": "support_path", "relocation": "stay"}'
mkdir -p "$case3/.claude/skills/legacyskill"
printf 'See scripts/legacy-misplaced.sh\n' > "$case3/.claude/skills/legacyskill/SKILL.md"
out3="$tmpdir/out3"
if ! bash "$SCRIPT" --root "$case3" --mode audit >"$out3" 2>&1; then
  echo "FAIL: case 3 — audit mode exited non-zero" >&2
  cat "$out3" >&2
  exit 1
fi
if ! grep -q "legacy-debt: scripts/legacy-misplaced.sh -> .claude/skills/legacyskill/scripts/" \
    "$out3"; then
  echo "FAIL: case 3 — audit did not report legacy-debt entry" >&2
  cat "$out3" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 4 (EC3 / AC4 adversarial): dynamic-invoke fixture, allowlisted
# with owner-skill + reason, must NOT be flagged.
# ------------------------------------------------------------------
case4="$tmpdir/case4"
build_repo "$case4"
cp "$ROOT/scripts/fixtures/script-categorization/dynamic-invoke-exception.sh" \
   "$case4/scripts/dynamic.sh"
write_manifest "$case4" \
  '{"path": "scripts/dynamic.sh", "kind": "support", "runner": "bash", "owner_surface": "skill_or_reference", "selftest": "N/A", "selftest_reason": "fixture", "lifecycle": "support_path", "relocation": "stay"}'
mkdir -p "$case4/.claude/skills/dynskill"
printf 'Invoked via bash "$resolved" — see scripts/dynamic.sh\n' \
  > "$case4/.claude/skills/dynskill/SKILL.md"
# Exception file with owner + reason.
exc4="$tmpdir/case4-exception.txt"
printf 'scripts/dynamic.sh\tdynskill\tDynamic invocation via runtime-resolved path; owner skill dispatches.\n' \
  > "$exc4"
out4="$tmpdir/out4"
if ! bash "$SCRIPT" --root "$case4" --mode diff \
    --file "scripts/dynamic.sh" --exception-file "$exc4" \
    >"$out4" 2>&1; then
  echo "FAIL: case 4 — exception allowlist did not honour valid entry" >&2
  cat "$out4" >&2
  exit 1
fi
if grep -q "POLARIS_SCRIPT_MISPLACED:" "$out4"; then
  echo "FAIL: case 4 — exception fixture still produced misplaced marker" >&2
  cat "$out4" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 5 (AC4 adversarial): exception entry missing the reason field is
# treated as malformed; fixture is still classified misplaced.
# ------------------------------------------------------------------
case5="$tmpdir/case5"
build_repo "$case5"
cp "$ROOT/scripts/fixtures/script-categorization/dynamic-invoke-exception.sh" \
   "$case5/scripts/dynamic-bare.sh"
write_manifest "$case5" \
  '{"path": "scripts/dynamic-bare.sh", "kind": "support", "runner": "bash", "owner_surface": "skill_or_reference", "selftest": "N/A", "selftest_reason": "fixture", "lifecycle": "support_path", "relocation": "stay"}'
mkdir -p "$case5/.claude/skills/bareonly"
printf 'See scripts/dynamic-bare.sh\n' > "$case5/.claude/skills/bareonly/SKILL.md"
exc5="$tmpdir/case5-exception.txt"
# Malformed: skill present but no reason. Should be ignored.
printf 'scripts/dynamic-bare.sh\tbareonly\t\n' > "$exc5"
out5="$tmpdir/out5"
if bash "$SCRIPT" --root "$case5" --mode diff \
    --file "scripts/dynamic-bare.sh" --exception-file "$exc5" \
    >"$out5" 2>&1; then
  echo "FAIL: case 5 — malformed exception entry let misplaced fixture pass" >&2
  cat "$out5" >&2
  exit 1
fi
if ! grep -q "POLARIS_SCRIPT_MISPLACED:" "$out5"; then
  echo "FAIL: case 5 — expected misplaced marker for malformed exception" >&2
  cat "$out5" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 6 (AC-NEG2): generated targets must never be flagged. We pass
# them through --file. They are .md (out of HOT_PATH_EXTS) so they
# should silently drop from scope and produce no marker.
# ------------------------------------------------------------------
case6="$tmpdir/case6"
build_repo "$case6"
write_manifest "$case6"
printf '# Bootstrap\n' > "$case6/CLAUDE.md"
printf '# Agents\n' > "$case6/AGENTS.md"
mkdir -p "$case6/.codex" "$case6/.github"
printf '# Codex\n' > "$case6/.codex/AGENTS.md"
printf '# Copilot\n' > "$case6/.github/copilot-instructions.md"
out6="$tmpdir/out6"
if ! bash "$SCRIPT" --root "$case6" --mode diff \
    --file "CLAUDE.md" --file "AGENTS.md" \
    --file ".codex/AGENTS.md" --file ".github/copilot-instructions.md" \
    >"$out6" 2>&1; then
  echo "FAIL: case 6 — generated target scan exited non-zero" >&2
  cat "$out6" >&2
  exit 1
fi
if grep -q "POLARIS_SCRIPT_MISPLACED:" "$out6"; then
  echo "FAIL: case 6 — generated target produced unexpected marker" >&2
  cat "$out6" >&2
  exit 1
fi

echo "PASS: validate-script-categorization selftest"
