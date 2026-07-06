#!/usr/bin/env bash
# Mark an Epic/Bug/Task spec as IMPLEMENTED (or ABANDONED) by updating
# the frontmatter status field in refinement.md / plan.md / task.md.
#
# Usage:
#   mark-spec-implemented.sh <ticket_key> [--status IMPLEMENTED|ABANDONED] [--workspace <path>] [--auto-archive|--no-auto-archive]
#
# Examples:
#   mark-spec-implemented.sh EPIC-521
#   mark-spec-implemented.sh TASK-3847 --status IMPLEMENTED
#   mark-spec-implemented.sh EPIC-483 --status ABANDONED
#
# Behavior:
#   Epic/Bug anchor (refinement.md / plan.md):
#     - Updates frontmatter in-place (existing behavior, unchanged)
#     - Idempotent: already same status → NOOP exit 0
#
#   Task anchor (T{n}.md / V{n}.md  resolved by "JIRA: KEY" header):
#     - MOVE-FIRST sequence (DP-033 D6):
#         1. mv tasks/T.md → tasks/pr-release/T.md
#         2. Update frontmatter status in pr-release/T.md
#     - Idempotent:
#         - File already in pr-release/ + already IMPLEMENTED → NOOP exit 0
#         - File already in pr-release/ (different status) → update frontmatter, exit 0
#         - tasks/ copy AND pr-release/ copy with SAME content → remove active, continue
#         - tasks/ copy AND pr-release/ copy with DIFFERENT content → exit 2 (invariant violation)
#     - Creates tasks/pr-release/ directory if absent
#
# Exit codes:
#   0 — success (including idempotent no-op)
#   1 — error (file not found, parse failure, filesystem error)
#   2 — same-key invariant violation (tasks/ and pr-release/ exist with different content)
#
# Non-goals:
#   - Does NOT sync to JIRA
#   - Does NOT regenerate docs-manager routes; docs-manager reads canonical specs directly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"
SYNC_SPEC_SIDEBAR="${SCRIPT_DIR}/sync-spec-sidebar-metadata.sh"
ARCHIVE_SPEC="${MARK_SPEC_ARCHIVE_SPEC_BIN:-${SCRIPT_DIR}/archive-spec.sh}"
FINALIZE_LEDGER="${MARK_SPEC_FINALIZE_LEDGER_BIN:-${SCRIPT_DIR}/auto-pass-finalize-ledger.sh}"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

run_selftest() {
  local tmpdir=""
  local archive_stub=""
  local archive_log=""
  local rc=0

  tmpdir="$(mktemp -d -t mark-spec-implemented-selftest.XXXXXX)"
  trap "rm -rf '$tmpdir'" EXIT
  archive_log="$tmpdir/archive.log"
  archive_stub="$tmpdir/archive-spec-stub.sh"
  cat > "$archive_stub" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${MARK_SPEC_ARCHIVE_LOG:?}"
SH
  chmod +x "$archive_stub"

  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks" \
           "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-001/tasks" \
           "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-OLD/tasks"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/T1.md" <<'MD'
# T1: Canonical DP task (1 pt)

> Source: DP-050 | Task: DP-050-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-050 |
| Task ID | DP-050-T1 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-050-T1-canonical |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" DP-050-T1 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] canonical DP mark implemented failed"; return 1; }
  [[ ! -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/T1.md" ]] || { echo "[selftest] active task was not moved"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/pr-release/T1.md" ]] || { echo "[selftest] pr-release task missing"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-050-dp-pseudo-task-identity-separation/tasks/pr-release/T1.md" || { echo "[selftest] status missing"; return 1; }

  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-001/tasks/T2.md" <<'MD'
# T2: Active product task (1 pt)
> Source: EPIC-001 | Task: EPIC-001 | JIRA: EPIC-001 | Repo: exampleco
## Operational Context
| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EPIC-001 |
| Task ID | EPIC-001 |
| JIRA key | EPIC-001 |
| Base branch | main |
| Task branch | task/EPIC-001-active |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-OLD/tasks/T2.md" <<'MD'
# T2: Archived product task (1 pt)
> Source: GT-OLD | Task: GT-OLD | JIRA: GT-OLD | Repo: exampleco
## Operational Context
| Task branch | task/GT-OLD-archived |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" T2 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] active task key mark implemented failed"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-001/tasks/pr-release/T2.md" ]] || { echo "[selftest] active T2 pr-release task missing"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-OLD/tasks/T2.md" ]] || { echo "[selftest] archived T2 was moved unexpectedly"; return 1; }

  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-051-folder-native-task-closeout/tasks/T3"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-051-folder-native-task-closeout/tasks/T3/index.md" <<'MD'
# T3: Folder-native DP task (1 pt)

