#!/usr/bin/env bash
# Selftest for the thin artifact-location resolver and DP/JIRA source parity.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$ROOT_DIR/scripts/resolve-artifact-location.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-artifact-location.sh"
tmp="$(mktemp -d -t polaris-artifact-location.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=test -c user.email=test@example.com commit --allow-empty -q -m init
head_sha="$(git -C "$repo" rev-parse HEAD)"
export POLARIS_EVIDENCE_ROOT="$tmp/evidence"

fail() { echo "resolve-artifact-location-selftest: FAIL: $*" >&2; exit 1; }

dp_path="$($RESOLVER --kind verify --repo "$repo" --ticket DP-422-T6 --head-sha "$head_sha")"
[[ "$dp_path" == "$POLARIS_EVIDENCE_ROOT/verify/polaris-verified-DP-422-T6-${head_sha}.json" ]] || fail "unexpected DP path: $dp_path"

jira_path="$($RESOLVER --kind verify --repo "$repo" --ticket PROJ-1234 --head-sha "$head_sha")"
[[ "$jira_path" == "$POLARIS_EVIDENCE_ROOT/verify/polaris-verified-PROJ-1234-${head_sha}.json" ]] || fail "unexpected JIRA path: $jira_path"

vr_path="$($RESOLVER --kind vr --repo "$repo" --ticket DP-422-T6 --head-sha "$head_sha")"
[[ "$vr_path" == "$POLARIS_EVIDENCE_ROOT/vr/polaris-vr-DP-422-T6-${head_sha}.json" ]] || fail "unexpected VR path: $vr_path"

json="$($RESOLVER --kind verify --repo "$repo" --ticket DP-422-T6 --head-sha "$head_sha" --format json)"
python3 - "$json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assert data["authority"] == "scripts/lib/verification-evidence.sh"
assert data["kind"] == "verify"
PY

[[ ! -e "$POLARIS_EVIDENCE_ROOT" ]] || fail "resolver created filesystem state"

# The registry blocking consumer exercises the full producer -> validator
# chain, while the dedicated validator selftest carries its adversarial cases.
mkdir -p "$(dirname "$dp_path")"
cat >"$dp_path" <<EOF
{"ticket":"DP-422-T6","head_sha":"$head_sha","writer":"run-verify-command.sh","exit_code":0,"at":"2026-07-16T00:00:00Z"}
EOF
"$VALIDATOR" --kind verify --repo "$repo" --ticket DP-422-T6 --head-sha "$head_sha" >/dev/null

if "$RESOLVER" --kind behavior --repo "$repo" --ticket DP-422-T6 --head-sha "$head_sha" >/dev/null 2>&1; then
  fail "unsupported kind passed"
fi
if "$RESOLVER" --kind verify --repo "$repo" --ticket DP-422-T6 --head-sha "${head_sha}stale" >/dev/null 2>&1; then
  fail "stale head passed"
fi

echo "resolve-artifact-location-selftest: PASS"
