#!/usr/bin/env bash
# Selftest for canonical location and head-bound marker validation.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$ROOT_DIR/scripts/resolve-artifact-location.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-artifact-location.sh"
tmp="$(mktemp -d -t polaris-artifact-validator.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=test -c user.email=test@example.com commit --allow-empty -q -m init
head_sha="$(git -C "$repo" rev-parse HEAD)"
ticket="DP-422-T6"
export POLARIS_EVIDENCE_ROOT="$tmp/evidence"

fail() { echo "validate-artifact-location-selftest: FAIL: $*" >&2; exit 1; }

verify_path="$($RESOLVER --kind verify --repo "$repo" --ticket "$ticket" --head-sha "$head_sha")"
mkdir -p "$(dirname "$verify_path")"
cat >"$verify_path" <<EOF
{"ticket":"$ticket","head_sha":"$head_sha","writer":"run-verify-command.sh","exit_code":0,"at":"2026-07-16T00:00:00Z"}
EOF
"$VALIDATOR" --kind verify --repo "$repo" --ticket "$ticket" --head-sha "$head_sha" >/dev/null

if "$VALIDATOR" --kind verify --repo "$repo" --ticket "$ticket" --head-sha "$head_sha" --artifact "$tmp/other.json" >/dev/null 2>&1; then
  fail "non-canonical path passed"
fi

python3 - "$verify_path" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["head_sha"] += "stale"
json.dump(data, open(path, "w", encoding="utf-8"))
PY
if "$VALIDATOR" --kind verify --repo "$repo" --ticket "$ticket" --head-sha "$head_sha" >/dev/null 2>&1; then
  fail "stale verify marker passed"
fi

vr_path="$($RESOLVER --kind vr --repo "$repo" --ticket "$ticket" --head-sha "$head_sha")"
mkdir -p "$(dirname "$vr_path")"
cat >"$vr_path" <<EOF
{"ticket":"$ticket","head_sha":"$head_sha","writer":"run-visual-snapshot.sh","mode":"compare","status":"BLOCK","at":"2026-07-16T00:00:00Z"}
EOF
if "$VALIDATOR" --kind vr --repo "$repo" --ticket "$ticket" --head-sha "$head_sha" >/dev/null 2>&1; then
  fail "blocking VR marker passed"
fi
python3 - "$vr_path" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["status"] = "PASS"
json.dump(data, open(path, "w", encoding="utf-8"))
PY
"$VALIDATOR" --kind vr --repo "$repo" --ticket "$ticket" --head-sha "$head_sha" >/dev/null

echo "validate-artifact-location-selftest: PASS"