> Source: DP-051 | Task: DP-051-T3 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-051 |
| Task ID | DP-051-T3 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-051-T3-folder-native |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" DP-051-T3 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] folder-native DP mark implemented failed"; return 1; }
  [[ ! -d "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-051-folder-native-task-closeout/tasks/T3" ]] || { echo "[selftest] folder-native active task was not moved"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-051-folder-native-task-closeout/tasks/pr-release/T3/index.md" ]] || { echo "[selftest] folder-native pr-release task missing"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-051-folder-native-task-closeout/tasks/pr-release/T3/index.md" || { echo "[selftest] folder-native status missing"; return 1; }

  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-052-folder-native-verification-closeout/tasks/V1"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-052-folder-native-verification-closeout/tasks/V1/index.md" <<'MD'
# V1: Folder-native DP verification task (1 pt)

> Source: DP-052 | Task: DP-052-V1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-052 |
| Task ID | DP-052-V1 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-052-V1-folder-native |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" DP-052-V1 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] folder-native DP verification mark implemented failed"; return 1; }
  [[ ! -d "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-052-folder-native-verification-closeout/tasks/V1" ]] || { echo "[selftest] folder-native active verification task was not moved"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-052-folder-native-verification-closeout/tasks/pr-release/V1/index.md" ]] || { echo "[selftest] folder-native pr-release verification task missing"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-052-folder-native-verification-closeout/tasks/pr-release/V1/index.md" || { echo "[selftest] folder-native verification status missing"; return 1; }

  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/GT-PARENT"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/GT-PARENT/refinement.md" <<'MD'
---
title: "GT-PARENT"
status: DISCUSSION
sidebar:
  badge:
    text: "DISCUSSION"
    variant: "note"
---

# GT-PARENT
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" GT-PARENT --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] parent mark implemented failed"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/GT-PARENT/refinement.md" || { echo "[selftest] parent status not updated"; return 1; }
  grep -q 'text: "IMPLEMENTED"' "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/GT-PARENT/refinement.md" || { echo "[selftest] parent sidebar badge not refreshed"; return 1; }
  grep -q -- "--workspace $tmpdir .*GT-PARENT/refinement.md" "$archive_log" || { echo "[selftest] parent auto-archive was not invoked"; return 1; }

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" GT-PARENT --workspace "$tmpdir" --no-auto-archive >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] parent no-auto-archive failed"; return 1; }

  # DP-311 T7 (AC9): bare-DP 遞迴必須傳 fully-qualified key（container-bound Path 3），
  # 雙容器同名 stem 時不得 cross-DP 誤標另一個 container 的同名 task。
  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-053-bare-dp-qualified-recursion/tasks" \
           "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-054-sibling-same-stem/tasks"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-053-bare-dp-qualified-recursion/tasks/T9.md" <<'MD'
# T9: Owning container task (1 pt)

> Source: DP-053 | Task: DP-053-T9 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-053 |
| Task ID | DP-053-T9 |
| Task branch | task/DP-053-T9-owning |
MD
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-054-sibling-same-stem/tasks/T9.md" <<'MD'
# T9: Sibling container task with same stem (1 pt)

> Source: DP-054 | Task: DP-054-T9 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-054 |
| Task ID | DP-054-T9 |
| Task branch | task/DP-054-T9-sibling |
MD
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-053-bare-dp-qualified-recursion/index.md" <<'MD'
---
title: "DP-053"
status: LOCKED
---

# DP-053
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" DP-053 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] bare DP qualified-key recursion failed"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-053-bare-dp-qualified-recursion/tasks/pr-release/T9.md" ]] || { echo "[selftest] owning container T9 pr-release missing"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-053-bare-dp-qualified-recursion/tasks/pr-release/T9.md" || { echo "[selftest] owning container T9 status missing"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-054-sibling-same-stem/tasks/T9.md" ]] || { echo "[selftest] sibling container T9 was moved (cross-DP mis-mark)"; return 1; }
  [[ ! -e "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-054-sibling-same-stem/tasks/pr-release/T9.md" ]] || { echo "[selftest] sibling container T9 leaked into pr-release"; return 1; }

  # DP-311 T7 (AC-NEG8): Path 2 bare task key 多 match（跨 container 同名 stem）必須
  # fail-closed 並列出全部候選，不得取 first match。
  rc=0
  multi_match_out="$(env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" T9 --workspace "$tmpdir" 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || { echo "[selftest] bare task key with multiple matches did not fail closed"; return 1; }
  printf '%s\n' "$multi_match_out" | grep -q 'DP-053-bare-dp-qualified-recursion/tasks/pr-release/T9.md' || { echo "[selftest] multi-match candidate list missing DP-053 T9"; return 1; }
  printf '%s\n' "$multi_match_out" | grep -q 'DP-054-sibling-same-stem/tasks/T9.md' || { echo "[selftest] multi-match candidate list missing DP-054 T9"; return 1; }

  # DP-311 T7: 同 container 的 active + pr-release 同內容是單一 identity，
  # 仍走既有 idempotent reconciliation，不得被多 match fail-closed 誤擋。
  cp "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-001/tasks/pr-release/T2.md" \
     "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-001/tasks/T2.md"
  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" T2 --workspace "$tmpdir" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] same-container dual-presence reconciliation regressed"; return 1; }
  [[ ! -f "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-001/tasks/T2.md" ]] || { echo "[selftest] active duplicate T2 not reconciled"; return 1; }

  # DP-310 T2 (AC3): archive 容器（design-plans/archive/DP-NNN-*）內的 folder-native task
  # anchor 必須能被 DP task key 解析（Path 3），flip status 並 MOVE-FIRST 搬入該容器的
  # tasks/pr-release/；重跑 idempotent NOOP exit 0。
  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-070-archived-folder-native/tasks/V1"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-070-archived-folder-native/tasks/V1/index.md" <<'MD'
---
status: LOCKED
ac_verification:
  status: PASS
---

# V1: Archived folder-native DP verification task (1 pt)

