#!/usr/bin/env bash
# Purpose: DP-294 T4 / AC4+AC5 + DP-360 T7 — selftest for
#          scripts/lib/evidence-classifier.sh.
# Inputs:  none (hermetic tmp git repo + tmp DP specs tree with task.md blocks).
# Outputs: PASS/FAIL lines; exit 0 (all pass) / 1 (any fail).
# Covers:  classify metadata_only / release_bump / behavioral (incl. mixed
#          behavioral fail-closed + empty fail-closed); DP-360 T7 marker-pass now
#          reads the task.md `deliverable` block instead of a head-sha marker:
#            - AC3:    no marker file anywhere; PASS resolves from task.md block.
#            - head-bound: a different head fails closed.
#            - non-PASS deliverable.verification.status fails closed.
#            - missing deliverable block fails closed.
#            - AC-NEG1: a polluted branch ref does NOT rescue a non-PASS block.
#            - AC-NEG2: a (stray) head-sha marker is ignored — no marker read.

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

# === marker-pass (AC5 + DP-360 T7 task.md-block contract) ====================
# DP-360 T7: marker-pass no longer reads a head-sha completion_gate marker. It
# resolves the task.md by work_item_id and asserts deliverable.head_sha is bound
# to the requested head AND deliverable.verification.status == PASS. We scaffold a
# DP specs tree under the hermetic repo so resolve-task-md.sh can find the task.md.
WI="DP-294-T4"
JIRA_WI="FOO-646-T1"
HS="$H_BEH"
SPECS="$R/docs-manager/src/content/docs/specs"
TASK_DIR="$SPECS/design-plans/DP-294-evidence-classifier-fixture/tasks/T4"
JIRA_TASK_DIR="$SPECS/companies/exampleco/FOO-646/tasks/T1"
mkdir -p "$TASK_DIR"
mkdir -p "$JIRA_TASK_DIR"
TASK_MD="$TASK_DIR/index.md"
JIRA_TASK_MD="$JIRA_TASK_DIR/index.md"

# Write a task.md carrying a deliverable block. $1 head_sha, $2 verification status.
write_task_block() {
  local head="$1" status="$2"
  cat >"$TASK_MD" <<EOF
---
title: "fixture"
status: IN_PROGRESS
task_kind: T
task_shape: implementation
deliverable:
  pr_url: https://github.com/o/r/pull/1
  pr_state: OPEN
  head_sha: ${head}
  verification:
    status: ${status}
    ac_counts:
      ac_total: 1
      ac_pass: 1
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
---
# fixture
EOF
}

# Write a task.md with NO deliverable block at all.
write_task_no_block() {
  cat >"$TASK_MD" <<'EOF'
---
title: "fixture"
status: IN_PROGRESS
task_kind: T
task_shape: implementation
---
# fixture
EOF
}

marker_pass() { bash "$CLS" marker-pass --repo "$R" --work-item-id "$WI" --head-sha "$1"; }
jira_marker_pass() { bash "$CLS" marker-pass --repo "$R" --work-item-id "$JIRA_WI" --head-sha "$1"; }

# AC3: PASS block at the requested head, with NO marker file anywhere -> exit 0.
write_task_block "$HS" PASS
[[ ! -d "$R/.polaris/evidence/completion-gate" ]] || bad "AC3 precondition: no marker dir should exist"
if marker_pass "$HS" >/dev/null 2>&1; then ok; else bad "AC3 PASS task.md block (no marker) -> exit 0"; fi

# JIRA Epic composite parity: marker-pass resolves companies/{co}/{EPIC}/task.md
# by work_item_id through the same canonical resolver as DP composite ids.
cp "$TASK_MD" "$JIRA_TASK_MD"
if jira_marker_pass "$HS" >/dev/null 2>&1; then ok; else bad "JIRA Epic composite PASS task.md block -> exit 0"; fi

# head-bound: a different head fails closed (task.md head does not match).
if marker_pass "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" >/dev/null 2>&1; then
  bad "different head should exit 2"; else ok; fi
if jira_marker_pass "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" >/dev/null 2>&1; then
  bad "JIRA Epic composite different head should exit 2"; else ok; fi

# non-PASS verification.status fails closed.
write_task_block "$HS" FAIL
if marker_pass "$HS" >/dev/null 2>&1; then bad "FAIL-status block should exit 2"; else ok; fi

# missing deliverable block fails closed.
write_task_no_block
if marker_pass "$HS" >/dev/null 2>&1; then bad "missing deliverable block should exit 2"; else ok; fi

# AC-NEG1: a non-PASS block must NOT be rescued by branch state. Create a branch
# whose name embeds the head, then assert a FAIL block still fails closed (the
# reader never consults a branch ref for delivery head / PASS).
write_task_block "$HS" FAIL
git -C "$R" branch -f "task/${WI}-${HS}" "$HS" 2>/dev/null || true
if marker_pass "$HS" >/dev/null 2>&1; then bad "AC-NEG1 branch ref must not rescue FAIL block"; else ok; fi

# AC-NEG2: a stray head-sha marker on disk must be IGNORED (no marker read). The
# task.md block is FAIL, so even a PASS marker file must not flip the result.
mkdir -p "$R/.polaris/evidence/completion-gate"
python3 - "$R/.polaris/evidence/completion-gate/$WI-$HS.json" "$WI" "$HS" <<'PY'
import json,sys
out,wi,head=sys.argv[1:4]
json.dump({"schema_version":1,"marker_kind":"completion_gate","writer":"engineering",
          "owning_skill":"engineering","source_id":"DP-294","work_item_id":wi,
          "status":"PASS","freshness":{"head_sha":head},
          "at":"2026-06-07T10:00:00+00:00"}, open(out,"w")); open(out,"a").write("\n")
PY
if marker_pass "$HS" >/dev/null 2>&1; then bad "AC-NEG2 stray PASS marker must not flip FAIL block"; else ok; fi
# Flip the block to PASS: still exit 0 — proving the PASS came from the block, not
# the marker (the marker was already present above for both polarities).
write_task_block "$HS" PASS
if marker_pass "$HS" >/dev/null 2>&1; then ok; else bad "AC3 PASS block resolves even with stray marker present"; fi

echo "[evidence-classifier-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
