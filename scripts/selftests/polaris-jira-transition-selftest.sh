#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/polaris-jira-transition.sh"

tmpdir="$(mktemp -d -t polaris-jira-transition.XXXXXX)"
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

write_company_config() {
  local dir="$1"
  local project="$2"
  mkdir -p "$dir"
  cat >"$dir/workspace-config.yaml" <<EOF
github:
  org: "$(basename "$dir")-org"
jira:
  instance: "$(basename "$dir").atlassian.net"
  projects:
    - key: "$project"
      team: "Core"
projects: []
EOF
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

canon() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

write_root_config
write_company_config "$tmpdir/acme" "ACME"
write_company_config "$tmpdir/beta" "BETA"
mkdir -p "$tmpdir/acme/repo"
acme_cfg="$(canon "$tmpdir/acme/workspace-config.yaml")"
beta_cfg="$(canon "$tmpdir/beta/workspace-config.yaml")"

# shellcheck source=/dev/null
source "$SCRIPT"

pushd "$tmpdir" >/dev/null
cfg="$(find_company_config "BETA-123")"
popd >/dev/null
cfg="$(canon "$cfg")"
assert_eq "resolver-first ticket routing" "$cfg" "$beta_cfg"

pushd "$tmpdir/acme/repo" >/dev/null
cfg="$(find_company_config "NOPE-1")"
popd >/dev/null
cfg="$(canon "$cfg")"
assert_eq "cwd fallback when resolver has no match" "$cfg" "$acme_cfg"

mkdir -p "$tmpdir/pinned"
write_company_config "$tmpdir/pinned" "PIN"
pinned_cfg="$(canon "$tmpdir/pinned/workspace-config.yaml")"
POLARIS_COMPANY_DIR="$tmpdir/pinned"
pushd "$tmpdir" >/dev/null
cfg="$(find_company_config "ACME-1")"
popd >/dev/null
unset POLARIS_COMPANY_DIR
cfg="$(canon "$cfg")"
assert_eq "explicit company dir override" "$cfg" "$pinned_cfg"

echo "PASS: polaris-jira-transition selftest"
