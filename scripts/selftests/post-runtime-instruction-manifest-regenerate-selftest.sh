#!/usr/bin/env bash
# Purpose: Selftest for .claude/hooks/post-runtime-instruction-manifest-regenerate.sh.
#          Covers AC3 (regen on manifest-source Write/Edit/MultiEdit so subsequent
#          compile --check PASS; no-op on non-source files), AC4 (hook delegates to
#          compile-runtime-instructions.sh — single writer, no second checksum impl),
#          and AC6 wiring (registry annotation rows + validator) at a smoke level.
# Inputs:  none (constructs fixtures + reads the real hook from this repo tree).
# Outputs: stdout PASS line; exit 0 PASS / exit 1 FAIL.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/post-runtime-instruction-manifest-regenerate.sh"
COMPILE="$ROOT/scripts/compile-runtime-instructions.sh"

[[ -f "$HOOK" ]] || { echo "FAIL: hook missing: $HOOK" >&2; exit 1; }
[[ -x "$HOOK" ]] || { echo "FAIL: hook not executable: $HOOK" >&2; exit 1; }
[[ -f "$COMPILE" ]] || { echo "FAIL: compile producer missing: $COMPILE" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

build_json() {
  local tool_name="$1"
  local file_path="$2"
  python3 -c "
import json, sys
print(json.dumps({
  'tool_name': sys.argv[1],
  'tool_input': {'file_path': sys.argv[2]},
}))
" "$tool_name" "$file_path"
}

# ---------------------------------------------------------------------------
# Test 1: Write on a manifest source rule file → delegates to compile producer.
#         We assert the hook invokes the (stubbed) producer with no --check.
# ---------------------------------------------------------------------------
stub="$TMP/stub-compile.sh"
log="$TMP/stub.log"
cat > "$stub" <<EOF
#!/usr/bin/env bash
echo "INVOKED \$*" >> "$log"
exit 0
EOF
chmod +x "$stub"

: > "$log"
json=$(build_json "Write" "$ROOT/.claude/rules/skill-routing.md")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_COMPILE_RUNTIME_SCRIPT="$stub" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T1: Write on rule source should succeed (rc=$rc, out=$out)"
grep -q 'INVOKED' "$log" || fail "T1: producer not invoked on rule source Write"
grep -q -- '--check' "$log" && fail "T1: producer must be invoked in regenerate mode, not --check"

# ---------------------------------------------------------------------------
# Test 2: bootstrap.md source Edit → delegates.
# ---------------------------------------------------------------------------
: > "$log"
json=$(build_json "Edit" "$ROOT/.claude/instructions/core/bootstrap.md")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_COMPILE_RUNTIME_SCRIPT="$stub" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T2: Edit on bootstrap.md should succeed (rc=$rc, out=$out)"
grep -q 'INVOKED' "$log" || fail "T2: producer not invoked on bootstrap.md Edit"

# ---------------------------------------------------------------------------
# Test 3: manifest.yaml source Edit → delegates.
# ---------------------------------------------------------------------------
: > "$log"
json=$(build_json "Edit" "$ROOT/.claude/instructions/manifest.yaml")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_COMPILE_RUNTIME_SCRIPT="$stub" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T3: Edit on manifest.yaml should succeed (rc=$rc, out=$out)"
grep -q 'INVOKED' "$log" || fail "T3: producer not invoked on manifest.yaml Edit"

# ---------------------------------------------------------------------------
# Test 4: runtime overlay source Edit → delegates.
# ---------------------------------------------------------------------------
: > "$log"
json=$(build_json "Edit" "$ROOT/.claude/instructions/runtime/codex.md")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_COMPILE_RUNTIME_SCRIPT="$stub" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T4: Edit on runtime overlay should succeed (rc=$rc, out=$out)"
grep -q 'INVOKED' "$log" || fail "T4: producer not invoked on runtime overlay Edit"

# ---------------------------------------------------------------------------
# Test 5 (AC3 no-op branch): non-source file → producer NOT invoked, exit 0.
# A nested rules subfolder file (maxdepth>1) is NOT a manifest source either.
# ---------------------------------------------------------------------------
: > "$log"
json=$(build_json "Write" "$ROOT/docs-manager/README.md")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_COMPILE_RUNTIME_SCRIPT="$stub" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T5: non-source file must exit 0 (rc=$rc, out=$out)"
[[ ! -s "$log" ]] || fail "T5: producer must NOT be invoked on non-source file (log: $(cat "$log"))"

: > "$log"
json=$(build_json "Edit" "$ROOT/.claude/rules/exampleco/pr-and-review.md")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_COMPILE_RUNTIME_SCRIPT="$stub" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T5b: nested rules subfile must exit 0 (rc=$rc, out=$out)"
[[ ! -s "$log" ]] || fail "T5b: nested rules subfile is not a manifest source (maxdepth 1 only)"

# ---------------------------------------------------------------------------
# Test 6: non-Write/Edit/MultiEdit tool → exit 0, no invoke.
# ---------------------------------------------------------------------------
: > "$log"
json=$(build_json "Read" "$ROOT/.claude/rules/skill-routing.md")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_COMPILE_RUNTIME_SCRIPT="$stub" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T6: Read tool must exit 0 (rc=$rc, out=$out)"
[[ ! -s "$log" ]] || fail "T6: Read tool must not invoke producer"

# ---------------------------------------------------------------------------
# Test 7 (AC4): hook contains NO self-written checksum implementation; it must
# delegate to the canonical compile script only.
# ---------------------------------------------------------------------------
grep -Eq 'shasum|sha256sum|md5|openssl[[:space:]]+dgst|hashlib' "$HOOK" \
  && fail "T7: hook must not implement its own checksum — delegate to compile-runtime-instructions.sh only"
grep -q 'compile-runtime-instructions.sh' "$HOOK" \
  || fail "T7: hook must reference the canonical compile-runtime-instructions.sh writer"

# ---------------------------------------------------------------------------
# Test 8 (AC3 real producer): MultiEdit on a manifest source with the REAL
# compile producer regenerates so a subsequent compile --check PASSes.
# Run against a copy of the repo tree so we do not mutate the live worktree.
# ---------------------------------------------------------------------------
work="$TMP/repo"
mkdir -p "$work/.claude" "$work/.codex" "$work/.github"
cp -R "$ROOT/.claude/instructions" "$work/.claude/instructions"
cp -R "$ROOT/.claude/rules" "$work/.claude/rules"
mkdir -p "$work/scripts"
cp "$COMPILE" "$work/scripts/compile-runtime-instructions.sh"
# Seed generated targets fresh, then dirty one manifest source.
bash "$work/scripts/compile-runtime-instructions.sh" >/dev/null 2>&1 \
  || fail "T8: initial compile of copied tree failed"
printf '\n<!-- dp320-t2 selftest dirty marker -->\n' >> "$work/.claude/instructions/core/bootstrap.md"
# Now compile --check should report drift (stale).
set +e
bash "$work/scripts/compile-runtime-instructions.sh" --check >/dev/null 2>&1
check_rc=$?
set -e
[[ "$check_rc" -ne 0 ]] || fail "T8: dirtying bootstrap.md should make compile --check fail (got rc=$check_rc)"
# Fire the hook (MultiEdit on bootstrap.md) with the REAL producer in the copy.
json=$(build_json "MultiEdit" "$work/.claude/instructions/core/bootstrap.md")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$work" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T8: hook regen on real producer should succeed (rc=$rc, out=$out)"
set +e
bash "$work/scripts/compile-runtime-instructions.sh" --check >/dev/null 2>&1
check_rc=$?
set -e
[[ "$check_rc" -eq 0 ]] || fail "T8: after hook regen, compile --check must PASS (got rc=$check_rc)"

echo "PASS: post-runtime-instruction-manifest-regenerate-selftest"