> Source: DP-070 | Task: DP-070-V1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-070 |
| Task ID | DP-070-V1 |
| Task branch | task/DP-070-V1-archived |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" DP-070-V1 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] archived design-plans folder-native DP task mark implemented failed"; return 1; }
  [[ ! -d "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-070-archived-folder-native/tasks/V1" ]] || { echo "[selftest] archived design-plans active task was not moved"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-070-archived-folder-native/tasks/pr-release/V1/index.md" ]] || { echo "[selftest] archived design-plans pr-release task missing"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-070-archived-folder-native/tasks/pr-release/V1/index.md" || { echo "[selftest] archived design-plans status missing"; return 1; }
  grep -q '^  status: PASS$' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-070-archived-folder-native/tasks/pr-release/V1/index.md" || { echo "[selftest] archived design-plans ac_verification block not preserved"; return 1; }
  # idempotent rerun → NOOP exit 0, no half state
  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" DP-070-V1 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] archived design-plans folder-native idempotent rerun failed"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-070-archived-folder-native/tasks/pr-release/V1/index.md" ]] || { echo "[selftest] archived design-plans pr-release task lost on rerun"; return 1; }

  # DP-310 T2 (AC3): companies/*/archive 對稱——archived JIRA Epic-backed source 容器內的
  # folder-native task anchor 必須能被 JIRA key 解析（Path 4），MOVE-FIRST 搬入該容器
  # tasks/pr-release/（source parity，不留 DP-only path）。
  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-ARCH/tasks/T1"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-ARCH/tasks/T1/index.md" <<'MD'
---
status: LOCKED
---

# T1: Archived product folder-native task (1 pt)

> Source: GT-ARCH | Task: GT-ARCH-T1 | JIRA: GT-ARCH | Repo: exampleco

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | GT-ARCH |
| Task ID | GT-ARCH-T1 |
| JIRA key | GT-ARCH |
| Task branch | task/GT-ARCH-T1-archived |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" GT-ARCH --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] archived companies folder-native JIRA task mark implemented failed"; return 1; }
  [[ ! -d "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-ARCH/tasks/T1" ]] || { echo "[selftest] archived companies active task was not moved"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-ARCH/tasks/pr-release/T1/index.md" ]] || { echo "[selftest] archived companies pr-release task missing"; return 1; }
  grep -q '^status: IMPLEMENTED$' "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/GT-ARCH/tasks/pr-release/T1/index.md" || { echo "[selftest] archived companies status missing"; return 1; }

  # DP-310 T2 (AC-NEG2): active-vs-archive 同 DP task key——active 容器存在同 key anchor 時，
  # archive fallback 不得被選中；DP-071-V1 必須解析到 active 容器、archive 容器不被搬動。
  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-071-active-priority/tasks/V1" \
           "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-071-archived-same-key/tasks/V1"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-071-active-priority/tasks/V1/index.md" <<'MD'
# V1: Active container verification task (1 pt)

> Source: DP-071 | Task: DP-071-V1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task branch | task/DP-071-V1-active |
MD
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-071-archived-same-key/tasks/V1/index.md" <<'MD'
# V1: Archived container verification task with same DP task key (1 pt)

> Source: DP-071 | Task: DP-071-V1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task branch | task/DP-071-V1-archived |
MD

  rc=0
  env -u MARK_SPEC_IMPLEMENTED_SELFTEST MARK_SPEC_ARCHIVE_SPEC_BIN="$archive_stub" MARK_SPEC_ARCHIVE_LOG="$archive_log" bash "$0" DP-071-V1 --workspace "$tmpdir" >/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "[selftest] active-vs-archive same key mark implemented failed"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-071-active-priority/tasks/pr-release/V1/index.md" ]] || { echo "[selftest] active container was not selected (AC-NEG2)"; return 1; }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-071-archived-same-key/tasks/V1/index.md" ]] || { echo "[selftest] archived same-key container was moved (active priority violated, AC-NEG2)"; return 1; }
  [[ ! -e "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-071-archived-same-key/tasks/pr-release/V1/index.md" ]] || { echo "[selftest] archived same-key container leaked into pr-release (AC-NEG2)"; return 1; }

  echo "[selftest] PASS"
}

if [[ "${MARK_SPEC_IMPLEMENTED_SELFTEST:-0}" == "1" ]]; then
  run_selftest
  exit $?
fi

TICKET=""
STATUS="IMPLEMENTED"
WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPECS_ROOT=""
AUTO_ARCHIVE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --status)     STATUS="$2"; shift 2 ;;
    --workspace)  WORKSPACE_ROOT="$2"; shift 2 ;;
    --auto-archive) AUTO_ARCHIVE=1; shift ;;
    --no-auto-archive) AUTO_ARCHIVE=0; shift ;;
    -h|--help)
      sed -n '2,33p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TICKET" ]; then
        TICKET="$1"
        shift
      else
        echo "ERROR: unexpected arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

SPECS_ROOT="$(resolve_specs_root "$WORKSPACE_ROOT")" || {
  echo "ERROR: unable to resolve specs root" >&2
  exit 1
}

if [ -z "$TICKET" ]; then
  echo "ERROR: ticket key required (e.g., EPIC-521 or TASK-3847)" >&2
  exit 1
fi

case "$STATUS" in
  IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION) ;;
  *)
    echo "ERROR: invalid status '$STATUS' (must be IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION)" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# update_frontmatter_status <file> <new_status>
