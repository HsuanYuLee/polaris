#!/usr/bin/env bash
#
# pipeline-handoff-authority-selftest.sh
#
# DP-238-T1 enforcement:
#   pipeline-handoff-atom-matrix.md 是 refinement / T task / V task /
#   lifecycle marker / orchestration signal 的 canonical authority mapping。
#   selftest 守住三件事：
#     1. matrix 表頭必含 required columns（atom / owner / canonical_source /
#        derived_surfaces / allowed_consumers / validator_or_selftest /
#        llm_role / drift_policy）；refinement、T task、V task、lifecycle、
#        orchestration、work_item_id、jira_key、delivery_ticket_key、
#        loop_counters atoms 必須出現。
#     2. matrix 只做 ownership mapping，不再複製 refinement.json / task.md /
#        V*.md 完整欄位表（duplicate schema fail-stop）。
#     3. loop_counters atom 必須宣告 auto-pass-probe.sh 為 read-only consumer，
#        drift policy = fail_stop_on_schema_mismatch；對應 probe + ledger
#        writer parity（AC7）。
#
# DP-238-T2 enforcement（consumer boundary correction + reference dedup）：
#     4. engineering-consumer-boundary（AC2）：reference / SKILL prose 不得宣告
#        engineering 直接消費 refinement.json 的 AC / module 欄位作 scope
#        authority；breakdown 是唯一 work-order derivation owner。refinement-artifact.md
#        的下游 consumer 表不得把 engineering 列為直接讀 refinement.json
#        acceptance_criteria / modules 的 consumer；atom matrix 必須正向宣告
#        engineering 只依 task.md。
#     5. v-envelope-boundary（AC3）：V*.md schema 必須明文宣告自己是 verify-AC
#        execution envelope / lifecycle surface，並指出
#        refinement.json.acceptance_criteria[].verification 才是 verification
#        method/detail authority；不得把 V*.md 描述成第二份 AC verification
#        method 來源。
#     6. duplicate-schema-scan（AC4）：refinement / breakdown / engineering /
#        verify-AC 四個 SKILL.md 主文不得內嵌完整 artifact schema 表，必須
#        pointer 到 canonical schema reference 與 atom matrix。
#
# DP-238-T3 enforcement（duplicate / drift deterministic selftest 守則）：
#     7. probe-ledger-schema-parity（AC7）：auto-pass-probe.sh 是 loop_counters
#        ledger 的 read-only consumer；DP-246 後 ledger writer 把 int counter 改成
#        `{count, evidence_ids}` dict。本 case 用 legacy int 與 DP-246 dict 兩個
#        runtime ledger fixture 跑 probe，斷言兩端對 count 的解讀一致（schema
#        parity）：count >= 3 → loop_cap_reached、count < 3 → 不 cap。若 probe 對
#        dict shape drift，count 會被讀成 0、cap 不觸發 → case fail（exit 1）。
#     8. raw-prose-not-authority（AC-NEG2）：final answer / JIRA comment / task
#        display text 等 raw prose surface 不得補足 missing lifecycle marker 或
#        missing canonical field。本 case 在 atom matrix 斷言 lifecycle_marker /
#        orchestration_signal 的 drift policy 是 fail_stop（marker 缺失 → blocked，
#        不是 prose PASS），並用 prose-only 的 completion fixture 跑 probe，斷言
#        probe 對「marker 不存在但 prose 宣稱 PASS」回 blocked_by_gate_failure。
#
# DP-238-T4 enforcement（identity consumer 邊界鞏固）：
#     9. identity-atom-split（AC6）：parse-task-md.sh 必須把 `work_item_id` /
#        `jira_key` / `delivery_ticket_key` 三個 identity atom 拆開。本 case 跑
#        parser + branch resolver + PR title gate 三層：
#          - Bug source（Task ID=PROJ-4190-T1, JIRA key=PROJ-4190）的
#            `delivery_ticket_key` = `jira_key` = `PROJ-4190`（不是 internal
#            task marker PROJ-4190-T1），`work_item_id` 保留 PROJ-4190-T1；
#            branch / PR title 使用 PROJ-4190。
#          - DP-backed source（Task ID=DP-238-T4, JIRA=N/A）的
#            `delivery_ticket_key` = `work_item_id` = DP-238-T4（向後相容；DP
#            source identity 不被本變更打到，[DP-238-T4] PR title 仍合法）。
#    10. bug-source-product-pr-identity（AC-NEG5）：Bug source internal id 不可
#        外溢到 product PR identity。本 case 對 task/PROJ-4190-T1-* branch 與
#        [PROJ-4190-T1] PR title 斷言 deterministic gate fail-stop（resolve-task-branch
#        + gate-pr-title 都不得用 legacy task_jira_key alias 把 internal marker
#        當成 product PR identity 放行）；同時斷言合法的 PROJ-4190 identity PASS。
#
# DP-238-T4 verify-AC V1 補洞（refinement.json 宣告的 AC verification method 對齊）：
#    11. no-gate-removal（AC-NEG1）：本 DP 不移除既有 gate。本 case 斷言 language /
#        Starlight / producer-env writer / boundary / task readiness / proof marker /
#        AC verification gate 的 script / hook / registry 仍存在「且仍被 wire」。
#        非 tautological：拔掉任一 gate 的 script 或拔掉其 wiring 引用都會 RED。
#    12. legacy-reader-compatibility（AC-NEG4）：slimming 不破壞 legacy reader。本 case
#        斷言 identity atom split 後仍保留的 legacy compatibility pointer——
#        parse-task-md.sh 的 `task_jira_key` migration alias（DP source 回填
#        work_item_id，product source 等於 jira_key）與 atom matrix
#        `delivery_ticket_key` row 的 parser-derived alias 宣告 + compatibility
#        bridge sunset 規則——仍在。移除 alias 回填或 matrix 宣告會 RED。
#    13. bug-source-product-pr-identity-negative（AC-NEG5）：以獨立可執行 case 重申
#        AC-NEG5 negative assertion——task/{BUG_KEY}-T1-* branch 與 [{BUG_KEY}-T1]
#        PR title 作為 Bug source product PR identity 必須被 deterministic gate 擋下，
#        且 consumer 不得用 legacy task_jira_key alias 補判斷。委派
#        bug-source-product-pr-identity 的 negative 分支邏輯，使本 case 可單獨以
#        --case bug-source-product-pr-identity-negative 跑且 PASS。
#
# 預設（無 --case）：依序跑全部 case（含 verify-AC-deterministic-consumption
# sibling selftest），任一 fail 即 fail-stop（AC5 duplicate / drift scan 的
# aggregate 入口；Test / Verify Command 直接跑無 --case 形式）。
#
# Usage:
#   scripts/selftests/pipeline-handoff-authority-selftest.sh
#       (no --case: run all cases as an aggregate)
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case atom-matrix-required-columns
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case atom-matrix-no-full-schema-copy
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case probe-ledger-atom-declared
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case engineering-consumer-boundary
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case v-envelope-boundary
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case duplicate-schema-scan
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case probe-ledger-schema-parity
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case raw-prose-not-authority
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case identity-atom-split
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case bug-source-product-pr-identity
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case no-gate-removal
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case legacy-reader-compatibility
#   scripts/selftests/pipeline-handoff-authority-selftest.sh \
#       --case bug-source-product-pr-identity-negative

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MATRIX="$ROOT/.claude/skills/references/pipeline-handoff-atom-matrix.md"
HANDOFF="$ROOT/.claude/skills/references/pipeline-handoff.md"
INDEX="$ROOT/.claude/skills/references/INDEX.md"
REFINEMENT_ARTIFACT="$ROOT/.claude/skills/references/refinement-artifact.md"
V_SCHEMA="$ROOT/.claude/skills/references/task-md-schema-verification.md"
SKILL_REFINEMENT="$ROOT/.claude/skills/refinement/SKILL.md"
SKILL_BREAKDOWN="$ROOT/.claude/skills/breakdown/SKILL.md"
SKILL_ENGINEERING="$ROOT/.claude/skills/engineering/SKILL.md"
SKILL_VERIFY_AC="$ROOT/.claude/skills/verify-AC/SKILL.md"
PARSE_TASK_MD="$ROOT/scripts/parse-task-md.sh"
RESOLVE_TASK_BRANCH="$ROOT/scripts/resolve-task-branch.sh"
GATE_PR_TITLE="$ROOT/scripts/gates/gate-pr-title.sh"
BOOTSTRAP="$ROOT/.claude/instructions/core/bootstrap.md"
EVIDENCE_PRODUCERS="$ROOT/scripts/lib/evidence-producers.json"
NO_DIRECT_EVIDENCE_HOOK="$ROOT/.claude/hooks/no-direct-evidence-write.sh"
# DP-360 T7: completion-gate marker writer retired; the proof-marker surface is
# now the task.md deliverable.verification block written by finalize-engineering-delivery.sh.
DELIVERABLE_VERIFICATION_WRITER="$ROOT/scripts/finalize-engineering-delivery.sh"
VERIFY_AC_SIBLING="$ROOT/scripts/selftests/verify-AC-deterministic-consumption-selftest.sh"

