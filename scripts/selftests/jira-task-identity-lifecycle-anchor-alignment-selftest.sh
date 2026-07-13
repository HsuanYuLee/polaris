#!/usr/bin/env bash
# Purpose: DP-417 T4 (AC4 / AC-N1) — prove the three task-identity input forms
#          resolve to ONE canonical task id shared by breakdown / engineering /
#          auto-pass, aligned to the source parent lifecycle anchor:
#            * short id            — T1
#            * full (source) id    — {SOURCE}-T1 (JIRA-Epic and DP forms)
#            * folder-native path  — tasks/T1/index.md AND tasks/pr-release/T1/index.md
#          The canonical id is parse-task-md.sh's `work_item_id` ({source}-T{n});
#          the parent lifecycle anchor is its `source_id` ({DP}/{Epic}). Every
#          form must yield the SAME work_item_id and the SAME source_id.
#
#          Reuses the single canonical machinery — no reimplementation:
#            * full id / folder-native path -> resolve-task-md.sh
#            * short id within a tasks dir  -> parse-task-md.sh --key --tasks-dir
#              (DP-033 D8 active->pr-release reader, extended to folder-native)
#            * canonical id derivation      -> parse-task-md.sh --field
#
# Covers:  AC4 (three forms -> one canonical id + parent anchor alignment, for
#            both a DP-backed source and a JIRA-Epic-backed source, across active
#            and pr-release folder-native layouts), AC-N1 (executable coverage;
#            plus no-false-positive: an absent short id fails closed and a
#            prefix-similar sibling source is never misresolved).
# Inputs:  none (builds a hermetic specs tree in a tmpdir using GENERIC
#            placeholder identities — DP-900 / EXCO-700 / exampleco-web — never
#            live slugs)
# Outputs: stdout PASS line; exit 0 PASS, non-zero FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVE="$ROOT_DIR/scripts/resolve-task-md.sh"
PARSE="$ROOT_DIR/scripts/parse-task-md.sh"

[[ -f "$RESOLVE" ]] || { echo "FAIL: resolve-task-md.sh missing: $RESOLVE" >&2; exit 1; }
[[ -f "$PARSE" ]] || { echo "FAIL: parse-task-md.sh missing: $PARSE" >&2; exit 1; }

tmpdir="$(mktemp -d -t jira-task-identity-anchor.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail=0
SPECS="$tmpdir/docs-manager/src/content/docs/specs"

# --- fixtures: folder-native task.md, active + pr-release, DP + JIRA-Epic ---
write_task() {
  # write_task <path> <source_id> <work_item_id> <source_type> <jira_key> <title>
  local path="$1" source_id="$2" work_item_id="$3" source_type="$4" jira_key="$5" title="$6"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<MD
# T1: ${title} (1 pt)

> Source: ${source_id} | Task: ${work_item_id} | JIRA: ${jira_key} | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | ${source_type} |
| Source ID | ${source_id} |
| Work item ID | ${work_item_id} |
| Task ID | ${work_item_id} |
| JIRA key | ${jira_key} |
| Base branch | develop |
| Task branch | task/${work_item_id}-fixture |

## Test Environment

- **Level**: static
MD
}

# DP-backed source (folder-native, active T1)
write_task "$SPECS/design-plans/DP-900-canonical-id-fixture/tasks/T1/index.md" \
  "DP-900" "DP-900-T1" "dp" "N/A" "DP canonical active"
# DP-backed source (folder-native, pr-release T2 — doubly nested)
write_task "$SPECS/design-plans/DP-900-canonical-id-fixture/tasks/pr-release/T2/index.md" \
  "DP-900" "DP-900-T2" "dp" "N/A" "DP canonical pr-release"
# JIRA-Epic-backed source (folder-native, active T1)
write_task "$SPECS/companies/exampleco/EXCO-700/tasks/T1/index.md" \
  "EXCO-700" "EXCO-700-T1" "jira" "EXCO-712" "JIRA canonical active"
# AC-N1 decoy: prefix-similar sibling Epic (EXCO-7000) must never be misresolved
write_task "$SPECS/companies/exampleco/EXCO-7000/tasks/T1/index.md" \
  "EXCO-7000" "EXCO-7000-T1" "jira" "EXCO-7012" "JIRA decoy sibling"

hermetic_resolve() {
  # hermetic_resolve <scan_root> <input>  — env unset keeps the child hermetic
  env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT bash "$RESOLVE" --scan-root "$1" "$2"
}
field() {
  # field <task.md> <field>  (set -e safe: never aborts the caller's assignment)
  bash "$PARSE" "$1" --no-resolve --field "$2" 2>/dev/null || true
}
key_field() {
  # key_field <tasks_dir> <task_key> <field>  (set -e safe)
  bash "$PARSE" --key "$2" --tasks-dir "$1" --field "$3" 2>/dev/null || true
}
expect_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "[selftest] FAIL ($label): got '$got' want '$want'" >&2
    fail=1
  fi
}

