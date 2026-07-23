#!/usr/bin/env bash
# auto-pass-report-producer-selftest.sh — DP-230 T12 / D32 / AC32 / AC-NEG12.
#
# Verifies that auto-pass report writes are gated by the canonical producer
# registry contract:
#
#   AC32  scripts/write-producer-owned-artifact.sh --producer-token
#         auto-pass:report writes artifacts/auto-pass/YYYYMMDD-HHMMSS-report.json
#         successfully and dispatches validate-auto-pass-report.sh.
#   AC32  no-direct-evidence-write.sh denies a Write to
#         artifacts/auto-pass/*-report.json without POLARIS_PRODUCER, emitting
#         stderr token POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED.
#   AC32  no-direct-evidence-write.sh denies a Write with an unrelated token
#         (e.g. breakdown:initial-create) on a *-report.json path, also
#         emitting POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED.
#   AC-NEG12  existing producer tokens (auto-pass:source, auto-pass:verify
#         resume context, breakdown:initial-create) keep functioning — token
#         uniqueness invariant holds.
#
# Exit 0 → PASS; non-zero exit prints diagnostic.

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
HOOK="$ROOT_DIR/.claude/hooks/no-direct-evidence-write.sh"
WRITER="$ROOT_DIR/scripts/write-producer-owned-artifact.sh"
PRODUCERS_JSON="$ROOT_DIR/scripts/lib/evidence-producers.json"
FIXTURE_DIR="$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/DP-938-auto-pass-report-producer-selftest"
WORKDIR="$(mktemp -d -t dp230-t12-auto-pass-report.XXXXXX)"
trap 'rm -rf "$WORKDIR"; rm -rf "$FIXTURE_DIR"' EXIT

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook not executable: $HOOK" >&2
  exit 1
fi
if [[ ! -x "$WRITER" ]]; then
  echo "FAIL: writer not executable: $WRITER" >&2
  exit 1
fi
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "FAIL: producers table missing: $PRODUCERS_JSON" >&2
  exit 1
fi

# Contract sanity: producer_tokens[] uniqueness + auto-pass:report registered.
python3 - <<PY
import json, sys
data = json.load(open("$PRODUCERS_JSON"))
seen = set()
required = {"auto-pass:report", "auto-pass:source", "auto-pass:verify",
            "auto-pass:breakdown", "auto-pass:engineering",
            "breakdown:initial-create", "verify-AC:evidence-layout"}
for p in data.get("producers", []):
    for t in (p.get("producer_tokens") or []):
        if t in seen:
            print(f"FAIL: duplicate token in producer_tokens[]: {t}", file=sys.stderr)
            sys.exit(2)
        seen.add(t)
missing = required - seen
if missing:
    print(f"FAIL: producer_tokens missing: {sorted(missing)}", file=sys.stderr)
    sys.exit(2)
PY

