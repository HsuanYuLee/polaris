#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-311 T4 (AC3) framework-release closeout V
#          task auto-enumeration / idempotent confirm. Before the single parent
#          closeout call (Phase 2), framework-release-closeout.sh must enumerate
#          V task entries directly from the source container so that:
#            (a) an already-advanced V (tasks/pr-release/ + IMPLEMENTED +
#                ac_verification PASS) is an idempotent confirm — re-running
#                closeout is a NOOP that never re-moves or rewrites it;
#            (b) an operator who omitted an advance-eligible V task
#                (ac_verification PASS + human_disposition=passed) from
#                --task-md does not leave the parent stuck — closeout folds the
#                V in through the existing canonical writer
#                mark-spec-implemented.sh and the parent can archive;
#            (c) a non-eligible V (FAIL / PASS+rejected / missing block) is
#                NEVER auto-advanced (AC-NEG1) — the parent stays blocked by
#                close-parent's active_verification contract (soft-block);
#            (d) ABANDONED V siblings keep the close-parent carve-out (left in
#                place, never advanced, never blocking);
#            (e) the V terminal contract itself stays owned by
#                close-parent-spec-if-complete.sh — closeout only invokes the
#                existing writer / reader (AC-NEG3: no second terminal
#                determination).
# Inputs:  none (CLI args ignored). Builds synthetic git repos + specs
#          containers + release commits in a private tmpdir. Uses the REAL
#          framework-release-closeout.sh, parse-task-md.sh and
#          mark-spec-implemented.sh; downstream release helpers and
#          close-parent-spec-if-complete.sh are deterministic stubs (the
#          close-parent stub mirrors the real active_verification block:
#          exit 2 + "active verification tasks remain" when a non-ABANDONED V
#          is still active under tasks/).
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never mutates the real workspace.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMPROOT="$(mktemp -d -t fr-closeout-v-enum-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
TOTAL=0

_assert_eq() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: expected=%q got=%q\n' "$TOTAL" "$3" "$2" "$1" >&2
  fi
}

_assert_contains() {
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$1" | grep -qF -- "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: substring not found: %q\n' "$TOTAL" "$3" "$2" >&2
    printf '       in: %s\n' "$1" >&2
  fi
}

_assert_not_contains() {
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$1" | grep -qF -- "$2"; then
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: substring should NOT appear: %q\n' "$TOTAL" "$3" "$2" >&2
  else
    PASS=$((PASS + 1))
  fi
}

_assert_file() {
  TOTAL=$((TOTAL + 1))
  if [[ -f "$1" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: file missing: %s\n' "$TOTAL" "$2" "$1" >&2
  fi
}

_assert_no_path() {
  TOTAL=$((TOTAL + 1))
  if [[ -e "$1" ]]; then
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: path should NOT exist: %s\n' "$TOTAL" "$2" "$1" >&2
  else
    PASS=$((PASS + 1))
  fi
}

# ---------------------------------------------------------------------------
# Description: build a stub scripts/ dir hosting the REAL closeout + parser +
#              mark-spec-implemented + lib, with side-effecting downstream
#              release helpers replaced by stubs. The
#              close-parent-spec-if-complete.sh stub mirrors the real
#              active_verification contract slice: any non-ABANDONED V still
#              active under tasks/ (not pr-release) blocks with exit 2 +
#              "active verification tasks remain" (the real BLOCK exit code);
#              otherwise it records the invocation and, when
#              --archive-terminal-parent is present, logs a simulated archive.
# Args:        $1 = destination stub scripts dir
# Side effects: creates $1 with copied + stubbed scripts
# ---------------------------------------------------------------------------
build_stub_scripts_dir() {
  local dst="$1"
  mkdir -p "$dst/selftests"
  cp -R "$ROOT/scripts/lib" "$dst/lib"
  cp "$ROOT/scripts/framework-release-closeout.sh" "$dst/framework-release-closeout.sh"
  cp "$ROOT/scripts/parse-task-md.sh" "$dst/parse-task-md.sh"
  # REAL canonical writer: the auto-enumeration path under test must go through
  # mark-spec-implemented.sh (AC-NEG3 — no second writer / terminal判定).
  cp "$ROOT/scripts/mark-spec-implemented.sh" "$dst/mark-spec-implemented.sh"

  local helper
  for helper in check-release-eligible.sh check-release-completed.sh \
                check-main-chain-compliance.sh write-extension-deliverable.sh \
                check-local-extension-completion.sh engineering-clean-worktree.sh; do
    cat >"$dst/$helper" <<STUB
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$helper" "\$*" >>"\${POLARIS_STUB_LOG:?}"
exit 0
STUB
    chmod +x "$dst/$helper"
  done

  cat >"$dst/close-parent-spec-if-complete.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'close-parent-spec-if-complete.sh %s\n' "$*" >>"${POLARIS_STUB_LOG:?}"
TASK_MD=""
ARCHIVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="$2"; shift 2 ;;
    --archive-terminal-parent) ARCHIVE=1; shift ;;
    *) shift ;;
  esac
done
container="$TASK_MD"
while [[ -n "$container" && "$(basename "$container")" != "tasks" ]]; do
  container="$(dirname "$container")"
done
container="$(dirname "$container")"
# Mirror the real active_verification block slice: a non-ABANDONED V sibling
# still active under tasks/ (not pr-release) blocks the parent with exit 2.
if [[ -d "$container/tasks" ]]; then
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    case "$v" in
      */tasks/pr-release/*) continue ;;
    esac
    if grep -q '^status: ABANDONED$' "$v"; then
      continue
    fi
    printf '[polaris parent-closeout] BLOCKED: active verification tasks remain: %s\n' "$v" >&2
    exit 2
  done < <(find "$container/tasks" \( -path '*/V*/index.md' -o -name 'V*.md' \) -type f 2>/dev/null)
fi
if [[ "$ARCHIVE" -eq 1 ]]; then
  printf 'ARCHIVED %s\n' "$container" >>"${POLARIS_STUB_LOG:?}"
fi
exit 0
STUB
  chmod +x "$dst/close-parent-spec-if-complete.sh"
}