#   Updates (or inserts) `status: <new_status>` in YAML frontmatter.
#   Exits non-zero on parse failure.
# ---------------------------------------------------------------------------
update_frontmatter_status() {
  python3 - "$1" "$2" <<'PY'
import sys
import re
from pathlib import Path

path = Path(sys.argv[1])
new_status = sys.argv[2]

content = path.read_text(encoding="utf-8")
lines = content.split("\n")

if lines and lines[0] == "---":
    # Has frontmatter — find closing ---
    try:
        close_idx = lines.index("---", 1)
    except ValueError:
        print(f"ERROR: unclosed frontmatter in {path}", file=sys.stderr)
        sys.exit(1)

    fm = lines[1:close_idx]
    status_pattern = re.compile(r"^status:\s*")
    found = False
    for i, line in enumerate(fm):
        if status_pattern.match(line):
            fm[i] = f"status: {new_status}"
            found = True
            break
    if not found:
        fm.append(f"status: {new_status}")

    new_content = "---\n" + "\n".join(fm) + "\n---\n" + "\n".join(lines[close_idx+1:])
else:
    # No frontmatter — prepend
    new_content = f"---\nstatus: {new_status}\n---\n\n" + content

path.write_text(new_content, encoding="utf-8")
print(f"OK: {path} → status: {new_status}")
PY
}

sync_parent_sidebar_metadata() {
  local file="$1"
  [[ -x "$SYNC_SPEC_SIDEBAR" ]] || return 0
  bash "$SYNC_SPEC_SIDEBAR" --apply "$file" >/dev/null
}

# Description: DP-311 T2 — 在 parent 翻 IMPLEMENTED 之前（source 仍 LOCKED 階段），把
#   對應 auto-pass ledger 的 terminal_status 推進成 complete。只在 parent / bare-DP 分支
#   觸發（task-level path 不觸發，EC7）；non-complete terminal / 未解除 pause / archived /
#   已 IMPLEMENTED 由 helper 自身判定 NOOP。helper exit 非 0 時 fail-stop，parent 不得翻面。
# Args:        $1 = source container 絕對路徑；$2 = parent anchor 檔案路徑
# Side effects: 可能改寫 {container}/artifacts/auto-pass/ 最新 ledger 的 terminal_status
finalize_auto_pass_ledger_before_flip() {
  local container="$1"
  local anchor="$2"
  [ "$STATUS" = "IMPLEMENTED" ] || return 0
  if [ ! -f "$FINALIZE_LEDGER" ]; then
    echo "POLARIS_TOOL_MISSING:auto-pass-finalize-ledger.sh (${FINALIZE_LEDGER})" >&2
    return 1
  fi
  bash "$FINALIZE_LEDGER" --source-container "$container" --anchor "$anchor" --source-id "$TICKET"
}

auto_archive_parent_if_terminal() {
  local file="$1"
  [[ "$AUTO_ARCHIVE" -eq 1 ]] || return 0
  case "$STATUS" in
    IMPLEMENTED|ABANDONED) ;;
    *) return 0 ;;
  esac
  case "$file" in
    */specs/design-plans/archive/*|*/specs/companies/*/archive/*) return 0 ;;
  esac
  [[ -x "$ARCHIVE_SPEC" ]] || return 0
  bash "$ARCHIVE_SPEC" --workspace "$WORKSPACE_ROOT" "$file"
}

# ---------------------------------------------------------------------------
# get_existing_status <file>
#   Echoes the current status value (may be empty string if absent).
# ---------------------------------------------------------------------------
get_existing_status() {
  local file="$1"
  local existing_status=""
  if head -1 "$file" | grep -q '^---$'; then
    existing_status=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^status:' | head -1 | sed 's/^status:[[:space:]]*//' || true)
  fi
  printf '%s' "$existing_status"
}

# ---------------------------------------------------------------------------
# is_task_key <string>
#   Returns 0 (true) if the string looks like a task filename key: T{n}[a-z]
#   or V{n}[a-z] (i.e., a bare task ID, NOT a full path and NOT a JIRA key).
# ---------------------------------------------------------------------------
is_task_key() {
  echo "$1" | grep -qE '^[TV][0-9]+[a-z]*$'
}

# ---------------------------------------------------------------------------
# Resolve anchor file — three resolution paths:
#   1) Epic-level: {workspace}/docs-manager/src/content/docs/specs/companies/<company>/<ticket>/refinement.md, plan.md, or index.md
#   2) Task-level (task key T{n}/V{n}): scan specs/*/tasks/ by filename
#   3) DP task-level (DP-NNN-Tn / DP-NNN-Vn): scan docs-manager/src/content/docs/specs/design-plans/DP-NNN-*/tasks/{T,V}n.md
#   4) Task-level (JIRA key): parser jira_key match first, legacy "> JIRA: <ticket>" fallback
# ---------------------------------------------------------------------------
ANCHOR=""
ANCHOR_TYPE=""  # "epic" | "task"
TASK_FILENAME=""  # task entry name (T1.md for legacy file, T3b for folder-native)
TASKS_DIR=""    # absolute path to the tasks/ directory containing the task

