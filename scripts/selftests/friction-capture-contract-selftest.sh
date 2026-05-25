#!/usr/bin/env bash
# friction-capture-contract-selftest.sh — DP-230-T1 (D14)
#
# Verifies the canonical friction capture contract reference is wired into
# auto-pass / framework-release / auto-pass-ledger surfaces.
#
# Contract (AC10):
#   - .claude/skills/references/friction-capture-contract.md exists
#   - line count of friction-capture-contract.md <= 400
#   - .claude/skills/auto-pass/SKILL.md references friction-capture-contract.md
#   - .claude/skills/framework-release/SKILL.md references friction-capture-contract.md
#     AND contains the "## Friction Capture during release tail" section
#   - .claude/skills/references/auto-pass-ledger.md references friction-capture-contract.md
#   - .claude/skills/references/INDEX.md lists friction-capture-contract.md
#   - Missing wiring on any surface fails with stderr token
#     POLARIS_FRICTION_CAPTURE_WIRING_MISSING
#
# Exit: 0 PASS, non-zero FAIL.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACT="$ROOT/.claude/skills/references/friction-capture-contract.md"
AUTO_PASS_SKILL="$ROOT/.claude/skills/auto-pass/SKILL.md"
FRAMEWORK_RELEASE_SKILL="$ROOT/.claude/skills/framework-release/SKILL.md"
LEDGER_REF="$ROOT/.claude/skills/references/auto-pass-ledger.md"
INDEX_REF="$ROOT/.claude/skills/references/INDEX.md"

TOKEN="POLARIS_FRICTION_CAPTURE_WIRING_MISSING"

