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
cat >"$TMPDIR_SELFTEST/scripts/tool-direct-call-inventory.txt" <<'EOF'
path	line	tool	owner	install_authority	runtime_profile	goes_to_mise
scripts/baseline.sh	3	node	framework	root_mise	core	true
EOF
cat >"$TMPDIR_SELFTEST/scripts/tool-direct-call-inventory-disposition.txt" <<'EOF'
path	line	tool	disposition	owner_decision	remediation_task	expiry	scope
scripts/baseline.sh	3	node	accepted_current_debt	selftest baseline debt	SELFTEST-1	M-future	core
EOF

cat >"$TMPDIR_SELFTEST/scripts/ok.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
polaris_with_runtime_tools rg -n "x" README.md
polaris_with_runtime_tools jq . package.json
polaris_require_delivery_tool gh
SH

cat >"$TMPDIR_SELFTEST/scripts/baseline.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
node tool.mjs
SH

cat >"$TMPDIR_SELFTEST/scripts/bad.sh" <<'SH'
#!/usr/bin/env bash
brew install jq
SH

cat >"$TMPDIR_SELFTEST/scripts/bad-direct.sh" <<'SH'
#!/usr/bin/env bash
node tool.mjs
pnpm install
jq . package.json
rg -n "x" README.md
gh pr view 1
SH

cat >"$TMPDIR_SELFTEST/scripts/bad-hardcode.sh" <<'SH'
#!/usr/bin/env bash
/Applications/Visual Studio Code.app/Contents/Resources/app/node_modules/@vscode/ripgrep/bin/rg -n x .
SH

cat >"$TMPDIR_SELFTEST/scripts/bad-ticket-scoped.sh" <<'SH'
#!/usr/bin/env bash
playwright test
SH

cat >"$TMPDIR_SELFTEST/scripts/bad.py" <<'PY'
import requests
PY

cat >"$TMPDIR_SELFTEST/scripts/bad.mjs" <<'JS'
import leftPad from 'left-pad';
console.log(leftPad('x', 2));
JS

(cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/ok.sh >/dev/null)
(cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/baseline.sh >/dev/null)

if (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/bad.sh >/dev/null 2>&1); then
  echo "expected unmanaged shell command to fail" >&2
  exit 1
fi

if (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/bad-direct.sh >/tmp/validate-script-direct.out 2>&1); then
  echo "expected Tier A direct calls to fail" >&2
  exit 1
fi
grep -q "POLARIS_TOOL_DIRECT_CALL tool=node owner=framework install_authority=root_mise runtime_profile=core goes_to_mise=true" /tmp/validate-script-direct.out
grep -q "POLARIS_TOOL_DIRECT_CALL tool=gh owner=delivery install_authority=system runtime_profile=delivery goes_to_mise=false" /tmp/validate-script-direct.out

if (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/bad-hardcode.sh >/tmp/validate-script-hardcode.out 2>&1); then
  echo "expected hardcoded tool path to fail" >&2
  exit 1
fi
grep -q "POLARIS_TOOL_HARDCODED_PATH tool=rg" /tmp/validate-script-hardcode.out

if (cd "$TMPDIR_SELFTEST" && bash scripts/validate-script-dependencies.sh --path scripts/bad-ticket-scoped.sh >/tmp/validate-script-ticket.out 2>&1); then
  echo "expected ticket-scoped direct call to fail with task-scoped classification" >&2
  exit 1
fi
grep -q "POLARIS_TICKET_SCOPED_TOOL_DIRECT_CALL tool=playwright" /tmp/validate-script-ticket.out
grep -q "goes_to_mise=false" /tmp/validate-script-ticket.out

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
