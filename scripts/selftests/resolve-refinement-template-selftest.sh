#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/resolve-refinement-template.sh"
tmpdir="$(mktemp -d -t resolve-refinement-template.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/.claude/skills/references"
cp "$ROOT_DIR/.claude/skills/references/refinement-source-template.md" "$tmpdir/.claude/skills/references/refinement-source-template.md"

source_json="$(bash "$SCRIPT" --repo "$tmpdir" --format json)"
python3 - <<'PY' "$source_json"
import json, sys
d=json.loads(sys.argv[1])
assert d["source"] == "framework"
assert d["template_id"] == "framework-default"
assert "downstream_breakdown_hints" in d["framework_sections"]
PY

mkdir -p "$tmpdir/acme/polaris-config/refinement/templates"
cat >"$tmpdir/acme/polaris-config/refinement/templates/company.yaml" <<'YAML'
template_id: acme-default
company_sections:
  - business_metric
  - rollout_policy
YAML
company_json="$(bash "$SCRIPT" --repo "$tmpdir" --company acme --format json)"
python3 - <<'PY' "$company_json"
import json, sys
d=json.loads(sys.argv[1])
assert d["source"] == "company"
assert d["template_id"] == "acme-default"
assert d["company_sections"] == ["business_metric", "rollout_policy"]
PY

mkdir -p "$tmpdir/acme/polaris-config/web/refinement/templates"
cat >"$tmpdir/acme/polaris-config/web/refinement/templates/project.yaml" <<'YAML'
template_id: web-default
company_sections:
  - browser_matrix
YAML
project_json="$(bash "$SCRIPT" --repo "$tmpdir" --company acme --project web --format json)"
python3 - <<'PY' "$project_json"
import json, sys
d=json.loads(sys.argv[1])
assert d["source"] == "project"
assert d["template_id"] == "web-default"
assert d["company_sections"] == ["browser_matrix"]
PY

cat >"$tmpdir/acme/polaris-config/web/refinement/templates/project.yaml" <<'YAML'
template_id: bad
framework_sections:
  - only_one
YAML
if bash "$SCRIPT" --repo "$tmpdir" --company acme --project web --format json >/dev/null 2>&1; then
  echo "FAIL: forbidden framework_sections override passed" >&2
  exit 1
fi

echo "PASS: resolve-refinement-template selftest"