# ---------------------------------------------------------------------------
# assert_three_forms — the AC4 heart. Given a source's tasks dir, a short id, a
# full id, and the expected canonical work_item_id + parent anchor source_id,
# assert all three input forms resolve to the SAME canonical id + SAME anchor.
# ---------------------------------------------------------------------------
assert_three_forms() {
  local label="$1" tasks_dir="$2" short_id="$3" full_id="$4" \
        want_work_item_id="$5" want_source_id="$6"

  # Form 2 — full (source-qualified) id via resolve-task-md.sh
  local p_full rc=0
  p_full="$(hermetic_resolve "$tmpdir" "$full_id")" || rc=$?
  [[ $rc -eq 0 && -f "$p_full" ]] || { echo "[selftest] FAIL ($label.full_id): resolve failed for $full_id" >&2; fail=1; return; }
  expect_eq "$label.full_id.work_item_id" "$(field "$p_full" work_item_id)" "$want_work_item_id"
  expect_eq "$label.full_id.source_id"    "$(field "$p_full" source_id)"    "$want_source_id"

  # Form 3 — folder-native path via resolve-task-md.sh (direct path resolution)
  local p_path
  rc=0
  p_path="$(hermetic_resolve "$tmpdir" "$p_full")" || rc=$?
  [[ $rc -eq 0 && "$p_path" == "$p_full" ]] || { echo "[selftest] FAIL ($label.path): folder-native path did not resolve to same task.md ($p_path vs $p_full)" >&2; fail=1; }
  expect_eq "$label.path.work_item_id" "$(field "$p_path" work_item_id)" "$want_work_item_id"

  # Form 1 — short id within the source tasks dir via parse-task-md.sh --key
  local sid_wi sid_src
  sid_wi="$(key_field "$tasks_dir" "$short_id" work_item_id)"
  sid_src="$(key_field "$tasks_dir" "$short_id" source_id)"
  expect_eq "$label.short_id.work_item_id" "$sid_wi" "$want_work_item_id"
  expect_eq "$label.short_id.source_id"    "$sid_src" "$want_source_id"

  # Cross-form invariant: one canonical id, one parent anchor.
  if [[ "$(field "$p_full" work_item_id)" != "$sid_wi" ]]; then
    echo "[selftest] FAIL ($label.cross): short id and full id disagree on canonical work_item_id" >&2
    fail=1
  fi
}

# AC4 — DP-backed source, active folder-native (short=T1, full=DP-900-T1)
assert_three_forms "AC4.dp.active" \
  "$SPECS/design-plans/DP-900-canonical-id-fixture/tasks" \
  "T1" "DP-900-T1" "DP-900-T1" "DP-900"

# AC4 — DP-backed source, pr-release folder-native (short=T2 -> pr-release/T2/index.md)
assert_three_forms "AC4.dp.pr_release" \
  "$SPECS/design-plans/DP-900-canonical-id-fixture/tasks" \
  "T2" "DP-900-T2" "DP-900-T2" "DP-900"

# AC4 — JIRA-Epic-backed source, active folder-native
assert_three_forms "AC4.jira.active" \
  "$SPECS/companies/exampleco/EXCO-700/tasks" \
  "T1" "EXCO-700-T1" "EXCO-700-T1" "EXCO-700"

# ---------------------------------------------------------------------------
# AC-N1 no-false-positive — an absent short id must fail closed (exit 2), and a
# prefix-similar sibling source must never be misresolved by the full id.
# ---------------------------------------------------------------------------
rc=0
key_out="$(bash "$PARSE" --key T9 --tasks-dir "$SPECS/design-plans/DP-900-canonical-id-fixture/tasks" --field work_item_id 2>/dev/null)" || rc=$?
if [[ $rc -eq 0 || -n "$key_out" ]]; then
  echo "[selftest] FAIL (AC-N1.absent): absent short id T9 resolved instead of failing closed (rc=$rc out='$key_out')" >&2
  fail=1
fi

# Full id EXCO-700-T1 must resolve the EXCO-700 Epic, never the EXCO-7000 decoy.
rc=0
decoy_check="$(hermetic_resolve "$tmpdir" "EXCO-700-T1")" || rc=$?
if [[ $rc -ne 0 || "$decoy_check" != *"/EXCO-700/tasks/T1/index.md" || "$decoy_check" == *"/EXCO-7000/"* ]]; then
  echo "[selftest] FAIL (AC-N1.decoy): EXCO-700-T1 misresolved to '$decoy_check'" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "jira-task-identity-lifecycle-anchor-alignment selftest FAIL" >&2
  exit 1
fi

echo "jira-task-identity-lifecycle-anchor-alignment selftest PASS"
