#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/resolve-company-context.sh"

tmpdir="$(mktemp -d -t resolve-company-context.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

write_root_config() {
  cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
companies:
  - name: acme
    base_dir: "$tmpdir/acme"
  - name: beta
    base_dir: "$tmpdir/beta"
EOF
}

write_root_config_with_default() {
  cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
default_company: beta
companies:
  - name: acme
    base_dir: "$tmpdir/acme"
  - name: beta
    base_dir: "$tmpdir/beta"
EOF
}

write_company_config() {
  local dir="$1"
  local org="$2"
  local project="$3"
  mkdir -p "$dir"
  cat >"$dir/workspace-config.yaml" <<EOF
github:
  org: "$org"
jira:
  projects:
    - key: "$project"
      team: "Core"
slack:
  channels:
    pr_review: "C123"
projects: []
EOF
}

write_company_config_missing_jira() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/workspace-config.yaml" <<'EOF'
github:
  org: "broken-org"
jira:
  projects: []
projects: []
EOF
}

write_company_config_without_slack() {
  local dir="$1"
  local org="$2"
  local project="$3"
  mkdir -p "$dir"
  cat >"$dir/workspace-config.yaml" <<EOF
github:
  org: "$org"
jira:
  projects:
    - key: "$project"
      team: "Core"
projects: []
EOF
}

assert_field() {
  local expected="$1"
  shift
  local actual
  actual="$("$SCRIPT" --workspace-root "$tmpdir" --format field "$@")"
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL: expected=$expected got=$actual args=$*" >&2
    exit 1
  }
}

assert_json_contains() {
  local needle="$1"
  shift
  local output
  output="$("$SCRIPT" --workspace-root "$tmpdir" --format json "$@")"
  grep -q "$needle" <<<"$output" || {
    echo "FAIL: json missing $needle args=$*" >&2
    echo "$output" >&2
    exit 1
  }
}

mkdir -p "$tmpdir/acme/projects/app" "$tmpdir/beta/projects/app"
write_root_config
write_company_config "$tmpdir/acme" "acme-org" "ACME"
write_company_config "$tmpdir/beta" "beta-org" "BETA"

assert_field "ok" --field status --company acme
assert_field "acme" --field company_name --company acme
assert_field "company_name_match" --field resolved_via --company acme
assert_field "ok" --field status --ticket ACME-123
assert_field "acme" --field company_name --ticket ACME-123
assert_field "jira_project_prefix" --field resolved_via --ticket ACME-123
assert_field "ok" --field status --project BETA
assert_field "beta" --field company_name --project BETA
assert_field "ok" --field status --cwd "$tmpdir/beta/projects/app"
assert_field "beta" --field company_name --cwd "$tmpdir/beta/projects/app"
assert_field "cwd_base_dir" --field resolved_via --cwd "$tmpdir/beta/projects/app"

assert_field "error" --field status
assert_field "default_company_unset" --field error_code

write_root_config_with_default
assert_field "ok" --field status
assert_field "beta" --field company_name
assert_field "default_company" --field resolved_via

cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
companies:
  - name: acme
    base_dir: "$tmpdir/acme"
  - name: acme-prod
    base_dir: "$tmpdir/acme-prod"
EOF
write_company_config "$tmpdir/acme-prod" "acme-prod-org" "ACMEP"
assert_field "error" --field status --company acm
assert_field "company_name_ambiguous" --field error_code --company acm

cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
companies:
  - name: acme
    base_dir: "$tmpdir/acme"
  - name: gamma
    base_dir: "$tmpdir/gamma"
EOF
write_company_config "$tmpdir/gamma" "gamma-org" "ACME"
assert_field "error" --field status --project ACME
assert_field "project_prefix_ambiguous" --field error_code --project ACME

cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
companies:
  - name: broken
    base_dir: "$tmpdir/broken"
EOF
write_company_config_missing_jira "$tmpdir/broken"
assert_field "error" --field status --company broken
assert_field "company_config_invalid" --field error_code --company broken

write_company_config_without_slack "$tmpdir/broken" "broken-org" "BROKEN"
assert_json_contains '"slack channels not configured"' --company broken

echo "PASS: resolve-company-context selftest"
