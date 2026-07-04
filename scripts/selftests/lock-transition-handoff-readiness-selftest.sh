#!/usr/bin/env bash
# Purpose: DP-368 T1 — verify scripts/write-producer-owned-artifact.sh's
#          refinement_primary_doc branch enforces a LOCK-readiness pre-write gate.
#          A non-LOCKED -> LOCKED status transition of a container index.md must
#          fail closed (exit 2 + POLARIS_LOCK_READINESS_NOT_MET, no LOCKED write)
#          unless the sibling refinement.json passes BOTH refinement-handoff-gate.sh
#          AND validate-refinement-lock-preflight.sh. LOCKED->LOCKED amendments do
#          NOT re-fire the gate. dp and jira-Epic containers are handled
#          symmetrically (container resolved by dirname, no source-type prefix).
#          POLARIS_*_BYPASS env must NOT silence the gate.
# Inputs:  none (self-contained; isolated tmpdir fixtures + repo-tracked validators).
# Outputs: stdout "PASS" + exit 0 on success; diagnostic + non-zero exit on failure.
# Side effects: writes/cleans fixtures under a private tmpdir only; never touches the
#          live DP-368 container or any tracked design-plans / companies container.
#
# Cases:
#   AC1  handoff-green dp container, DISCUSSION -> LOCKED -> exit 0 + on-disk LOCKED.
#   AC2a handoff-fail (missing changed_files), DISCUSSION -> LOCKED -> exit 2 +
#        POLARIS_LOCK_READINESS_NOT_MET, on-disk stays DISCUSSION (pre-write gate).
#   AC2b handoff-fail (artifact parity: index.md missing AC id) -> exit 2.
#   AC3  on-disk already LOCKED, write LOCKED again (amendment) -> gate does NOT
#        fire (handoff gate never runs), write succeeds.
#   AC4  dp + jira-Epic parity: each green path allowed, each fail path blocked.
#   AC-NEG1 bypass env (POLARIS_LANGUAGE_POLICY_BYPASS / POLARIS_SKILL_BOUNDARY_BYPASS /
#        POLARIS_CROSS_LLM_PARITY_BYPASS) set + handoff-fail -> still exit 2 + marker.
#   AC-NEG2 (DP-368 T2 teardown): the post-hoc backfill mechanism is retired. The T1
#        pre-write gate above covers the missing-changed_files invariant at the LOCK
#        point, so scripts/backfill-locked-dp-changed-files.sh, its governed selftest,
#        and their scripts/manifest.json rows must all be GONE with no dangling caller.
#   Isolation: refinement:primary-doc writes a DISCUSSION index.md -> gate must NOT
#        fire (non-LOCKED target is not a LOCK transition); write succeeds.

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
WRITER="$ROOT_DIR/scripts/write-producer-owned-artifact.sh"
RENDER_REFINEMENT_MD="$ROOT_DIR/scripts/render-refinement-md.sh"
WORKDIR="$(mktemp -d -t dp368-lock-transition.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$WRITER" ]]; then
  echo "FAIL: writer not executable: $WRITER" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Fixture helpers.
# ---------------------------------------------------------------------------

# write_index_body <out> <title> <status> [extra_ac_token]
# Synthesize a Starlight-valid container index.md body. The AC token (default
# "AC1") is embedded in the prose so validate-refinement-artifact-parity's
# index.md AC-id coverage check passes for a green container. Omit/blank it to
# build a parity-failing index.md (AC id absent).
write_index_body() {
  # ${4-AC1} (no colon): an explicitly-passed empty 4th arg stays empty (parity-fail
  # fixture), while an omitted 4th arg defaults to AC1 (green fixture).
  local out="$1" title="$2" status="$3" ac_token="${4-AC1}"
  cat >"$out" <<EOF
---
title: "$title"
description: "DP-368 T1 lock-transition selftest 用的 container index fixture。"
status: $status
---

## 背景

供 selftest 使用的 container index 內容，會被 sanctioned writer 整份覆寫；涵蓋 ${ac_token}。
EOF
}

