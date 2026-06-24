#!/usr/bin/env bash
# Purpose: selftest for DP-360 T6 — assert scripts/derive-task-md-from-refinement-json.sh
#   can write a task.md delivery/verification block (deliverable.head_sha +
#   verification PASS status + AC disposition / ac_counts) when delivery inputs are
#   supplied, and that the block is YAML-legal + machine-parseable by validate-task-md.sh.
#   D1: deliverable.head_sha is the persisted artifact field that absorbs the delivered
#       head role (contract source #3, not a mutable branch ref).
#   D2: the marker payload (PASS / ac_counts / verify binding) is relocated into the
#       task.md block schema shape (this task only proves the derive writer can emit it;
#       marker writer teardown is T7).
#   Back-compat (AC-NEG): a refinement.json with no delivery inputs still derives a
#       legal task.md WITHOUT the block — old inputs keep deriving the old body.
# Inputs:  none (constructs refinement.json fixtures in a tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
VALIDATE_TASK_MD="$ROOT_DIR/scripts/validate-task-md.sh"

[[ -f "$DERIVE" ]] || { echo "FAIL: derive script not found: $DERIVE" >&2; exit 1; }
[[ -f "$VALIDATE_TASK_MD" ]] || { echo "FAIL: validate-task-md not found: $VALIDATE_TASK_MD" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-delivery-block.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "FAIL [$1]: $2" >&2
  exit 1
}

# A minimal valid DP-backed refinement.json with a single implementation T task.
write_refinement() {
  local out="$1"
  cat >"$out" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-901",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/design-plans/DP-901-sample",
    "plan_path": "/tmp/dp-901/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "modules": [
    { "path": "scripts/selftests/derive-delivery-block-fixture-selftest.sh", "action": "create", "complexity": "low", "risk": "low", "reason": "fixture", "references": 0 }
  ],
  "tasks": [
    {
      "id": "DP-901-T1",
      "kind": "implementation",
      "title": "delivery block fixture task",
      "scope": "驗證 derive 能寫出 delivery/verification block。",
      "allowed_files": ["scripts/selftests/derive-delivery-block-fixture-selftest.sh"],
      "modules": ["scripts/selftests/derive-delivery-block-fixture-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "task_shape": "implementation",
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/derive-delivery-block-fixture-selftest.sh",
        "verify_command": "bash scripts/selftests/derive-delivery-block-fixture-selftest.sh",
        "behavior_contract": { "applies": false, "reason": "framework infra" },
        "test_environment": { "level": "static" },
        "references": ["scripts/selftests/derive-delivery-block-fixture-selftest.sh"]
      }
    }
  ]
}
JSON
}

write_refinement "$tmpdir/refinement.json"

# Helper: extract the value of a `<indent>key:` scalar line from a file (first match).
scalar_field() {
  local file="$1" key="$2"
  grep -E "^[[:space:]]*${key}:[[:space:]]" "$file" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//; s/[[:space:]]+\$//"
}

