#!/usr/bin/env bash
# Selftest for resolve-handbook-paths.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
resolver="$script_dir/resolve-handbook-paths.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/acme/polaris-config/acme-web/handbook/nested"
printf '# Index\n' > "$tmp/acme/polaris-config/acme-web/handbook/index.md"
printf '# Nested\n' > "$tmp/acme/polaris-config/acme-web/handbook/nested/rules.md"
mkdir -p "$tmp/acme/polaris-config/empty-web/handbook"
mkdir -p "$tmp/acme-web/handbook"
printf '# Wrong\n' > "$tmp/acme-web/handbook/index.md"

existing="$("$resolver" --workspace "$tmp" --company acme --project acme-web)"
empty="$("$resolver" --workspace "$tmp" --company acme --project empty-web)"
missing="$("$resolver" --workspace "$tmp" --company acme --project missing-web)"

python3 - "$existing" "$tmp" <<'PY'
import json
import sys
from pathlib import Path

paths = json.loads(sys.argv[1])
root = Path(sys.argv[2]).resolve()
expected = [
    str(root / "acme/polaris-config/acme-web/handbook/index.md"),
    str(root / "acme/polaris-config/acme-web/handbook/nested/rules.md"),
]
if paths != expected:
    raise SystemExit(f"unexpected paths: {paths!r}")
if any("/acme-web/handbook/" in path and "/polaris-config/" not in path for path in paths):
    raise SystemExit("resolver returned repo-local handbook path")
PY

[[ "$empty" == "[]" ]]
[[ "$missing" == "[]" ]]

echo "resolve-handbook-paths selftest: PASS"