# Description: init a synthetic workspace git repo with a specs tree.
# Args:        $1 = repo path
# Side effects: creates git repo with an initial commit
init_workspace_repo() {
  local repo="$1"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  git -C "$repo" checkout -q -b main
  mkdir -p "$repo/docs-manager/src/content/docs/specs/design-plans"
  echo init >"$repo/seed.txt"
  git -C "$repo" add seed.txt
  git -C "$repo" commit -qm init
}

# Description: write the container parent index.md (LOCKED) for a fixture.
# Args:        $1 = container dir  $2 = container label
# Side effects: writes $1/index.md
write_parent_index() {
  local dir="$1" label="$2"
  mkdir -p "$dir"
  cat >"$dir/index.md" <<MD
---
title: "${label} fixture parent"
status: LOCKED
---

# ${label}
MD
}

# Description: write a no-branch (content-delivered) confirmation task under a
#              container's tasks/<suffix>/index.md.
# Args:        $1 = container dir  $2 = source-id  $3 = suffix  $4 = allowed file
#              $5 = jira key (default N/A; company containers need a resolvable
#                   key so the real mark-spec-implemented Path 4 can anchor it)
# Side effects: writes tasks/<suffix>/index.md
write_no_branch_task() {
  local dir="$1" sid="$2" suffix="$3" allowed="$4" jira="${5:-N/A}"
  mkdir -p "$dir/tasks/$suffix"
  {
    printf -- '---\n'
    printf 'status: IN_PROGRESS\n'
    printf 'task_kind: T\n'
    printf 'task_shape: confirmation\n'
    printf -- '---\n\n'
    printf '# %s: fixture task (1 pt)\n\n' "$suffix"
    printf '> Source: %s | Task: %s-%s | JIRA: %s | Repo: polaris-framework\n\n' "$sid" "$sid" "$suffix" "$jira"
    printf '## Operational Context\n\n'
    printf '| 欄位 | 值 |\n|------|-----|\n'
    printf '| Source type | dp |\n'
    printf '| Source ID | %s |\n' "$sid"
    printf '| Task ID | %s-%s |\n' "$sid" "$suffix"
    printf '| JIRA key | %s |\n' "$jira"
    printf '| Base branch | main |\n'
    printf '\n## Allowed Files\n\n'
    printf -- '- `%s`\n' "$allowed"
    printf '\n## Test Environment\n\n- **Level**: static\n'
  } >"$dir/tasks/$suffix/index.md"
}