set_task_anchor_from_file() {
  local file="$1"
  local bname dir parent
  ANCHOR="$file"
  bname="$(basename "$file")"
  dir="$(dirname "$file")"
  if [ "$bname" = "index.md" ] && echo "$(basename "$dir")" | grep -qE '^[TV][0-9]+[a-z]*$'; then
    TASK_FILENAME="$(basename "$dir")"
    parent="$(dirname "$dir")"
    if [ "$(basename "$parent")" = "pr-release" ]; then
      TASKS_DIR="$(dirname "$parent")"
    else
      TASKS_DIR="$parent"
    fi
  else
    TASK_FILENAME="$bname"
    if [ "$(basename "$dir")" = "pr-release" ]; then
      TASKS_DIR="$(dirname "$dir")"
    else
      TASKS_DIR="$dir"
    fi
  fi
  ANCHOR_TYPE="task"
}

# Path 1 — Epic-level
for company_specs_dir in "$SPECS_ROOT"/companies/*/; do
  [ -d "$company_specs_dir" ] || continue
  candidate="${company_specs_dir}${TICKET}"
  if [ -d "$candidate" ]; then
    if [ -f "$candidate/refinement.md" ]; then
      ANCHOR="$candidate/refinement.md"
      ANCHOR_TYPE="epic"
      break
    fi
    if [ -f "$candidate/plan.md" ]; then
      ANCHOR="$candidate/plan.md"
      ANCHOR_TYPE="epic"
      break
    fi
    if [ -f "$candidate/index.md" ]; then
      ANCHOR="$candidate/index.md"
      ANCHOR_TYPE="epic"
      break
    fi
  fi
done

# Path 1b — Bare DP container key (DP-NNN)
# Resolves to design-plans/DP-NNN-*/{index.md,plan.md,refinement.md}
# Marks all active T*/V* tasks IMPLEMENTED first (skipping ABANDONED siblings),
# then updates parent status and auto-archives if --auto-archive is enabled.
if [ -z "$ANCHOR" ] && echo "$TICKET" | grep -qE '^DP-[0-9]{3}$'; then
  dp_container=""
  for dp_dir in "$SPECS_ROOT"/design-plans/"$TICKET"-*; do
    [ -d "$dp_dir" ] || continue
    if [ -n "$dp_container" ]; then
      echo "ERROR: bare DP key $TICKET resolved to multiple containers" >&2
      echo "  $dp_container" >&2
      echo "  $dp_dir" >&2
      exit 1
    fi
    dp_container="$dp_dir"
  done
  # Archive fallback: only resolve design-plans/archive/DP-NNN-* when no active
  # container matched, so an active container always wins over an archived one.
  if [ -z "$dp_container" ]; then
    for dp_dir in "$SPECS_ROOT"/design-plans/archive/"$TICKET"-*; do
      [ -d "$dp_dir" ] || continue
      if [ -n "$dp_container" ]; then
        echo "ERROR: bare DP key $TICKET resolved to multiple archived containers" >&2
        echo "  $dp_container" >&2
        echo "  $dp_dir" >&2
        exit 1
      fi
      dp_container="$dp_dir"
    done
  fi
  if [ -n "$dp_container" ]; then
    # Locate parent anchor (index.md preferred, plan.md fallback, refinement.md fallback)
    if [ -f "$dp_container/index.md" ]; then
      ANCHOR="$dp_container/index.md"
    elif [ -f "$dp_container/plan.md" ]; then
      ANCHOR="$dp_container/plan.md"
    elif [ -f "$dp_container/refinement.md" ]; then
      ANCHOR="$dp_container/refinement.md"
    fi
    if [ -n "$ANCHOR" ]; then
      ANCHOR_TYPE="bare_dp"
      BARE_DP_CONTAINER="$dp_container"
    fi
  fi
fi

# Description: 解析 task 檔案（T1.md / T1/index.md，含 pr-release/ 變體）所屬的
#   normalized tasks/ 目錄（pr-release 折回上層 tasks/），輸出到 stdout。
#   同一 task 的 active 與 pr-release 變體會 normalize 成同一個目錄（同一 identity）。
# Args:        $1 = task 檔案絕對路徑
# Side effects: 無（read-only）
resolve_task_identity_dir() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"
  if [ "$(basename "$file")" = "index.md" ]; then
    dir="$(dirname "$dir")"
  fi
  if [ "$(basename "$dir")" = "pr-release" ]; then
    dir="$(dirname "$dir")"
  fi
  printf '%s' "$dir"
}

