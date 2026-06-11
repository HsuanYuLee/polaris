#!/usr/bin/env bash
# Purpose: DP-280 T3 hermetic selftest for scripts/detect-closeout-drift.sh —
#          assert the 3-source (completion-gate marker / merged PR / CHANGELOG)
#          evidence collection + drift classification, the single-writer auto
#          close path through mark-spec-implemented.sh, the gh-absent fail-open
#          carve-out, the active/LOCKED-only scope, and the negative guards
#          (in-flight never auto flips, stranded never auto changes state, no
#          second closeout writer).
# Inputs:  none (builds synthetic workspaces + DP containers + markers under
#          mktemp; stubs gh and mark-spec-implemented.sh).
# Outputs: stdout PASS/FAIL lines; exit 0 all-pass, exit 1 any failure.
# Side effects: tmpdir only (removed on EXIT). No live workspace mutation,
#          no real gh calls, no real archiving.
#
# Coverage map:
#   AC1     — 3-source evidence + classification (delivered-drift-high|low /
#             stranded / in-flight) emitted in machine-readable report.
#   AC2     — delivered-drift-high (all task markers + merged PR) auto calls
#             mark-spec-implemented.sh (flip + archive delegated to it).
#   AC3     — delivered-drift-low (partial evidence) + stranded (zero evidence)
#             are report-only, no state change.
#   AC5     — gh absent => PR source fail-open skip, report annotated
#             "PR evidence unchecked", classification still completes.
#   AC6     — only active/ LOCKED containers scanned; archive/ and non-LOCKED
#             (DISCUSSION) are no-op.
#   AC-NEG1 — in-flight DP never auto flip+archive.
#   AC-NEG2 — stranded DP never auto state change.
#   AC-NEG3 — auto-close routes through mark-spec-implemented.sh (no second
#             closeout writer path).
#   open-PR guard — markers-complete + OPEN title-PR => in-flight, never
#             auto-close (DP-280 dogfood regression: body-mention merged PRs
#             must not read as the DP's own delivery).
#   stacked guard — markers + merged title-PR + open title-PR => in-flight
#             (open delivery PR wins; no premature archive of stacked delivery).
#   in:title precision — PR search scoped to title so body cross-references
#             are not counted as the DP's own delivery PR.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detector="$script_dir/detect-closeout-drift.sh"

if [[ ! -x "$detector" ]]; then
  echo "FAIL: detector not executable: $detector" >&2
  exit 1
fi

pass=0
fail=0
record_pass() { echo "PASS $1"; pass=$((pass + 1)); }
record_fail() { echo "FAIL $1" >&2; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# Build a synthetic workspace root with the canonical specs + evidence layout.
make_workspace() {
  local root="$1"
  mkdir -p "$root/docs-manager/src/content/docs/specs/design-plans/archive"
  mkdir -p "$root/.polaris/evidence/completion-gate"
  : >"$root/CHANGELOG.md"
}

# Create a LOCKED (or arbitrary-status) DP container with N implementation tasks
# (task_kind: T) under tasks/T{n}/index.md.
# Usage: make_dp <root> <DP-NNN> <slug> <status> <num_tasks> [archive]
make_dp() {
  local root="$1" dp="$2" slug="$3" status="$4" num_tasks="$5" archived="${6:-}"
  local base="$root/docs-manager/src/content/docs/specs/design-plans"
  local container
  if [[ "$archived" == "archive" ]]; then
    container="$base/archive/${dp}-${slug}"
  else
    container="$base/${dp}-${slug}"
  fi
  mkdir -p "$container/tasks"
  cat >"$container/index.md" <<EOF
---
title: "${dp} ${slug}"
status: ${status}
---

# ${dp}
EOF
  local i
  for ((i = 1; i <= num_tasks; i++)); do
    mkdir -p "$container/tasks/T${i}"
    cat >"$container/tasks/T${i}/index.md" <<EOF
---
title: "${dp} T${i}"
status: IN_PROGRESS
task_kind: T
task_shape: implementation
---

# T${i}
EOF
  done
  printf '%s\n' "$container"
}

# Write a completion-gate marker for a DP task.
# Usage: make_marker <root> <DP-NNN> <T-stem>
make_marker() {
  local root="$1" dp="$2" stem="$3"
  local sha
  sha="$(printf '%s-%s' "$dp" "$stem" | shasum | cut -c1-40)"
  cat >"$root/.polaris/evidence/completion-gate/${dp}-${stem}-${sha}.json" <<EOF
{"schema_version":1,"marker_kind":"completion_gate","writer":"engineering","source_id":"${dp}","work_item_id":"${dp}-${stem}","status":"PASS"}
EOF
}

# Append a CHANGELOG Fixed/Added section for a DP.
make_changelog_entry() {
  local root="$1" dp="$2"
  printf '### Fixed — %s synthetic closeout drift fixture\n\n- entry for %s\n\n' "$dp" "$dp" \
    >>"$root/CHANGELOG.md"
}

# gh stub: a merged title-PR exists, NO open title-PR (clean delivered drift).
# State-aware so the open-PR in-flight guard is exercised correctly: a delivered
# DP has a merged PR but no open PR.
make_gh_stub_merged() {
  local path="$1"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
# `--state merged` => one merged PR; `--state open` (or anything else) => none.
case "$*" in
  *"pr list"*"--state merged"*) printf '[{"number":1,"state":"MERGED"}]\n' ;;
  *) printf '[]\n' ;;
