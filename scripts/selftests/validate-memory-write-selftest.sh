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

# ===========================================================================
# DP-282: Hot-membership single canonical definition convergence.
# Hermetic memory dir with >15 fresh-write, no-topic-folder files. Exercises the
# real `memory-hygiene-tiering.py dry-run --json | apply` chain (no bypass env)
# and asserts the durable hot_overflow_demoted signal + validator agreement.
# Covers AC1-AC4 + AC-NEG1 + AC-NEG2.
# ===========================================================================
TIERING="$ROOT/scripts/memory-hygiene-tiering.py"
[[ -f "$TIERING" ]] || fail "DP-282: tiering script missing: $TIERING"

# Guard: this selftest must never run with the apply bypass env set (AC-NEG2).
if [[ "${POLARIS_MEMORY_HYGIENE_APPLY:-}" == "1" ]]; then
  fail "DP-282: selftest must not run with POLARIS_MEMORY_HYGIENE_APPLY=1"
fi

DP282_TODAY="2026-06-04"

# fresh_write_file <path> <name> [extra frontmatter lines...]
# Fresh-write = created within grace, no last_triggered, no trigger_count → Hot
# by classify(), eligible for overflow demotion.
fresh_write_file() {
  local path="$1" name="$2"; shift 2
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s entry\n' "$name"
    printf 'type: feedback\n'
    printf 'created: %s\n' "$DP282_TODAY"
    while [[ $# -gt 0 ]]; do printf '%s\n' "$1"; shift; done
    printf -- '---\n\nbody\n'
  } > "$path"
}

run_hygiene_apply() {
  # Canonical chain: dry-run --json | apply. No bypass env (AC-NEG2).
  local mem="$1"
  python3 "$TIERING" dry-run --json --memory-dir "$mem" --today "$DP282_TODAY" \
    | python3 "$TIERING" apply --memory-dir "$mem" --today "$DP282_TODAY" >/dev/null
}

frontmatter_has_signal() {
  # returns 0 if file has `hot_overflow_demoted: true` in its flat frontmatter
  grep -qE '^hot_overflow_demoted:[[:space:]]*true[[:space:]]*$' "$1"
}

# --- Build hermetic dir: 18 fresh-write flat files, no topic folders ---------
mem="$(make_memory_dir "$TMP/dp282/memory")"
for i in $(seq -w 1 18); do
  fresh_write_file "$mem/fresh_${i}.md" "fresh_${i}"
done
# Two protected files that must NEVER be demoted / signaled (AC-NEG1).
fresh_write_file "$mem/pinned_keep.md" "pinned_keep" \
  "pinned: true" "pinned_reason: user-declared retain forever"
fresh_write_file "$mem/graduated_keep.md" "graduated_keep" \
  "graduated_to: .claude/rules/feedback-and-memory.md"

run_hygiene_apply "$mem"

# --- AC1: overflow flat files carry the signal and stay flat -----------------
signaled=0
for f in "$mem"/fresh_*.md; do
  if frontmatter_has_signal "$f"; then
    signaled=$((signaled + 1))
    [[ "$(dirname "$f")" == "$mem" ]] || fail "AC1: signaled file left flat root: $f"
  fi
done
[[ "$signaled" -ge 1 ]] || fail "AC1: no fresh-write file received hot_overflow_demoted signal"
# 20 Hot candidates (18 fresh + pinned + graduated-is-cold) → capacity 15 means
# at least 18+1(pinned)=19 minus 15 = 4 demoted among the non-pinned fresh files.
[[ "$signaled" -ge 4 ]] || fail "AC1: expected >=4 overflow-demoted signals, got $signaled"

# --- AC-NEG1: pinned & graduated never signaled ------------------------------
# pinned stays flat in Hot; graduated_to is classified Cold and moved to archive/.
if frontmatter_has_signal "$mem/pinned_keep.md"; then
  fail "AC-NEG1: pinned file must never carry hot_overflow_demoted"
fi
graduated_landing="$mem/graduated_keep.md"
[[ -f "$graduated_landing" ]] || graduated_landing="$mem/archive/graduated_keep.md"
[[ -f "$graduated_landing" ]] || fail "AC-NEG1: graduated file vanished: $mem/graduated_keep.md"
if frontmatter_has_signal "$graduated_landing"; then
  fail "AC-NEG1: graduated_to file must never carry hot_overflow_demoted"
fi

# --- AC2: validator excludes signaled files; Hot <= 15; new flat write passes -
# Count files the validator considers Hot after apply.
hot_now="$(python3 - "$mem" "$DP282_TODAY" <<'PY'
import sys, re
from pathlib import Path
from datetime import date
mem = Path(sys.argv[1]); today = date.fromisoformat(sys.argv[2])
FM = re.compile(r"\A---\n(.*?)\n---", re.DOTALL)
HOT_DAYS=30; HOT_TC=5; GRACE=7
def pf(t):
    m=FM.search(t)
    out={}
    if not m: return out
    for raw in m.group(1).splitlines():
        if not raw or raw.startswith("#") or raw.startswith(" ") or ":" not in raw: continue
        k,_,v=raw.partition(":"); v=v.strip()
        if v.lower()=="true": out[k.strip()]=True
        elif v.lower()=="false": out[k.strip()]=False
        else: out[k.strip()]=v
    return out
def pd(v):
    try: return date.fromisoformat(str(v).strip())
    except Exception: return None
def is_hot(fm):
    if fm.get("graduated_to"): return False
    if fm.get("hot_overflow_demoted") is True: return False
    if fm.get("pinned") is True: return True
    try: tc=int(fm.get("trigger_count") or 0)
    except Exception: tc=0
    if tc>=HOT_TC: return True
    lt=pd(fm.get("last_triggered"))
    if lt is not None: return (today-lt).days<=HOT_DAYS
    cr=pd(fm.get("created"))
    if cr is not None: return (today-cr).days<=GRACE
    return False
n=0
for p in mem.iterdir():
    if p.is_file() and p.suffix==".md" and p.name!="MEMORY.md":
        if is_hot(pf(p.read_text())): n+=1
print(n)
PY
)"
[[ "$hot_now" -le 15 ]] || fail "AC2: Hot count after apply must be <= 15, got $hot_now"

