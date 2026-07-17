#!/usr/bin/env bash
# Purpose: Verify legacy framework handbook routing and compatibility adapters are fully retired.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR="$(mktemp -d -t handbook-routing-retirement.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

for tool in python3 rg; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:$tool" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
done

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

retired_paths=(
  "scripts/validate-framework-handbook-routing.sh"
  "scripts/selftests/validate-framework-handbook-routing-selftest.sh"
  "scripts/handbook-config-reader.sh"
  "scripts/handbook-config-selftest.sh"
  ".claude/skills/review-inbox/scripts/resolve-handbook-paths.sh"
  ".claude/skills/review-inbox/scripts/resolve-handbook-paths-selftest.sh"
)
for path in "${retired_paths[@]}"; do
  [[ ! -e "$ROOT_DIR/$path" ]] || fail "retired path still exists: $path"
done

live_referrers=(
  ".claude/rules/workspace-self-development.md"
  ".claude/skills/references/breakdown-dp-intake-flow.md"
  ".claude/skills/references/refinement-source-mode.md"
  ".claude/skills/references/engineering-entry-resolution.md"
  ".claude/skills/references/review-inbox-discovery-flow.md"
  ".claude/skills/references/evidence-immune-execution.md"
  ".claude/skills/references/delivery-unit-completion-standard.md"
  ".claude/skills/references/deterministic-hooks-registry.md"
  ".claude/skills/references/mechanism-deterministic-contracts.md"
  "polaris-config/polaris-framework/handbook/index.md"
  "polaris-config/polaris-framework/handbook/configuration-surface.md"
  "scripts/start-test-env.sh"
  ".claude/skills/review-inbox/scripts/build-review-prompt.sh"
  "scripts/validate-framework-script-structure.sh"
  "scripts/selftests/framework-script-structure-selftest.sh"
  "scripts/selftests/resolve-handbook-selftest.sh"
  "scripts/manifest.json"
)

for path in "${live_referrers[@]}"; do
  [[ -f "$ROOT_DIR/$path" ]] || fail "expected live referrer missing: $path"
done

if rg -n '(\.claude/rules/handbook/framework/|handbook-config-reader\.sh|handbook-config-selftest\.sh|resolve-handbook-paths\.sh|resolve-handbook-paths-selftest\.sh|validate-framework-handbook-routing\.sh|validate-framework-handbook-routing-selftest\.sh)' \
  "${live_referrers[@]/#/$ROOT_DIR/}"; then
  fail "live referrer still points at retired handbook routing"
fi

rg -q 'resolve-handbook\.sh' "$ROOT_DIR/scripts/start-test-env.sh" \
  || fail "start-test-env does not call the canonical resolver"
rg -q 'resolve-handbook\.sh' "$ROOT_DIR/.claude/skills/review-inbox/scripts/build-review-prompt.sh" \
  || fail "review-inbox prompt builder does not call the canonical resolver"

resolver_payload="$("$ROOT_DIR/scripts/resolve-handbook.sh" --project polaris-framework)"
script_governance="$(python3 - "$resolver_payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
matches = [path for path in payload["narrative_paths"] if path.endswith("/script-governance.md")]
assert len(matches) == 1
print(matches[0])
PY
)"
[[ -f "$script_governance" ]] || fail "resolver did not surface script-governance.md"

config_fixtures="$ROOT_DIR/scripts/fixtures/handbook-config"
valid_config="$config_fixtures/valid-company/polaris-config/web/handbook/config.yaml"
valid_workspace="$config_fixtures/valid-company/workspace.fixture.yaml"
health_check="$("$ROOT_DIR/scripts/resolve-handbook.sh" \
  --config "$valid_config" \
  --field runtime.health_check | python3 -c 'import json,sys; print(json.load(sys.stdin))')"
[[ "$health_check" == "https://dev.example.test/health" ]] \
  || fail "canonical resolver field selection drifted"

bash "$ROOT_DIR/scripts/handbook-config-validator.sh" \
  --config "$valid_config" \
  --project web \
  --workspace-config "$valid_workspace" \
  --require-section runtime \
  --require-section test \
  --check-conflicts >/dev/null

for invalid_config in missing-runtime.yaml unsupported-version.yaml malformed.yaml; do
  if bash "$ROOT_DIR/scripts/handbook-config-validator.sh" \
    --config "$config_fixtures/$invalid_config" \
    --require-section runtime >/dev/null 2>&1; then
    fail "invalid handbook config unexpectedly passed: $invalid_config"
  fi
done

cp -R "$ROOT_DIR/scripts/fixtures/handbook-config/start-test-env-company" "$TMPDIR/company"
while IFS= read -r config; do
  printf '# Fixture handbook\n' >"$(dirname "$config")/index.md"
done < <(find "$TMPDIR/company/polaris-config" -name config.yaml -type f -print)
start_env_workspace="$TMPDIR/company/workspace.fixture.yaml"
handbook_source="$(bash "$ROOT_DIR/scripts/start-test-env.sh" \
  --project handbook-web \
  --workspace-config "$start_env_workspace" \
  --resolve-config-only | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
[[ "$handbook_source" == "handbook_config" ]] \
  || fail "start-test-env did not consume canonical handbook config"

fallback_source="$(bash "$ROOT_DIR/scripts/start-test-env.sh" \
  --project legacy-only \
  --workspace-config "$start_env_workspace" \
  --resolve-config-only | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
[[ "$fallback_source" == "workspace_config_fallback" ]] \
  || fail "start-test-env did not preserve explicit no-handbook fallback"

if bash "$ROOT_DIR/scripts/start-test-env.sh" \
  --project conflict-web \
  --workspace-config "$start_env_workspace" \
  --resolve-config-only >/dev/null 2>&1; then
  fail "start-test-env conflict unexpectedly passed"
fi

bash "$ROOT_DIR/scripts/selftests/resolve-handbook-selftest.sh"
bash "$ROOT_DIR/scripts/selftests/framework-script-structure-selftest.sh"
bash "$ROOT_DIR/.claude/skills/review-inbox/scripts/build-review-prompt-selftest.sh"
bash "$ROOT_DIR/scripts/check-script-manifest.sh"

echo "PASS: handbook routing retirement"