esac
SH
  chmod +x "$path"
}

# gh stub: NO merged title-PR, an OPEN title-PR exists. This is the DP-280 dogfood
# case — an in-flight DP whose only title-PRs are open; the body-mention merged PRs
# that a plain full-text search would have matched are excluded by the detector's
# in:title scoping, so merged returns empty here.
make_gh_stub_open_only() {
  local path="$1"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"pr list"*"--state open"*) printf '[{"number":1,"state":"OPEN"}]\n' ;;
  *) printf '[]\n' ;;
esac
SH
  chmod +x "$path"
}

# gh stub: BOTH a merged title-PR and an open title-PR (stacked mid-flight — some
# task PRs merged, others still open). The open-PR in-flight guard must win over
# the merged-PR delivered signal.
make_gh_stub_merged_and_open() {
  local path="$1"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
# Any pr list query returns a non-empty array (both merged and open present).
printf '[{"number":1}]\n'
SH
  chmod +x "$path"
}

# gh stub that simulates NO merged PR.
make_gh_stub_empty() {
  local path="$1"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '[]\n'
SH
  chmod +x "$path"
}

# mark-spec-implemented stub: log invocations instead of really archiving.
make_mark_stub() {
  local path="$1"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'MARK_SPEC_CALLED %s\n' "$*" >>"${MARK_SPEC_LOG:?}"
SH
  chmod +x "$path"
}

# Run the detector against a workspace, capturing JSON report to a file.
# Usage: run_detector <root> <gh_bin|""> <mark_bin> <mark_log> <json_out> [extra args...]
run_detector() {
  local root="$1" gh_bin="$2" mark_bin="$3" mark_log="$4" json_out="$5"
  shift 5
  : >"$mark_log"
  POLARIS_WORKSPACE_ROOT="$root" \
  CLOSEOUT_DRIFT_GH_BIN="$gh_bin" \
  CLOSEOUT_DRIFT_MARK_SPEC_BIN="$mark_bin" \
  MARK_SPEC_LOG="$mark_log" \
    bash "$detector" --workspace "$root" --json "$@" >"$json_out" 2>"$json_out.err" || {
      echo "--- detector stderr ---" >&2
      cat "$json_out.err" >&2
      return 1
    }
}

# Extract the classification for a DP from the JSON report.
classify_of() {
  local json="$1" dp="$2"
  python3 - "$json" "$dp" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
dp = sys.argv[2]
for item in data.get("results", []):
    if item.get("dp") == dp:
        print(item.get("classification", ""))
        break
else:
    print("__ABSENT__")
PY
}

