#!/usr/bin/env bash
# Purpose: DP-277 T1 — topic-folder index writer + disk-driven emit-index contract.
# Inputs:  none (hermetic; builds tmpdir memory_dir fixtures)
# Outputs: PASS line on stdout, exit 0; FAIL line on stderr + exit 1 on failure.
#
# Verifies:
#   AC1: apply topic-index lists existing (N) + just-moved (M) files, each
#        summary from that file's OWN frontmatter.
#   AC2: emit-index per-topic pointer is disk-driven (folder with files shows
#        its T/ pointer + count even when flat has no topic-T file).
#   AC3: emit-index + apply are idempotent (byte-identical between two runs).
#   AC4: apply index entry count == emit-index "— N entries" count (shared enum).
#   AC-NEG1: archive/ is excluded from per-topic discovery.
#   AC-NEG2: missing description / missing name falls back gracefully (exit 0).
#   AC-NEG3: dry-run orphan/missing lists do not contain topic-folder files.

set -euo pipefail

REPO="${REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
TIERING="$REPO/scripts/memory-hygiene-tiering.py"
VALIDATOR="$REPO/scripts/validate-memory-hygiene-plan.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$TIERING" ]] || fail "$TIERING not found"

WORK="$(mktemp -d -t mh-topic-XXXX)"
trap 'rm -rf "$WORK"' EXIT

# === AC1: existing N=2 + moved M=1 → index lists 3, own-frontmatter summaries ===
MD1="$WORK/ac1/memory"
mkdir -p "$MD1/cwv-epics"

# N=2 existing files already in the topic folder, each with OWN frontmatter
cat >"$MD1/cwv-epics/existing_a.md" <<'EOF'
---
name: Existing A
description: summary-for-existing-a
type: project
created: 2026-04-01
topic: cwv-epics
---
body a
EOF
cat >"$MD1/cwv-epics/existing_b.md" <<'EOF'
---
name: Existing B
description: summary-for-existing-b
type: project
created: 2026-04-01
topic: cwv-epics
---
body b
EOF
# Pre-existing topic index listing only the 2 prior files
cat >"$MD1/cwv-epics/index.md" <<'EOF'
# cwv-epics — Warm Memory

Topic folder for memory files moved out of Hot index.

## Files

- [Existing A](existing_a.md) — summary-for-existing-a
- [Existing B](existing_b.md) — summary-for-existing-b
EOF

# M=1 flat file that should classify warm with topic cwv-epics (stale snapshot)
cat >"$MD1/moved_c.md" <<'EOF'
---
name: Moved C
description: summary-for-moved-c
type: project
topic: cwv-epics
created: 2026-01-01
snapshot_of: DP-191
snapshot_taken: 2026-01-02
---
body c
EOF
printf '# Memory Index\n\n' >"$MD1/MEMORY.md"

# Build a dry-run plan and force moved_c into warm/cwv-epics deterministically.
plan1="$WORK/ac1/plan.json"
python3 "$TIERING" dry-run --json --memory-dir "$MD1" >"$plan1"
python3 - "$plan1" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for c in d["classifications"]:
    if c["file"] == "moved_c.md":
        c["tier"] = "warm"
        c["topic"] = "cwv-epics"
        c["reason"] = "forced warm topic for AC1 selftest"
        if isinstance(c.get("flags"), dict):
            c["flags"]["graduated_feedback"] = False
json.dump(d, open(p, "w"))
PY

# Validate (verdict to stderr on PASS) then apply
"$VALIDATOR" --input "$plan1" >/dev/null 2>"$WORK/ac1/val.err" \
  || { cat "$WORK/ac1/val.err" >&2; fail "AC1 validator rejected forced plan"; }
python3 "$TIERING" apply --memory-dir "$MD1" <"$plan1" >"$WORK/ac1/apply.out" 2>&1 \
  || { cat "$WORK/ac1/apply.out" >&2; fail "AC1 apply exited non-zero"; }

idx1="$MD1/cwv-epics/index.md"
[[ -f "$idx1" ]] || fail "AC1 topic index missing after apply"
n_entries="$(grep -c '^- \[' "$idx1" || true)"
[[ "$n_entries" -eq 3 ]] || { cat "$idx1" >&2; fail "AC1 index has $n_entries entries (expected 3 = N+M)"; }
grep -q 'summary-for-existing-a' "$idx1" || { cat "$idx1" >&2; fail "AC1 missing existing_a own summary"; }
grep -q 'summary-for-existing-b' "$idx1" || { cat "$idx1" >&2; fail "AC1 missing existing_b own summary"; }
grep -q 'summary-for-moved-c' "$idx1" || { cat "$idx1" >&2; fail "AC1 missing moved_c own summary"; }