run_hook() {
  local payload="$1"
  local expected_exit="$2"
  local label="$3"
  local env_var="${4:-}"
  local out_file="$WORKDIR/${label}.out"
  set +e
  if [[ -n "$env_var" ]]; then
    env $env_var bash -c 'printf "%s" "$1" | "$2" >"$3" 2>&1' _ "$payload" "$HOOK" "$out_file"
  else
    printf '%s' "$payload" | "$HOOK" >"$out_file" 2>&1
  fi
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" ]]; then
    echo "FAIL ($label): expected exit $expected_exit, got $rc" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

report_path="$FIXTURE_DIR/artifacts/auto-pass/20260524-120000-report.json"

# AC32 hook NEG (no token): writing *-report.json without POLARIS_PRODUCER must
# fail-stop with POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED.
payload_neg1=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$report_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_neg1" 2 ac32-neg-no-token
grep -q 'POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED' "$WORKDIR/ac32-neg-no-token.out"
grep -q 'BLOCKED' "$WORKDIR/ac32-neg-no-token.out"

# AC32 hook NEG (wrong token): breakdown:initial-create on *-report.json
# fails-stop with POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED.
payload_neg2=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$report_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_neg2" 2 ac32-neg-wrong-token "POLARIS_PRODUCER=breakdown:initial-create"
grep -q 'POLARIS_EVIDENCE_PRODUCER_TOKEN_REQUIRED' "$WORKDIR/ac32-neg-wrong-token.out"

# AC32 hook POSITIVE (correct token): auto-pass:report token writing report json.
payload_pos=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$report_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_pos" 0 ac32-pos-token-bypass "POLARIS_PRODUCER=auto-pass:report"
grep -q 'producer=auto-pass:report' "$WORKDIR/ac32-pos-token-bypass.out"

# DP-438 AC1: the canonical writer must persist a complete report while the
# parent is still LOCKED, after validating every non-lifecycle constraint.
mkdir -p "$FIXTURE_DIR"
cat >"$FIXTURE_DIR/index.md" <<'MD'
---
title: "DP-938"
description: "auto-pass report producer selftest fixture."
status: LOCKED
---

# DP-938
MD

ledger_path="$WORKDIR/dummy-ledger.json"
cat >"$ledger_path" <<'JSON'
{
  "schema_version": 1,
  "terminal_status": null,
  "pause": null,
  "friction_log": [],
  "created_at": "2026-05-24T00:00:00+08:00"
}
JSON

report_body="$WORKDIR/report.json"
python3 - "$report_body" "$ledger_path" <<'PY'
import json, sys
report_path, ledger_path = sys.argv[1:3]
payload = {
    "schema_version": 1,
    "source_id": "DP-938",
    "terminal_status": "complete",
    "created_at": "2026-05-24T00:00:00+08:00",
    "ledger_path": ledger_path,
    "required_prs": [],
    "verification": {"status": "N/A", "work_item_id": None},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [{"candidate": "self", "disposition": "keep", "reason": "fixture"}],
    "follow_up_dp_seed": None,
    "framework_release_tail": {
        "trigger": "framework-release DP-938",
        "allowed": True,
        "reason": "fixture"
    }
}
open(report_path, "w").write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
PY

mkdir -p "$(dirname "$report_path")"
set +e
"$WRITER" \
  --producer-token auto-pass:report \
  --path "$report_path" \
  --body-file "$report_body" >"$WORKDIR/writer-report.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (AC32 writer report): expected exit 0, got $rc" >&2
  cat "$WORKDIR/writer-report.out" >&2
  exit 1
fi
grep -q 'artifact_kind=auto_pass_report' "$WORKDIR/writer-report.out" || {
  echo "FAIL (AC32 writer): expected artifact_kind=auto_pass_report" >&2
  cat "$WORKDIR/writer-report.out" >&2
  exit 1
}
grep -q 'producer=auto-pass:report' "$WORKDIR/writer-report.out" || {
  echo "FAIL (AC32 writer): expected producer=auto-pass:report stderr trace" >&2
  cat "$WORKDIR/writer-report.out" >&2
  exit 1
}

# The default validator remains the full terminal check and must still reject
# the active LOCKED parent before archive.
set +e
"$ROOT_DIR/scripts/validate-auto-pass-report.sh" "$report_path" >"$WORKDIR/full-prearchive.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]] || ! grep -q 'POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED' "$WORKDIR/full-prearchive.out"; then
  echo "FAIL (DP-438 AC1): default validator did not fail-closed before archive" >&2
  cat "$WORKDIR/full-prearchive.out" >&2
  exit 1
fi

# AC-NEG1: pre-archive phase delays only the lifecycle postcondition. A broken
# ledger reference is still invalid and the writer must roll the target back.
invalid_report_body="$WORKDIR/invalid-report.json"
invalid_report_path="$FIXTURE_DIR/artifacts/auto-pass/20260524-120001-report.json"
python3 - "$report_body" "$invalid_report_body" <<'PY'
import json, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:3])
d = json.loads(src.read_text())
d["ledger_path"] = str(dst.parent / "missing-ledger.json")
dst.write_text(json.dumps(d) + "\n", encoding="utf-8")
PY
set +e
"$WRITER" \
  --producer-token auto-pass:report \
  --path "$invalid_report_path" \
  --body-file "$invalid_report_body" >"$WORKDIR/writer-invalid-report.out" 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]] || [[ -e "$invalid_report_path" ]]; then
  echo "FAIL (DP-438 AC-NEG1): invalid pre-archive report was not rolled back" >&2
  cat "$WORKDIR/writer-invalid-report.out" >&2
  exit 1
fi

# AC-NEG12: existing tokens (auto-pass:source, auto-pass:verify,
# breakdown:initial-create) still resolve to their canonical producer entry
# post D31/D32 expansion. Test by writing to an out-of-glob path and asserting
# the writer reports "not covered by producer" (proves token is registered and
# its path_globs[] is intact).
set +e
"$WRITER" \
  --producer-token auto-pass:source \
  --path "$WORKDIR/oos-source.json" \
  --body-file "$ledger_path" >"$WORKDIR/writer-ledger.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]] || ! grep -q 'not covered by producer' "$WORKDIR/writer-ledger.out"; then
  echo "FAIL (AC-NEG12 auto-pass:source resolution): broke" >&2
  cat "$WORKDIR/writer-ledger.out" >&2
  exit 1
fi

set +e
"$WRITER" \
  --producer-token auto-pass:verify \
  --path "$WORKDIR/oos-verify.json" \
  --body-file "$ledger_path" >"$WORKDIR/writer-verify.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]] || ! grep -q 'not covered by producer' "$WORKDIR/writer-verify.out"; then
  echo "FAIL (AC-NEG12 auto-pass:verify resolution): broke" >&2
  cat "$WORKDIR/writer-verify.out" >&2
  exit 1
fi

set +e
"$WRITER" \
  --producer-token breakdown:initial-create \
  --path "$WORKDIR/oos-breakdown.md" \
  --body-file "$ledger_path" >"$WORKDIR/writer-breakdown.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]] || ! grep -q 'not covered by producer' "$WORKDIR/writer-breakdown.out"; then
  echo "FAIL (AC-NEG12 breakdown:initial-create resolution): broke" >&2
  cat "$WORKDIR/writer-breakdown.out" >&2
  exit 1
fi

echo "PASS"