# Path 2 — Task key (T{n}/V{n}) — look up by filename in active tasks/ or pr-release/
if [ -z "$ANCHOR" ] && is_task_key "$TICKET"; then
  # Search for T{n}[suffix].md or V{n}[suffix].md in tasks/ directories
  # The key is the "stem" (e.g., T1 matches T1.md but not T10.md).
  # We match: tasks/{TICKET}.md  or  tasks/pr-release/{TICKET}.md
  # DP-311 T7 (AC-NEG8): collect ALL matches first; resolving to more than one task
  # identity (distinct normalized tasks/ dirs) is fail-closed — do not take first match.
  task_key_matches=()
  while IFS= read -r f; do
    bname="$(basename "$f")"
    if [ "$bname" = "index.md" ]; then
      stem="$(basename "$(dirname "$f")")"
    else
      stem="${bname%.md}"
    fi
    if [ "$stem" = "$TICKET" ]; then
      task_key_matches+=("$f")
    fi
  done < <(find "$SPECS_ROOT" \
    \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
    -o \( -type f \( \
      -path "*/tasks/${TICKET}.md" \
      -o -path "*/tasks/${TICKET}/index.md" \
      -o -path "*/tasks/pr-release/${TICKET}.md" \
      -o -path "*/tasks/pr-release/${TICKET}/index.md" \
    \) -print \) 2>/dev/null | sort)
  if [ "${#task_key_matches[@]}" -gt 0 ]; then
    # active + pr-release of the SAME task normalize to one identity (the existing
    # downstream same-key reconciliation handles that pair); distinct containers
    # with the same stem are distinct identities and must fail closed.
    identity_count="$(for f in "${task_key_matches[@]}"; do resolve_task_identity_dir "$f"; printf '\n'; done | sort -u | grep -c .)"
    if [ "$identity_count" -gt 1 ]; then
      echo "ERROR: task key $TICKET resolved to multiple matches:" >&2
      for f in "${task_key_matches[@]}"; do
        echo "  $f" >&2
      done
      echo "  Use a fully-qualified key (e.g., DP-NNN-${TICKET}) or a JIRA key to disambiguate." >&2
      exit 1
    fi
    set_task_anchor_from_file "${task_key_matches[0]}"
  fi
fi

# Path 3 — DP task key (DP-NNN-Tn / DP-NNN-Vn) — look up by DP folder + task filename
# Active containers (design-plans/DP-NNN-*) are resolved first; archive containers
# (design-plans/archive/DP-NNN-*) are a separate fallback ordered after active so a
# same-key active anchor always wins (AC-NEG2). DP-NNN-* glob never matches the nested
# archive/ subdir, so the two branches stay disjoint.
if [ -z "$ANCHOR" ] && echo "$TICKET" | grep -qE '^DP-[0-9]{3}-[TV][0-9]+[a-z]*$'; then
  dp_id="$(printf '%s' "$TICKET" | sed -E 's/^(DP-[0-9]{3})-[TV][0-9]+[a-z]*$/\1/')"
  task_stem="$(printf '%s' "$TICKET" | sed -E 's/^DP-[0-9]{3}-([TV][0-9]+[a-z]*)$/\1/')"
  for f in \
    "$SPECS_ROOT"/design-plans/"$dp_id"-*/tasks/"$task_stem".md \
    "$SPECS_ROOT"/design-plans/"$dp_id"-*/tasks/"$task_stem"/index.md \
    "$SPECS_ROOT"/design-plans/"$dp_id"-*/tasks/pr-release/"$task_stem".md \
    "$SPECS_ROOT"/design-plans/"$dp_id"-*/tasks/pr-release/"$task_stem"/index.md \
    "$SPECS_ROOT"/design-plans/archive/"$dp_id"-*/tasks/"$task_stem".md \
    "$SPECS_ROOT"/design-plans/archive/"$dp_id"-*/tasks/"$task_stem"/index.md \
    "$SPECS_ROOT"/design-plans/archive/"$dp_id"-*/tasks/pr-release/"$task_stem".md \
    "$SPECS_ROOT"/design-plans/archive/"$dp_id"-*/tasks/pr-release/"$task_stem"/index.md
  do
    [ -f "$f" ] || continue
    set_task_anchor_from_file "$f"
    break
  done
fi

# Description: 在指定 find 範圍掃 task anchor，依 canonical parser jira_key（fallback 到
#   legacy "> JIRA: KEY" header）比對 ${TICKET}，命中即設定 ANCHOR 並回傳 0；無命中回傳 1。
#   stdin 接 newline-separated 的 task anchor 候選路徑（由 caller 的 find 提供），讓 active
#   與 archive 兩種掃描共用同一套比對邏輯。
# Args:        無（候選路徑由 stdin 提供）
# Side effects: 命中時設定 global ANCHOR / ANCHOR_TYPE / TASK_FILENAME / TASKS_DIR
match_task_by_jira_key() {
  local f parsed_jira
  while IFS= read -r f; do
    parsed_jira=""
    if [ -x "$PARSE_TASK_MD" ]; then
      parsed_jira="$(bash "$PARSE_TASK_MD" "$f" --no-resolve --field jira_key 2>/dev/null || true)"
    fi
    if [ "$parsed_jira" = "$TICKET" ] || grep -Eq "^> .*JIRA: ${TICKET}([[:space:]]|\$|\|)" "$f"; then
      set_task_anchor_from_file "$f"
      return 0
    fi
  done
  return 1
}

# Path 4 — Task-level by JIRA key in header (only if Path 1-3 missed)
# Active containers are scanned first (archive pruned); archive containers
# (specs/*/archive/**) are only scanned as a fallback when no active anchor matched,
# so a same-key active anchor always wins over an archived one (AC-NEG2 / source parity).
if [ -z "$ANCHOR" ]; then
  match_task_by_jira_key < <(find "$SPECS_ROOT" \
    \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
    -o \( -type f \( \
      -path "*/tasks/T*.md" \
      -o -path "*/tasks/V*.md" \
      -o -path "*/tasks/T*/index.md" \
      -o -path "*/tasks/V*/index.md" \
      -o -path "*/tasks/pr-release/T*.md" \
      -o -path "*/tasks/pr-release/V*.md" \
      -o -path "*/tasks/pr-release/T*/index.md" \
      -o -path "*/tasks/pr-release/V*/index.md" \
    \) -print \) 2>/dev/null) || true
fi