# Core AC2: pre-fix bug counted the demoted flat files toward Hot, so EVERY write
# (even re-writing an existing file) stayed blocked at >15. After the fix, a
# re-write of a demoted file is excluded → passes with no hot_soft_limit_exceeded.
demoted_one=""
for f in "$mem"/fresh_*.md; do
  if frontmatter_has_signal "$f"; then demoted_one="$f"; break; fi
done
[[ -n "$demoted_one" ]] || fail "AC2: no demoted file found to re-write"
set +e
out="$("$VALIDATOR" --candidate-path "$demoted_one" --memory-dir "$mem" --today "$DP282_TODAY" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC2: re-write of demoted (excluded) file must pass (rc=$rc): $out"
if grep -q 'hot_soft_limit_exceeded' <<< "$out"; then
  fail "AC2: re-writing a demoted file must not emit hot_soft_limit_exceeded"
fi

# --- AC3: rewriting an existing pinned Hot file is not falsely blocked --------
"$VALIDATOR" --candidate-path "$mem/pinned_keep.md" --memory-dir "$mem" \
  --today "$DP282_TODAY" >/dev/null \
  || fail "AC3: rewrite of existing pinned Hot file must pass"

# --- AC4: re-qualified file is promoted and loses the signal ------------------
# Pick the first signaled file, bump trigger_count >= 5, re-run apply.
requal=""
for f in "$mem"/fresh_*.md; do
  if frontmatter_has_signal "$f"; then requal="$f"; break; fi
done
[[ -n "$requal" ]] || fail "AC4: no signaled file to re-qualify"
# Rewrite with trigger_count: 6 (drop the demotion signal as a real promotion
# would; apply must keep it cleared and keep the file Hot).
fresh_write_file "$requal" "$(basename "$requal" .md)" "trigger_count: 6"
run_hygiene_apply "$mem"
if frontmatter_has_signal "$requal"; then
  fail "AC4: re-qualified file must have hot_overflow_demoted removed"
fi

# --- EC4: apply re-run is idempotent (no spurious churn on signals) ----------
collect_signaled() {
  local mem="$1" f
  for f in "$mem"/*.md; do
    if frontmatter_has_signal "$f"; then printf '%s\n' "$(basename "$f")"; fi
  done | sort
}
before="$(collect_signaled "$mem")"
run_hygiene_apply "$mem"
after="$(collect_signaled "$mem")"
[[ "$before" == "$after" ]] || fail "EC4: apply re-run changed signal set (not idempotent)"

echo "PASS: validate-memory-write-selftest"
