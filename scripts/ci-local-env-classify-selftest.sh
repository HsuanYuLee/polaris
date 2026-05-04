#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/ci-local-env-classify.py"
TMPROOT="$(mktemp -d -t ci-local-env-classify-XXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0

assert_json_field() {
  local desc="$1"
  local json="$2"
  local field="$3"
  local expected="$4"
  local actual
  actual="$(python3 - "$json" "$field" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
value = payload
for part in sys.argv[2].split("."):
    value = value.get(part) if isinstance(value, dict) else None
print("" if value is None else value)
PY
)"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  ✗ %s — expected '%s' got '%s'\n" "$desc" "$expected" "$actual" >&2
  fi
}

assert_not_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    FAIL=$((FAIL + 1))
    printf "  ✗ %s — leaked '%s'\n" "$desc" "$needle" >&2
  else
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$desc"
  fi
}

repo="$TMPROOT/repo"
mkdir -p "$repo"
cat > "$repo/.npmrc" <<'EOF'
registry=https://registry.npmjs.org/
@exampleco:registry=https://user:secret@nexus3.sit.exampleco.com/repository/npm-group/?token=abc123
//nexus3.sit.exampleco.com/repository/npm-group/:_authToken=npm_secret_token
EOF
cat > "$repo/.yarnrc.yml" <<'EOF'
npmRegistryServer: "https://yarn-registry.sit.exampleco.com/npm/"
EOF

dns_json="$(python3 "$CLASSIFIER" --repo "$repo" --category install --command 'pnpm install --frozen-lockfile' --output ' ERR_PNPM_META_FETCH_FAIL getaddrinfo ENOTFOUND nexus3.sit.exampleco.com')"
assert_json_field "DNS failure -> BLOCKED_ENV" "$dns_json" status BLOCKED_ENV
assert_json_field "DNS reason" "$dns_json" reason dns_resolution_failed
assert_json_field "DNS host" "$dns_json" host nexus3.sit.exampleco.com

timeout_json="$(python3 "$CLASSIFIER" --category install --command 'npm ci' --output 'connect ETIMEDOUT registry.npmjs.org:443')"
assert_json_field "timeout -> BLOCKED_ENV" "$timeout_json" status BLOCKED_ENV
assert_json_field "timeout reason" "$timeout_json" reason connection_timeout

tls_json="$(python3 "$CLASSIFIER" --category install --command 'yarn install' --output 'request to https://registry.yarnpkg.com failed, reason: self signed certificate in certificate chain')"
assert_json_field "TLS/proxy -> BLOCKED_ENV" "$tls_json" status BLOCKED_ENV
assert_json_field "TLS/proxy reason" "$tls_json" reason tls_or_proxy_failure

auth_json="$(python3 "$CLASSIFIER" --category install --command 'pnpm install' --output 'npm ERR! 401 Unauthorized - GET https://registry.npmjs.org/private')"
assert_json_field "auth -> BLOCKED_ENV" "$auth_json" status BLOCKED_ENV
assert_json_field "auth reason" "$auth_json" reason auth_required_or_forbidden

vpn_json="$(python3 "$CLASSIFIER" --category install --command 'pnpm install' --output 'private network or VPN required for packages.internal')"
assert_json_field "VPN/private -> BLOCKED_ENV" "$vpn_json" status BLOCKED_ENV
assert_json_field "VPN/private reason" "$vpn_json" reason vpn_or_private_network_required

fail_json="$(python3 "$CLASSIFIER" --category test --command 'pnpm test' --output 'AssertionError: expected true to equal false')"
assert_json_field "non-env test failure -> FAIL" "$fail_json" status FAIL
assert_json_field "non-env classification null" "$fail_json" classification ""

secret_json="$(python3 "$CLASSIFIER" --category install --command 'pnpm install' --output 'Bearer abc.def.ghi https://user:pass@nexus3.sit.exampleco.com/npm/?token=abc&_authToken=secret')"
assert_not_contains "scrubs bearer token" "$secret_json" "abc.def.ghi"
assert_not_contains "scrubs basic auth password" "$secret_json" "user:pass"
assert_not_contains "scrubs query token" "$secret_json" "token=abc"
assert_not_contains "scrubs auth token key" "$secret_json" "_authToken=secret"

echo "ci-local-env-classify-selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