# Path 4b — archive fallback for JIRA key (design-plans/archive/** and companies/*/archive/**)
if [ -z "$ANCHOR" ]; then
  match_task_by_jira_key < <(find "$SPECS_ROOT" \
    \( -type d \( -name .git -o -name .worktrees -o -name node_modules \) -prune \) \
    -o \( -type f \( \
      -path "*/archive/*/tasks/T*.md" \
      -o -path "*/archive/*/tasks/V*.md" \
      -o -path "*/archive/*/tasks/T*/index.md" \
      -o -path "*/archive/*/tasks/V*/index.md" \
      -o -path "*/archive/*/tasks/pr-release/T*.md" \
      -o -path "*/archive/*/tasks/pr-release/V*.md" \
      -o -path "*/archive/*/tasks/pr-release/T*/index.md" \
      -o -path "*/archive/*/tasks/pr-release/V*/index.md" \
    \) -print \) 2>/dev/null) || true
fi

if [ -z "$ANCHOR" ]; then
  echo "ERROR: no spec found for $TICKET" >&2
  echo "  Searched:" >&2
  echo "    - $SPECS_ROOT/companies/*/$TICKET/{refinement.md,plan.md,index.md}" >&2
  echo "    - $SPECS_ROOT/**/tasks/{T,V}*.md (by filename key '$TICKET')" >&2
  echo "    - $SPECS_ROOT/design-plans/DP-NNN-*/tasks/{T,V}*.md (by DP task key / header)" >&2
  echo "    - $SPECS_ROOT/**/tasks/{T,V}*.md (by '> JIRA: $TICKET' header)" >&2
  echo "    - $SPECS_ROOT/**/tasks/pr-release/*.md (active→pr-release fallback)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Epic anchor — existing in-place update (behavior unchanged)
# ---------------------------------------------------------------------------
if [ "$ANCHOR_TYPE" = "epic" ]; then
  # DP-311 T2: ledger finalize 必須在 parent 翻 IMPLEMENTED 之前（仍 LOCKED）執行
  finalize_auto_pass_ledger_before_flip "$(dirname "$ANCHOR")" "$ANCHOR"
  existing_status="$(get_existing_status "$ANCHOR")"
  if [ "$existing_status" = "$STATUS" ]; then
    sync_parent_sidebar_metadata "$ANCHOR"
    auto_archive_parent_if_terminal "$ANCHOR"
    echo "NOOP: $ANCHOR already has status: $STATUS"
    exit 0
  fi
  update_frontmatter_status "$ANCHOR" "$STATUS"
  sync_parent_sidebar_metadata "$ANCHOR"
  auto_archive_parent_if_terminal "$ANCHOR"
  exit 0
fi

# ---------------------------------------------------------------------------
# Bare DP container anchor — mark all active T*/V* tasks IMPLEMENTED first,
# then update parent status and auto-archive.
# ABANDONED tasks are carved out: not marked IMPLEMENTED, but do not block.
# ---------------------------------------------------------------------------
if [ "$ANCHOR_TYPE" = "bare_dp" ]; then
  case "$STATUS" in
    IMPLEMENTED) ;;
    *)
      echo "ERROR: bare DP container key only supports --status IMPLEMENTED (got $STATUS)" >&2
      exit 1
      ;;
  esac

  tasks_dir="${BARE_DP_CONTAINER}/tasks"
  if [ -d "$tasks_dir" ]; then
    # Iterate active T*/V* tasks (legacy T1.md and folder-native T1/index.md)
    while IFS= read -r task_entry; do
      [ -n "$task_entry" ] || continue
      # task_entry is the path: file (.md) or directory (T1/) under tasks/
      bname="$(basename "$task_entry")"
      if [ -d "$task_entry" ]; then
        # folder-native
        status_file="$task_entry/index.md"
      else
        status_file="$task_entry"
      fi
      [ -f "$status_file" ] || continue
      task_status="$(get_existing_status "$status_file")"
      case "$task_status" in
        ABANDONED)
          # AC-NEG13: ABANDONED siblings carved out — left in place, do not mark IMPLEMENTED
          echo "INFO: skip ABANDONED sibling: $status_file"
          continue
          ;;
      esac

      # Derive the task stem (T1, V1, T3b, ...) for recursive invocation
      if [ -d "$task_entry" ]; then
        stem="$bname"
      else
        stem="${bname%.md}"
      fi

      # Recursively invoke this script in per-task mode so move-first + frontmatter
      # update logic stays in one place. We disable auto-archive here because the
      # bare-DP flow archives the parent container after all tasks finish.
      # DP-311 T7 (AC9): pass the fully-qualified key (DP-NNN-{stem}) so the recursion
      # resolves container-bound via Path 3 — a bare stem would fall into Path 2's
      # global find and could mis-mark a same-stem task in another container.
      env -u MARK_SPEC_IMPLEMENTED_SELFTEST bash "$0" "${TICKET}-${stem}" \
        --workspace "$WORKSPACE_ROOT" --no-auto-archive >/dev/null || {
          echo "ERROR: failed to mark task ${TICKET}-${stem} IMPLEMENTED under ${BARE_DP_CONTAINER}" >&2
          exit 1
        }
    done < <(find "$tasks_dir" -mindepth 1 -maxdepth 1 \
      \( -type f -name 'T*.md' -o -type f -name 'V*.md' \
         -o -type d -name 'T*' -o -type d -name 'V*' \) \
      \! -name 'pr-release' 2>/dev/null | sort)
  fi

  # DP-311 T2: ledger finalize 必須在 parent 翻 IMPLEMENTED 之前（仍 LOCKED）執行
  finalize_auto_pass_ledger_before_flip "$BARE_DP_CONTAINER" "$ANCHOR"

  # Update parent anchor status
  existing_status="$(get_existing_status "$ANCHOR")"
  if [ "$existing_status" != "$STATUS" ]; then
    update_frontmatter_status "$ANCHOR" "$STATUS"
  else
    echo "NOOP: $ANCHOR already has status: $STATUS"
  fi
  sync_parent_sidebar_metadata "$ANCHOR"
  auto_archive_parent_if_terminal "$ANCHOR"
  exit 0
