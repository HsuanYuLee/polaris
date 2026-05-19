#!/usr/bin/env bash
# pre-memory-write-hook-selftest.sh — covers Write / Edit / MultiEdit JSON
# reconstruction, non-memory paths, MEMORY.md direct write, env-var bypass,
# and POLARIS_MEMORY_DIR override.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/pre-memory-write.sh"

[[ -x "$HOOK" ]] || { echo "FAIL: hook missing or not executable: $HOOK" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

run_hook() {
  local json="$1"
  # Hook reads JSON from stdin. Capture rc + stderr.
  set +e
  out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" "$HOOK" 2>&1)"
  rc=$?
  set -e
  printf '%s' "$out"
  return "$rc"
}

# ---------------------------------------------------------------------------
# Test 1: Write to non-memory path → PASS (exit 0, no output)
# ---------------------------------------------------------------------------
mkdir -p "$TMP/random"
non_memory="$TMP/random/file.txt"
json=$(python3 -c "import json; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':'$non_memory','content':'hello'}}))")
set +e
run_hook "$json" >/dev/null 2>&1; rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T1: non-memory path must pass through (rc=$rc)"

# ---------------------------------------------------------------------------
# Test 2: Write with valid frontmatter → PASS (POLARIS_MEMORY_DIR scoped)
# ---------------------------------------------------------------------------
mem="$TMP/t2/memory"
mkdir -p "$mem"
file_path="$mem/sample.md"
content=$(cat <<'EOF'
---
name: t2
description: t2
type: feedback
created: 2026-05-20
---

body
EOF
)
json=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':'$file_path','content':sys.stdin.read()}}))" <<< "$content")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T2: valid Write should pass (rc=$rc, out=$out)"

# ---------------------------------------------------------------------------
# Test 3: Write with bad frontmatter → FAIL with structured stderr
# ---------------------------------------------------------------------------
mem="$TMP/t3/memory"
mkdir -p "$mem"
file_path="$mem/bad.md"
content=$(cat <<'EOF'
---
name: bad
type: feedback
---

body
EOF
)
json=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':'$file_path','content':sys.stdin.read()}}))" <<< "$content")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T3: bad Write should exit 2 (rc=$rc)"
grep -q 'POLARIS_MEMORY_WRITE_BLOCKED' <<< "$out" || fail "T3: missing structured stderr code"

# ---------------------------------------------------------------------------
# Test 4: Edit reconstruction — existing file, replace one chunk
# ---------------------------------------------------------------------------
mem="$TMP/t4/memory"
mkdir -p "$mem"
file_path="$mem/entry.md"
cat > "$file_path" <<'EOF'
---
name: entry
description: existing
type: feedback
created: 2026-05-20
---

OLD-BODY
EOF
old_string="OLD-BODY"
new_string="NEW-BODY"
json=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Edit',
  'tool_input': {
    'file_path': '$file_path',
    'old_string': '$old_string',
    'new_string': '$new_string',
    'replace_all': False,
  }
}))")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T4: Edit on valid file should pass (rc=$rc, out=$out)"

# Edit that REMOVES `created:` → should now fail required-field check
old_string="created: 2026-05-20"
new_string=""
json=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Edit',
  'tool_input': {
    'file_path': '$file_path',
    'old_string': '$old_string',
    'new_string': '$new_string',
    'replace_all': False,
  }
}))")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T4: Edit removing created should fail (rc=$rc)"
grep -q 'frontmatter_required_field_missing' <<< "$out" \
  || fail "T4: Edit removal must report required-field violation"

# ---------------------------------------------------------------------------
# Test 5: MultiEdit reconstruction — apply edits in order
# ---------------------------------------------------------------------------
mem="$TMP/t5/memory"
mkdir -p "$mem"
file_path="$mem/multi.md"
cat > "$file_path" <<'EOF'
---
name: multi
description: multi
type: feedback
created: 2026-05-20
---

ALPHA BETA
EOF
json=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'MultiEdit',
  'tool_input': {
    'file_path': '$file_path',
    'edits': [
      {'old_string': 'ALPHA', 'new_string': 'A1', 'replace_all': False},
      {'old_string': 'BETA', 'new_string': 'B2', 'replace_all': False},
    ],
  }
}))")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T5: MultiEdit should pass (rc=$rc, out=$out)"

# MultiEdit removing `name:` → required-field fail
json=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'MultiEdit',
  'tool_input': {
    'file_path': '$file_path',
    'edits': [
      {'old_string': 'name: multi', 'new_string': '', 'replace_all': False},
    ],
  }
}))")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T5: MultiEdit removing name should fail (rc=$rc)"
grep -q 'frontmatter_required_field_missing' <<< "$out" \
  || fail "T5: MultiEdit must surface required-field violation"

# ---------------------------------------------------------------------------
# Test 6: Direct MEMORY.md Write → FAIL (no bypass)
# ---------------------------------------------------------------------------
mem="$TMP/t6/memory"
mkdir -p "$mem"
file_path="$mem/MEMORY.md"
json=$(python3 -c "import json; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':'$file_path','content':'hand-edited'}}))")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T6: MEMORY.md Write must exit 2"
grep -q 'memory_md_direct_write' <<< "$out" \
  || fail "T6: memory_md_direct_write code missing"

# Bypass via POLARIS_MEMORY_HYGIENE_APPLY=1 → PASS
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" POLARIS_MEMORY_HYGIENE_APPLY=1 "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T6 bypass: hygiene apply env should let MEMORY.md write pass (rc=$rc, out=$out)"

# ---------------------------------------------------------------------------
# Test 7: POLARIS_MEMORY_DIR override — production layout independence
# ---------------------------------------------------------------------------
custom_mem="$TMP/t7/override-memory"
mkdir -p "$custom_mem"
file_path="$custom_mem/x.md"
content=$(cat <<'EOF'
---
name: x
description: x
type: feedback
created: 2026-05-20
---

body
EOF
)
json=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':'$file_path','content':sys.stdin.read()}}))" <<< "$content")
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$custom_mem" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T7: POLARIS_MEMORY_DIR override must scope memory detection (rc=$rc)"

# Same file path without POLARIS_MEMORY_DIR set AND not under ~/.claude/projects/*/memory
# → hook should treat as non-memory and pass through.
set +e
out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" "$HOOK" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T7: unscoped path must pass (rc=$rc)"

# ---------------------------------------------------------------------------
# Test 8: Escalation counter increments and surfaces banner at 3
# ---------------------------------------------------------------------------
mem="$TMP/t8/memory"
mkdir -p "$mem"
file_path="$mem/escalate.md"
json=$(python3 -c "import json; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':'$file_path','content':'---\\nname: bad\\n---\\nbody\\n'}}))")
banner_seen=0
for attempt in 1 2 3; do
  set +e
  out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" POLARIS_MEMORY_DIR="$mem" "$HOOK" 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "T8: attempt $attempt should still exit 2 (rc=$rc)"
  if [[ "$attempt" -ge 3 ]]; then
    if grep -q 'POLARIS_MEMORY_WRITE_ESCALATION' <<< "$out"; then
      banner_seen=1
    fi
  fi
done
[[ "$banner_seen" -eq 1 ]] || fail "T8: escalation banner missing after 3 attempts"

echo "PASS: pre-memory-write-hook-selftest"
