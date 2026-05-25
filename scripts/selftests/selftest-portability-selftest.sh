#!/usr/bin/env bash
# scripts/selftests/selftest-portability-selftest.sh — DP-230 T6 AC15.
#
# Verifies the selftest portability convention:
#   AC15-1  scripts/lib/selftest-bootstrap.sh provides an init_ROOT_DIR helper
#           that resolves the framework root via BASH_SOURCE and validates the
#           sentinel file workspace-config.yaml.example.
#   AC15-2  A fixture selftest that uses init_ROOT_DIR runs PASS in a fresh
#           git clone environment where `git rev-parse --show-toplevel` fails
#           (we strip .git to simulate the fresh-clone / detached HEAD scenario).
#   AC15-3  scripts/selftests/check-skills-mirror-mode-selftest.sh (the
#           representative migrated selftest) passes when invoked against the
#           live framework workspace.
#   AC15-4  validate-script-dependencies.sh fail-stops on a fixture selftest
#           that calls `git rev-parse --show-toplevel`, emitting the
#           POLARIS_SELFTEST_GIT_REV_PARSE_FORBIDDEN token.
#   AC15-5  Adversarial: a fixture init_ROOT_DIR that falls back to pwd fails
#           the sentinel check (POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING).

set -euo pipefail

# shellcheck source=../lib/selftest-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"

BOOTSTRAP="$ROOT_DIR/scripts/lib/selftest-bootstrap.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-script-dependencies.sh"
MIRROR_SELFTEST="$ROOT_DIR/scripts/selftests/check-skills-mirror-mode-selftest.sh"

for required in "$BOOTSTRAP" "$VALIDATOR" "$MIRROR_SELFTEST"; do
  if [[ ! -f "$required" ]]; then
    echo "FAIL: required artifact missing: $required" >&2
    exit 1
  fi
done

WORKDIR="$(mktemp -d -t dp230-t6-portability.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

# ---- AC15-1: init_ROOT_DIR helper exists in bootstrap ----
if ! grep -q '^init_ROOT_DIR()' "$BOOTSTRAP"; then
  echo "FAIL: AC15-1 init_ROOT_DIR() helper not defined in $BOOTSTRAP" >&2
  exit 1
fi

# ---- AC15-2: fresh-clone fixture ----
# Stage a fixture framework workspace at $WORKDIR/fixture-root that mirrors
# the layout init_ROOT_DIR expects (sentinel at root, scripts/lib/ and
# scripts/selftests/ siblings). Then strip any .git directory so
# `git rev-parse --show-toplevel` cannot resolve the root.
fixture_root="$WORKDIR/fixture-root"
mkdir -p "$fixture_root/scripts/lib"
mkdir -p "$fixture_root/scripts/selftests"
cp "$BOOTSTRAP" "$fixture_root/scripts/lib/selftest-bootstrap.sh"
touch "$fixture_root/workspace-config.yaml.example"

cat >"$fixture_root/scripts/selftests/fresh-clone-selftest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"
[[ -n "$ROOT_DIR" ]] || { echo "FAIL: ROOT_DIR empty" >&2; exit 1; }
[[ -f "$ROOT_DIR/workspace-config.yaml.example" ]] || {
  echo "FAIL: sentinel missing under $ROOT_DIR" >&2
  exit 1
}
echo "PASS: fresh-clone-fixture"
EOF
chmod +x "$fixture_root/scripts/selftests/fresh-clone-selftest.sh"

# Run in a subshell with PATH wrapping `git` to a stub that simulates fresh
# clone (rev-parse --show-toplevel exits non-zero). The bootstrap must not
# rely on `git`, so this must still PASS.
stub_dir="$WORKDIR/git-stub"
mkdir -p "$stub_dir"
cat >"$stub_dir/git" <<'EOF'
#!/usr/bin/env bash
# Simulate fresh-clone: any rev-parse invocation fails.
if [[ "${1:-}" == "rev-parse" ]]; then
  echo "fatal: not a git repository (stub)" >&2
  exit 128
fi
echo "stub-git: unsupported subcommand $*" >&2
exit 128
EOF
chmod +x "$stub_dir/git"

if ! PATH="$stub_dir:/usr/bin:/bin" \
  bash "$fixture_root/scripts/selftests/fresh-clone-selftest.sh" \
  >"$WORKDIR/fresh.stdout" 2>"$WORKDIR/fresh.stderr"; then
  echo "FAIL: AC15-2 fresh-clone fixture did not PASS under stubbed git" >&2
  echo "stdout:" >&2
  cat "$WORKDIR/fresh.stdout" >&2
  echo "stderr:" >&2
  cat "$WORKDIR/fresh.stderr" >&2
  exit 1
fi

# ---- AC15-3: live check-skills-mirror-mode-selftest passes ----
if ! bash "$MIRROR_SELFTEST" >"$WORKDIR/mirror.stdout" 2>"$WORKDIR/mirror.stderr"; then
  echo "FAIL: AC15-3 check-skills-mirror-mode-selftest did not PASS" >&2
  echo "stdout:" >&2
  cat "$WORKDIR/mirror.stdout" >&2
  echo "stderr:" >&2
  cat "$WORKDIR/mirror.stderr" >&2
  exit 1
fi

# ---- AC15-4: validate-script-dependencies flags `git rev-parse --show-toplevel` ----
bad_fixture_dir="$WORKDIR/bad-validator-fixture"
mkdir -p "$bad_fixture_dir/scripts/selftests"
# Stage a minimal copy of the validator + its companion files so it can run
# standalone against the fixture root.
cp "$VALIDATOR" "$bad_fixture_dir/scripts/validate-script-dependencies.sh"
# Inventory files are required by the validator's TSV loader. Stage empty
# placeholders (header-only is acceptable; missing entirely is also fine
# because load_tsv returns [] when the file is absent).
cat >"$bad_fixture_dir/scripts/selftests/bad-rev-parse-selftest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
echo "$ROOT_DIR"
EOF
chmod +x "$bad_fixture_dir/scripts/selftests/bad-rev-parse-selftest.sh"