# Description: write a folder-native V task fixture with an ac_verification
#              frontmatter block (the verify-AC writer output shape).
# Args:        $1 = container dir  $2 = stem (V1)  $3 = ac status (NONE omits
#              the block)  $4 = human_disposition (empty omits the field)
#              $5 = task frontmatter status (default IN_PROGRESS)
# Side effects: writes tasks/<stem>/index.md
write_v_task() {
  local dir="$1" stem="$2" ac_status="$3" disposition="${4:-}" task_status="${5:-IN_PROGRESS}"
  mkdir -p "$dir/tasks/$stem"
  {
    printf -- '---\n'
    printf 'title: "%s fixture verification task"\n' "$stem"
    printf 'status: %s\n' "$task_status"
    printf 'task_kind: V\n'
    if [[ "$ac_status" != "NONE" ]]; then
      printf 'ac_verification:\n'
      printf '  status: %s\n' "$ac_status"
      if [[ -n "$disposition" ]]; then
        printf '  human_disposition: %s\n' "$disposition"
      fi
      printf '  ac_total: 1\n'
      printf '  ac_pass: 1\n'
    fi
    printf -- '---\n\n'
    printf '# %s fixture\n' "$stem"
  } >"$dir/tasks/$stem/index.md"
}

# Description: write a valid head-bound verify evidence marker JSON.
# Args:        $1 = path  $2 = ticket  $3 = head sha
# Side effects: writes $1
valid_verify_marker() {
  local path="$1" ticket="$2" head="$3"
  cat >"$path" <<JSON
{"ticket":"${ticket}","head_sha":"${head}","writer":"run-verify-command.sh","exit_code":0,"at":"2026-06-11T00:00:00Z","status":"PASS"}
JSON
}

# Description: run the real closeout from a stub scripts dir, capturing output
#              + exit code into CLOSEOUT_OUT / CLOSEOUT_RC.
# Args:        $1 = stub scripts dir; remaining = closeout args
# Side effects: sets CLOSEOUT_OUT / CLOSEOUT_RC
run_closeout() {
  local scripts_dir="$1"; shift
  set +e
  CLOSEOUT_OUT="$(POLARIS_STUB_LOG="$STUB_LOG" \
    bash "$scripts_dir/framework-release-closeout.sh" "$@" 2>&1)"
  CLOSEOUT_RC=$?
  set -e
}

# Description: commit the workspace fixture and run closeout listing ONLY the
#              T1 confirmation task of the given container.
# Args:        $1 = label  $2 = workspace  $3 = stub scripts dir
#              $4 = container dir  $5 = source-id
# Side effects: git commit; sets CLOSEOUT_OUT / CLOSEOUT_RC / RELEASE_HEAD
run_closeout_with_t1_only() {
  local label="$1" ws="$2" scripts="$3" dir="$4" sid="$5"
  git -C "$ws" add -A
  git -C "$ws" commit -qm "fixture release (${label})"
  RELEASE_HEAD="$(git -C "$ws" rev-parse HEAD)"
  local marker="$TMPROOT/${label}-T1.json"
  valid_verify_marker "$marker" "${sid}-T1" "$RELEASE_HEAD"
  run_closeout "$scripts" \
    --task-md "$dir/tasks/T1/index.md" --verify-evidence "$marker" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$ws"
}

# ===========================================================================
# Case A (AC3-b): operator omits an advance-eligible V task from --task-md.
# Closeout must auto-enumerate it from the source container, fold it in via
# the canonical writer (qualified DP-NNN-V1 key), and the parent can archive.
# ===========================================================================
case_auto_enumeration_dp() {
  local label="auto-enum-dp"
  local WS="$TMPROOT/${label}-ws"
  local SCRIPTS="$TMPROOT/${label}-scripts"
  STUB_LOG="$TMPROOT/${label}-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  local dir="$WS/docs-manager/src/content/docs/specs/design-plans/DP-920-fixture"
  write_parent_index "$dir" "DP-920"
  write_no_branch_task "$dir" DP-920 T1 'docs-manager/a'
  write_v_task "$dir" V1 PASS passed

  run_closeout_with_t1_only "$label" "$WS" "$SCRIPTS" "$dir" DP-920

  _assert_eq "$CLOSEOUT_RC" "0" "${label} closeout exits 0"
  _assert_contains "$CLOSEOUT_OUT" "auto-advanced unlisted V task DP-920-V1" \
    "${label} auto-advance reported with qualified DP key"
  _assert_no_path "$dir/tasks/V1" "${label} active tasks/V1 folded into pr-release"
  _assert_file "$dir/tasks/pr-release/V1/index.md" "${label} pr-release V1 exists"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$dir/tasks/pr-release/V1/index.md" || true)" "1" \
    "${label} pr-release V1 status IMPLEMENTED"
  _assert_eq "$(grep -c '^  status: PASS$' "$dir/tasks/pr-release/V1/index.md" || true)" "1" \
    "${label} ac_verification block preserved"
  _assert_eq "$(grep -c '^  human_disposition: passed$' "$dir/tasks/pr-release/V1/index.md" || true)" "1" \
    "${label} human_disposition preserved"
  # T task lifecycle regression: the listed confirmation task still flips.
  _assert_file "$dir/tasks/pr-release/T1/index.md" "${label} T1 moved to pr-release"
  # Parent closeout proceeded: close-parent ran without the verification block
  # and the terminal parent archive was requested.
  _assert_not_contains "$CLOSEOUT_OUT" "active verification tasks remain" \
    "${label} no verification block after fold-in"
  _assert_contains "$(cat "$STUB_LOG")" "--archive-terminal-parent" \
    "${label} terminal parent archive requested"
  _assert_contains "$(cat "$STUB_LOG")" "ARCHIVED ${dir}" \
    "${label} parent archived"
}

