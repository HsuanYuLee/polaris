#!/usr/bin/env bash
# Verifies the public bootstrap task deterministically regenerates the four
# session bootstrap targets and that maintainer docs describe the same contract.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp="$(mktemp -d -t bootstrap-runtime-targets.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/workspace"
mkdir -p "$fixture/scripts/lib" "$fixture/.claude/instructions/core" \
  "$fixture/.claude/instructions/runtime" "$fixture/.claude/rules"

cp "$ROOT/scripts/polaris-bootstrap.sh" "$fixture/scripts/polaris-bootstrap.sh"
cp "$ROOT/scripts/compile-runtime-instructions.sh" "$fixture/scripts/compile-runtime-instructions.sh"
cp "$ROOT/scripts/lib/tool-resolution.sh" "$fixture/scripts/lib/tool-resolution.sh"
cp "$ROOT/scripts/lib/tool-attribution.sh" "$fixture/scripts/lib/tool-attribution.sh"
cp "$ROOT/mise.toml" "$fixture/mise.toml"
cp "$ROOT/.claude/instructions/manifest.yaml" "$fixture/.claude/instructions/manifest.yaml"
cp "$ROOT/.claude/instructions/core/bootstrap.md" "$fixture/.claude/instructions/core/bootstrap.md"
cp "$ROOT/.claude/instructions/runtime/claude.md" "$fixture/.claude/instructions/runtime/claude.md"
cp "$ROOT/.claude/instructions/runtime/codex.md" "$fixture/.claude/instructions/runtime/codex.md"
cp "$ROOT/.claude/instructions/runtime/copilot.md" "$fixture/.claude/instructions/runtime/copilot.md"
find "$ROOT/.claude/rules" -maxdepth 1 -type f -name '*.md' -exec cp {} "$fixture/.claude/rules/" \;

fake_mise="$tmp/mise"
cat > "$fake_mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  trust|install) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$fake_mise"

bash "$fixture/scripts/compile-runtime-instructions.sh" >/dev/null

targets=(
  "CLAUDE.md"
  "AGENTS.md"
  ".codex/AGENTS.md"
  ".github/copilot-instructions.md"
)

for target in "${targets[@]}"; do
  printf '\nHAND-EDITED\n' >> "$fixture/$target"
  if bash "$fixture/scripts/compile-runtime-instructions.sh" --check >/dev/null 2>&1; then
    fail "fixture did not become stale after corrupting $target"
  fi
  POLARIS_TOOLCHAIN_ROOT="$fixture" POLARIS_MISE_BIN="$fake_mise" \
    bash "$fixture/scripts/polaris-bootstrap.sh" --profile core >/dev/null
  bash "$fixture/scripts/compile-runtime-instructions.sh" --check >/dev/null \
    || fail "bootstrap did not regenerate stale runtime target: $target"
done

for doc in "$ROOT/README.md" "$ROOT/polaris-config/polaris-framework/handbook/index.md"; do
  grep -Fq 'mise run bootstrap' "$doc" || fail "$doc missing public bootstrap command"
  grep -Fq 'bash scripts/compile-runtime-instructions.sh' "$doc" \
    || fail "$doc missing direct regeneration command"
  for target in "${targets[@]}"; do
    grep -Fq "$target" "$doc" || fail "$doc missing runtime target $target"
  done
done

for quick_start in "$ROOT/docs/codex-quick-start.md" "$ROOT/docs/codex-quick-start.zh-TW.md"; do
  if grep -Fq '.codex/.generated/rules-manifest.txt' "$quick_start"; then
    fail "$quick_start still documents retired rules-manifest snapshot"
  fi
  grep -Fq '.codex/AGENTS.md' "$quick_start" || fail "$quick_start missing Codex runtime target"
done

echo "PASS: bootstrap regenerates four runtime targets and docs match the contract"
