#!/usr/bin/env bash
# Purpose: Verify lazy first-touch handbook loading, marker reuse, and fail-closed errors.
# Inputs: Hermetic Git repos and resolver fixtures.
# Outputs: PASS when AC3 and AC-NEG3 state transitions hold.

set -euo pipefail

for tool in python3 rg; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:$tool" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
done

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-handbook-load-gate.sh"
HOOK="$ROOT_DIR/.claude/hooks/pre-handbook-load-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_fails() {
  local name="$1"
  shift
  if "$@" >"$TMP/out" 2>"$TMP/err"; then
    fail "$name unexpectedly passed"
  fi
  rg -q 'POLARIS_HANDBOOK_LOAD_GATE_BLOCKED' "$TMP/err" || fail "$name missing structured marker"
}

repo="$TMP/repo"
mkdir -p "$repo/polaris-config/demo/handbook"
git -C "$TMP" init -q repo
cat > "$repo/polaris-config/demo/handbook/config.yaml" <<'YAML'
schema_version: 1
project: demo
base_branch: main
YAML
printf '# Demo handbook\n' > "$repo/polaris-config/demo/handbook/index.md"
printf 'tracked\n' > "$repo/tracked.txt"
git -C "$repo" add .
git -C "$repo" commit -qm init

runtime="$TMP/runtime"
log="$TMP/resolver.log"
cat > "$TMP/logging-resolver.sh" <<EOF
#!/usr/bin/env bash
echo called >> "$log"
exec "$ROOT_DIR/scripts/resolve-handbook.sh" "\$@"
EOF
chmod +x "$TMP/logging-resolver.sh"

first="$(POLARIS_RUNTIME_DIR="$runtime" "$VALIDATOR" --repo "$repo" --path "$repo/tracked.txt" --project demo --session-id s1 --resolver "$TMP/logging-resolver.sh")"
rg -q 'index.md' <<<"$first" || fail "first touch did not surface handbook index"
[[ "$(wc -l < "$log" | tr -d ' ')" == "1" ]] || fail "first touch did not call resolver exactly once"
[[ "$(find "$runtime/handbook-load" -type f -name '*.json' | wc -l | tr -d ' ')" == "1" ]] || fail "first touch did not write marker"

POLARIS_RUNTIME_DIR="$runtime" "$VALIDATOR" --repo "$repo" --path "$repo/tracked.txt" --project demo --session-id s1 --resolver "$TMP/logging-resolver.sh" >/dev/null
[[ "$(wc -l < "$log" | tr -d ' ')" == "1" ]] || fail "existing marker did not suppress resolver"

assert_fails "missing resolver" env POLARIS_RUNTIME_DIR="$runtime" "$VALIDATOR" --repo "$repo" --path "$repo/tracked.txt" --project demo --session-id s2 --resolver "$TMP/missing-resolver"
assert_fails "unknown explicit project" env POLARIS_RUNTIME_DIR="$runtime" "$VALIDATOR" --repo "$repo" --path "$repo/tracked.txt" --project missing-project --session-id s2b --resolver "$TMP/missing-resolver"
cat > "$TMP/broken-resolver.sh" <<'EOF'
#!/usr/bin/env bash
echo '{broken'
EOF
chmod +x "$TMP/broken-resolver.sh"
assert_fails "broken payload" env POLARIS_RUNTIME_DIR="$runtime" "$VALIDATOR" --repo "$repo" --path "$repo/tracked.txt" --project demo --session-id s3 --resolver "$TMP/broken-resolver.sh"
cat > "$TMP/wrong-path-resolver.sh" <<EOF
#!/usr/bin/env bash
python3 - <<'PY'
import json
print(json.dumps({
  "scope_root": "$repo",
  "scope_id": "demo",
  "config_path": "$repo/tracked.txt",
  "index_path": "$repo/tracked.txt"
}))
PY
EOF
chmod +x "$TMP/wrong-path-resolver.sh"
assert_fails "wrong canonical paths" env POLARIS_RUNTIME_DIR="$runtime" "$VALIDATOR" --repo "$repo" --path "$repo/tracked.txt" --project demo --session-id s3b --resolver "$TMP/wrong-path-resolver.sh"

no_handbook="$TMP/no-handbook"
git -C "$TMP" init -q no-handbook
printf 'tracked\n' > "$no_handbook/tracked.txt"
git -C "$no_handbook" add tracked.txt
git -C "$no_handbook" commit -qm init
POLARIS_RUNTIME_DIR="$runtime" "$VALIDATOR" --repo "$no_handbook" --path "$no_handbook/tracked.txt" --project demo --session-id s4 --resolver "$ROOT_DIR/scripts/resolve-handbook.sh" >/dev/null

hook_runtime="$TMP/hook-runtime"
payload="$(python3 - "$repo/tracked.txt" <<'PY'
import json, sys
print(json.dumps({"tool_input": {"file_path": sys.argv[1]}}))
PY
)"
printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$repo" POLARIS_PROJECT=demo POLARIS_SESSION_ID=hook-session POLARIS_RUNTIME_DIR="$hook_runtime" POLARIS_HANDBOOK_RESOLVER="$ROOT_DIR/scripts/resolve-handbook.sh" POLARIS_HANDBOOK_VALIDATOR="$VALIDATOR" "$HOOK" >"$TMP/hook.out"
rg -q 'index.md' "$TMP/hook.out" || fail "hook did not surface handbook context"
[[ -n "$(find "$hook_runtime/handbook-load" -type f -name '*.json' -print -quit)" ]] || fail "hook did not write marker"

echo "PASS: handbook lazy-load gate"