usage() {
  cat <<'EOF'
usage: pipeline-handoff-authority-selftest.sh [--case <name>]

With no --case: run every case in sequence (aggregate; AC5 entry point).

Options:
  --case <name>   selftest case to run; one of:
                    atom-matrix-required-columns
                    atom-matrix-no-full-schema-copy
                    probe-ledger-atom-declared
                    engineering-consumer-boundary
                    v-envelope-boundary
                    duplicate-schema-scan
                    probe-ledger-schema-parity
                    raw-prose-not-authority
                    identity-atom-split
                    bug-source-product-pr-identity
                    no-gate-removal
                    legacy-reader-compatibility
                    bug-source-product-pr-identity-negative
  --help, -h      Show this help and exit.
EOF
}

# Ordered list of every case (consumed by the no-argument aggregate run).
ALL_CASES=(
  atom-matrix-required-columns
  atom-matrix-no-full-schema-copy
  probe-ledger-atom-declared
  engineering-consumer-boundary
  v-envelope-boundary
  duplicate-schema-scan
  probe-ledger-schema-parity
  raw-prose-not-authority
  identity-atom-split
  bug-source-product-pr-identity
  no-gate-removal
  legacy-reader-compatibility
  bug-source-product-pr-identity-negative
)

CASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --case)
      CASE="${2:-}"
      shift 2
      ;;
    --case=*)
      CASE="${1#--case=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: required file missing: $path" >&2
    exit 1
  fi
}

# No --case → aggregate run (AC5): every case + the verify-AC deterministic
# consumption sibling selftest. Any failure fails the whole run (fail-stop).
if [[ -z "$CASE" ]]; then
  self="${BASH_SOURCE[0]}"
  for c in "${ALL_CASES[@]}"; do
    if ! bash "$self" --case "$c"; then
      echo "FAIL: aggregate run stopped at case '$c'" >&2
      exit 1
    fi
  done
  sibling="$ROOT/scripts/selftests/verify-AC-deterministic-consumption-selftest.sh"
  if [[ -f "$sibling" ]]; then
    if ! bash "$sibling"; then
      echo "FAIL: aggregate run stopped at verify-AC-deterministic-consumption sibling selftest" >&2
      exit 1
    fi
  fi
  echo "PASS: pipeline-handoff-authority aggregate (all cases + verify-AC sibling)"
  exit 0
fi

