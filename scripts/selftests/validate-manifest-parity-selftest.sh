#!/usr/bin/env bash
# validate-manifest-parity-selftest.sh — DP-230 D20 (AC16).
#
# Verifies scripts/validate-manifest-parity.sh:
#   * FAIL when scripts/manifest.json is missing an entry that exists on disk,
#     with stderr token `POLARIS_MANIFEST_MISSING: {path}`.
#   * PASS when manifest covers every scripts/*.sh / scripts/lib/*.py /
#     scripts/selftests/*.sh path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-manifest-parity.sh"

if [[ ! -x "$VALIDATOR" ]]; then
  echo "FAIL: validator missing or not executable: $VALIDATOR" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t validate-manifest-parity.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Build a synthetic workspace with three scripts across the AC16 globs and a
# minimal manifest that registers all three.
ws="$tmpdir/ws"
mkdir -p "$ws/scripts/lib" "$ws/scripts/selftests"
cat >"$ws/scripts/example.sh" <<'SH'
#!/usr/bin/env bash
echo example
SH
cat >"$ws/scripts/lib/example.py" <<'PY'
"""example helper"""
PY
cat >"$ws/scripts/selftests/example-selftest.sh" <<'SH'
#!/usr/bin/env bash
echo selftest
SH
chmod +x "$ws/scripts/example.sh" "$ws/scripts/selftests/example-selftest.sh"

cat >"$ws/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/example.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "script_internal",
      "selftest": "scripts/selftests/example-selftest.sh",
      "lifecycle": "support_path",
      "relocation": "stay"
    },
    {
      "path": "scripts/lib/example.py",
      "kind": "support",
      "runner": "python3",
      "owner_surface": "script_internal",
      "selftest": "N/A",
      "lifecycle": "support_path",
      "relocation": "stay",
      "selftest_reason": "library helper"
    },
    {
      "path": "scripts/selftests/example-selftest.sh",
      "kind": "selftest",
      "runner": "bash",
      "owner_surface": "selftest_suite",
      "selftest": "N/A",
      "lifecycle": "support_path",
      "relocation": "stay",
      "selftest_reason": "selftest script"
    }
  ]
}
JSON

# --- Case A: clean fixture → PASS ---
set +e
bash "$VALIDATOR" --root "$ws" --quiet >/tmp/validate-manifest-parity-clean.out 2>/tmp/validate-manifest-parity-clean.err
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: clean fixture expected exit 0, got $rc" >&2
  cat /tmp/validate-manifest-parity-clean.err >&2
  exit 1
fi

# --- Case B: remove a manifest entry → FAIL with POLARIS_MANIFEST_MISSING ---
python3 - "$ws/scripts/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["scripts"] = [e for e in d["scripts"] if e["path"] != "scripts/lib/example.py"]
json.dump(d, open(p, "w"), indent=2)
PY

set +e
bash "$VALIDATOR" --root "$ws" --quiet >/tmp/validate-manifest-parity-missing.out 2>/tmp/validate-manifest-parity-missing.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: missing-entry fixture expected non-zero exit, got 0" >&2
  exit 1
fi
if ! grep -q "POLARIS_MANIFEST_MISSING: scripts/lib/example.py" /tmp/validate-manifest-parity-missing.err; then
  echo "FAIL: stderr missing POLARIS_MANIFEST_MISSING token for scripts/lib/example.py" >&2
  cat /tmp/validate-manifest-parity-missing.err >&2
  exit 1
fi

# --- Case C: restore entry → PASS again ---
python3 - "$ws/scripts/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["scripts"].append({
  "path": "scripts/lib/example.py",
  "kind": "support",
  "runner": "python3",
  "owner_surface": "script_internal",
  "selftest": "N/A",
  "lifecycle": "support_path",
  "relocation": "stay",
  "selftest_reason": "library helper"
})
json.dump(d, open(p, "w"), indent=2)
PY

set +e
bash "$VALIDATOR" --root "$ws" --quiet >/tmp/validate-manifest-parity-restore.out 2>/tmp/validate-manifest-parity-restore.err
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: restored fixture expected exit 0, got $rc" >&2
  cat /tmp/validate-manifest-parity-restore.err >&2
  exit 1
fi

# --- Case D: real workspace must still PASS (validates the backfill) ---
set +e
bash "$VALIDATOR" --root "$ROOT" --quiet >/tmp/validate-manifest-parity-real.out 2>/tmp/validate-manifest-parity-real.err
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: real workspace manifest parity failed; check backfill" >&2
  cat /tmp/validate-manifest-parity-real.err >&2
  exit 1
fi

echo "PASS: validate-manifest-parity selftest"
