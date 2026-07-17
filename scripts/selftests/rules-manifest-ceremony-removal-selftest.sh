#!/usr/bin/env bash
# Verifies DP-423 T6 removes the rules-manifest snapshot ceremony while
# retaining deterministic freshness checks for the four real runtime targets.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPILER="$ROOT/scripts/compile-runtime-instructions.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

snapshots=(
  ".codex/.generated/rules-manifest.txt"
  ".github/.generated/copilot-rules-manifest.txt"
)

for snapshot in "${snapshots[@]}"; do
  [[ ! -e "$ROOT/$snapshot" ]] || fail "retired snapshot still exists: $snapshot"
done

cluster_sources=(
  "$ROOT/.claude/hooks/post-runtime-instruction-manifest-regenerate.sh"
  "$ROOT/scripts/compile-runtime-instructions.sh"
  "$ROOT/scripts/sync-to-polaris.sh"
  "$ROOT/scripts/selftests/compile-runtime-instructions-selftest.sh"
  "$ROOT/scripts/selftests/gate-runtime-instruction-manifest-selftest.sh"
  "$ROOT/scripts/selftests/post-runtime-instruction-manifest-regenerate-selftest.sh"
  "$ROOT/scripts/manifest.json"
  "$ROOT/.claude/rules/mechanism-registry.md"
)

if rg -n 'rules-manifest\.txt|write_manifest_snapshot|write_generated_manifest_targets' "${cluster_sources[@]}"; then
  fail "rules-manifest producer/copy/assertion cluster still has a live referrer"
fi

tmp="$(mktemp -d -t rules-manifest-removal.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/.claude/instructions/core" \
  "$tmp/.claude/instructions/runtime" "$tmp/.claude/rules" \
  "$tmp/.codex" "$tmp/.github"
cp "$COMPILER" "$tmp/scripts/compile-runtime-instructions.sh"
cp "$ROOT/.claude/instructions/manifest.yaml" "$tmp/.claude/instructions/manifest.yaml"
cp "$ROOT/.claude/instructions/core/bootstrap.md" "$tmp/.claude/instructions/core/bootstrap.md"
cp "$ROOT/.claude/instructions/runtime/claude.md" "$tmp/.claude/instructions/runtime/claude.md"
cp "$ROOT/.claude/instructions/runtime/codex.md" "$tmp/.claude/instructions/runtime/codex.md"
cp "$ROOT/.claude/instructions/runtime/copilot.md" "$tmp/.claude/instructions/runtime/copilot.md"
find "$ROOT/.claude/rules" -maxdepth 1 -type f -name '*.md' -exec cp {} "$tmp/.claude/rules/" \;

bash "$tmp/scripts/compile-runtime-instructions.sh" >/dev/null

targets=(
  "CLAUDE.md"
  "AGENTS.md"
  ".codex/AGENTS.md"
  ".github/copilot-instructions.md"
)

for target in "${targets[@]}"; do
  [[ -f "$tmp/$target" ]] || fail "compiler did not produce runtime target: $target"
done
for snapshot in "${snapshots[@]}"; do
  [[ ! -e "$tmp/$snapshot" ]] || fail "compiler recreated retired snapshot: $snapshot"
done

# A rule-body-only edit does not change the generated rule index or runtime
# bodies, so it must no longer demand a checksum snapshot regeneration.
printf '\n<!-- body-only edit intentionally outside generated targets -->\n' \
  >> "$tmp/.claude/rules/canonical-contract-governance.md"
bash "$tmp/scripts/compile-runtime-instructions.sh" --check >/dev/null \
  || fail "rule-body-only edit still triggers retired snapshot freshness"

# Each real runtime target remains independently freshness-gated.
for target in "${targets[@]}"; do
  printf '\nHAND-EDITED\n' >> "$tmp/$target"
  if bash "$tmp/scripts/compile-runtime-instructions.sh" --check >/dev/null 2>&1; then
    fail "compile --check did not reject stale runtime target: $target"
  fi
  bash "$tmp/scripts/compile-runtime-instructions.sh" >/dev/null
done

echo "PASS: rules-manifest ceremony removed; four runtime targets remain freshness-gated"