case "$CASE" in
  atom-matrix-required-columns)
    require_file "$MATRIX"
    require_file "$HANDOFF"
    require_file "$INDEX"

    # Header row must declare all required ownership columns.
    REQUIRED_COLUMNS=(
      "atom"
      "owner"
      "canonical_source"
      "derived_surfaces"
      "allowed_consumers"
      "validator_or_selftest"
      "llm_role"
      "drift_policy"
    )
    for col in "${REQUIRED_COLUMNS[@]}"; do
      if ! grep -q "| $col " "$MATRIX"; then
        echo "FAIL: atom matrix header missing required column: $col" >&2
        exit 1
      fi
    done

    # Required atoms must each appear as a row identifier in the matrix.
    REQUIRED_ATOMS=(
      "refinement_artifact"
      "t_task_work_order"
      "v_task_envelope"
      "lifecycle_marker"
      "orchestration_signal"
      "work_item_id"
      "jira_key"
      "delivery_ticket_key"
      "loop_counters"
    )
    for atom in "${REQUIRED_ATOMS[@]}"; do
      if ! grep -q "^| \`$atom\`" "$MATRIX"; then
        echo "FAIL: atom matrix missing required atom row: $atom" >&2
        exit 1
      fi
    done

    # pipeline-handoff.md must point to the new matrix; INDEX must register it.
    if ! grep -q "pipeline-handoff-atom-matrix.md" "$HANDOFF"; then
      echo "FAIL: pipeline-handoff.md missing pointer to atom matrix" >&2
      exit 1
    fi
    if ! grep -q "pipeline-handoff-atom-matrix.md" "$INDEX"; then
      echo "FAIL: references/INDEX.md missing atom matrix entry" >&2
      exit 1
    fi

    echo "PASS: pipeline-handoff atom matrix required columns"
    ;;

  atom-matrix-no-full-schema-copy)
    require_file "$MATRIX"

    # AC-NEG3: matrix must not copy full refinement.json / task.md / V*.md
    # schema tables. We block headers and section markers that indicate full
    # schema duplication (not just inline field references — pointing to a
    # specific field name is legitimate ownership mapping).
    DUPLICATE_HEADERS=(
      "^## refinement\.json Schema"
      "^## task\.md Schema"
      "^## V\*\.md Schema"
      "^## Gate Closure Matrix"
      "^\| Header \`"
      "^\| Metadata line \|"
      "^\| Frontmatter \`"
    )
    fail=0
    for marker in "${DUPLICATE_HEADERS[@]}"; do
      if grep -E -q "$marker" "$MATRIX"; then
        echo "FAIL: atom matrix duplicates canonical schema section: $marker" >&2
        fail=1
      fi
    done
    if (( fail == 1 )); then
      exit 1
    fi

    # Belt-and-suspenders: ownership mapping rows are |-table rows describing
    # an atom. A full schema duplication tends to have many rows that look
    # like `| field_name | type | required | rule |` — i.e. 4+ pipe segments
    # of field-style content. Count atom rows vs schema-style rows; matrix
    # must remain ownership-heavy.
    schema_rows=$(awk -F'|' '/^\| `[a-z_]+` \| (string|array|object|bool|int)/{ c++ } END { print c+0 }' "$MATRIX")
    if (( schema_rows > 0 )); then
      echo "FAIL: atom matrix contains $schema_rows schema-style rows (type column suggests duplicated field schema)" >&2
      exit 1
    fi

    # Hard cap: matrix file body must stay focused on ownership mapping,
    # not become a third schema authority. 240 lines is the planning
    # ceiling derived from DP-238 D7 (atom matrix is mapping + drift
    # policy, not full schema).
    lines=$(wc -l < "$MATRIX")
    if (( lines > 240 )); then
      echo "FAIL: atom matrix exceeds line cap ($lines > 240); possible schema duplication" >&2
      exit 1
    fi

    echo "PASS: pipeline-handoff atom matrix has no full schema copy"
    ;;

  probe-ledger-atom-declared)
    require_file "$MATRIX"

    # AC7: loop_counters row must list auto-pass-probe.sh as a consumer
    # and declare fail_stop_on_schema_mismatch drift policy.
    if ! awk '
      /^\| `loop_counters`/ {
        row = $0
        if (index(row, "auto-pass-probe.sh") > 0 \
            && index(row, "fail_stop_on_schema_mismatch") > 0) {
          found = 1
        }
      }
      END { exit (found ? 0 : 1) }
    ' "$MATRIX"; then
      echo "FAIL: loop_counters row must declare auto-pass-probe.sh consumer + fail_stop_on_schema_mismatch drift policy" >&2
      exit 1
    fi

    # Ledger writer must be the canonical authority for loop_counters.
    if ! grep -E -q '^\| `loop_counters`.*auto-pass-increment-counter\.sh' "$MATRIX"; then
      echo "FAIL: loop_counters row must declare auto-pass-increment-counter.sh as canonical writer" >&2
      exit 1
    fi

    # Runtime parity sanity: probe schema and ledger writer must keep the
    # dict-shape contract (DP-246). If either side drops the dict path the
    # atom matrix promise becomes a lie.
    PROBE="$ROOT/scripts/auto-pass-probe.sh"
    WRITER="$ROOT/scripts/auto-pass-increment-counter.sh"
    require_file "$PROBE"
    require_file "$WRITER"
    if ! grep -q "isinstance(value, dict)" "$PROBE"; then
      echo "FAIL: auto-pass-probe.sh lost dict-shape parity for loop_counters" >&2
      exit 1
    fi

    echo "PASS: pipeline-handoff loop_counters atom + probe parity"
    ;;

  engineering-consumer-boundary)
    # AC2: engineering 只消費 authoritative task.md，不直接讀 refinement.json 的
    # acceptance_criteria / modules 作 scope authority；breakdown 是唯一 work-order
    # derivation owner。
    require_file "$MATRIX"
    require_file "$REFINEMENT_ARTIFACT"
    require_file "$SKILL_ENGINEERING"

    # (a) atom matrix 必須正向宣告 engineering 不讀 refinement.json 補 scope。
    if ! grep -q '不得讀 `refinement.json` 補 scope authority' "$MATRIX"; then
      echo "FAIL: atom matrix t_task_work_order row must declare engineering 不得讀 refinement.json 補 scope authority" >&2
      exit 1
    fi

    # (b) refinement-artifact.md 的下游 consumer 表不得把 engineering 列為
    # 直接讀 refinement.json acceptance_criteria / modules 的 consumer。
    # 合法寫法：engineering 經由 breakdown 產出的 task.md 取得這些資訊。
    if grep -E -q '^\| \*\*engineering\*\* \| `acceptance_criteria' "$REFINEMENT_ARTIFACT"; then
      echo "FAIL: refinement-artifact.md still lists engineering as a direct refinement.json acceptance_criteria/modules consumer (AC2 violation)" >&2
      exit 1
    fi

    # (c) refinement-artifact.md 開場不得宣告 engineering 直接消費 refinement artifact。
    if grep -E -q '供下游 skill（breakdown, engineering）直接消費' "$REFINEMENT_ARTIFACT"; then
      echo "FAIL: refinement-artifact.md opening still declares engineering 直接消費 refinement artifact (AC2 violation)" >&2
      exit 1
    fi

    # (d) engineering SKILL.md 必須保留 task.md-only consumer boundary 宣告。
    if ! grep -q '不直接讀 refinement.json' "$SKILL_ENGINEERING"; then
      echo "FAIL: engineering SKILL.md must declare it does not read refinement.json for scope (consumes authoritative task.md only)" >&2
      exit 1
    fi

    echo "PASS: engineering consumer boundary (task.md only, breakdown owns derivation)"
    ;;

  v-envelope-boundary)
    # AC3: V*.md schema 必須明文宣告自己是 verify-AC execution envelope /
    # lifecycle surface，且 refinement.json.acceptance_criteria[].verification 才是
    # verification method/detail authority。
    require_file "$V_SCHEMA"
    require_file "$MATRIX"

    # (a) V schema 必須含 envelope/lifecycle 定位宣告。
    if ! grep -q 'execution envelope' "$V_SCHEMA"; then
      echo "FAIL: task-md-schema-verification.md must declare V*.md is a verify-AC execution envelope / lifecycle surface" >&2
      exit 1
    fi

    # (b) V schema 必須指向 refinement.json verification 作 method/detail authority。
    if ! grep -q 'refinement.json` `acceptance_criteria\[\].verification' "$V_SCHEMA" \
       && ! grep -q 'refinement.json.acceptance_criteria\[\].verification' "$V_SCHEMA"; then
      echo "FAIL: task-md-schema-verification.md must point verification method/detail authority to refinement.json.acceptance_criteria[].verification" >&2
      exit 1
    fi

    # (c) atom matrix v_task_envelope row 必須維持同一語意（envelope, not 2nd AC source）。
    if ! grep -E -q '^\| `v_task_envelope`.*execution envelope' "$MATRIX"; then
      echo "FAIL: atom matrix v_task_envelope row must describe V*.md as execution envelope (not second AC source)" >&2
      exit 1
    fi

    echo "PASS: V*.md envelope boundary (refinement.json owns verification method/detail)"
    ;;

  duplicate-schema-scan)
    # AC4: 四個 SKILL.md 主文不得內嵌完整 artifact schema 表，必須 pointer 到
    # canonical schema reference 與 atom matrix。
    for skill in "$SKILL_REFINEMENT" "$SKILL_BREAKDOWN" "$SKILL_ENGINEERING" "$SKILL_VERIFY_AC"; do
      require_file "$skill"
    done

    fail=0

    # (a) SKILL.md 主文不得出現 full schema section header（duplicate authority signal）。
    DUPLICATE_HEADERS=(
      '^### refinement\.json Schema'
      '^## refinement\.json Schema'
      '^## task\.md Schema'
      '^### task\.md Schema'
      '^## V\*\.md Schema'
      '^## Artifact Schemas'
    )
    for skill in "$SKILL_REFINEMENT" "$SKILL_BREAKDOWN" "$SKILL_ENGINEERING" "$SKILL_VERIFY_AC"; do
      for marker in "${DUPLICATE_HEADERS[@]}"; do
        if grep -E -q "$marker" "$skill"; then
          echo "FAIL: SKILL.md inlines full schema section ($marker): $skill" >&2
          fail=1
        fi
      done
      # (b) SKILL.md 主文不得出現 field|type|required 的完整欄位表 row。
      if grep -E -q '^\| `[a-z_]+` \| (string|array|object|bool|int)' "$skill"; then
        echo "FAIL: SKILL.md contains field-schema-style table row (duplicated artifact schema): $skill" >&2
        fail=1
      fi
    done
    if (( fail == 1 )); then
      exit 1
    fi

    # (c) 每個 SKILL.md 必須 pointer 到 canonical handoff schema reference
    # （pipeline-handoff.md § Artifact Schemas）並可達 atom matrix。
    for skill in "$SKILL_REFINEMENT" "$SKILL_BREAKDOWN" "$SKILL_ENGINEERING" "$SKILL_VERIFY_AC"; do
      if ! grep -q 'pipeline-handoff.md' "$skill"; then
        echo "FAIL: SKILL.md missing pointer to canonical pipeline-handoff.md schema reference: $skill" >&2
        fail=1
      fi
      if ! grep -q 'pipeline-handoff-atom-matrix.md' "$skill"; then
        echo "FAIL: SKILL.md missing pointer to pipeline-handoff-atom-matrix.md (atom ownership authority): $skill" >&2
        fail=1
      fi
    done
    if (( fail == 1 )); then
      exit 1
    fi

    echo "PASS: SKILL.md main bodies pointer-only (no duplicate artifact schema)"
    ;;

  probe-ledger-schema-parity)
    # AC7: auto-pass-probe.sh is a read-only consumer of the ledger
    # loop_counters atom. DP-246 changed the ledger writer to emit a
    # `{count, evidence_ids}` dict instead of a bare int. This case runs the
    # probe at runtime against three ledger fixtures and asserts the probe
    # reads the DP-246 dict shape identically to the legacy int shape:
    #   - legacy int counter == 3        → loop_cap_reached
    #   - DP-246 dict {count: 3}          → loop_cap_reached (parity)
    #   - DP-246 dict {count: 1}          → NOT loop_cap_reached
    # If the probe lost dict parity, {count: 3} would read as 0 and the cap
    # would not fire — this case catches that DP-246-class cascade gap.
    PROBE="$ROOT/scripts/auto-pass-probe.sh"
    require_file "$PROBE"

    tmpdir="$(mktemp -d -t probe-ledger-schema-parity.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT

    # probe terminal_status for stage=breakdown depends only on ledger
    # loop_counters (ledger_terminal() runs before any source resolution), so a
    # synthetic source-id / work-item-id is sufficient and keeps the case
    # hermetic (no specs container, no resolver dependency).
    probe_terminal() {
      local ledger="$1"
      bash "$PROBE" --stage breakdown \
        --source-id DP-FIXTURE --work-item-id DP-FIXTURE-T1 \
        --ledger "$ledger" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("terminal_status"))'
    }

    legacy_int_ledger="$tmpdir/legacy-int.json"
    cat >"$legacy_int_ledger" <<'JSON'
{
  "schema_version": 1,
  "source": {"id": "DP-FIXTURE"},
  "loop_counters": {"engineering_to_breakdown": 3}
}
JSON

    dict_cap_ledger="$tmpdir/dict-cap.json"
    cat >"$dict_cap_ledger" <<'JSON'
{
  "schema_version": 1,
  "source": {"id": "DP-FIXTURE"},
  "loop_counters": {"engineering_to_breakdown": {"count": 3, "evidence_ids": ["e1", "e2", "e3"]}}
}
JSON

    dict_under_ledger="$tmpdir/dict-under.json"
    cat >"$dict_under_ledger" <<'JSON'
{
  "schema_version": 1,
  "source": {"id": "DP-FIXTURE"},
  "loop_counters": {"engineering_to_breakdown": {"count": 1, "evidence_ids": ["e1"]}}
}
JSON

    legacy_terminal="$(probe_terminal "$legacy_int_ledger")"
    dict_cap_terminal="$(probe_terminal "$dict_cap_ledger")"
    dict_under_terminal="$(probe_terminal "$dict_under_ledger")"

    if [[ "$legacy_terminal" != "loop_cap_reached" ]]; then
      echo "FAIL: probe legacy int counter=3 should yield loop_cap_reached, got: $legacy_terminal" >&2
      exit 1
    fi
    if [[ "$dict_cap_terminal" != "loop_cap_reached" ]]; then
      echo "FAIL: probe lost DP-246 dict parity — {count:3} should yield loop_cap_reached, got: $dict_cap_terminal" >&2
      exit 1
    fi
    if [[ "$dict_under_terminal" == "loop_cap_reached" ]]; then
      echo "FAIL: probe {count:1} must not trip the loop cap, got: $dict_under_terminal" >&2
      exit 1
    fi

    # Atom matrix must keep declaring the parity drift policy so the contract
    # and the runtime check stay coupled.
    if ! grep -E -q '^\| `loop_counters`.*fail_stop_on_schema_mismatch' "$MATRIX"; then
      echo "FAIL: atom matrix loop_counters row must declare fail_stop_on_schema_mismatch drift policy" >&2
      exit 1
    fi

    trap - EXIT
    rm -rf "$tmpdir"
    echo "PASS: probe ↔ ledger loop_counters schema parity (legacy int + DP-246 dict)"
    ;;

  raw-prose-not-authority)
    # AC-NEG2: final answer / JIRA comment / task display text (raw prose) must
    # not be allowed to substitute a missing lifecycle marker or a missing
    # canonical field. Two layers:
    #   (a) atom matrix lifecycle_marker / orchestration_signal rows must declare
    #       a fail_stop drift policy (marker missing → blocked, not prose PASS).
    #   (b) runtime: run the probe against a worktree whose completion-gate
    #       marker is absent — even though a prose "PASS" claim exists in a
    #       sibling final-answer file, the probe must return
    #       blocked_by_gate_failure (it reads durable markers, never prose).
    require_file "$MATRIX"
    PROBE="$ROOT/scripts/auto-pass-probe.sh"
    require_file "$PROBE"

    # (a) drift policy declarations.
    if ! grep -E -q '^\| `lifecycle_marker`.*fail_stop_on_missing_marker' "$MATRIX"; then
      echo "FAIL: atom matrix lifecycle_marker row must declare fail_stop_on_missing_marker (prose cannot substitute marker)" >&2
      exit 1
    fi
    if ! grep -E -q '^\| `orchestration_signal`.*fail_stop_on_runner_json_missing_field' "$MATRIX"; then
      echo "FAIL: atom matrix orchestration_signal row must declare fail_stop on missing runner JSON field (no prose补判斷)" >&2
      exit 1
    fi

    tmpdir="$(mktemp -d -t raw-prose-not-authority.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT

    # Synthetic repo with NO completion-gate marker, but with a prose "final
    # answer" that falsely claims PASS. The probe must ignore the prose.
    repo="$tmpdir/repo"
    mkdir -p "$repo/.polaris/evidence"
    cat >"$tmpdir/final-answer.txt" <<'TXT'