# === AC2: flat has NO cwv-epics-topic file, folder has 2 → emit-index pointer ===
MD2="$WORK/ac2/memory"
mkdir -p "$MD2/cwv-epics"
cat >"$MD2/cwv-epics/in_folder_1.md" <<'EOF'
---
name: In Folder 1
description: folder file one
type: project
created: 2026-04-01
topic: cwv-epics
---
body 1
EOF
cat >"$MD2/cwv-epics/in_folder_2.md" <<'EOF'
---
name: In Folder 2
description: folder file two
type: project
created: 2026-04-01
topic: cwv-epics
---
body 2
EOF
# A flat Hot file with NO cwv-epics topic (keeps MEMORY.md non-empty)
cat >"$MD2/hot_flat.md" <<'EOF'
---
name: Hot Flat
description: a hot flat entry
type: feedback
last_triggered: 2026-05-20
trigger_count: 3
created: 2026-05-01
---
body
EOF
printf '# Memory Index\n\n' >"$MD2/MEMORY.md"

python3 "$TIERING" --emit-index --memory-dir "$MD2" --today 2026-05-20 >/dev/null
mem2="$MD2/MEMORY.md"
grep -q '\[cwv-epics/\](cwv-epics/index.md)' "$mem2" \
  || { cat "$mem2" >&2; fail "AC2 missing disk-driven cwv-epics/ pointer"; }
grep -q '\[cwv-epics/\](cwv-epics/index.md) — 2 entries' "$mem2" \
  || { cat "$mem2" >&2; fail "AC2 cwv-epics/ pointer count != 2 entries"; }

# === AC3: idempotency — emit-index twice byte-identical; apply twice (no 2nd move) ===
python3 "$TIERING" --emit-index --memory-dir "$MD2" --today 2026-05-20 >/dev/null
cp "$mem2" "$WORK/ac3-emit-1.md"
python3 "$TIERING" --emit-index --memory-dir "$MD2" --today 2026-05-20 >/dev/null
cmp "$WORK/ac3-emit-1.md" "$mem2" || fail "AC3 emit-index not idempotent (MEMORY.md differs)"

# apply idempotency: second apply has no remaining moves (all files already placed)
cp "$idx1" "$WORK/ac3-idx-1.md"
cp "$MD1/MEMORY.md" "$WORK/ac3-mem-1.md"
plan1b="$WORK/ac1/plan2.json"
python3 "$TIERING" dry-run --json --memory-dir "$MD1" >"$plan1b"
"$VALIDATOR" --input "$plan1b" >/dev/null 2>"$WORK/ac3-val.err" \
  || { cat "$WORK/ac3-val.err" >&2; fail "AC3 validator rejected 2nd-run plan"; }
python3 "$TIERING" apply --memory-dir "$MD1" <"$plan1b" >"$WORK/ac3-apply2.out" 2>&1 \
  || { cat "$WORK/ac3-apply2.out" >&2; fail "AC3 second apply exited non-zero"; }
cmp "$WORK/ac3-idx-1.md" "$idx1" || fail "AC3 topic index not idempotent across applies"

# === AC4: apply index entry count == emit-index — N entries count ===
# Refresh MEMORY.md for MD1 via emit-index, then compare cwv-epics count
python3 "$TIERING" --emit-index --memory-dir "$MD1" --today 2026-05-20 >/dev/null
apply_count="$(grep -c '^- \[' "$idx1" || true)"
emit_count="$(grep -oE '\[cwv-epics/\]\(cwv-epics/index.md\) — [0-9]+ entries' "$MD1/MEMORY.md" \
  | grep -oE '[0-9]+' | head -1)"
[[ -n "$emit_count" ]] || { cat "$MD1/MEMORY.md" >&2; fail "AC4 no cwv-epics count in MEMORY.md"; }
[[ "$apply_count" -eq "$emit_count" ]] \
  || fail "AC4 count mismatch: index.md=$apply_count vs MEMORY.md=$emit_count"