set +e
output="$(bash "$bad_fixture_dir/scripts/validate-script-dependencies.sh" \
  --mode diff --path "scripts/selftests/bad-rev-parse-selftest.sh" 2>&1)"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "FAIL: AC15-4 validator should fail-stop on selftest with git rev-parse" >&2
  echo "output:" >&2
  echo "$output" >&2
  exit 1
fi
if ! grep -q "POLARIS_SELFTEST_GIT_REV_PARSE_FORBIDDEN" <<<"$output"; then
  echo "FAIL: AC15-4 expected POLARIS_SELFTEST_GIT_REV_PARSE_FORBIDDEN token in stderr" >&2
  echo "output:" >&2
  echo "$output" >&2
  exit 1
fi

# AC15-4b: same call inside a non-selftest path must NOT trip the new gate
# (otherwise we false-positive on, e.g., scripts/lib helpers that legitimately
# resolve a worktree). Stage one and ensure no rev-parse token.
mkdir -p "$bad_fixture_dir/scripts/lib"
cat >"$bad_fixture_dir/scripts/lib/non-selftest-rev-parse.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
echo "$ROOT_DIR"
EOF
set +e
non_selftest_output="$(bash "$bad_fixture_dir/scripts/validate-script-dependencies.sh" \
  --mode diff --path "scripts/lib/non-selftest-rev-parse.sh" 2>&1)"
non_selftest_status=$?
set -e
if grep -q "POLARIS_SELFTEST_GIT_REV_PARSE_FORBIDDEN" <<<"$non_selftest_output"; then
  echo "FAIL: AC15-4b validator must not flag non-selftest paths" >&2
  echo "output:" >&2
  echo "$non_selftest_output" >&2
  exit 1
fi
# (We intentionally do not assert exit 0 here: scripts/lib/ files may carry
# other governance findings; we only assert the rev-parse token is absent.)
: "$non_selftest_status"

# ---- AC15-5: adversarial pwd-fallback fixture fails sentinel ----
pwd_fixture_dir="$WORKDIR/pwd-fallback-fixture"
mkdir -p "$pwd_fixture_dir/scripts/lib"
mkdir -p "$pwd_fixture_dir/scripts/selftests"
# Bootstrap copy that silently falls back to pwd instead of fail-stop — the
# adversarial variant the AC15 adversarial pass calls out.
cat >"$pwd_fixture_dir/scripts/lib/selftest-bootstrap-bad.sh" <<'EOF'
#!/usr/bin/env bash
init_ROOT_DIR() {
  local candidate
  candidate="$(pwd)"   # <-- adversarial: pwd fallback instead of fail-stop
  ROOT_DIR="$candidate"
  export ROOT_DIR
}
EOF
cat >"$pwd_fixture_dir/scripts/selftests/pwd-fallback-selftest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap-bad.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"
if [[ ! -f "$ROOT_DIR/workspace-config.yaml.example" ]]; then
  echo "POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING: pwd fallback found no sentinel" >&2
  exit 2
fi
echo "PASS: pwd-fallback-selftest"
EOF
chmod +x "$pwd_fixture_dir/scripts/selftests/pwd-fallback-selftest.sh"

# Run the adversarial selftest from a directory that lacks the sentinel —
# tmpdir root. The expectation: it must fail-stop.
set +e
pwd_output="$(
  set -e
  cd "$WORKDIR"
  bash "$pwd_fixture_dir/scripts/selftests/pwd-fallback-selftest.sh" 2>&1
)"
pwd_status=$?
set -e
if [[ "$pwd_status" -eq 0 ]]; then
  echo "FAIL: AC15-5 adversarial pwd-fallback fixture should have failed sentinel check" >&2
  echo "output:" >&2
  echo "$pwd_output" >&2
  exit 1
fi
if ! grep -q "POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING" <<<"$pwd_output"; then
  echo "FAIL: AC15-5 expected POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING token" >&2
  echo "output:" >&2
  echo "$pwd_output" >&2
  exit 1
fi

# ---- AC15-5b: real init_ROOT_DIR fails fast when sentinel is removed ----
no_sentinel_root="$WORKDIR/no-sentinel-root"
mkdir -p "$no_sentinel_root/scripts/lib"
mkdir -p "$no_sentinel_root/scripts/selftests"
cp "$BOOTSTRAP" "$no_sentinel_root/scripts/lib/selftest-bootstrap.sh"
# (Note: intentionally do NOT create workspace-config.yaml.example.)
cat >"$no_sentinel_root/scripts/selftests/missing-sentinel-selftest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"
echo "should not reach here"
EOF
chmod +x "$no_sentinel_root/scripts/selftests/missing-sentinel-selftest.sh"
set +e
missing_output="$(bash "$no_sentinel_root/scripts/selftests/missing-sentinel-selftest.sh" 2>&1)"
missing_status=$?
set -e
if [[ "$missing_status" -eq 0 ]]; then
  echo "FAIL: AC15-5b init_ROOT_DIR should fail-stop when sentinel is missing" >&2
  echo "output:" >&2
  echo "$missing_output" >&2
  exit 1
fi
if ! grep -q "POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING" <<<"$missing_output"; then
  echo "FAIL: AC15-5b expected POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING token" >&2
  echo "output:" >&2
  echo "$missing_output" >&2
  exit 1
fi

echo "PASS: DP-230-T6"
