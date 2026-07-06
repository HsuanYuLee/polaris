#!/usr/bin/env bash
# Purpose: validate-config-driven-authoring.sh selftest。覆蓋硬編 external-write
#          prose、language-aware producer、callsite exception，以及禁止 broad allowlist。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/validate-config-driven-authoring.sh"

tmpdir="$(mktemp -d -t config-driven-authoring.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/scripts/lib"

write_exceptions() {
  local body="$1"
  printf '%s\n' "$body" >"$tmpdir/scripts/lib/config-driven-authoring-exceptions.json"
}

write_exceptions '{"schema_version":1,"exceptions":[]}'

cat >"$tmpdir/scripts/bad-release.sh" <<'SH'
#!/usr/bin/env bash
gh pr comment "$1" --body "released — orphan task PR cleaned by release-cleanup-sweep"
SH

if bash "$SCRIPT" --root "$tmpdir" --path scripts/bad-release.sh >/dev/null 2>"$tmpdir/bad.err"; then
  echo "FAIL: expected hardcoded external-write prose to fail" >&2
  exit 1
fi
grep -q "config-driven authoring audit" "$tmpdir/bad.err" || {
  echo "FAIL: missing audit failure marker" >&2
  cat "$tmpdir/bad.err" >&2
  exit 1
}

cat >"$tmpdir/scripts/good-release.sh" <<'SH'
#!/usr/bin/env bash
body_file="$(mktemp)"
printf '%s\n' "已 release，關閉 task PR。" >"$body_file"
POLARIS_EXTERNAL_WRITE_WRITER=framework-release:task-pr-comment \
  bash scripts/polaris-external-write-gate.sh --surface github-pr-comment --body-file "$body_file"
gh pr comment "$1" --body-file "$body_file"
SH

bash "$SCRIPT" --root "$tmpdir" --path scripts/good-release.sh >/dev/null

write_exceptions '{"schema_version":1,"exceptions":[{"path":"scripts/bad-release.sh","contains":"released — orphan task PR cleaned by release-cleanup-sweep","owner_dp":"DP-405-T3","reason":"fixture 例外"}]}'
bash "$SCRIPT" --root "$tmpdir" --path scripts/bad-release.sh >/dev/null

write_exceptions '{"schema_version":1,"exceptions":[{"path":"scripts/**","contains":"released","owner_dp":"DP-405-T3","reason":"過寬例外"}]}'
if bash "$SCRIPT" --root "$tmpdir" --path scripts/bad-release.sh >/dev/null 2>"$tmpdir/broad.err"; then
  echo "FAIL: expected broad exception to fail" >&2
  exit 1
fi
grep -q "broad path exception is forbidden" "$tmpdir/broad.err" || {
  echo "FAIL: missing broad exception failure" >&2
  cat "$tmpdir/broad.err" >&2
  exit 1
}

echo "PASS: config-driven authoring audit selftest"