DP-FIXTURE-T1 完成：engineering 已交付，completion gate PASS。
TXT

    probe_json="$(bash "$PROBE" --stage engineering \
      --source-id DP-FIXTURE --work-item-id DP-FIXTURE-T1 \
      --head-sha deadbeef --repo "$repo")"
    terminal="$(printf '%s' "$probe_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("terminal_status"))')"
    status="$(printf '%s' "$probe_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status"))')"

    if [[ "$terminal" != "blocked_by_gate_failure" ]]; then
      echo "FAIL: missing completion-gate marker must yield blocked_by_gate_failure (prose PASS must not substitute), got terminal: $terminal" >&2
      exit 1
    fi
    if [[ "$status" == "PASS" ]]; then
      echo "FAIL: probe reported PASS without a durable completion-gate marker (raw prose leaked into authority)" >&2
      exit 1
    fi

    trap - EXIT
    rm -rf "$tmpdir"
    echo "PASS: raw prose is not authority (missing marker → blocked, not prose PASS)"
    ;;

  identity-atom-split)
    # AC6: parse-task-md.sh must split work_item_id / jira_key /
    # delivery_ticket_key. The product-PR-identity consumers (branch resolver,
    # PR title gate, PR-create evidence) must key off delivery_ticket_key, which
    # the parser derives as:
    #   - Bug / JIRA source  → jira_key   (PROJ-4190, not internal PROJ-4190-T1)
    #   - DP-backed source   → work_item_id (DP-238-T4; backward compatible)
    require_file "$PARSE_TASK_MD"
    require_file "$RESOLVE_TASK_BRANCH"
    require_file "$MATRIX"

    tmpdir="$(mktemp -d -t identity-atom-split.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT

    # --- Bug source fixture: internal task marker != delivery ticket ---------
    bug_md="$tmpdir/bug-T1.md"
    cat >"$bug_md" <<'MD'
