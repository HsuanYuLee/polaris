#!/usr/bin/env bash
# Purpose: DP-417 T5 — prove the auto-pass terminal-complete closeout chain
#          enforces a FIXED order (complete report write → archive → report
#          validation) and an active/archive gate applicability matrix, driven
#          through the EXISTING scripts (validate-auto-pass-report.sh as the
#          report-validation gate + mark-spec-implemented.sh as the archive
#          producer), never a reimplemented order.
# Inputs:  none (hermetic temp fixtures under mktemp).
# Outputs: "PASS: ..." on stdout; exit 0 all cells green, exit 1 on any cell.
#          Asserts AC5 (fixed order + active/archive matrix), AC-NEG2 (order
#          violation / archive-state misjudgment fail-closed) and AC-N1
#          (no-false-positive on non-complete terminal / genuinely-active source).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
MARK_SPEC="$ROOT/scripts/mark-spec-implemented.sh"

TMP="$(mktemp -d -t report-archive-validation-order.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

HEAD_SHA="cccccccccccccccccccccccccccccccccccccccc"

# ---------------------------------------------------------------------------
# Hermetic mark-spec-implemented dependencies (mirrors the proven fixture in
# mark-spec-implemented-bare-key-selftest.sh): a fake mise+node shim for the
# close-parent lifecycle reconciler and an archive stub that moves the resolved
# container into the design-plans/archive/ namespace. The archive step's own
# correctness is owned by mark-spec-implemented / archive-spec and their own
# selftests; here it is used only as the ordering producer that transitions the
# fixture from active → archived so the report-validation gate can be re-driven.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat >"$TMP/bin/mise" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "exec" ]]; then
  shift
  [[ "\${1:-}" == "--" ]] && shift
  if [[ "\${1:-}" == "bash" && "\${2:-}" == "-lc" ]]; then
    case "\${3:-}" in
      *"command -v node"*) echo "$TMP/bin/node"; exit 0 ;;
      *) exit 0 ;;
    esac
  fi
  exec "\$@"
fi
exit 0
EOF
cat >"$TMP/bin/node" <<'NODE_EOF'
#!/usr/bin/env bash
set -euo pipefail
script="${1:-}"
if [[ "$script" == *"reconcile-spec-lifecycle.mjs" ]]; then
  parent="${@: -1}"
  python3 - "$parent" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if text.startswith("---\n"):
    end = text.find("\n---\n", 4)
    if end != -1:
        fm = text[:end]
        body = text[end:]
        if re.search(r"^status:", fm, re.M):
            fm = re.sub(r"^status:.*$", "status: IMPLEMENTED", fm, flags=re.M)
        else:
            fm += "\nstatus: IMPLEMENTED"
        path.write_text(fm + body, encoding="utf-8")
        print("status: IMPLEMENTED")
        raise SystemExit(0)
path.write_text("---\nstatus: IMPLEMENTED\n---\n" + text, encoding="utf-8")
print("status: IMPLEMENTED")
PY
  exit 0
fi
echo "fake node"
NODE_EOF
chmod +x "$TMP/bin/mise" "$TMP/bin/node"

ARCHIVE_STUB="$TMP/archive-spec-stub.sh"
cat >"$ARCHIVE_STUB" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE=""
SOURCE_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) SOURCE_PATH="$1"; shift ;;
  esac
done
[ -n "$SOURCE_PATH" ] || exit 0
container_dir="$(dirname "$SOURCE_PATH")"
[ -d "$container_dir" ] || exit 0
parent_dir="$(dirname "$container_dir")"
archive_dir="$parent_dir/archive"
mkdir -p "$archive_dir"
mv "$container_dir" "$archive_dir/"
SH
chmod +x "$ARCHIVE_STUB"