# === AC-NEG1: archive/ excluded from per-topic discovery ===
MD3="$WORK/neg1/memory"
mkdir -p "$MD3/archive"
cat >"$MD3/archive/old_dead.md" <<'EOF'
---
name: Old Dead
description: archived file
type: feedback
created: 2026-01-01
---
body
EOF
cat >"$MD3/hot_flat.md" <<'EOF'
---
name: Hot Flat
description: a hot flat entry
type: feedback
last_triggered: 2026-05-20
trigger_count: 3
created: 2026-05-01
---
body
EOF
printf '# Memory Index\n\n' >"$MD3/MEMORY.md"
python3 "$TIERING" --emit-index --memory-dir "$MD3" --today 2026-05-20 >/dev/null
if grep -q 'archive/](archive/index.md)' "$MD3/MEMORY.md"; then
  cat "$MD3/MEMORY.md" >&2
  fail "AC-NEG1 archive/ leaked into per-topic pointers"
fi

# === AC-NEG2: missing description (and missing name) → graceful, valid markdown ===
MD4="$WORK/neg2/memory"
mkdir -p "$MD4/cwv-epics"
# file missing description
cat >"$MD4/cwv-epics/no_desc.md" <<'EOF'
---
name: No Desc
type: project
created: 2026-04-01
topic: cwv-epics
---
body
EOF
# file missing name (link text must fall back to filename)
cat >"$MD4/cwv-epics/no_name.md" <<'EOF'
---
description: has-desc-no-name
type: project
created: 2026-04-01
topic: cwv-epics
---
body
EOF
cat >"$MD4/moved_x.md" <<'EOF'
---
name: Moved X
description: summary-x
type: project
topic: cwv-epics
created: 2026-01-01
snapshot_of: DP-191
snapshot_taken: 2026-01-02
---
body
EOF
printf '# Memory Index\n\n' >"$MD4/MEMORY.md"
plan4="$WORK/neg2/plan.json"
python3 "$TIERING" dry-run --json --memory-dir "$MD4" >"$plan4"
python3 - "$plan4" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for c in d["classifications"]:
    if c["file"] == "moved_x.md":
        c["tier"] = "warm"
        c["topic"] = "cwv-epics"
        c["reason"] = "forced warm topic for AC-NEG2 selftest"
        if isinstance(c.get("flags"), dict):
            c["flags"]["graduated_feedback"] = False
json.dump(d, open(p, "w"))
PY
"$VALIDATOR" --input "$plan4" >/dev/null 2>"$WORK/neg2/val.err" \
  || { cat "$WORK/neg2/val.err" >&2; fail "AC-NEG2 validator rejected plan"; }
neg2_exit=0
python3 "$TIERING" apply --memory-dir "$MD4" <"$plan4" >"$WORK/neg2/apply.out" 2>&1 || neg2_exit=$?
[[ "$neg2_exit" -eq 0 ]] || { cat "$WORK/neg2/apply.out" >&2; fail "AC-NEG2 apply exited $neg2_exit (expected 0)"; }
python3 "$TIERING" --emit-index --memory-dir "$MD4" --today 2026-05-20 >/dev/null
idx4="$MD4/cwv-epics/index.md"
# missing-name file must fall back to filename for link text
grep -q '\[no_name.md\](no_name.md)' "$idx4" \
  || { cat "$idx4" >&2; fail "AC-NEG2 missing-name link did not fall back to filename"; }
# missing-description file must render without a dangling " — "
if grep -qE '^- \[No Desc\]\(no_desc\.md\) — ?$' "$idx4"; then
  cat "$idx4" >&2
  fail "AC-NEG2 missing-description rendered a dangling em-dash"
fi
grep -q '\[No Desc\](no_desc.md)' "$idx4" \
  || { cat "$idx4" >&2; fail "AC-NEG2 no_desc entry missing"; }

# === AC-NEG3: dry-run orphan/missing lists must NOT contain topic-folder files ===
dryrun_out="$(python3 "$TIERING" dry-run --memory-dir "$MD2" 2>&1)"
if echo "$dryrun_out" | grep -q 'in_folder_1.md\|in_folder_2.md'; then
  echo "$dryrun_out" >&2
  fail "AC-NEG3 dry-run referenced topic-folder files (collect must scan flat only)"
fi

echo "PASS: memory-hygiene-topic-folder-index selftest (AC1/2/3/4 + NEG1/2/3)"