fi

# ---------------------------------------------------------------------------
# Task anchor — MOVE-FIRST sequence (DP-033 D6)
# ---------------------------------------------------------------------------
# At this point ANCHOR may be:
#   a) active:   TASKS_DIR/{TASK_FILENAME}
#   b) pr-release: TASKS_DIR/pr-release/{TASK_FILENAME}
# We need to ensure the move-first invariant.

ACTIVE_PATH="${TASKS_DIR}/${TASK_FILENAME}"
PR_RELEASE_DIR="${TASKS_DIR}/pr-release"
PR_RELEASE_PATH="${PR_RELEASE_DIR}/${TASK_FILENAME}"

task_status_file() {
  local path="$1"
  if [ -d "$path" ]; then
    printf '%s/index.md' "$path"
  else
    printf '%s' "$path"
  fi
}

task_path_exists() {
  [ -f "$1" ] || [ -d "$1" ]
}

task_paths_same_content() {
  local left="$1"
  local right="$2"
  if [ -f "$left" ] && [ -f "$right" ]; then
    cmp -s "$left" "$right"
    return $?
  fi
  if [ -d "$left" ] && [ -d "$right" ]; then
    diff -qr "$left" "$right" >/dev/null
    return $?
  fi
  return 1
}

# Determine current state
active_exists=0
pr_release_exists=0
task_path_exists "$ACTIVE_PATH" && active_exists=1
task_path_exists "$PR_RELEASE_PATH" && pr_release_exists=1

# Case: already in pr-release/, not in active → check status, update if needed
if [ "$pr_release_exists" -eq 1 ] && [ "$active_exists" -eq 0 ]; then
  PR_RELEASE_STATUS_FILE="$(task_status_file "$PR_RELEASE_PATH")"
  existing_status="$(get_existing_status "$PR_RELEASE_STATUS_FILE")"
  if [ "$existing_status" = "$STATUS" ]; then
    echo "NOOP: $PR_RELEASE_PATH already has status: $STATUS (already moved)"
    exit 0
  fi
  update_frontmatter_status "$PR_RELEASE_STATUS_FILE" "$STATUS"
  exit 0
fi

# Case: both exist — conflict detection
if [ "$active_exists" -eq 1 ] && [ "$pr_release_exists" -eq 1 ]; then
  if task_paths_same_content "$ACTIVE_PATH" "$PR_RELEASE_PATH"; then
    # Same content — idempotent reconciliation: remove active copy, proceed
    echo "INFO: tasks/ and pr-release/ copies are identical — removing active copy (idempotent reconciliation)" >&2
    rm -rf "$ACTIVE_PATH"
    active_exists=0
    # Now update frontmatter in pr-release/
    PR_RELEASE_STATUS_FILE="$(task_status_file "$PR_RELEASE_PATH")"
    existing_status="$(get_existing_status "$PR_RELEASE_STATUS_FILE")"
    if [ "$existing_status" = "$STATUS" ]; then
      echo "NOOP: $PR_RELEASE_PATH already has status: $STATUS"
      exit 0
    fi
    update_frontmatter_status "$PR_RELEASE_STATUS_FILE" "$STATUS"
    exit 0
  else
    # Different content — same-key invariant violation, fail loudly
    echo "ERROR: same-key invariant violation for ${TASK_FILENAME}" >&2
    echo "  Both exist with DIFFERENT content:" >&2
    echo "    active:   $ACTIVE_PATH" >&2
    echo "    pr-release: $PR_RELEASE_PATH" >&2
    echo "  Manual resolution required — do NOT clobber." >&2
    echo "  Hint: verify which copy is authoritative, then remove the other." >&2
    exit 2
  fi
fi

# Case: only active exists — execute move-first sequence
if [ "$active_exists" -eq 1 ] && [ "$pr_release_exists" -eq 0 ]; then
  # Step 1: create pr-release/ directory if absent
  mkdir -p "$PR_RELEASE_DIR"

  # Step 2: mv (atomic within same filesystem; safe because we checked pr-release/ doesn't exist)
  mv "$ACTIVE_PATH" "$PR_RELEASE_PATH"
  echo "MOVED: $ACTIVE_PATH → $PR_RELEASE_PATH" >&2

  # Step 3: update frontmatter in pr-release/ location only
  update_frontmatter_status "$(task_status_file "$PR_RELEASE_PATH")" "$STATUS"
  exit 0
fi

# Unreachable: neither active nor pr-release exists (ANCHOR was found above, so this can't happen)
echo "ERROR: unexpected state — $TASK_FILENAME not found at active or pr-release paths" >&2
exit 1