# ===========================================================================
# Case B (AC3-a): V already advanced (auto-pass already drove it to canonical
# terminal). Re-running closeout is an idempotent confirm: no re-move, no
# rewrite (byte-identical), parent closeout unblocked.
# ===========================================================================
case_idempotent_already_advanced() {
  local label="idempotent-advanced"
  local WS="$TMPROOT/${label}-ws"
  local SCRIPTS="$TMPROOT/${label}-scripts"
  STUB_LOG="$TMPROOT/${label}-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  local dir="$WS/docs-manager/src/content/docs/specs/design-plans/DP-921-fixture"
  write_parent_index "$dir" "DP-921"
  write_no_branch_task "$dir" DP-921 T1 'docs-manager/a'
  # V1 already at the canonical terminal: pr-release/ + IMPLEMENTED + PASS.
  write_v_task "$dir" V1 PASS passed IMPLEMENTED
  mkdir -p "$dir/tasks/pr-release"
  mv "$dir/tasks/V1" "$dir/tasks/pr-release/V1"

  local before
  before="$(cksum "$dir/tasks/pr-release/V1/index.md")"

  run_closeout_with_t1_only "$label" "$WS" "$SCRIPTS" "$dir" DP-921

  _assert_eq "$CLOSEOUT_RC" "0" "${label} closeout exits 0"
  _assert_contains "$CLOSEOUT_OUT" "idempotent confirm" "${label} idempotent confirm reported"
  _assert_not_contains "$CLOSEOUT_OUT" "auto-advanced unlisted V task" \
    "${label} no writer call for already-advanced V"
  _assert_eq "$(cksum "$dir/tasks/pr-release/V1/index.md")" "$before" \
    "${label} pr-release V1 byte-identical (NOOP)"
  _assert_not_contains "$CLOSEOUT_OUT" "active verification tasks remain" \
    "${label} parent closeout unblocked"
  _assert_contains "$(cat "$STUB_LOG")" "ARCHIVED ${dir}" \
    "${label} parent archived"
}

# ===========================================================================
# Case C (AC-NEG1 guard): non-eligible active V is NEVER auto-advanced. The
# parent stays behind close-parent's active_verification block (soft-block),
# and closeout itself still exits 0 (DP-293 soft-block semantics).
# Variants: FAIL+passed / PASS+rejected / missing ac_verification block.
# ===========================================================================
case_non_eligible_not_advanced() {
  local variant ac_status disposition
  for variant in 'fail-passed:FAIL:passed' 'pass-rejected:PASS:rejected' 'no-block:NONE:'; do
    IFS=':' read -r vname ac_status disposition <<<"$variant"
    local label="non-eligible-${vname}"
    local WS="$TMPROOT/${label}-ws"
    local SCRIPTS="$TMPROOT/${label}-scripts"
    STUB_LOG="$TMPROOT/${label}-stub.log"
    : >"$STUB_LOG"
    build_stub_scripts_dir "$SCRIPTS"
    init_workspace_repo "$WS"

    local dir="$WS/docs-manager/src/content/docs/specs/design-plans/DP-922-fixture"
    write_parent_index "$dir" "DP-922"
    write_no_branch_task "$dir" DP-922 T1 'docs-manager/a'
    write_v_task "$dir" V1 "$ac_status" "$disposition"

    run_closeout_with_t1_only "$label" "$WS" "$SCRIPTS" "$dir" DP-922

    _assert_eq "$CLOSEOUT_RC" "0" "${label} closeout exits 0 (soft-block)"
    _assert_contains "$CLOSEOUT_OUT" "not advance-eligible" "${label} non-eligible V reported"
    _assert_file "$dir/tasks/V1/index.md" "${label} V1 stays active under tasks/"
    _assert_no_path "$dir/tasks/pr-release/V1" "${label} V1 not advanced"
    _assert_contains "$CLOSEOUT_OUT" "parent closeout soft-block" \
      "${label} parent closeout soft-blocked"
    _assert_not_contains "$(cat "$STUB_LOG")" "ARCHIVED ${dir}" \
      "${label} parent NOT archived"
  done
}

