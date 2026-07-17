#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/tool-resolution.sh
source "$ROOT/scripts/lib/tool-resolution.sh"
RESOLVER="$ROOT/scripts/resolve-skill-flow-transition.sh"

record="$(bash "$RESOLVER" --id engineering.self_review_outcome)"
polaris_with_runtime_tools jq -e '.id == "engineering.self_review_outcome" and .callable_interface.path == "scripts/write-engineering-self-review-result.sh" and .validator == "scripts/validate-engineering-self-review-result.sh"' <<<"$record" >/dev/null

if bash "$RESOLVER" --id "continue anyway" >/dev/null 2>&1; then
  echo "FAIL: freeform phrase must not resolve as a transition id" >&2
  exit 1
fi

echo "PASS: resolve skill-flow transition selftest"
