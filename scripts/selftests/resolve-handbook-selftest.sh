#!/usr/bin/env bash
# Purpose: Verify the single config-driven handbook resolver and legacy adapter retirement.
# Inputs: Hermetic framework/product handbook fixtures.
# Outputs: PASS on symmetric resolution, strict failures, and legacy adapter absence.

set -euo pipefail

for tool in python3 rg; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:$tool" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
done

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESOLVER="$ROOT_DIR/scripts/resolve-handbook.sh"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name unexpectedly passed"
  fi
}

mkdir -p "$FIXTURE_ROOT/acme/polaris-config/storefront/handbook"
cat > "$FIXTURE_ROOT/acme/polaris-config/storefront/handbook/config.yaml" <<'YAML'
schema_version: 1
project: storefront
base_branch: main
YAML
cat > "$FIXTURE_ROOT/acme/polaris-config/storefront/handbook/index.md" <<'MARKDOWN'
# Storefront handbook
MARKDOWN

framework_json="$("$RESOLVER" --project polaris-framework)"
product_json="$("$RESOLVER" --company-dir "$FIXTURE_ROOT/acme" --project storefront)"

python3 - "$framework_json" "$ROOT_DIR" "$product_json" "$FIXTURE_ROOT" <<'PY'
import json
import pathlib
import sys

framework = json.loads(sys.argv[1])
root = pathlib.Path(sys.argv[2]).resolve()
product = json.loads(sys.argv[3])
fixture = pathlib.Path(sys.argv[4]).resolve()

assert framework["scope_id"] == "polaris-framework"
assert pathlib.Path(framework["scope_root"]) == root
assert pathlib.Path(framework["config_path"]) == root / "polaris-config/polaris-framework/handbook/config.yaml"
assert pathlib.Path(framework["index_path"]) == root / "polaris-config/polaris-framework/handbook/index.md"
assert framework["config"]["project"] == "polaris-framework"
assert framework["narrative_paths"][0] == framework["index_path"]

assert product["scope_id"] == "storefront"
assert pathlib.Path(product["scope_root"]) == fixture / "acme"
assert pathlib.Path(product["config_path"]) == fixture / "acme/polaris-config/storefront/handbook/config.yaml"
assert pathlib.Path(product["index_path"]) == fixture / "acme/polaris-config/storefront/handbook/index.md"
assert product["config"]["project"] == "storefront"
PY

assert_fails "missing project mapping" "$RESOLVER" --company-dir "$FIXTURE_ROOT/acme" --project missing
sed 's/project: storefront/project: wrong-project/' \
  "$FIXTURE_ROOT/acme/polaris-config/storefront/handbook/config.yaml" \
  > "$FIXTURE_ROOT/acme/polaris-config/storefront/handbook/config.yaml.tmp"
mv "$FIXTURE_ROOT/acme/polaris-config/storefront/handbook/config.yaml.tmp" \
  "$FIXTURE_ROOT/acme/polaris-config/storefront/handbook/config.yaml"
assert_fails "project identity mismatch" "$RESOLVER" --company-dir "$FIXTURE_ROOT/acme" --project storefront

if rg -n 'is_framework_owned|framework-special|polaris-framework\)' "$RESOLVER" >/dev/null; then
  fail "resolver contains a framework-specific path branch"
fi

reader_segment="reader"
paths_segment="paths"
legacy_reader="$ROOT_DIR/scripts/handbook-config-${reader_segment}.sh"
legacy_review_resolver="$ROOT_DIR/.claude/skills/review-inbox/scripts/resolve-handbook-${paths_segment}.sh"
for adapter in "$legacy_reader" "$legacy_review_resolver"; do
  [[ ! -e "$adapter" ]] || fail "legacy adapter still exists: $adapter"
done

echo "PASS: canonical handbook resolver"