# ---------------------------------------------------------------------------
# AC2 + AC1 + AC-NEG3: delivered-drift-high => auto mark-spec-implemented
# ---------------------------------------------------------------------------
test_delivered_high() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  make_dp "$tc" "DP-901" "high-drift" "LOCKED" 2 >/dev/null
  make_marker "$tc" "DP-901" "T1"
  make_marker "$tc" "DP-901" "T2"
  make_changelog_entry "$tc" "DP-901"
  local gh; gh="$tc/gh"; make_gh_stub_merged "$gh"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out"; then
    record_fail "AC1/AC2 detector run (delivered-high)"; return
  fi

  local cls; cls="$(classify_of "$out" "DP-901")"
  if [[ "$cls" == "delivered-drift-high" ]]; then
    record_pass "AC1 classify delivered-drift-high"
  else
    record_fail "AC1 classify delivered-drift-high (got: $cls)"
  fi

  if grep -q 'MARK_SPEC_CALLED' "$log" && grep -q 'DP-901' "$log"; then
    record_pass "AC2 auto mark-spec-implemented invoked for delivered-high"
  else
    record_fail "AC2 mark-spec-implemented NOT invoked for delivered-high"
  fi

  # AC-NEG3: the auto-close must route through the mark-spec-implemented binary
  # (the only closeout writer). The detector source must reference the override
  # var and must NOT contain a second in-place frontmatter status flip writer.
  if grep -q 'CLOSEOUT_DRIFT_MARK_SPEC_BIN' "$detector" \
     && grep -q 'mark-spec-implemented' "$detector"; then
    record_pass "AC-NEG3 auto-close routes through mark-spec-implemented (single writer)"
  else
    record_fail "AC-NEG3 detector does not delegate to mark-spec-implemented"
  fi
  # Guard against a second writer: detector must not itself sed/awk a status flip.
  if grep -Eq "status:[[:space:]]*IMPLEMENTED" "$detector"; then
    record_fail "AC-NEG3 detector appears to write IMPLEMENTED status itself (second writer)"
  else
    record_pass "AC-NEG3 detector does not write IMPLEMENTED status itself"
  fi
}

# ---------------------------------------------------------------------------
# AC3 + AC-NEG2: stranded (zero evidence + old) => report-only, no state change
# ---------------------------------------------------------------------------
test_stranded() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  local container; container="$(make_dp "$tc" "DP-902" "stranded-old" "LOCKED" 2)"
  # No markers, no CHANGELOG, no merged PR. Force the container to look old.
  touch -t 202001010000 "$container/index.md" "$container"
  local gh; gh="$tc/gh"; make_gh_stub_empty "$gh"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"
  local before_status
  before_status="$(sed -n 's/^status:[[:space:]]*//p' "$container/index.md" | head -1)"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out" --stranded-days 14; then
    record_fail "AC3 detector run (stranded)"; return
  fi

  local cls; cls="$(classify_of "$out" "DP-902")"
  if [[ "$cls" == "stranded" ]]; then
    record_pass "AC3 classify stranded"
  else
    record_fail "AC3 classify stranded (got: $cls)"
  fi

  if grep -q 'MARK_SPEC_CALLED' "$log"; then
    record_fail "AC-NEG2 stranded triggered auto state change (mark-spec called)"
  else
    record_pass "AC-NEG2 stranded did NOT trigger auto state change"
  fi

  local after_status
  after_status="$(sed -n 's/^status:[[:space:]]*//p' "$container/index.md" | head -1)"
  if [[ "$before_status" == "$after_status" && "$after_status" == "LOCKED" ]]; then
    record_pass "AC3 stranded container status unchanged (LOCKED)"
  else
    record_fail "AC3 stranded container status changed ($before_status -> $after_status)"
  fi
}

# ---------------------------------------------------------------------------
# AC3: delivered-drift-low (partial evidence, e.g. only CHANGELOG) => report-only
# ---------------------------------------------------------------------------
test_delivered_low() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  local container; container="$(make_dp "$tc" "DP-903" "low-drift" "LOCKED" 2)"
  # Only CHANGELOG evidence (no markers covering all tasks, no merged PR).
  make_changelog_entry "$tc" "DP-903"
  local gh; gh="$tc/gh"; make_gh_stub_empty "$gh"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out"; then
    record_fail "AC3 detector run (delivered-low)"; return
  fi

  local cls; cls="$(classify_of "$out" "DP-903")"
  if [[ "$cls" == "delivered-drift-low" ]]; then
    record_pass "AC3 classify delivered-drift-low"
  else
    record_fail "AC3 classify delivered-drift-low (got: $cls)"
  fi

  if grep -q 'MARK_SPEC_CALLED' "$log"; then
    record_fail "AC3 delivered-low triggered auto state change (mark-spec called)"
  else
    record_pass "AC3 delivered-low report-only (no mark-spec call)"
  fi
}

# ---------------------------------------------------------------------------
# AC-NEG1: in-flight (partial markers, PR open/unmerged) => never auto flip+archive
# ---------------------------------------------------------------------------
test_in_flight() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  make_dp "$tc" "DP-904" "in-flight" "LOCKED" 3 >/dev/null
  # Partial markers: only T1 of 3 tasks. No merged PR.
  make_marker "$tc" "DP-904" "T1"
  local gh; gh="$tc/gh"; make_gh_stub_empty "$gh"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out"; then
    record_fail "AC-NEG1 detector run (in-flight)"; return
  fi

  local cls; cls="$(classify_of "$out" "DP-904")"
  if [[ "$cls" == "in-flight" ]]; then
    record_pass "AC-NEG1 classify in-flight"
  else
    record_fail "AC-NEG1 classify in-flight (got: $cls)"
  fi

  if grep -q 'MARK_SPEC_CALLED' "$log"; then
    record_fail "AC-NEG1 in-flight triggered auto flip+archive (mark-spec called)"
  else
    record_pass "AC-NEG1 in-flight did NOT auto flip+archive"
  fi
}

