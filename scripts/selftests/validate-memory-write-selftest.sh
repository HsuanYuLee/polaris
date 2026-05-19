#!/usr/bin/env bash
# validate-memory-write-selftest.sh — covers required-fields / pinned_reason /
# topic / Hot soft-limit / MEMORY.md direct-write / bypass paths.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-memory-write.sh"

if [[ ! -x "$VALIDATOR" ]]; then
  echo "FAIL: validator missing or not executable: $VALIDATOR" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

valid_frontmatter() {
  cat <<EOF
---
name: $1
description: $1 description
type: feedback
created: 2026-05-20
EOF
  shift
  while [[ $# -gt 0 ]]; do
    printf '%s\n' "$1"
    shift
  done
  printf -- '---\n\nbody\n'
}

make_memory_dir() {
  local dir="$1"
  mkdir -p "$dir"
  echo "$dir"
}

# ---------------------------------------------------------------------------
# T1: PASS — valid frontmatter
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t1/memory")"
file="$mem/sample.md"
valid_frontmatter "T1 sample" > "$file"
"$VALIDATOR" --candidate-path "$file" --memory-dir "$mem" --today 2026-05-20 >/dev/null \
  || fail "T1: valid frontmatter should pass"

# ---------------------------------------------------------------------------
# T2: FAIL — missing required field (no description)
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t2/memory")"
file="$mem/bad.md"
cat > "$file" <<'EOF'
---
name: bad
type: feedback
created: 2026-05-20
---

body
EOF
set +e
out="$("$VALIDATOR" --candidate-path "$file" --memory-dir "$mem" --today 2026-05-20 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T2: missing description should exit 2 (got $rc)"
grep -q 'frontmatter_required_field_missing' <<< "$out" \
  || fail "T2: missing-field error code not in stderr"
grep -q 'description' <<< "$out" \
  || fail "T2: stderr must name the missing field"

# ---------------------------------------------------------------------------
# T3: FAIL — pinned: true without pinned_reason
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t3/memory")"
file="$mem/pinned.md"
cat > "$file" <<'EOF'
---
name: pinned
description: pinned without reason
type: feedback
created: 2026-05-20
pinned: true
---

body
EOF
set +e
out="$("$VALIDATOR" --candidate-path "$file" --memory-dir "$mem" --today 2026-05-20 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T3: pinned without reason should exit 2"
grep -q 'pinned_missing_reason' <<< "$out" \
  || fail "T3: pinned_missing_reason code expected"

# Same setup but with pinned_reason → PASS
cat > "$file" <<'EOF'
---
name: pinned
description: pinned with reason
type: feedback
created: 2026-05-20
pinned: true
pinned_reason: user-declared retain forever
---

body
EOF
"$VALIDATOR" --candidate-path "$file" --memory-dir "$mem" --today 2026-05-20 >/dev/null \
  || fail "T3: pinned with reason should pass"

# ---------------------------------------------------------------------------
# T4: FAIL — topic refers to non-existent folder
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t4/memory")"
file="$mem/topical.md"
cat > "$file" <<'EOF'
---
name: topical
description: topic missing folder
type: project
created: 2026-05-20
topic: nonexistent-topic
---

body
EOF
set +e
out="$("$VALIDATOR" --candidate-path "$file" --memory-dir "$mem" --today 2026-05-20 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T4: missing topic folder should exit 2"
grep -q 'topic_folder_missing' <<< "$out" || fail "T4: topic_folder_missing code expected"

# Create the topic folder → PASS
mkdir -p "$mem/nonexistent-topic"
"$VALIDATOR" --candidate-path "$file" --memory-dir "$mem" --today 2026-05-20 >/dev/null \
  || fail "T4: existing topic folder should pass"

# ---------------------------------------------------------------------------
# T5: FAIL — Hot soft-limit (new file would push count > 3)
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t5/memory")"
for i in 1 2 3; do
  cat > "$mem/hot${i}.md" <<EOF
---
name: hot${i}
description: hot ${i}
type: feedback
created: 2026-05-15
last_triggered: 2026-05-15
trigger_count: 6
---

body
EOF
done
candidate="$mem/new-hot.md"
cat > "$candidate" <<'EOF'
---
name: new-hot
description: new hot
type: feedback
created: 2026-05-20
pinned: true
pinned_reason: ensure hot
---

body
EOF
set +e
out="$("$VALIDATOR" --candidate-path "$candidate" --memory-dir "$mem" --today 2026-05-20 --hot-soft-limit 3 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T5: Hot soft-limit exceeded should exit 2 (got $rc)"
grep -q 'hot_soft_limit_exceeded' <<< "$out" || fail "T5: hot_soft_limit_exceeded code expected"
grep -q 'soft limit 3' <<< "$out" || fail "T5: stderr must surface soft limit"
grep -q 'Oldest candidates' <<< "$out" || fail "T5: stderr must list oldest candidates"

# Same setup with --hot-soft-limit 5 → PASS
"$VALIDATOR" --candidate-path "$candidate" --memory-dir "$mem" --today 2026-05-20 --hot-soft-limit 5 >/dev/null \
  || fail "T5: under soft limit should pass"

# ---------------------------------------------------------------------------
# T6: FAIL — direct write to MEMORY.md (no bypass)
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t6/memory")"
touch "$mem/MEMORY.md"
set +e
out="$("$VALIDATOR" --candidate-path "$mem/MEMORY.md" --candidate-content - --memory-dir "$mem" --today 2026-05-20 2>&1 <<< "anything")"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "T6: MEMORY.md direct write should exit 2 (got $rc)"
grep -q 'memory_md_direct_write' <<< "$out" || fail "T6: memory_md_direct_write code expected"

# Bypass → PASS
POLARIS_MEMORY_HYGIENE_APPLY=1 "$VALIDATOR" \
  --candidate-path "$mem/MEMORY.md" \
  --candidate-content - \
  --memory-dir "$mem" \
  --today 2026-05-20 >/dev/null <<< "anything" \
  || fail "T6: POLARIS_MEMORY_HYGIENE_APPLY=1 should bypass"

# ---------------------------------------------------------------------------
# T7: PASS — non-memory path skipped (validator never enforces outside memory)
# ---------------------------------------------------------------------------
mkdir -p "$TMP/t7/outside"
file="$TMP/t7/outside/not-memory.md"
echo "no frontmatter" > "$file"
"$VALIDATOR" --candidate-path "$file" --today 2026-05-20 >/dev/null \
  || fail "T7: non-memory path should pass through"

# ---------------------------------------------------------------------------
# T8: PASS — candidate inside topic folder bypasses folder existence check
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t8/memory")"
mkdir -p "$mem/topical"
file="$mem/topical/entry.md"
cat > "$file" <<'EOF'
---
name: in-topic
description: in topic
type: project
created: 2026-05-20
topic: topical
---

body
EOF
"$VALIDATOR" --candidate-path "$file" --memory-dir "$mem" --today 2026-05-20 >/dev/null \
  || fail "T8: candidate inside topic folder should pass"

# ---------------------------------------------------------------------------
# T9: candidate-content stream — content not on disk
# ---------------------------------------------------------------------------
mem="$(make_memory_dir "$TMP/t9/memory")"
file="$mem/stream.md"  # never written to disk
set +e
out="$("$VALIDATOR" --candidate-path "$file" --candidate-content - --memory-dir "$mem" --today 2026-05-20 2>&1 <<EOF
---
name: stream
description: stream
type: feedback
created: 2026-05-20
---

body
EOF
)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "T9: stream candidate should pass (rc=$rc)"

echo "PASS: validate-memory-write-selftest"