# T1: bug source identity split (2 pt)

> Source: EXCO-4190 | Task: EXCO-4190-T1 | JIRA: EXCO-4190 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-4190 |
| Task ID | EXCO-4190-T1 |
| JIRA key | EXCO-4190 |
| Base branch | develop |
| Task branch | task/EXCO-4190-fix-leak |

## Test Environment

- **Level**: static
MD

    bug_work_item="$(bash "$PARSE_TASK_MD" "$bug_md" --no-resolve --field work_item_id 2>/dev/null)"
    bug_jira="$(bash "$PARSE_TASK_MD" "$bug_md" --no-resolve --field jira_key 2>/dev/null)"
    bug_delivery="$(bash "$PARSE_TASK_MD" "$bug_md" --no-resolve --field delivery_ticket_key 2>/dev/null)"

    if [[ "$bug_work_item" != "EXCO-4190-T1" ]]; then
      echo "FAIL: Bug source work_item_id should keep internal marker EXCO-4190-T1, got: $bug_work_item" >&2
      exit 1
    fi
    if [[ "$bug_jira" != "EXCO-4190" ]]; then
      echo "FAIL: Bug source jira_key should be EXCO-4190, got: $bug_jira" >&2
      exit 1
    fi
    if [[ "$bug_delivery" != "EXCO-4190" ]]; then
      echo "FAIL: Bug source delivery_ticket_key must equal jira_key EXCO-4190 (internal task marker must not leak), got: $bug_delivery" >&2
      exit 1
    fi

    # Branch resolver must produce a delivery-ticket-prefixed branch, NOT the
    # internal task marker prefix. The explicit Task branch already uses
    # EXCO-4190; resolving must accept it (delivery_ticket_key alignment).
    bug_branch="$(bash "$RESOLVE_TASK_BRANCH" "$bug_md" 2>/dev/null || true)"
    if [[ "$bug_branch" != "task/EXCO-4190-fix-leak" ]]; then
      echo "FAIL: Bug source branch must resolve to delivery-ticket-prefixed task/EXCO-4190-*, got: $bug_branch" >&2
      exit 1
    fi

    # --- DP source fixture: delivery_ticket_key == work_item_id (compat) ------
    # Summary is authored in the workspace language (zh-TW) so the PR-title
    # language gate, which gate-pr-title runs on the rendered title, passes.
    dp_md="$tmpdir/dp-T4.md"
    cat >"$dp_md" <<'MD'
# T4: 補 identity consumer 邊界 (3 pt)

> Source: DP-238 | Task: DP-238-T4 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-238 |
| Task ID | DP-238-T4 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-238-T4-identity |

## Test Environment