# ---------------------------------------------------------------------------
# In-flight open-PR guard (DP-280 dogfood regression): a DP whose impl-task
# markers are all complete but whose only title-PRs are OPEN must classify
# in-flight and NEVER auto-close. Before the guard, the detector's plain
# full-text PR search matched body-mention merged PRs and (with complete markers)
# mis-read this as delivered drift — the exact false-positive that flagged DP-280
# itself during the V1 dogfood.
# ---------------------------------------------------------------------------
test_in_flight_open_pr() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  make_dp "$tc" "DP-909" "open-pr-inflight" "LOCKED" 2 >/dev/null
  make_marker "$tc" "DP-909" "T1"
  make_marker "$tc" "DP-909" "T2"
  make_changelog_entry "$tc" "DP-909"
  local gh; gh="$tc/gh"; make_gh_stub_open_only "$gh"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out"; then
    record_fail "open-PR guard detector run (DP-909)"; return
  fi

  local cls; cls="$(classify_of "$out" "DP-909")"
  if [[ "$cls" == "in-flight" ]]; then
    record_pass "open-PR guard: markers-complete + open title-PR => in-flight (DP-280 regression)"
  else
    record_fail "open-PR guard: expected in-flight, got: $cls (DP-280 regression)"
  fi

  if grep -q 'MARK_SPEC_CALLED' "$log"; then
    record_fail "open-PR guard: in-flight DP auto-closed (mark-spec called)"
  else
    record_pass "open-PR guard: in-flight DP did NOT auto-close"
  fi

  # The report must expose the in-flight open-PR signal for downstream surfacing.
  if python3 - "$out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for item in data.get("results", []):
    if item.get("dp") == "DP-909":
        sys.exit(0 if item.get("evidence", {}).get("in_flight_open_pr") is True else 1)
sys.exit(1)
PY
  then
    record_pass "open-PR guard: report exposes in_flight_open_pr=true"
  else
    record_fail "open-PR guard: report did NOT expose in_flight_open_pr"
  fi
}

# ---------------------------------------------------------------------------
# Stacked mid-flight guard: markers complete + a merged title-PR + an open
# title-PR. Without the open-PR guard this is the dangerous case that would
# classify delivered-drift-high and auto-archive an in-flight DP. The guard
# must force in-flight and block auto-close.
# ---------------------------------------------------------------------------
test_in_flight_stacked() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  make_dp "$tc" "DP-910" "stacked-midflight" "LOCKED" 2 >/dev/null
  make_marker "$tc" "DP-910" "T1"
  make_marker "$tc" "DP-910" "T2"
  make_changelog_entry "$tc" "DP-910"
  local gh; gh="$tc/gh"; make_gh_stub_merged_and_open "$gh"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out"; then
    record_fail "stacked-midflight detector run (DP-910)"; return
  fi

  local cls; cls="$(classify_of "$out" "DP-910")"
  if [[ "$cls" == "in-flight" ]]; then
    record_pass "stacked guard: markers + merged + open title-PR => in-flight (no premature archive)"
  else
    record_fail "stacked guard: expected in-flight, got: $cls"
  fi

  if grep -q 'MARK_SPEC_CALLED' "$log"; then
    record_fail "stacked guard: in-flight stacked DP auto-closed (mark-spec called)"
  else
    record_pass "stacked guard: in-flight stacked DP did NOT auto-close"
  fi
}

# ---------------------------------------------------------------------------
# Precision lock: the merged-PR / open-PR searches must scope to in:title so
# body-mention cross-references are not counted as the DP's own delivery PR.
# ---------------------------------------------------------------------------
test_in_title_precision() {
  if grep -q 'in:title' "$detector"; then
    record_pass "precision: detector scopes PR search with in:title"
  else
    record_fail "precision: detector PR search not scoped with in:title (body mentions would false-match)"
  fi
}

