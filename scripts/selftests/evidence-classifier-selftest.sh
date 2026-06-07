#!/usr/bin/env bash
# Purpose: DP-294 T4 / AC4+AC5 — selftest for scripts/lib/evidence-classifier.sh.
# Inputs:  none (hermetic tmp git repo + tmp completion-gate markers).
# Outputs: PASS/FAIL lines; exit 0 (all pass) / 1 (any fail).
# Covers:  classify metadata_only / release_bump / behavioral (incl. mixed
#          behavioral fail-closed + empty fail-closed); marker-pass valid PASS,
#          missing marker FAIL, stale head FAIL, non-PASS status FAIL.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLS="$ROOT/scripts/lib/evidence-classifier.sh"
[[ -x "$CLS" ]] || { echo "FAIL: missing/not executable: $CLS" >&2; exit 1; }

TMP="$(mktemp -d -t evidence-classifier-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

# --- hermetic git repo --------------------------------------------------------
R="$TMP/repo"
mkdir -p "$R"
git -C "$R" init -q -b main
git -C "$R" config user.email selftest@example.com
git -C "$R" config user.name Selftest
echo "seed" >"$R/README.md"
printf '0.0.0\n' >"$R/VERSION"
printf '# changelog\n' >"$R/CHANGELOG.md"
mkdir -p "$R/scripts"
printf '#!/usr/bin/env bash\necho seed\n' >"$R/scripts/x.sh"
git -C "$R" add -A
git -C "$R" commit -q -m "seed"
BASE="$(git -C "$R" rev-parse HEAD)"

classify_range() { bash "$CLS" classify --repo "$R" --range "$1" 2>/dev/null; }
classify_head()  { bash "$CLS" classify --repo "$R" --head "$1" 2>/dev/null; }

# --- release_bump: VERSION + CHANGELOG only -----------------------------------
printf '0.0.1\n' >"$R/VERSION"
printf '# changelog\n- 0.0.1\n' >"$R/CHANGELOG.md"
git -C "$R" add -A; git -C "$R" commit -q -m "release bump"
H_REL="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_REL")" == "release_bump" ]] && ok || bad "VERSION+CHANGELOG -> release_bump"

# --- metadata_only: docs (*.md) only ------------------------------------------
printf 'more docs\n' >>"$R/README.md"
echo "extra" >"$R/NOTES.md"
git -C "$R" add -A; git -C "$R" commit -q -m "docs only"
H_META="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_META")" == "metadata_only" ]] && ok || bad "docs-only -> metadata_only"

# --- behavioral: a script change ----------------------------------------------
printf '#!/usr/bin/env bash\necho changed\n' >"$R/scripts/x.sh"
git -C "$R" add -A; git -C "$R" commit -q -m "behavioral script"
H_BEH="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_BEH")" == "behavioral" ]] && ok || bad ".sh change -> behavioral"

# --- adversarial: VERSION bump MIXED with a behavioral change -> behavioral ----
printf '0.0.2\n' >"$R/VERSION"
printf '#!/usr/bin/env bash\necho mixed\n' >"$R/scripts/x.sh"
git -C "$R" add -A; git -C "$R" commit -q -m "version + behavioral"
H_MIX="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_MIX")" == "behavioral" ]] && ok || bad "VERSION+.sh mixed -> behavioral (fail-closed)"

# --- empty range -> behavioral (fail-closed) ----------------------------------
[[ "$(classify_range "${H_MIX}..${H_MIX}")" == "behavioral" ]] && ok || bad "empty range -> behavioral"

# --- range spanning behavioral commit -> behavioral ---------------------------
[[ "$(classify_range "${BASE}..${H_BEH}")" == "behavioral" ]] && ok || bad "range incl behavioral -> behavioral"

# --- range spanning only release bump -> release_bump -------------------------
[[ "$(classify_range "${BASE}..${H_REL}")" == "release_bump" ]] && ok || bad "range VERSION+CHANGELOG -> release_bump"

# === marker-pass (AC5) =======================================================
WI="DP-294-T4"
MK_DIR="$R/.polaris/evidence/completion-gate"
mkdir -p "$MK_DIR"
TASK_MD="$TMP/task.md"; echo "# task" >"$TASK_MD"
HS="$H_BEH"

write_marker() {
  # $1 status, $2 head_sha, $3 source_artifact (or empty)
  python3 - "$MK_DIR/$WI-$2.json" "$WI" "$1" "$2" "${3:-}" <<'PY'
import json,sys
out,wi,status,head,art=sys.argv[1:6]
fr={"head_sha":head}
if art: fr["source_artifact"]=art
json.dump({"schema_version":1,"marker_kind":"completion_gate","writer":"engineering",
          "owning_skill":"engineering","source_id":"DP-294","work_item_id":wi,
          "status":status,"freshness":fr,"at":"2026-06-07T10:00:00+00:00"},
         open(out,"w")); open(out,"a").write("\n")
PY
}
marker_pass() { bash "$CLS" marker-pass --repo "$R" --work-item-id "$WI" --head-sha "$1"; }

# valid PASS marker with resolvable artifact -> exit 0
write_marker PASS "$HS" "$TASK_MD"
if marker_pass "$HS" >/dev/null 2>&1; then ok; else bad "valid PASS marker -> exit 0"; fi

# missing marker (different head) -> exit 2
if marker_pass "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" >/dev/null 2>&1; then bad "missing marker should exit 2"; else ok; fi

# status != PASS -> exit 2
rm -f "$MK_DIR/$WI-$HS.json"; write_marker FAIL "$HS" "$TASK_MD"
if marker_pass "$HS" >/dev/null 2>&1; then bad "FAIL-status marker should exit 2"; else ok; fi

# PASS but evidence artifact missing on disk -> exit 2
rm -f "$MK_DIR/$WI-$HS.json"; write_marker PASS "$HS" "$TMP/nonexistent.md"
if marker_pass "$HS" >/dev/null 2>&1; then bad "marker w/ missing artifact should exit 2"; else ok; fi

echo "[evidence-classifier-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