# Embedded contract checker: given a fixture root, verify all wiring constraints.
# Emits stderr with TOKEN + missing list on failure.
check_wiring() {
  local fixture_root="$1"
  local contract="$fixture_root/.claude/skills/references/friction-capture-contract.md"
  local auto_pass="$fixture_root/.claude/skills/auto-pass/SKILL.md"
  local frel="$fixture_root/.claude/skills/framework-release/SKILL.md"
  local ledger="$fixture_root/.claude/skills/references/auto-pass-ledger.md"
  local index="$fixture_root/.claude/skills/references/INDEX.md"
  local missing=()

  if [[ ! -f "$contract" ]]; then
    missing+=("contract_reference_missing:$contract")
  else
    local line_count
    line_count="$(wc -l <"$contract" | tr -d ' ')"
    if (( line_count > 400 )); then
      missing+=("contract_reference_too_long:${line_count}>400")
    fi
  fi

  for surface_pair in \
      "auto_pass_skill_no_xlink:$auto_pass" \
      "framework_release_skill_no_xlink:$frel" \
      "auto_pass_ledger_no_xlink:$ledger" \
      "references_index_no_entry:$index"; do
    local label="${surface_pair%%:*}"
    local path="${surface_pair#*:}"
    if [[ ! -f "$path" ]]; then
      missing+=("${label}:file_missing:$path")
      continue
    fi
    if ! grep -q "friction-capture-contract" "$path"; then
      missing+=("${label}:$path")
    fi
  done

  if [[ -f "$frel" ]]; then
    if ! grep -q '^## Friction Capture during release tail' "$frel"; then
      missing+=("framework_release_skill_no_section:$frel")
    fi
  fi

  if (( ${#missing[@]} > 0 )); then
    echo "$TOKEN: ${missing[*]}" >&2
    return 1
  fi
  return 0
}

TMP="$(mktemp -d -t friction-capture-contract-XXXX)"
trap 'rm -rf "$TMP"' EXIT

# --- Broken fixture: missing contract file ---
BROKEN="$TMP/broken"
mkdir -p \
  "$BROKEN/.claude/skills/references" \
  "$BROKEN/.claude/skills/auto-pass" \
  "$BROKEN/.claude/skills/framework-release"
cat >"$BROKEN/.claude/skills/auto-pass/SKILL.md" <<'MD'
# auto-pass fixture
no friction wiring
MD
cat >"$BROKEN/.claude/skills/framework-release/SKILL.md" <<'MD'
# framework-release fixture
no friction wiring
MD
cat >"$BROKEN/.claude/skills/references/auto-pass-ledger.md" <<'MD'
# ledger fixture
no friction wiring
MD
cat >"$BROKEN/.claude/skills/references/INDEX.md" <<'MD'
# index fixture
no friction wiring
MD

if check_wiring "$BROKEN" 2>"$TMP/broken.err"; then
  echo "FAIL: broken fixture should not pass wiring check" >&2
  exit 1
fi
if ! grep -q "$TOKEN" "$TMP/broken.err"; then
  echo "FAIL: broken fixture missing token $TOKEN in stderr" >&2
  cat "$TMP/broken.err" >&2
  exit 1
fi

# --- Fixed fixture: full wiring present ---
FIXED="$TMP/fixed"
mkdir -p \
  "$FIXED/.claude/skills/references" \
  "$FIXED/.claude/skills/auto-pass" \
  "$FIXED/.claude/skills/framework-release"
cat >"$FIXED/.claude/skills/references/friction-capture-contract.md" <<'MD'
# friction-capture-contract fixture
canonical reference fixture
MD
cat >"$FIXED/.claude/skills/auto-pass/SKILL.md" <<'MD'
# auto-pass fixture
see .claude/skills/references/friction-capture-contract.md
MD
cat >"$FIXED/.claude/skills/framework-release/SKILL.md" <<'MD'
# framework-release fixture

## Friction Capture during release tail
see .claude/skills/references/friction-capture-contract.md
MD
cat >"$FIXED/.claude/skills/references/auto-pass-ledger.md" <<'MD'
# ledger fixture
see friction-capture-contract.md
MD
cat >"$FIXED/.claude/skills/references/INDEX.md" <<'MD'
# index fixture
- friction-capture-contract.md
MD

if ! check_wiring "$FIXED" 2>"$TMP/fixed.err"; then
  echo "FAIL: fixed fixture should pass wiring check" >&2
  cat "$TMP/fixed.err" >&2
  exit 1
fi

# --- Oversize contract fixture ---
OVERSIZE="$TMP/oversize"
mkdir -p \
  "$OVERSIZE/.claude/skills/references" \
  "$OVERSIZE/.claude/skills/auto-pass" \
  "$OVERSIZE/.claude/skills/framework-release"
python3 -c "import sys; sys.stdout.write('\n'.join(['line %d' % i for i in range(420)]) + '\n')" \
  >"$OVERSIZE/.claude/skills/references/friction-capture-contract.md"
cat >"$OVERSIZE/.claude/skills/auto-pass/SKILL.md" <<'MD'
see friction-capture-contract.md
MD
cat >"$OVERSIZE/.claude/skills/framework-release/SKILL.md" <<'MD'
## Friction Capture during release tail
see friction-capture-contract.md
MD
cat >"$OVERSIZE/.claude/skills/references/auto-pass-ledger.md" <<'MD'
see friction-capture-contract.md
MD
cat >"$OVERSIZE/.claude/skills/references/INDEX.md" <<'MD'
friction-capture-contract.md
MD

if check_wiring "$OVERSIZE" 2>"$TMP/oversize.err"; then
  echo "FAIL: oversize fixture (>400 lines) should not pass wiring check" >&2
  exit 1
fi
if ! grep -q "contract_reference_too_long" "$TMP/oversize.err"; then
  echo "FAIL: oversize fixture stderr missing too_long signal" >&2
  cat "$TMP/oversize.err" >&2
  exit 1
fi

# --- Missing framework-release section fixture ---
NOSECTION="$TMP/nosection"
mkdir -p \
  "$NOSECTION/.claude/skills/references" \
  "$NOSECTION/.claude/skills/auto-pass" \
  "$NOSECTION/.claude/skills/framework-release"
cat >"$NOSECTION/.claude/skills/references/friction-capture-contract.md" <<'MD'
# friction-capture-contract fixture
MD
cat >"$NOSECTION/.claude/skills/auto-pass/SKILL.md" <<'MD'
see friction-capture-contract.md
MD
cat >"$NOSECTION/.claude/skills/framework-release/SKILL.md" <<'MD'
see friction-capture-contract.md (but section missing)
MD
cat >"$NOSECTION/.claude/skills/references/auto-pass-ledger.md" <<'MD'
see friction-capture-contract.md
MD
cat >"$NOSECTION/.claude/skills/references/INDEX.md" <<'MD'
friction-capture-contract.md
MD

if check_wiring "$NOSECTION" 2>"$TMP/nosection.err"; then
  echo "FAIL: no-section fixture should not pass wiring check" >&2
  exit 1
fi
if ! grep -q "framework_release_skill_no_section" "$TMP/nosection.err"; then
  echo "FAIL: no-section fixture stderr missing section signal" >&2
  cat "$TMP/nosection.err" >&2
  exit 1
fi

# --- Real (workspace) wiring check ---
if ! check_wiring "$ROOT" 2>"$TMP/real.err"; then
  echo "FAIL: live workspace wiring check failed" >&2
  cat "$TMP/real.err" >&2
  exit 1
fi

echo "PASS: DP-230-T1 friction-capture-contract wiring (4 surfaces + size guard)"