# ---------------------------------------------------------------------------
# AC5: gh absent => PR source fail-open skip + report annotation, still classifies
# ---------------------------------------------------------------------------
test_gh_absent_fail_open() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  make_dp "$tc" "DP-905" "gh-absent" "LOCKED" 2 >/dev/null
  make_marker "$tc" "DP-905" "T1"
  make_marker "$tc" "DP-905" "T2"
  make_changelog_entry "$tc" "DP-905"
  # gh bin points to a nonexistent path => command -v must fail => fail-open.
  local gh; gh="$tc/no-such-gh-binary"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out"; then
    record_fail "AC5 detector run with gh absent (should NOT fail whole detector)"; return
  fi

  # Detector still produced a classification for the DP (not a hard failure).
  local cls; cls="$(classify_of "$out" "DP-905")"
  if [[ "$cls" != "__ABSENT__" && -n "$cls" ]]; then
    record_pass "AC5 detector completed classification with gh absent (got: $cls)"
  else
    record_fail "AC5 detector did not classify DP with gh absent"
  fi

  # PR evidence must be annotated as unchecked in the report.
  if python3 - "$out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for item in data.get("results", []):
    if item.get("dp") == "DP-905":
        ev = item.get("evidence", {})
        pr = ev.get("merged_pr")
        sys.exit(0 if pr in ("unchecked", None, "skipped") and item.get("pr_evidence_unchecked") is True else 1)
sys.exit(1)
PY
  then
    record_pass "AC5 report annotates PR evidence unchecked (pr_evidence_unchecked=true)"
  else
    record_fail "AC5 report did NOT annotate PR evidence unchecked"
  fi

  # Without a confirmed merged PR, a marker-complete DP must NOT auto-close
  # (high confidence requires the PR source which was skipped).
  if grep -q 'MARK_SPEC_CALLED' "$log"; then
    record_fail "AC5/AC-NEG1 gh-absent marker-complete DP auto-closed without PR confirmation"
  else
    record_pass "AC5 gh-absent marker-complete DP did NOT auto-close (no PR confirmation)"
  fi
}

# ---------------------------------------------------------------------------
# AC6: only active/ LOCKED scanned; archive/ + non-LOCKED no-op
# ---------------------------------------------------------------------------
test_active_locked_only() {
  local tc; tc="$(mktemp -d)"; trap 'rm -rf "'"$tc"'"' RETURN
  make_workspace "$tc"
  # Active LOCKED DP (should appear).
  make_dp "$tc" "DP-906" "active-locked" "LOCKED" 1 >/dev/null
  make_marker "$tc" "DP-906" "T1"
  make_changelog_entry "$tc" "DP-906"
  # Active non-LOCKED DP (DISCUSSION) — should be no-op / skipped.
  make_dp "$tc" "DP-907" "discussion" "DISCUSSION" 1 >/dev/null
  # Archived DP — should be no-op / skipped.
  make_dp "$tc" "DP-908" "archived" "LOCKED" 1 "archive" >/dev/null
  local gh; gh="$tc/gh"; make_gh_stub_merged "$gh"
  local mark; mark="$tc/mark.sh"; make_mark_stub "$mark"
  local log="$tc/mark.log" out="$tc/report.json"

  if ! run_detector "$tc" "$gh" "$mark" "$log" "$out"; then
    record_fail "AC6 detector run (scope)"; return
  fi

  local cls906 cls907 cls908
  cls906="$(classify_of "$out" "DP-906")"
  cls907="$(classify_of "$out" "DP-907")"
  cls908="$(classify_of "$out" "DP-908")"

  if [[ "$cls906" != "__ABSENT__" && -n "$cls906" ]]; then
    record_pass "AC6 active LOCKED DP scanned (DP-906)"
  else
    record_fail "AC6 active LOCKED DP NOT scanned (DP-906)"
  fi
  if [[ "$cls907" == "__ABSENT__" ]]; then
    record_pass "AC6 non-LOCKED (DISCUSSION) DP no-op (DP-907 absent)"
  else
    record_fail "AC6 non-LOCKED DP was scanned (DP-907 got: $cls907)"
  fi
  if [[ "$cls908" == "__ABSENT__" ]]; then
    record_pass "AC6 archived DP no-op (DP-908 absent)"
  else
    record_fail "AC6 archived DP was scanned (DP-908 got: $cls908)"
  fi
}

# ---------------------------------------------------------------------------
# Run all
# ---------------------------------------------------------------------------
test_delivered_high
test_stranded
test_delivered_low
test_in_flight
test_in_flight_open_pr
test_in_flight_stacked
test_in_title_precision
test_gh_absent_fail_open
test_active_locked_only

echo "----"
echo "detect-closeout-drift selftest: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