# ---------------------------------------------------------------------------
# Fixture builders. A source container lives at
#   $WS/docs-manager/src/content/docs/specs/design-plans/DP-<N>-selftest/
# with a V1 work item carrying the canonical ac_verification PASS lifecycle
# block. The report's verification head is bound to implementation evidence in
# required_prs[] rather than to a fake V deliverable.
# ---------------------------------------------------------------------------
specs_root_for() { printf '%s/docs-manager/src/content/docs/specs' "$1"; }

write_source() {
  # $1=workspace root  $2=dp number  $3=parent status
  local ws="$1" num="$2" status="$3"
  local design_plans container
  design_plans="$(specs_root_for "$ws")/design-plans"
  container="$design_plans/DP-${num}-selftest"
  mkdir -p "$container/tasks/V1"
  cat >"$container/index.md" <<MD
---
title: "DP-${num}"
description: "Report/archive order selftest fixture."
status: ${status}
---

# DP-${num}
MD
  cat >"$container/tasks/V1/index.md" <<MD
---
title: "DP-${num} V1"
status: IN_PROGRESS
task_kind: V
work_item_id: DP-${num}-V1
ac_verification:
  status: PASS
---

# V1

> Source: DP-${num} | Task: DP-${num}-V1 | JIRA: N/A | Repo: polaris-framework
MD
  mkdir -p "$container/tasks/T1"
  cat >"$container/tasks/T1/index.md" <<MD
---
task_kind: T
deliverable:
  head_sha: ${HEAD_SHA}
---

# T1

> Source: DP-${num} | Task: DP-${num}-T1 | JIRA: N/A | Repo: polaris-framework
MD
  printf '%s' "$container"
}

write_company_source() {
  # $1=workspace root  $2=company  $3=source id  $4=parent status
  local ws="$1" company="$2" source_id="$3" status="$4"
  local container
  container="$(specs_root_for "$ws")/companies/$company/$source_id"
  mkdir -p "$container/tasks/V1"
  cat >"$container/index.md" <<MD
---
title: "${source_id}"
description: "Report/archive order company fixture."
status: ${status}
---

# ${source_id}
MD
  cat >"$container/tasks/V1/index.md" <<MD
---
title: "${source_id} V1"
status: IN_PROGRESS
task_kind: V
work_item_id: ${source_id}-V1
ac_verification:
  status: PASS
---

# V1

> Source: ${source_id} | Task: ${source_id}-V1 | JIRA: N/A | Repo: polaris-framework
MD
  mkdir -p "$container/tasks/T1"
  cat >"$container/tasks/T1/index.md" <<MD
---
task_kind: T
deliverable:
  head_sha: ${HEAD_SHA}
---

# T1

> Source: ${source_id} | Task: ${source_id}-T1 | JIRA: N/A | Repo: polaris-framework
MD
  printf '%s' "$container"
}

write_ledger() {
  # $1=path  $2=terminal_status(json literal e.g. "complete" or null)
  local path="$1" terminal="$2"
  cat >"$path" <<JSON
{"schema_version":"1","terminal_status":${terminal},"pause":null,"friction_log":[]}
JSON
}