- **Level**: static
MD

    dp_work_item="$(bash "$PARSE_TASK_MD" "$dp_md" --no-resolve --field work_item_id 2>/dev/null)"
    dp_jira="$(bash "$PARSE_TASK_MD" "$dp_md" --no-resolve --field jira_key 2>/dev/null)"
    dp_delivery="$(bash "$PARSE_TASK_MD" "$dp_md" --no-resolve --field delivery_ticket_key 2>/dev/null)"

    if [[ "$dp_work_item" != "DP-238-T4" ]]; then
      echo "FAIL: DP source work_item_id should be DP-238-T4, got: $dp_work_item" >&2
      exit 1
    fi
    if [[ -n "$dp_jira" ]]; then
      echo "FAIL: DP source jira_key should be empty (N/A), got: $dp_jira" >&2
      exit 1
    fi
    if [[ "$dp_delivery" != "DP-238-T4" ]]; then
      echo "FAIL: DP source delivery_ticket_key must equal work_item_id DP-238-T4 (backward compatible), got: $dp_delivery" >&2
      exit 1
    fi

    # DP branch / PR-title identity must remain unaffected: [DP-238-T4] still legal.
    dp_branch="$(bash "$RESOLVE_TASK_BRANCH" "$dp_md" 2>/dev/null || true)"
    if [[ "$dp_branch" != "task/DP-238-T4-identity" ]]; then
      echo "FAIL: DP source branch resolution broke (regression), got: $dp_branch" >&2
      exit 1
    fi

    # gate-pr-title runtime positive: DP identity title [DP-238-T4] must PASS.
    # DP ids skip company resolution (not JIRA-regex), so this stays hermetic.
    require_file "$GATE_PR_TITLE"
    if ! bash "$GATE_PR_TITLE" --task-md "$dp_md" --title "[DP-238-T4] 補 identity consumer 邊界" >/dev/null 2>&1; then
      echo "FAIL: gate-pr-title must accept the legal DP identity title [DP-238-T4] (DP source regression)" >&2
      exit 1
    fi

    # Atom matrix must keep declaring the parser as delivery_ticket_key owner.
    if ! grep -E -q '^\| `delivery_ticket_key`.*parse-task-md\.sh' "$MATRIX"; then
      echo "FAIL: atom matrix delivery_ticket_key row must name parse-task-md.sh as the deriving owner" >&2
      exit 1
    fi

    trap - EXIT
    rm -rf "$tmpdir"
    echo "PASS: identity atom split (work_item_id / jira_key / delivery_ticket_key)"
    ;;

  bug-source-product-pr-identity)
    # AC-NEG5: Bug source internal id must not leak into product PR identity.
    # task/EXCO-4190-T1-* branch and [EXCO-4190-T1] PR title must fail-stop;
    # the consumers must not fall back to the legacy task_jira_key alias (which
    # aliases to the internal work_item_id) to admit them. The legal EXCO-4190
    # identity must still PASS.
    require_file "$RESOLVE_TASK_BRANCH"
    require_file "$GATE_PR_TITLE"
    require_file "$PARSE_TASK_MD"

    tmpdir="$(mktemp -d -t bug-source-product-pr-identity.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT

    # (a) NEGATIVE branch: explicit Task branch reuses the internal task marker
    # as the product branch prefix → resolver must reject (branch must be
    # delivery_ticket_key-prefixed, not work_item_id-prefixed).
    leak_branch_md="$tmpdir/leak-branch.md"
    cat >"$leak_branch_md" <<'MD'
# T1: bug source id leak via branch (2 pt)

> Source: EXCO-4190 | Task: EXCO-4190-T1 | JIRA: EXCO-4190 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-4190 |
| Task ID | EXCO-4190-T1 |
| JIRA key | EXCO-4190 |
| Base branch | develop |
| Task branch | task/EXCO-4190-T1-fix-leak |

## Test Environment

- **Level**: static
MD

    if bash "$RESOLVE_TASK_BRANCH" "$leak_branch_md" >/dev/null 2>&1; then
      leaked="$(bash "$RESOLVE_TASK_BRANCH" "$leak_branch_md" 2>/dev/null || true)"
      echo "FAIL: Bug source product branch task/EXCO-4190-T1-* must fail-stop (internal marker leaked), but resolver returned: $leaked" >&2
      exit 1
    fi

    # (b) POSITIVE branch: delivery-ticket-prefixed branch must still resolve.
    ok_branch_md="$tmpdir/ok-branch.md"
    cat >"$ok_branch_md" <<'MD'
# T1: bug source legal delivery branch (2 pt)

> Source: EXCO-4190 | Task: EXCO-4190-T1 | JIRA: EXCO-4190 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-4190 |
| Task ID | EXCO-4190-T1 |
| JIRA key | EXCO-4190 |
| Base branch | develop |
| Task branch | task/EXCO-4190-fix-leak |

## Test Environment

