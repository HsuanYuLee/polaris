#!/usr/bin/env bash
# Selftest for validate-script-dependencies.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-script-dependencies.sh"
TMPDIR_SELFTEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT

mkdir -p "$TMPDIR_SELFTEST/scripts"
cp "$VALIDATOR" "$TMPDIR_SELFTEST/scripts/validate-script-dependencies.sh"
cat >"$TMPDIR_SELFTEST/package.json" <<'JSON'
{"type":"module","dependencies":{}}
JSON

cat >"$TMPDIR_SELFTEST/scripts/ok.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
rg -n "x" README.md
jq . package.json
SH

cat >"$TMPDIR_SELFTEST/scripts/bad.sh" <<'SH'
#!/usr/bin/env bash
brew install jq
SH

cat >"$TMPDIR_SELFTEST/scripts/bad.py" <<'PY'
import requests
PY

cat >"$TMPDIR_SELFTEST/scripts/bad.mjs" <<'JS'
import leftPad from 'left-pad';
console.log(leftPad('x', 2));
JS

(cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/ok.sh >/dev/null)

if (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/bad.sh >/dev/null 2>&1); then
  echo "expected unmanaged shell command to fail" >&2
  exit 1
fi

if (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/bad.py >/dev/null 2>&1); then
  echo "expected third-party Python import to fail" >&2
  exit 1
fi

if (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/bad.mjs >/dev/null 2>&1); then
  echo "expected undeclared Node import to fail" >&2
  exit 1
fi

if ! (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --mode audit --path scripts/bad.sh >/dev/null 2>&1); then
  echo "expected audit mode to report advisory without failing" >&2
  exit 1
fi

echo "PASS: validate-script-dependencies selftest"