write_report_for_source() {
  # $1=path $2=source id $3=terminal $4=verification_status $5=ledger $6=seed(json)
  local path="$1" source_id="$2" terminal="$3" vstatus="$4" ledger="$5" seed="$6"
  python3 - "$path" "$source_id" "$terminal" "$vstatus" "$ledger" "$HEAD_SHA" "$seed" <<'PY'
import json
import sys
from pathlib import Path

path, source_id, terminal, vstatus, ledger, head, seed_raw = sys.argv[1:8]
payload = {
    "schema_version": 1,
    "source_id": source_id,
    "terminal_status": terminal,
    "created_at": "2026-07-13T00:00:00+08:00",
    "ledger_path": ledger,
    "required_prs": [{"task_id": f"{source_id}-T1", "head_sha": head}],
    "verification": {"status": vstatus, "work_item_id": f"{source_id}-V1", "head_sha": head},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": json.loads(seed_raw),
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

write_report() {
  # $1=path $2=dp number $3=terminal $4=verification_status $5=ledger $6=seed(json)
  write_report_for_source "$1" "DP-$2" "$3" "$4" "$5" "$6"
}

run_validate() {
  # $1=workspace root  $2=report path  ; stdout+stderr → $3
  local ws="$1" report="$2" out="$3"
  POLARIS_WORKSPACE_ROOT="$ws" POLARIS_SPECS_ROOT="$(specs_root_for "$ws")" \
    "$REPORT_VALIDATOR" "$report" >"$out" 2>&1
}

fail() { echo "FAIL: $1" >&2; [ -n "${2:-}" ] && cat "$2" >&2; exit 1; }

# ===========================================================================
# CELL A — FIXED ORDER end-to-end through the real scripts (AC5) plus
# AC-NEG2 (report-validation BEFORE archive on an active LOCKED parent must
# fail-closed) and continue-after-archive (post-archive re-validation passes,
# no re-fail).
# ===========================================================================
WS_A="$TMP/wsA"
CONTAINER_A="$(write_source "$WS_A" 811 LOCKED)"
mkdir -p "$CONTAINER_A/artifacts/auto-pass"
LEDGER_A="$CONTAINER_A/artifacts/auto-pass/ledgerA.json"; write_ledger "$LEDGER_A" '"complete"'
REPORT_A="$CONTAINER_A/artifacts/auto-pass/reportA.json"
write_report "$REPORT_A" 811 complete PASS "$LEDGER_A" null

# Step 1 done (report written). Step 3-before-2: validate BEFORE archive → must
# fail-closed with the active-parent archive gate (order violation / AC-NEG2).
rc=0; run_validate "$WS_A" "$REPORT_A" "$TMP/A-prearchive.out" || rc=$?
[ "$rc" -ne 0 ] || fail "A: report validation passed on active LOCKED parent before archive (order violation not fail-closed)" "$TMP/A-prearchive.out"
grep -q "POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED" "$TMP/A-prearchive.out" \
  || fail "A: pre-archive validation did not emit TERMINAL_PARENT_NOT_ARCHIVED" "$TMP/A-prearchive.out"

# Step 2: archive via the REAL mark-spec-implemented.sh --auto-archive producer.
env -u MARK_SPEC_IMPLEMENTED_SELFTEST \
    PATH="$TMP/bin:$PATH" \
    MARK_SPEC_ARCHIVE_SPEC_BIN="$ARCHIVE_STUB" \
  bash "$MARK_SPEC" DP-811 --workspace "$WS_A" --auto-archive >"$TMP/A-markspec.out" 2>&1 \
  || fail "A: mark-spec-implemented --auto-archive failed" "$TMP/A-markspec.out"

DP_A="$(specs_root_for "$WS_A")/design-plans"
[ ! -d "$DP_A/DP-811-selftest" ] || fail "A: active container was not archived by the archive step"
ARCHIVED_A="$DP_A/archive/DP-811-selftest"
[ -d "$ARCHIVED_A" ] || fail "A: archived container missing at expected path"
grep -q '^status: IMPLEMENTED$' "$ARCHIVED_A/index.md" || fail "A: archived parent status not IMPLEMENTED"
ARCHIVED_REPORT_A="$ARCHIVED_A/artifacts/auto-pass/reportA.json"
[ -f "$ARCHIVED_REPORT_A" ] || fail "A: report did not move with the archived source container"

# Recreate the old active ledger path with a conflicting terminal. The archived
# report must stay bound to the ledger that moved with its source container.
mkdir -p "$(dirname "$LEDGER_A")"
write_ledger "$LEDGER_A" '"blocked_by_gate_failure"'

# Step 3: report validation AFTER archive → must PASS (continue-after-archive,
# no re-fail on an already-archived source). The report still contains the
# pre-archive absolute ledger path, proving the constrained relocation path.
run_validate "$WS_A" "$ARCHIVED_REPORT_A" "$TMP/A-postarchive.out" \
  || fail "A: report validation failed after archive (continue-after-archive re-failed)" "$TMP/A-postarchive.out"
grep -q "PASS: auto-pass report validation" "$TMP/A-postarchive.out" \
  || fail "A: post-archive validation did not report PASS" "$TMP/A-postarchive.out"

# ===========================================================================
# CELL B — active/archive matrix: active namespace + status IMPLEMENTED
# (status flipped, not yet moved) → gate PASSES. Proves the gate keys on the
# parent status, not merely on the namespace.
# ===========================================================================
WS_B="$TMP/wsB"
write_source "$WS_B" 812 IMPLEMENTED >/dev/null
LEDGER_B="$TMP/ledgerB.json"; write_ledger "$LEDGER_B" '"complete"'
REPORT_B="$TMP/reportB.json"
write_report "$REPORT_B" 812 complete PASS "$LEDGER_B" null
run_validate "$WS_B" "$REPORT_B" "$TMP/B.out" \
  || fail "B: complete report on active-namespace IMPLEMENTED parent should PASS" "$TMP/B.out"
grep -q "PASS: auto-pass report validation" "$TMP/B.out" || fail "B: active+IMPLEMENTED did not PASS" "$TMP/B.out"

# ===========================================================================
# CELL C — AC-NEG2 archive-state misjudgment: active DISCUSSION parent (a
# genuinely-active, non-IMPLEMENTED source) claiming complete must fail-closed.
# ===========================================================================
WS_C="$TMP/wsC"
write_source "$WS_C" 813 DISCUSSION >/dev/null
LEDGER_C="$TMP/ledgerC.json"; write_ledger "$LEDGER_C" '"complete"'
REPORT_C="$TMP/reportC.json"
write_report "$REPORT_C" 813 complete PASS "$LEDGER_C" null
rc=0; run_validate "$WS_C" "$REPORT_C" "$TMP/C.out" || rc=$?
[ "$rc" -ne 0 ] || fail "C: complete report on active non-IMPLEMENTED parent should fail-closed" "$TMP/C.out"
grep -q "POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED" "$TMP/C.out" \
  || fail "C: active non-IMPLEMENTED completion did not emit TERMINAL_PARENT_NOT_ARCHIVED" "$TMP/C.out"

# ===========================================================================
# CELL D — AC-N1 no-false-positive: a NON-complete terminal (blocked_by_gate_
# failure) on an active LOCKED parent must NOT trip the archive gate. The
# active-parent gate applies only to terminal_status=complete.
# ===========================================================================
WS_D="$TMP/wsD"
write_source "$WS_D" 814 LOCKED >/dev/null
LEDGER_D="$TMP/ledgerD.json"; write_ledger "$LEDGER_D" '"blocked_by_gate_failure"'
REPORT_D="$TMP/reportD.json"
SEED_D='{"path":"docs-manager/src/content/docs/specs/design-plans/DP-899-follow-up/index.md","reason":"selftest non-complete terminal","source_report":"reportD.json","framework_gap":false,"contract_evidence":[]}'
write_report "$REPORT_D" 814 blocked_by_gate_failure FAIL "$LEDGER_D" "$SEED_D"
run_validate "$WS_D" "$REPORT_D" "$TMP/D.out" \
  || fail "D: valid non-complete report should not fail validation" "$TMP/D.out"
! grep -q "POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED" "$TMP/D.out" \
  || fail "D: archive gate misfired on a non-complete terminal (false positive)" "$TMP/D.out"

# ===========================================================================
# CELL E — an archived report must not use an arbitrary same-basename file as
# a fallback. The declared missing ledger repeats the source basename under an
# unrelated parent; even though a local ledger with that basename exists,
# validation fails closed.
# ===========================================================================
WS_E="$TMP/wsE"
CONTAINER_E="$(write_source "$WS_E" 815 IMPLEMENTED)"
DP_E="$(specs_root_for "$WS_E")/design-plans"
mkdir -p "$DP_E/archive"
mv "$CONTAINER_E" "$DP_E/archive/"
ARCHIVED_E="$DP_E/archive/DP-815-selftest"
mkdir -p "$ARCHIVED_E/artifacts/auto-pass"
LOCAL_LEDGER_E="$ARCHIVED_E/artifacts/auto-pass/ledgerE.json"
write_ledger "$LOCAL_LEDGER_E" '"complete"'
REPORT_E="$ARCHIVED_E/artifacts/auto-pass/reportE.json"
UNRELATED_LEDGER_E="$TMP/unrelated/DP-815-selftest/artifacts/auto-pass/ledgerE.json"
mkdir -p "$(dirname "$UNRELATED_LEDGER_E")"
write_ledger "$UNRELATED_LEDGER_E" '"complete"'
write_report "$REPORT_E" 815 complete PASS "$UNRELATED_LEDGER_E" null
rc=0; run_validate "$WS_E" "$REPORT_E" "$TMP/E.out" || rc=$?
[ "$rc" -ne 0 ] || fail "E: archived report accepted an unrelated same-basename ledger fallback" "$TMP/E.out"
grep -q "POLARIS_AUTO_PASS_REPORT_LEDGER_UNREADABLE" "$TMP/E.out" \
  || fail "E: unrelated ledger fallback did not fail with LEDGER_UNREADABLE" "$TMP/E.out"

# ===========================================================================
# CELL F — a same-directory symlink is not ledger identity. Even when its
# resolved target is another valid ledger beside the report, relocation rejects
# the alias and fails closed.
# ===========================================================================
WS_F="$TMP/wsF"
CONTAINER_F="$(write_source "$WS_F" 816 IMPLEMENTED)"
DP_F="$(specs_root_for "$WS_F")/design-plans"
mkdir -p "$DP_F/archive"
mv "$CONTAINER_F" "$DP_F/archive/"
ARCHIVED_F="$DP_F/archive/DP-816-selftest"
mkdir -p "$ARCHIVED_F/artifacts/auto-pass"
write_ledger "$ARCHIVED_F/artifacts/auto-pass/ledgerF-target.json" '"complete"'
ln -s ledgerF-target.json "$ARCHIVED_F/artifacts/auto-pass/ledgerF.json"
REPORT_F="$ARCHIVED_F/artifacts/auto-pass/reportF.json"
DECLARED_F="$DP_F/DP-816-selftest/artifacts/auto-pass/ledgerF.json"
write_report "$REPORT_F" 816 complete PASS "$DECLARED_F" null
rc=0; run_validate "$WS_F" "$REPORT_F" "$TMP/F.out" || rc=$?
[ "$rc" -ne 0 ] || fail "F: archived report accepted a same-directory ledger symlink" "$TMP/F.out"
grep -q "POLARIS_AUTO_PASS_REPORT_LEDGER_UNREADABLE" "$TMP/F.out" \
  || fail "F: ledger symlink did not fail with LEDGER_UNREADABLE" "$TMP/F.out"

# ===========================================================================
# CELL G — JIRA Epic/company archive parity: the same constrained relocation
# succeeds when the report and ledger move from companies/<company>/<EPIC> to
# companies/<company>/archive/<EPIC>.
# ===========================================================================
WS_G="$TMP/wsG"
CONTAINER_G="$(write_company_source "$WS_G" acme EPIC-817 IMPLEMENTED)"
mkdir -p "$CONTAINER_G/artifacts/auto-pass"
LEDGER_G="$CONTAINER_G/artifacts/auto-pass/ledgerG.json"
write_ledger "$LEDGER_G" '"complete"'
REPORT_G="$CONTAINER_G/artifacts/auto-pass/reportG.json"
write_report_for_source "$REPORT_G" EPIC-817 complete PASS "$LEDGER_G" null
COMPANIES_G="$(specs_root_for "$WS_G")/companies/acme"
mkdir -p "$COMPANIES_G/archive"
mv "$CONTAINER_G" "$COMPANIES_G/archive/"
ARCHIVED_REPORT_G="$COMPANIES_G/archive/EPIC-817/artifacts/auto-pass/reportG.json"
run_validate "$WS_G" "$ARCHIVED_REPORT_G" "$TMP/G.out" \
  || fail "G: JIRA Epic archived report did not resolve its moved ledger" "$TMP/G.out"
grep -q "PASS: auto-pass report validation" "$TMP/G.out" \
  || fail "G: JIRA Epic archived relocation did not report PASS" "$TMP/G.out"

# ===========================================================================
# CELL H — company parent is part of ledger identity. Repeating the same Epic
# and ledger basename under another company must not bind to the archived local
# candidate.
# ===========================================================================
WS_H="$TMP/wsH"
CONTAINER_H="$(write_company_source "$WS_H" acme EPIC-818 IMPLEMENTED)"
COMPANIES_H="$(specs_root_for "$WS_H")/companies"
mkdir -p "$COMPANIES_H/acme/archive"
mv "$CONTAINER_H" "$COMPANIES_H/acme/archive/"
ARCHIVED_H="$COMPANIES_H/acme/archive/EPIC-818"
mkdir -p "$ARCHIVED_H/artifacts/auto-pass"
write_ledger "$ARCHIVED_H/artifacts/auto-pass/ledgerH.json" '"complete"'
REPORT_H="$ARCHIVED_H/artifacts/auto-pass/reportH.json"
OTHER_COMPANY_LEDGER_H="$COMPANIES_H/other/EPIC-818/artifacts/auto-pass/ledgerH.json"
mkdir -p "$(dirname "$OTHER_COMPANY_LEDGER_H")"
write_ledger "$OTHER_COMPANY_LEDGER_H" '"complete"'
write_report_for_source "$REPORT_H" EPIC-818 complete PASS "$OTHER_COMPANY_LEDGER_H" null
rc=0; run_validate "$WS_H" "$REPORT_H" "$TMP/H.out" || rc=$?
[ "$rc" -ne 0 ] || fail "H: archived report crossed company ownership for ledger relocation" "$TMP/H.out"
grep -q "POLARIS_AUTO_PASS_REPORT_LEDGER_UNREADABLE" "$TMP/H.out" \
  || fail "H: cross-company ledger fallback did not fail with LEDGER_UNREADABLE" "$TMP/H.out"

# ===========================================================================
# CELL I — the stale declared active path is lexical identity, not live
# filesystem identity. Recreating that path as a symlink to a different ledger
# cannot rewrite the archived candidate basename.
# ===========================================================================
WS_I="$TMP/wsI"
CONTAINER_I="$(write_source "$WS_I" 819 IMPLEMENTED)"
mkdir -p "$CONTAINER_I/artifacts/auto-pass"
LEDGER_I="$CONTAINER_I/artifacts/auto-pass/ledgerI.json"
write_ledger "$LEDGER_I" '"complete"'
REPORT_I="$CONTAINER_I/artifacts/auto-pass/reportI.json"
write_report "$REPORT_I" 819 complete PASS "$LEDGER_I" null
DP_I="$(specs_root_for "$WS_I")/design-plans"
mkdir -p "$DP_I/archive"
mv "$CONTAINER_I" "$DP_I/archive/"
ARCHIVED_I="$DP_I/archive/DP-819-selftest"
ARCHIVED_REPORT_I="$ARCHIVED_I/artifacts/auto-pass/reportI.json"
mkdir -p "$(dirname "$LEDGER_I")"
write_ledger "$(dirname "$LEDGER_I")/ledgerI-other.json" '"blocked_by_gate_failure"'
ln -s ledgerI-other.json "$LEDGER_I"
run_validate "$WS_I" "$ARCHIVED_REPORT_I" "$TMP/I.out" \
  || fail "I: declared active-path symlink rewrote archived ledger identity" "$TMP/I.out"
grep -q "PASS: auto-pass report validation" "$TMP/I.out" \
  || fail "I: declared active-path symlink fixture did not report PASS" "$TMP/I.out"

echo "PASS: report archive validation order selftest"