- **Level**: static
MD

    ok_branch="$(bash "$RESOLVE_TASK_BRANCH" "$ok_branch_md" 2>/dev/null || true)"
    if [[ "$ok_branch" != "task/EXCO-4190-fix-leak" ]]; then
      echo "FAIL: legal delivery-ticket branch task/EXCO-4190-fix-leak must resolve, got: $ok_branch" >&2
      exit 1
    fi

    # (c) Source-level: branch resolver and PR title gate must consume
    # delivery_ticket_key and must NOT fall back to the legacy task_jira_key
    # alias for product PR identity (that alias holds the internal work_item_id
    # for Bug sources and would re-admit the leak).
    if ! grep -q 'identity.delivery_ticket_key' "$RESOLVE_TASK_BRANCH"; then
      echo "FAIL: resolve-task-branch.sh must consume identity.delivery_ticket_key for the product branch prefix" >&2
      exit 1
    fi
    # The actual code invocation (not the doc comment) must not read the legacy
    # task_jira_key alias for branch identity. Match the json_field call form.
    if grep -E -q 'json_field "operational_context\.task_jira_key"' "$RESOLVE_TASK_BRANCH"; then
      echo "FAIL: resolve-task-branch.sh must not read legacy operational_context.task_jira_key for product branch identity (AC-NEG5)" >&2
      exit 1
    fi
    if ! grep -q 'field delivery_ticket_key' "$GATE_PR_TITLE"; then
      echo "FAIL: gate-pr-title.sh must derive the PR title ticket from delivery_ticket_key" >&2
      exit 1
    fi
    if grep -q -- '--field task_jira_key' "$GATE_PR_TITLE"; then
      echo "FAIL: gate-pr-title.sh must not derive product PR title from legacy task_jira_key alias (AC-NEG5)" >&2
      exit 1
    fi

    # (d) Atom matrix must keep the AC-NEG5 fail-stop drift policy declared.
    if ! grep -E -q '^\| `delivery_ticket_key`.*fail_stop_on_internal_work_item_id_in_product_pr_identity' "$MATRIX"; then
      echo "FAIL: atom matrix delivery_ticket_key row must declare fail_stop_on_internal_work_item_id_in_product_pr_identity (AC-NEG5)" >&2
      exit 1
    fi

    trap - EXIT
    rm -rf "$tmpdir"
    echo "PASS: bug source internal id does not leak into product PR identity (AC-NEG5)"
    ;;

  no-gate-removal)
    # AC-NEG1: this DP must NOT remove any existing gate. The slimming work
    # touches reference / SKILL prose and identity consumers, so the regression
    # risk is "a gate's script/hook silently dropped or its wiring removed."
    # This case asserts each named gate (language / Starlight / producer-env
    # writer / boundary / task readiness / proof marker / AC verification) is
    # BOTH present AND still wired into its callsite. It is non-tautological:
    # deleting a gate script, or removing the reference that wires it in, turns
    # this case RED.
    require_file "$MATRIX"

    fail=0

    # (1) language gate: validator present + wired into the constitutional
    # Markdown Authoring Contract (bootstrap.md).
    require_file "$ROOT/scripts/validate-language-policy.sh"
    require_file "$BOOTSTRAP"
    if ! grep -q 'validate-language-policy.sh' "$BOOTSTRAP"; then
      echo "FAIL: language gate no longer wired into bootstrap.md Markdown Authoring Contract" >&2
      fail=1
    fi

    # (2) Starlight gate: validator present + wired into bootstrap.md.
    require_file "$ROOT/scripts/validate-starlight-authoring.sh"
    if ! grep -q 'validate-starlight-authoring.sh' "$BOOTSTRAP"; then
      echo "FAIL: Starlight gate no longer wired into bootstrap.md Markdown Authoring Contract" >&2
      fail=1
    fi

    # (3) producer-env writer: producer registry present + consumed by the
    # no-direct-evidence-write hook (the specs-bound write gate).
    require_file "$EVIDENCE_PRODUCERS"
    require_file "$NO_DIRECT_EVIDENCE_HOOK"
    if ! grep -q 'evidence-producers.json' "$NO_DIRECT_EVIDENCE_HOOK"; then
      echo "FAIL: producer-env registry no longer consumed by no-direct-evidence-write hook" >&2
      fail=1
    fi

    # (4) boundary gate: script present + wired into the engineering SKILL.
    require_file "$ROOT/scripts/skill-workflow-boundary-gate.sh"
    require_file "$SKILL_ENGINEERING"
    if ! grep -q 'skill-workflow-boundary-gate.sh' "$SKILL_ENGINEERING"; then
      echo "FAIL: skill-workflow boundary gate no longer wired into engineering SKILL.md" >&2
      fail=1
    fi

    # (5) task readiness gate: validator present + referenced by a breakdown
    # intake reference (its planner-side callsite).
    require_file "$ROOT/scripts/validate-breakdown-ready.sh"
    if ! grep -rq 'validate-breakdown-ready.sh' "$ROOT/.claude/skills/references/"; then
      echo "FAIL: task readiness gate (validate-breakdown-ready.sh) no longer referenced by any skill reference" >&2
      fail=1
    fi

    # (6) proof marker writer: the proof surface is the task.md
    # deliverable.verification block (DP-360 T7 retired the head-sha-keyed
    # completion-gate marker). Assert the canonical writer is present AND
    # actually authors the deliverable.verification sub-block (contract, not a
    # bare file-existence laundering check).
    require_file "$DELIVERABLE_VERIFICATION_WRITER"
    if ! grep -q 'deliverable.verification' "$DELIVERABLE_VERIFICATION_WRITER"; then
      echo "FAIL: finalize-engineering-delivery.sh no longer authors the deliverable.verification proof surface" >&2
      fail=1
    fi
    if grep -q 'scripts/write-completion-gate-marker.sh' "$DELIVERABLE_VERIFICATION_WRITER"; then
      echo "FAIL: finalize-engineering-delivery.sh still references the retired completion-gate marker writer" >&2
      fail=1
    fi

    # (7) AC verification gate: verify-AC deterministic consumption sibling
    # selftest present (this DP's AC-verification deterministic surface) and
    # still wired into this suite's aggregate run.
    require_file "$VERIFY_AC_SIBLING"
    self="${BASH_SOURCE[0]}"
    if ! grep -q 'verify-AC-deterministic-consumption-selftest.sh' "$self"; then
      echo "FAIL: AC verification sibling selftest no longer wired into the aggregate run" >&2
      fail=1
    fi

    if (( fail == 1 )); then
      exit 1
    fi

    echo "PASS: no gate removed (language / Starlight / producer-env / boundary / task readiness / proof marker / AC verification all present and wired)"
    ;;

  legacy-reader-compatibility)
    # AC-NEG4: the identity-atom-split slimming must not break legacy readers.
    # When the parser split work_item_id / jira_key / delivery_ticket_key, the
    # legacy `task_jira_key` consumer path had to be preserved as a migration
    # alias (product source → real JIRA key; DP source → work_item_id) so old
    # consumers keep resolving. This case asserts:
    #   (a) parse-task-md.sh still backfills the task_jira_key migration alias.
    #   (b) the alias actually works at runtime for both a Bug source (alias ==
    #       jira_key) and a DP source (alias == work_item_id).
    #   (c) the atom matrix delivery_ticket_key row still declares the
    #       parser-derived alias provenance, and the matrix keeps the
    #       compatibility-bridge sunset rule.
    # Removing the alias backfill or the matrix compatibility declaration turns
    # this case RED.
    require_file "$PARSE_TASK_MD"
    require_file "$MATRIX"

    fail=0

    # (a) parser still backfills the legacy task_jira_key alias.
    if ! grep -q 'operational_context\["task_jira_key"\] = work_item_id' "$PARSE_TASK_MD"; then
      echo "FAIL: parse-task-md.sh dropped the legacy task_jira_key migration alias backfill (AC-NEG4)" >&2
      fail=1
    fi

    # (b) runtime: the legacy task_jira_key alias still backfills to work_item_id
    # for both source types when the (legacy) "Task JIRA key" column is absent,
    # so old consumers keep resolving a non-empty field. This is exactly why
    # AC-NEG5 forbids product PR identity from reading this alias: for a Bug
    # source it holds the internal marker (EXCO-4190-T1), not the bare JIRA key.
    tmpdir="$(mktemp -d -t legacy-reader-compatibility.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT

    bug_md="$tmpdir/bug-T1.md"
    cat >"$bug_md" <<'MD'
# T1: legacy reader bug source (2 pt)