# ===========================================================================
# Case D: ABANDONED V sibling keeps the close-parent carve-out — left in
# place, never advanced, never blocking the parent.
# ===========================================================================
case_abandoned_v_carve_out() {
  local label="abandoned-v"
  local WS="$TMPROOT/${label}-ws"
  local SCRIPTS="$TMPROOT/${label}-scripts"
  STUB_LOG="$TMPROOT/${label}-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  local dir="$WS/docs-manager/src/content/docs/specs/design-plans/DP-923-fixture"
  write_parent_index "$dir" "DP-923"
  write_no_branch_task "$dir" DP-923 T1 'docs-manager/a'
  write_v_task "$dir" V2 NONE '' ABANDONED

  run_closeout_with_t1_only "$label" "$WS" "$SCRIPTS" "$dir" DP-923

  _assert_eq "$CLOSEOUT_RC" "0" "${label} closeout exits 0"
  _assert_contains "$CLOSEOUT_OUT" "ABANDONED" "${label} ABANDONED carve-out reported"
  _assert_file "$dir/tasks/V2/index.md" "${label} ABANDONED V2 stays in tasks/"
  _assert_eq "$(grep -c '^status: ABANDONED$' "$dir/tasks/V2/index.md" || true)" "1" \
    "${label} ABANDONED status preserved"
  _assert_no_path "$dir/tasks/pr-release/V2" "${label} ABANDONED V2 never advanced"
  _assert_contains "$(cat "$STUB_LOG")" "ARCHIVED ${dir}" \
    "${label} parent archived despite ABANDONED V"
}

# ===========================================================================
# Case E: JIRA Epic-backed company container — auto-enumeration uses the bare
# stem key (mark-spec-implemented Path 2) and still folds the eligible V in.
# ===========================================================================
case_company_container_bare_stem() {
  local label="company-container"
  local WS="$TMPROOT/${label}-ws"
  local SCRIPTS="$TMPROOT/${label}-scripts"
  STUB_LOG="$TMPROOT/${label}-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  local dir="$WS/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-9"
  write_parent_index "$dir" "EPIC-9"
  write_no_branch_task "$dir" EPIC-9 T1 'docs-manager/a' EPIC-9-T1
  write_v_task "$dir" V1 PASS passed

  run_closeout_with_t1_only "$label" "$WS" "$SCRIPTS" "$dir" EPIC-9

  _assert_eq "$CLOSEOUT_RC" "0" "${label} closeout exits 0"
  _assert_contains "$CLOSEOUT_OUT" "auto-advanced unlisted V task V1" \
    "${label} auto-advance reported with bare stem key"
  _assert_no_path "$dir/tasks/V1" "${label} active tasks/V1 folded into pr-release"
  _assert_file "$dir/tasks/pr-release/V1/index.md" "${label} pr-release V1 exists"
  _assert_eq "$(grep -c '^status: IMPLEMENTED$' "$dir/tasks/pr-release/V1/index.md" || true)" "1" \
    "${label} pr-release V1 status IMPLEMENTED"
  _assert_contains "$(cat "$STUB_LOG")" "ARCHIVED ${dir}" \
    "${label} parent archived"
}

case_auto_enumeration_dp
case_idempotent_already_advanced
case_non_eligible_not_advanced
case_abandoned_v_carve_out
case_company_container_bare_stem

printf '\n[framework-release-closeout-v-enumeration-selftest] %d/%d assertions passed\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'FAIL: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
echo "PASS: framework-release closeout V enumeration selftest"