# write_refinement_json <out> <source_type> <source_id> <container> [with_changed_files]
# Synthesize a schema-valid refinement.json whose source.container / source.plan_path
# point at <container>. with_changed_files defaults to "1"; pass "0" to omit the
# changed_files array (handoff-gate then fails closed — the DP-368 invariant).
write_refinement_json() {
  local out="$1" source_type="$2" source_id="$3" container="$4" with_cf="${5:-1}"
  local jira_key="null"
  if [[ "$source_type" == "jira" ]]; then
    jira_key="\"$source_id\""
  fi
  SRC_TYPE="$source_type" SRC_ID="$source_id" CONTAINER="$container" \
    WITH_CF="$with_cf" JIRA_KEY="$jira_key" python3 - "$out" <<'PY'
import json, os, sys
src_type = os.environ["SRC_TYPE"]
src_id = os.environ["SRC_ID"]
container = os.environ["CONTAINER"].rstrip("/")
with_cf = os.environ["WITH_CF"] == "1"
jira_key = None if os.environ["JIRA_KEY"] == "null" else os.environ["JIRA_KEY"].strip('"')
# A jira-Epic source requires epic + source.repo + source.base_branch per the
# refinement.json schema; a dp source leaves them None.
is_jira = src_type == "jira"
source = {
    "type": src_type,
    "id": src_id,
    "container": container,
    "plan_path": os.path.join(container, "index.md"),
    "jira_key": jira_key,
}
if is_jira:
    source["repo"] = "exampleco-web"
    source["base_branch"] = "develop"
body = {
    "epic": src_id if is_jira else None,
    "source": source,
    "version": "1.0",
    "schema_version": "1.0",
    "created_at": "2026-06-03T00:00:00Z",
    "modules": [{"path": "scripts/x.sh", "action": "modify"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "t", "verification": {"method": "unit_test", "detail": "d"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
    "adversarial_pass": [{"ac_id": "AC1", "attack": "a", "enforce": "e"}],
    "tasks": [
        {
            "id": "T1", "kind": "T", "title": "新增 lock readiness fixture", "scope": "建立 LOCK readiness selftest fixture。",
            "modules": ["scripts/x.sh"],
            "ac_ids": ["AC1"], "dependencies": [],
            "verification": {"method": "unit_test", "detail": "echo PASS", "verify_command": "echo PASS"},
            # JIRA-Epic tasks derive their branch identity from tasks[].jira_key
            # (a real PROJ-NNN child key); without it derive-task-md emits JIRA: N/A
            # which validate-task-md rejects for source.type=jira. dp tasks omit it.
            **({"jira_key": "PR-9002"} if is_jira else {}),
        }
    ],
}
if with_cf:
    body["changed_files"] = ["scripts/x.sh"]
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(body, fh)
PY
}

# build_container <container_abs> <source_type> <source_id> <on_disk_status> \
#                 <handoff_green:1|0> [index_ac_token]
# Materialize a full container fixture:
#   - index.md at <on_disk_status>
#   - refinement.json (green => changed_files present; not-green => omitted)
#   - refinement.md rendered from the json (parity)
# For a parity-fail variant pass index_ac_token="" so the index.md omits AC1.
build_container() {
  local container="$1" source_type="$2" source_id="$3" on_disk_status="$4"
  # ${6-AC1} (no colon): an explicitly-passed empty 6th arg stays empty so the
  # index.md omits the AC id (artifact-parity-fail fixture); an omitted 6th arg
  # defaults to AC1 (green fixture).
  local handoff_green="$5" index_ac_token="${6-AC1}"
  mkdir -p "$container"
  write_index_body "$container/index.md" "$source_id Fixture" "$on_disk_status" "$index_ac_token"
  local with_cf="1"
  [[ "$handoff_green" == "1" ]] || with_cf="0"
  write_refinement_json "$container/refinement.json" "$source_type" "$source_id" "$container" "$with_cf"
  bash "$RENDER_REFINEMENT_MD" "$container/refinement.json" >"$container/refinement.md" 2>/dev/null || true
}

# Stage a LOCKED body file for a given target.
locked_body_for() {
  local target="$1" title="$2" out="$3"
  write_index_body "$out" "$title" LOCKED "AC1"
}

fail() {
  echo "FAIL: $1" >&2
  [[ -n "${2:-}" && -f "$2" ]] && cat "$2" >&2
  exit 1
}

on_disk_status() {
  awk -F ':' '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && /^status:/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }
  ' "$1"
}

# ---------------------------------------------------------------------------
# AC1: handoff-green dp container, DISCUSSION -> LOCKED, gate fires & passes.
# ---------------------------------------------------------------------------
ac1_c="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-901-green-dp"
build_container "$ac1_c" dp DP-901 DISCUSSION 1
ac1_body="$WORKDIR/ac1-locked.md"
locked_body_for "$ac1_c/index.md" "DP-901 green dp" "$ac1_body"
set +e
"$WRITER" --producer-token refinement:primary-doc \
  --path "$ac1_c/index.md" --body-file "$ac1_body" >"$WORKDIR/ac1.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC1: handoff-green DISCUSSION->LOCKED expected exit 0, got $rc" "$WORKDIR/ac1.out"
[[ "$(on_disk_status "$ac1_c/index.md")" == "LOCKED" ]] || fail "AC1: on-disk status should be LOCKED after green LOCK"

# ---------------------------------------------------------------------------
# AC2a: handoff-fail (missing changed_files), DISCUSSION -> LOCKED, fail closed.
# ---------------------------------------------------------------------------
ac2a_c="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-902-nochanged-dp"
build_container "$ac2a_c" dp DP-902 DISCUSSION 0
ac2a_body="$WORKDIR/ac2a-locked.md"
locked_body_for "$ac2a_c/index.md" "DP-902 nochanged dp" "$ac2a_body"
set +e
"$WRITER" --producer-token refinement:primary-doc \
  --path "$ac2a_c/index.md" --body-file "$ac2a_body" >"$WORKDIR/ac2a.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "AC2a: missing changed_files LOCK expected exit 2, got $rc" "$WORKDIR/ac2a.out"
grep -q 'POLARIS_LOCK_READINESS_NOT_MET' "$WORKDIR/ac2a.out" || fail "AC2a: expected POLARIS_LOCK_READINESS_NOT_MET marker" "$WORKDIR/ac2a.out"
[[ "$(on_disk_status "$ac2a_c/index.md")" == "DISCUSSION" ]] || fail "AC2a: on-disk status must stay DISCUSSION (pre-write gate; no half-written LOCKED)"

# ---------------------------------------------------------------------------
# AC2b: handoff-fail (artifact parity — index.md missing AC id), fail closed.
# ---------------------------------------------------------------------------
ac2b_c="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-903-parityfail-dp"
build_container "$ac2b_c" dp DP-903 DISCUSSION 1 ""   # changed_files present but index.md omits AC1
ac2b_body="$WORKDIR/ac2b-locked.md"
locked_body_for "$ac2b_c/index.md" "DP-903 parityfail dp" "$ac2b_body"
set +e
"$WRITER" --producer-token refinement:primary-doc \
  --path "$ac2b_c/index.md" --body-file "$ac2b_body" >"$WORKDIR/ac2b.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "AC2b: artifact-parity-fail LOCK expected exit 2, got $rc" "$WORKDIR/ac2b.out"
grep -q 'POLARIS_LOCK_READINESS_NOT_MET' "$WORKDIR/ac2b.out" || fail "AC2b: expected POLARIS_LOCK_READINESS_NOT_MET marker" "$WORKDIR/ac2b.out"
[[ "$(on_disk_status "$ac2b_c/index.md")" == "DISCUSSION" ]] || fail "AC2b: on-disk status must stay DISCUSSION"

# ---------------------------------------------------------------------------
# AC3: on-disk already LOCKED, re-write LOCKED (amendment) — gate must NOT fire.
# The container is intentionally handoff-FAIL (no changed_files); if the gate
# wrongly re-fired on a LOCKED->LOCKED write it would block the amendment.
# ---------------------------------------------------------------------------
ac3_c="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-904-amend-dp"
build_container "$ac3_c" dp DP-904 LOCKED 0
ac3_body="$WORKDIR/ac3-locked.md"
locked_body_for "$ac3_c/index.md" "DP-904 amend dp" "$ac3_body"
set +e
"$WRITER" --producer-token refinement:primary-doc \
  --path "$ac3_c/index.md" --body-file "$ac3_body" >"$WORKDIR/ac3.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC3: LOCKED->LOCKED amendment must not re-fire gate; expected exit 0, got $rc" "$WORKDIR/ac3.out"
grep -q 'POLARIS_LOCK_READINESS_NOT_MET' "$WORKDIR/ac3.out" && fail "AC3: gate must NOT fire on LOCKED->LOCKED amendment" "$WORKDIR/ac3.out"
[[ "$(on_disk_status "$ac3_c/index.md")" == "LOCKED" ]] || fail "AC3: on-disk status should remain LOCKED"

# ---------------------------------------------------------------------------
# AC4: dp + jira-Epic parity (container resolved by dirname, no source-type prefix).
#   jira green -> allowed; jira handoff-fail -> blocked. (dp covered by AC1/AC2a.)
# ---------------------------------------------------------------------------
ac4_green_c="$WORKDIR/docs-manager/src/content/docs/specs/companies/exampleco/PR-9001"
build_container "$ac4_green_c" jira PR-9001 DISCUSSION 1
ac4_green_body="$WORKDIR/ac4-green-locked.md"
locked_body_for "$ac4_green_c/index.md" "PR-9001 green jira" "$ac4_green_body"
set +e
"$WRITER" --producer-token refinement:primary-doc \
  --path "$ac4_green_c/index.md" --body-file "$ac4_green_body" >"$WORKDIR/ac4-green.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "AC4: jira-Epic green DISCUSSION->LOCKED expected exit 0, got $rc" "$WORKDIR/ac4-green.out"
[[ "$(on_disk_status "$ac4_green_c/index.md")" == "LOCKED" ]] || fail "AC4: jira-Epic on-disk status should be LOCKED after green LOCK"

ac4_fail_c="$WORKDIR/docs-manager/src/content/docs/specs/companies/exampleco/PR-9002"
build_container "$ac4_fail_c" jira PR-9002 DISCUSSION 0
ac4_fail_body="$WORKDIR/ac4-fail-locked.md"
locked_body_for "$ac4_fail_c/index.md" "PR-9002 fail jira" "$ac4_fail_body"
set +e
"$WRITER" --producer-token refinement:primary-doc \
  --path "$ac4_fail_c/index.md" --body-file "$ac4_fail_body" >"$WORKDIR/ac4-fail.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "AC4: jira-Epic handoff-fail LOCK expected exit 2, got $rc" "$WORKDIR/ac4-fail.out"
grep -q 'POLARIS_LOCK_READINESS_NOT_MET' "$WORKDIR/ac4-fail.out" || fail "AC4: jira-Epic expected POLARIS_LOCK_READINESS_NOT_MET marker" "$WORKDIR/ac4-fail.out"
[[ "$(on_disk_status "$ac4_fail_c/index.md")" == "DISCUSSION" ]] || fail "AC4: jira-Epic on-disk status must stay DISCUSSION"

# ---------------------------------------------------------------------------
# AC-NEG1: bypass env must NOT silence the gate.
# ---------------------------------------------------------------------------
neg1_c="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-905-bypass-dp"
build_container "$neg1_c" dp DP-905 DISCUSSION 0
neg1_body="$WORKDIR/neg1-locked.md"
locked_body_for "$neg1_c/index.md" "DP-905 bypass dp" "$neg1_body"
set +e
POLARIS_LANGUAGE_POLICY_BYPASS=1 POLARIS_SKILL_BOUNDARY_BYPASS=1 POLARIS_CROSS_LLM_PARITY_BYPASS=1 \
  "$WRITER" --producer-token refinement:primary-doc \
  --path "$neg1_c/index.md" --body-file "$neg1_body" >"$WORKDIR/neg1.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "AC-NEG1: bypass env must not silence gate; expected exit 2, got $rc" "$WORKDIR/neg1.out"
grep -q 'POLARIS_LOCK_READINESS_NOT_MET' "$WORKDIR/neg1.out" || fail "AC-NEG1: expected POLARIS_LOCK_READINESS_NOT_MET marker under bypass env" "$WORKDIR/neg1.out"
[[ "$(on_disk_status "$neg1_c/index.md")" == "DISCUSSION" ]] || fail "AC-NEG1: on-disk status must stay DISCUSSION under bypass env"

# ---------------------------------------------------------------------------
# Isolation: refinement:primary-doc writes a DISCUSSION index.md -> not a LOCK
# transition -> gate must NOT fire (no handoff gate run), write succeeds even
# though the container is handoff-FAIL (no changed_files).
# ---------------------------------------------------------------------------
iso_c="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-906-disc-dp"
build_container "$iso_c" dp DP-906 DISCUSSION 0
iso_body="$WORKDIR/iso-discussion.md"
write_index_body "$iso_body" "DP-906 disc dp" DISCUSSION "AC1"
set +e
"$WRITER" --producer-token refinement:primary-doc \
  --path "$iso_c/index.md" --body-file "$iso_body" >"$WORKDIR/iso.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail "Isolation: non-LOCKED target must not trigger LOCK-readiness gate; expected exit 0, got $rc" "$WORKDIR/iso.out"
grep -q 'POLARIS_LOCK_READINESS_NOT_MET' "$WORKDIR/iso.out" && fail "Isolation: gate must NOT fire on a DISCUSSION->DISCUSSION write" "$WORKDIR/iso.out"

# ---------------------------------------------------------------------------
# AC-NEG2 (DP-368 T2 teardown): the post-hoc backfill mechanism is retired.
# The T1 pre-write LOCK-readiness gate (exercised by AC2a above) now blocks a
# missing-changed_files container at the LOCK point, so the old post-hoc
# backfill that scanned LOCKED DPs to repair missing changed_files is no longer
# needed. Assert the end state: script gone + governed selftest gone + no
# manifest.json reference + no dangling caller anywhere under scripts/ / .claude/.
# ---------------------------------------------------------------------------
BACKFILL_TOKEN='backfill-locked-dp-changed-files'
BACKFILL_SCRIPT="$ROOT_DIR/scripts/$BACKFILL_TOKEN.sh"
BACKFILL_SELFTEST="$ROOT_DIR/scripts/selftests/$BACKFILL_TOKEN-selftest.sh"

[[ ! -e "$BACKFILL_SCRIPT" ]] || fail "AC-NEG2: retired backfill script must not exist: $BACKFILL_SCRIPT"
[[ ! -e "$BACKFILL_SELFTEST" ]] || fail "AC-NEG2: retired backfill governed selftest must not exist: $BACKFILL_SELFTEST"

if grep -q "$BACKFILL_TOKEN" "$ROOT_DIR/scripts/manifest.json" 2>/dev/null; then
  fail "AC-NEG2: scripts/manifest.json must not reference retired backfill mechanism ($BACKFILL_TOKEN)"
fi

# No dangling caller across scripts/ and .claude/. Exclude this selftest's own
# file (it carries the token in its assertion strings) so a self-reference does
# not masquerade as a dangling caller; the live DP-368 spec dir lives under
# docs-manager/ and is out of these two trees by construction.
SELF_BASENAME="$(basename "${BASH_SOURCE[0]}")"
dangling="$(grep -rl "$BACKFILL_TOKEN" "$ROOT_DIR/scripts" "$ROOT_DIR/.claude" 2>/dev/null \
  | grep -v "/$SELF_BASENAME$" || true)"
[[ -z "$dangling" ]] || fail "AC-NEG2: dangling reference(s) to retired backfill mechanism remain:
$dangling"

echo "PASS"