> Source: EXCO-4190 | Task: EXCO-4190-T1 | JIRA: EXCO-4190 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-4190 |
| Task ID | EXCO-4190-T1 |
| JIRA key | EXCO-4190 |
| Base branch | develop |
| Task branch | task/EXCO-4190-fix-leak |

## Test Environment

- **Level**: static
MD

    dp_md="$tmpdir/dp-T4.md"
    cat >"$dp_md" <<'MD'
# T4: legacy reader dp source (3 pt)

> Source: DP-238 | Task: DP-238-T4 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-238 |
| Task ID | DP-238-T4 |
| JIRA key | N/A |
| Base branch | main |
| Task branch | task/DP-238-T4-identity |

## Test Environment

- **Level**: static
MD

    bug_alias="$(bash "$PARSE_TASK_MD" "$bug_md" --no-resolve --field task_jira_key 2>/dev/null)"
    dp_alias="$(bash "$PARSE_TASK_MD" "$dp_md" --no-resolve --field task_jira_key 2>/dev/null)"

    if [[ "$bug_alias" != "EXCO-4190-T1" ]]; then
      echo "FAIL: legacy task_jira_key alias for Bug source must backfill work_item_id EXCO-4190-T1 (legacy reader broke), got: $bug_alias" >&2
      fail=1
    fi
    if [[ "$dp_alias" != "DP-238-T4" ]]; then
      echo "FAIL: legacy task_jira_key alias for DP source must backfill work_item_id DP-238-T4 (legacy reader broke), got: $dp_alias" >&2
      fail=1
    fi

    # (c) atom matrix keeps the delivery_ticket_key parser-derived alias
    # provenance and the compatibility-bridge sunset rule.
    if ! grep -E -q '^\| `delivery_ticket_key`.*parser-derived alias' "$MATRIX"; then
      echo "FAIL: atom matrix delivery_ticket_key row dropped the parser-derived alias provenance (legacy compatibility pointer)" >&2
      fail=1
    fi
    if ! grep -q 'Compatibility bridge' "$MATRIX"; then
      echo "FAIL: atom matrix dropped the compatibility-bridge sunset rule (legacy reader pointer policy)" >&2
      fail=1
    fi

    if (( fail == 1 )); then
      exit 1
    fi

    trap - EXIT
    rm -rf "$tmpdir"
    echo "PASS: legacy reader compatibility (task_jira_key migration alias + atom matrix compatibility pointer preserved)"
    ;;

  bug-source-product-pr-identity-negative)
    # AC-NEG5 (negative, standalone): a Bug source internal task marker must not
    # leak into the product PR identity. This is the negative half of the
    # bug-source-product-pr-identity case, promoted to its own runnable case so
    # the refinement-declared verification method
    #   --case bug-source-product-pr-identity-negative
    # resolves to an executable, non-tautological assertion. It asserts:
    #   (a) task/{BUG_KEY}-T1-* (internal marker prefix) fails branch resolution.
    #   (b) the legal delivery-ticket-prefixed branch still resolves (positive
    #       control, so the negative is not vacuously RED for everything).
    #   (c) source-level: resolve-task-branch.sh / gate-pr-title.sh consume
    #       delivery_ticket_key and must NOT fall back to the legacy
    #       task_jira_key alias for product PR identity.
    require_file "$RESOLVE_TASK_BRANCH"
    require_file "$GATE_PR_TITLE"

    tmpdir="$(mktemp -d -t bug-source-product-pr-identity-negative.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT

    # (a) NEGATIVE branch: internal task marker reused as product branch prefix.
    leak_branch_md="$tmpdir/leak-branch.md"
    cat >"$leak_branch_md" <<'MD'
# T1: bug source id leak via branch (2 pt)

> Source: EXCO-4190 | Task: EXCO-4190-T1 | JIRA: EXCO-4190 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-4190 |
| Task ID | EXCO-4190-T1 |
| JIRA key | EXCO-4190 |
| Base branch | develop |
| Task branch | task/EXCO-4190-T1-fix-leak |

## Test Environment

- **Level**: static
MD

    if bash "$RESOLVE_TASK_BRANCH" "$leak_branch_md" >/dev/null 2>&1; then
      leaked="$(bash "$RESOLVE_TASK_BRANCH" "$leak_branch_md" 2>/dev/null || true)"
      echo "FAIL: Bug source product branch task/EXCO-4190-T1-* must fail-stop (internal marker leaked), but resolver returned: $leaked" >&2
      exit 1
    fi

    # (b) POSITIVE control: legal delivery-ticket-prefixed branch must resolve.
    ok_branch_md="$tmpdir/ok-branch.md"
    cat >"$ok_branch_md" <<'MD'
# T1: bug source legal delivery branch (2 pt)

> Source: EXCO-4190 | Task: EXCO-4190-T1 | JIRA: EXCO-4190 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-4190 |
| Task ID | EXCO-4190-T1 |
| JIRA key | EXCO-4190 |
| Base branch | develop |
| Task branch | task/EXCO-4190-fix-leak |

## Test Environment

- **Level**: static
MD

    ok_branch="$(bash "$RESOLVE_TASK_BRANCH" "$ok_branch_md" 2>/dev/null || true)"
    if [[ "$ok_branch" != "task/EXCO-4190-fix-leak" ]]; then
      echo "FAIL: legal delivery-ticket branch task/EXCO-4190-fix-leak must resolve, got: $ok_branch" >&2
      exit 1
    fi

    # (c) Source-level: consumers must key off delivery_ticket_key and must NOT
    # read the legacy task_jira_key alias for product PR identity (that alias
    # holds the internal work_item_id for Bug sources and would re-admit the
    # leak).
    if ! grep -q 'identity.delivery_ticket_key' "$RESOLVE_TASK_BRANCH"; then
      echo "FAIL: resolve-task-branch.sh must consume identity.delivery_ticket_key for the product branch prefix" >&2
      exit 1
    fi
    if grep -E -q 'json_field "operational_context\.task_jira_key"' "$RESOLVE_TASK_BRANCH"; then
      echo "FAIL: resolve-task-branch.sh must not read legacy operational_context.task_jira_key for product branch identity (AC-NEG5)" >&2
      exit 1
    fi
    if grep -q -- '--field task_jira_key' "$GATE_PR_TITLE"; then
      echo "FAIL: gate-pr-title.sh must not derive product PR title from legacy task_jira_key alias (AC-NEG5)" >&2
      exit 1
    fi

    trap - EXIT
    rm -rf "$tmpdir"
    echo "PASS: bug source internal id does not leak into product PR identity (AC-NEG5 negative)"
    ;;

  *)
    echo "unknown case: $CASE" >&2
    exit 2
    ;;
esac
