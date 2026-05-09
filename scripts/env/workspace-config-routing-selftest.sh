#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

tmpdir="$(mktemp -d -t env-workspace-routing.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

canon() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $name" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

assert_fails() {
  local name="$1"
  shift
  if "$@" >/tmp/env-workspace-routing.out 2>/tmp/env-workspace-routing.err; then
    echo "FAIL: $name unexpectedly passed" >&2
    cat /tmp/env-workspace-routing.out >&2 || true
    cat /tmp/env-workspace-routing.err >&2 || true
    exit 1
  fi
}

assert_hint_contains() {
  local name="$1" expected="$2" start="$3"
  local actual
  actual="$(env_lib_workspace_config_resolution_hint "$start")"
  grep -q "$expected" <<<"$actual" || {
    echo "FAIL: $name" >&2
    echo "  expected hint containing: $expected" >&2
    echo "  actual hint: $actual" >&2
    exit 1
  }
}

write_root() {
  local body="$1"
  cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
$body
EOF
}

write_company_cfg() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/workspace-config.yaml" <<'EOF'
projects:
  - name: app
    dev_environment:
      start_command: "echo start"
      ready_signal: "ready"
      base_url: "http://localhost:3000"
      health_check: "http://localhost:3000/health"
      requires: []
EOF
}

write_company_cfg "$tmpdir/acme"
write_company_cfg "$tmpdir/beta"

write_root "companies:
  - name: acme
    base_dir: \"$tmpdir/acme\"
  - name: beta
    base_dir: \"$tmpdir/beta\""

assert_fails "multi-company root without default must fail-stop" env_lib_find_workspace_config "$tmpdir"
assert_hint_contains "ambiguous root hint" "multiple companies but no default_company" "$tmpdir"

write_root "default_company: beta
companies:
  - name: acme
    base_dir: \"$tmpdir/acme\"
  - name: beta
    base_dir: \"$tmpdir/beta\""

resolved="$(env_lib_find_workspace_config "$tmpdir")"
assert_eq "default_company resolves beta config" "$(canon "$resolved")" "$(canon "$tmpdir/beta/workspace-config.yaml")"

mkdir -p "$tmpdir/acme/repo"
resolved="$(env_lib_find_workspace_config "$tmpdir/acme/repo")"
assert_eq "company subtree resolves company config directly" "$(canon "$resolved")" "$(canon "$tmpdir/acme/workspace-config.yaml")"

write_root "companies:
  - name: acme
    base_dir: \"$tmpdir/acme\""

resolved="$(env_lib_find_workspace_config "$tmpdir")"
assert_eq "single-company root may resolve sole company" "$(canon "$resolved")" "$(canon "$tmpdir/acme/workspace-config.yaml")"

write_root "default_company: ghost
companies:
  - name: acme
    base_dir: \"$tmpdir/acme\"
  - name: beta
    base_dir: \"$tmpdir/beta\""

assert_fails "invalid default_company must fail-stop" env_lib_find_workspace_config "$tmpdir"
assert_hint_contains "invalid default hint" "default_company='ghost'" "$tmpdir"

echo "PASS: env workspace-config routing selftest"
