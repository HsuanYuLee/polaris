#!/usr/bin/env bash
# Purpose: selftest validate-framework-script-structure shell/Python/handbook structure cases.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-framework-script-structure.sh"
TMPDIR="$(mktemp -d -t framework-script-structure.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
  echo "[framework-script-structure-selftest] FAIL: $*" >&2
  exit 1
}

expect_pass() {
  local label="$1"
  shift
  "$@" >/dev/null 2>"$TMPDIR/${label}.err" || {
    cat "$TMPDIR/${label}.err" >&2
    fail "$label expected pass"
  }
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"$TMPDIR/${label}.out" 2>"$TMPDIR/${label}.err"; then
    cat "$TMPDIR/${label}.out" >&2
    fail "$label expected fail"
  fi
}

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# Purpose: fixture'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' '# shellcheck disable=SC2086'
  printf '%s\n' 'echo $VALUE'
} >"$TMPDIR/bad-suppression.sh"

cat >"$TMPDIR/good-suppression.sh" <<'SH'
#!/usr/bin/env bash
# Purpose: fixture
set -euo pipefail
# POLARIS_SHELLCHECK_JUSTIFICATION: fixture intentionally demonstrates word splitting.
# shellcheck disable=SC2086
echo $VALUE
SH

cat >"$TMPDIR/bad-cli.py" <<'PY'
#!/usr/bin/env python3
"""Purpose: fixture."""
import sys

if __name__ == "__main__":
    print(sys.argv[1:])
PY

cat >"$TMPDIR/good-cli.py" <<'PY'
#!/usr/bin/env python3
"""Purpose: fixture."""
import argparse


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--name", required=True)
    parser.parse_args()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

cat >"$TMPDIR/script-governance.md" <<'MD'
# Script Governance

Missing required baseline terms.
MD

expect_fail bad_suppression "$VALIDATOR" --mode diff --root "$TMPDIR" --file "$TMPDIR/bad-suppression.sh"
expect_pass good_suppression "$VALIDATOR" --mode diff --root "$TMPDIR" --file "$TMPDIR/good-suppression.sh"
expect_fail bad_cli "$VALIDATOR" --mode diff --root "$TMPDIR" --file "$TMPDIR/bad-cli.py"
expect_pass good_cli "$VALIDATOR" --mode diff --root "$TMPDIR" --file "$TMPDIR/good-cli.py"
expect_fail bad_handbook "$VALIDATOR" --mode diff --root "$TMPDIR" --file "$TMPDIR/script-governance.md"
handbook_payload="$("$ROOT_DIR/scripts/resolve-handbook.sh" --project polaris-framework)"
script_governance="$(python3 - "$handbook_payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
matches = [path for path in payload["narrative_paths"] if path.endswith("/script-governance.md")]
assert len(matches) == 1
print(matches[0])
PY
)"
expect_pass real_handbook "$VALIDATOR" --mode diff --root "$ROOT_DIR" --file "$script_governance"

"$VALIDATOR" --mode audit --root "$TMPDIR" --file "$TMPDIR/bad-suppression.sh" >"$TMPDIR/audit.json"
python3 - "$TMPDIR/audit.json" <<'PY' || fail "audit JSON inventory did not record expected debt"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["schema_version"] == 1
assert data["mode"] == "audit"
assert data["violation_count"] == 1
assert data["violations"][0]["path"] == "bad-suppression.sh"
assert "ShellCheck suppression" in data["violations"][0]["reason"]
PY

echo "[framework-script-structure-selftest] PASS"
