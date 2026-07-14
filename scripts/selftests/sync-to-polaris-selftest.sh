#!/usr/bin/env bash
# Purpose: DP-421 T3 / AC3 — selftest for the sync-to-polaris.sh release-surface
#          parity check. The GitHub release notes are a DERIVED VIEW of
#          CHANGELOG.md; per canonical-contract-governance § Derived Artifact Read
#          Boundary the business language gate must read the AUTHORITATIVE source
#          (the CHANGELOG version section), not the derived view. This asserts the
#          hermetic --check-release-notes-parity probe:
#            - conformant zh-TW CHANGELOG section  -> parity PASS (exit 0); the
#              mechanically-derived release notes pass by construction;
#            - tampered non-conformant (English) section -> parity FAIL (exit 1);
#            - version absent from CHANGELOG (nothing derived) -> PASS (exit 0).
# Inputs:  none (fixture CHANGELOG.md under a tmpdir; --language pinned for
#          determinism regardless of the ambient workspace language).
# Outputs: PASS/FAIL lines; exit 0 (all pass) / 1 (any fail).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC="$ROOT/scripts/sync-to-polaris.sh"
[[ -f "$SYNC" ]] || { echo "FAIL: missing: $SYNC" >&2; exit 1; }

TMP="$(mktemp -d -t sync-to-polaris-parity-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1" >&2; }

CHANGELOG="$TMP/CHANGELOG.md"
cat >"$CHANGELOG" <<'MD'
# Changelog

## [9.9.9] - 2026-07-14

- 新增 changeset body language gate（`scripts/gates/gate-changeset.sh`），release surface 改為 CHANGELOG 的 source-conformance / parity 檢查。

## [9.9.8] - 2026-07-13

- This is a tampered English changelog section that must fail the release-surface source parity gate at release time.
MD

probe() {
  local version="$1"
  bash "$SYNC" --check-release-notes-parity --version "$version" \
    --changelog "$CHANGELOG" --language zh-TW
}

# ── Scenario 1: conformant zh-TW CHANGELOG section -> parity PASS (exit 0) ──────
set +e
probe 9.9.9 >/dev/null 2>&1
rc1=$?
set -e
[[ "$rc1" -eq 0 ]] && ok "conformant zh-TW CHANGELOG section -> parity PASS (exit 0)" \
  || bad "conformant CHANGELOG section should PASS (exit 0); got exit $rc1"

# ── Scenario 2: tampered non-conformant (English) section -> parity FAIL (1) ────
set +e
probe 9.9.8 >/dev/null 2>&1
rc2=$?
set -e
[[ "$rc2" -eq 1 ]] && ok "tampered non-conformant CHANGELOG section -> parity FAIL (exit 1)" \
  || bad "tampered CHANGELOG section should FAIL (exit 1); got exit $rc2"

# ── Scenario 3: version absent from CHANGELOG (nothing derived) -> PASS (0) ─────
set +e
probe 0.0.0 >/dev/null 2>&1
rc3=$?
set -e
[[ "$rc3" -eq 0 ]] && ok "absent version (empty source section) -> parity PASS (exit 0)" \
  || bad "absent version should PASS trivially (exit 0); got exit $rc3"

echo ""
echo "[sync-to-polaris-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