# Helper: extract a scalar field that lives INSIDE the `deliverable:` block, so a
# same-named key elsewhere in the frontmatter (e.g. the top-level `status:
# IN_PROGRESS`) cannot shadow the nested deliverable.verification.status. Scans
# from the `deliverable:` line until the next top-level (unindented) YAML key.
deliverable_scoped_field() {
  local file="$1" key="$2"
  awk -v key="$key" '
    /^deliverable:/ { in_block=1; next }
    in_block && /^[^[:space:]#]/ { exit }
    in_block && match($0, "^[[:space:]]+" key ":[[:space:]]") {
      val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
      print val; exit
    }
  ' "$file"
}

DELIVERED_HEAD="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
PR_URL="https://github.com/exampleco/polaris/pull/1234"

# ===========================================================================
# Case 1 (D1/D2 — block emitted): supply delivery inputs -> derive emits a
# deliverable block carrying head_sha + a nested verification sub-block with
# PASS status + ac_counts. Substantive assertions on each field.
# ===========================================================================
out_with="$tmpdir/task-with-block.md"
bash "$DERIVE" \
  --refinement-json "$tmpdir/refinement.json" \
  --task-id "DP-901-T1" \
  --deliverable-head-sha "$DELIVERED_HEAD" \
  --deliverable-pr-url "$PR_URL" \
  --deliverable-pr-state MERGED \
  --verification-status PASS \
  --ac-total 3 --ac-pass 3 --ac-fail 0 --ac-manual-required 0 --ac-uncertain 0 \
  >"$out_with" 2>"$tmpdir/with.err" \
  || fail "case 1 / D1-D2" "derive failed with delivery inputs: $(cat "$tmpdir/with.err")"

# D1: deliverable.head_sha present and equals the supplied delivered head.
grep -qE '^deliverable:' "$out_with" \
  || fail "case 1 / D1" "expected a top-level 'deliverable:' block in the body"
got_head="$(deliverable_scoped_field "$out_with" head_sha)"
[[ "$got_head" == "$DELIVERED_HEAD" ]] \
  || fail "case 1 / D1" "deliverable.head_sha='$got_head' (expected '$DELIVERED_HEAD')"
got_pr_url="$(deliverable_scoped_field "$out_with" pr_url)"
[[ "$got_pr_url" == "$PR_URL" ]] \
  || fail "case 1 / D1" "deliverable.pr_url='$got_pr_url' (expected '$PR_URL')"
got_pr_state="$(deliverable_scoped_field "$out_with" pr_state)"
[[ "$got_pr_state" == "MERGED" ]] \
  || fail "case 1 / D1" "deliverable.pr_state='$got_pr_state' (expected MERGED)"

# D2: nested verification sub-block carries the PASS status + ac_counts payload.
# Use the deliverable-scoped extractor so the top-level `status: IN_PROGRESS`
# cannot shadow the nested deliverable.verification.status.
grep -qE '^[[:space:]]+verification:' "$out_with" \
  || fail "case 1 / D2" "expected a nested 'verification:' sub-block under deliverable"
got_vstatus="$(deliverable_scoped_field "$out_with" status)"
[[ "$got_vstatus" == "PASS" ]] \
  || fail "case 1 / D2" "deliverable.verification.status='$got_vstatus' (expected PASS)"
for kv in "ac_total:3" "ac_pass:3" "ac_fail:0" "ac_manual_required:0" "ac_uncertain:0"; do
  k="${kv%%:*}"; v="${kv##*:}"
  got="$(deliverable_scoped_field "$out_with" "$k")"
  [[ "$got" == "$v" ]] \
    || fail "case 1 / D2" "deliverable.verification.ac_counts.$k='$got' (expected $v)"
done

# Machine-parseable: validate-task-md.sh must accept the derived body (the deliverable
# block schema it enforces — pr_url / pr_state / head_sha — must all pass).
if ! bash "$VALIDATE_TASK_MD" "$out_with" >"$tmpdir/validate-with.log" 2>&1; then
  fail "case 1 / parse" "validate-task-md.sh rejected the body carrying a delivery block: $(cat "$tmpdir/validate-with.log")"
fi

# ===========================================================================
# Case 2 (AC-NEG back-compat): NO delivery inputs -> NO deliverable block, and
# the body still validates. This proves the block is purely additive: legacy
# refinement.json (no delivery inputs) keeps deriving the old body unchanged.
# ===========================================================================
out_without="$tmpdir/task-without-block.md"
bash "$DERIVE" \
  --refinement-json "$tmpdir/refinement.json" \
  --task-id "DP-901-T1" \
  >"$out_without" 2>"$tmpdir/without.err" \
  || fail "case 2 / back-compat" "derive failed without delivery inputs: $(cat "$tmpdir/without.err")"

if grep -qE '^deliverable:' "$out_without"; then
  fail "case 2 / back-compat" "a deliverable block leaked into the body when no delivery inputs were supplied (not additive)"
fi
if ! bash "$VALIDATE_TASK_MD" "$out_without" >"$tmpdir/validate-without.log" 2>&1; then
  fail "case 2 / back-compat" "validate-task-md.sh rejected the legacy (no-block) body: $(cat "$tmpdir/validate-without.log")"
fi

# Cross-check non-vacuity: the two bodies must differ ONLY by the delivery block —
# both must derive successfully, but only the with-inputs body carries the block.
if diff -q "$out_with" "$out_without" >/dev/null 2>&1; then
  fail "case 2 / non-vacuous" "with-inputs and no-inputs bodies are byte-identical (delivery block had no effect)"
fi

# ===========================================================================
# Case 3 (D2 — non-PASS verification status round-trips): a FAIL status with a
# matching ac_counts must be emitted faithfully (the writer relocates the real
# payload, it does not hardcode PASS). human_disposition required by
# validate-task-md.sh only applies to the V-mode ac_verification block, not this
# T-mode deliverable.verification sub-block, so a FAIL here must still validate.
# ===========================================================================
out_fail="$tmpdir/task-fail.md"
bash "$DERIVE" \
  --refinement-json "$tmpdir/refinement.json" \
  --task-id "DP-901-T1" \
  --deliverable-head-sha "$DELIVERED_HEAD" \
  --deliverable-pr-url "$PR_URL" \
  --deliverable-pr-state OPEN \
  --verification-status FAIL \
  --ac-total 2 --ac-pass 1 --ac-fail 1 --ac-manual-required 0 --ac-uncertain 0 \
  >"$out_fail" 2>"$tmpdir/fail.err" \
  || fail "case 3 / D2" "derive failed with FAIL verification status: $(cat "$tmpdir/fail.err")"
got_fstatus="$(deliverable_scoped_field "$out_fail" status)"
[[ "$got_fstatus" == "FAIL" ]] \
  || fail "case 3 / D2" "deliverable.verification.status='$got_fstatus' (expected FAIL — writer must not hardcode PASS)"

echo "PASS: derive-task-md-delivery-block selftest"
