#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/env/fixtures-start.sh"

tmpdir="$(mktemp -d -t fixtures-start-soft.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

fixture_dir="$tmpdir/fixtures"
mkdir -p "$fixture_dir"
cat >"$fixture_dir/sample.json" <<'EOF'
{"uuid":"fixture-sample","port":4010}
EOF

cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
companies:
  - name: acme
    base_dir: "$tmpdir/acme"
  - name: beta
    base_dir: "$tmpdir/beta"
EOF
mkdir -p "$tmpdir/acme" "$tmpdir/beta"
cat >"$tmpdir/acme/workspace-config.yaml" <<'EOF'
projects: []
EOF
cat >"$tmpdir/beta/workspace-config.yaml" <<'EOF'
projects: []
EOF

fake_runner="$tmpdir/fake-mockoon-runner.sh"
cat >"$fake_runner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" > "${FAKE_RUNNER_LOG:?}"
exit 0
EOF
chmod +x "$fake_runner"

runner_log="$tmpdir/runner.log"
stdout_file="$tmpdir/stdout"
stderr_file="$tmpdir/stderr"

(
  cd "$tmpdir"
  FAKE_RUNNER_LOG="$runner_log" \
  POLARIS_MOCKOON_RUNNER_OVERRIDE="$fake_runner" \
  bash "$SCRIPT" "$fixture_dir" >"$stdout_file" 2>"$stderr_file"
)

grep -q "PASS fixtures up via mockoon" "$stdout_file" || {
  echo "FAIL: fixtures-start did not report PASS" >&2
  cat "$stdout_file" >&2 || true
  cat "$stderr_file" >&2 || true
  exit 1
}

grep -q "start $fixture_dir" "$runner_log" || {
  echo "FAIL: fake runner was not invoked via framework default override" >&2
  cat "$runner_log" >&2 || true
  exit 1
}

grep -q "mockoon runner override skipped:" "$stderr_file" || {
  echo "FAIL: missing soft-override advisory" >&2
  cat "$stderr_file" >&2 || true
  exit 1
}

grep -q "falling back to framework default mockoon runner" "$stderr_file" || {
  echo "FAIL: missing fallback advisory" >&2
  cat "$stderr_file" >&2 || true
  exit 1
}

echo "PASS: fixtures-start soft override selftest"
