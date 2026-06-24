#!/usr/bin/env bash
# Purpose: Hermetic selftest for DP-303-T1 framework-release closeout authority
#          hygiene. Asserts the closeout head-resolution authority chain and the
#          --task-md boundary fail-closed contract:
#   - AC1 / AC-NEG1 / AC-NEG2 (DP-360 T7): with NO --task-head-sha, a non-bundle
#     task resolves its delivery head from the task.md deliverable.head_sha
#     delivery block, NOT from the (mutable) task/* branch ref and NOT from the
#     retired head-sha-keyed completion-gate marker. A fixture that pollutes the
#     task/* ref to a DIFFERENT commit AND drops a stray torn-down marker at that
#     polluted head must still close out against the task.md block —
#     resolve_branch_sha is no longer an authority source and the marker is gone.
#   - AC-NEG2 (no silent pass): with NO --task-head-sha AND no task.md delivery
#     head, closeout fail-closes instead of silently falling back to the branch
#     ref.
#   - AC6: a --task-md whose frontmatter is task_kind=V is rejected at argument
#     parsing with a parent-closeout hint (fail-closed, exit 2).
#   - AC7: an aggregate task (carries bundle_branch_alias) WITHOUT a matching
#     --task-head-sha fail-closes; the bundle path never auto-resolves the head.
# Inputs:  none (CLI args ignored). Builds synthetic git repos + specs
#          containers in a private tmpdir.
# Outputs: stdout PASS/FAIL summary. Exit 0 = all cases PASS, 1 = a case failed.
# Side effects: tmpdir only (trap-removed). Never mutates the real workspace.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMPROOT="$(mktemp -d -t fr-closeout-head-authority-selftest.XXXXXX)"
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

# ---------------------------------------------------------------------------
# Build a stub scripts/ dir: the REAL closeout + parser + lib, with the
# side-effecting downstream helpers replaced by deterministic stubs. Running
# the real closeout with SCRIPT_DIR pointing here exercises the actual head
# authority / boundary logic while keeping the test hermetic.
# ---------------------------------------------------------------------------
build_stub_scripts_dir() {
  local dst="$1"
  mkdir -p "$dst/selftests"
  cp -R "$ROOT/scripts/lib" "$dst/lib"
  cp "$ROOT/scripts/framework-release-closeout.sh" "$dst/framework-release-closeout.sh"
  cp "$ROOT/scripts/parse-task-md.sh" "$dst/parse-task-md.sh"
  cp "$ROOT/scripts/resolve-task-base.sh" "$dst/resolve-task-base.sh" 2>/dev/null || true

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

  # mark-spec-implemented stub: flips frontmatter status to IMPLEMENTED in place
  # and records the resolved head it was driven against (none directly, but its
  # invocation proves the closeout reached the flip stage = head resolved).
  cat >"$dst/mark-spec-implemented.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
TASK_ID="$1"; shift
WORKSPACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'mark-spec-implemented.sh %s\n' "$TASK_ID" >>"${POLARIS_STUB_LOG:?}"
specs="$WORKSPACE/docs-manager/src/content/docs/specs"
suffix="${TASK_ID##*-}"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  python3 - "$f" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1]); t = p.read_text(encoding="utf-8"); lines = t.split("\n")
if lines and lines[0] == "---":
    end = lines.index("---", 1)
    fm = lines[1:end]
    done = False
    for i, l in enumerate(fm):
        if re.match(r"^status:\s*", l):
            fm[i] = "status: IMPLEMENTED"; done = True; break
    if not done: fm.append("status: IMPLEMENTED")
    p.write_text("---\n" + "\n".join(fm) + "\n---\n" + "\n".join(lines[end+1:]), encoding="utf-8")
PY
done < <(find "$specs" -path "*/tasks/$suffix/index.md" 2>/dev/null)
exit 0
STUB
  chmod +x "$dst/mark-spec-implemented.sh"

  cat >"$dst/close-parent-spec-if-complete.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'close-parent-spec-if-complete.sh %s\n' "$*" >>"${POLARIS_STUB_LOG:?}"
exit 0
STUB
  chmod +x "$dst/close-parent-spec-if-complete.sh"
}

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

# Write a DP container with one task at tasks/<suffix>/index.md.
#   $1 repo  $2 dp-id  $3 suffix  $4 shape  $5 task-branch  $6 bundle-alias
#   $7 allowed-file  $8 task_kind (default T)  $9 deliverable.head_sha (optional)
write_task_container() {
  local repo="$1" dp="$2" suffix="$3" shape="$4" branch="$5" alias="$6" allowed="$7"
  local kind="${8:-T}" deliver_head="${9:-}"
  local dir="$repo/docs-manager/src/content/docs/specs/design-plans/${dp}-fixture"
  mkdir -p "$dir/tasks/$suffix"
  cat >"$dir/index.md" <<MD
---
title: "${dp} fixture parent"
status: LOCKED
---

# ${dp}
MD
  {
    printf -- '---\n'
    [[ -n "$alias" ]] && printf 'bundle_branch_alias: %s\n' "$alias"
    printf 'status: IN_PROGRESS\n'
    printf 'task_kind: %s\n' "$kind"
    [[ -n "$shape" ]] && printf 'task_shape: %s\n' "$shape"
    if [[ -n "$deliver_head" ]]; then
      printf 'deliverable:\n'
      printf '  head_sha: %s\n' "$deliver_head"
    fi
    printf -- '---\n\n'
    printf '# %s: fixture task (1 pt)\n\n' "$suffix"
    printf '> Source: %s | Task: %s-%s | JIRA: N/A | Repo: polaris-framework\n\n' "$dp" "$dp" "$suffix"
    printf '## Operational Context\n\n'
    printf '| 欄位 | 值 |\n|------|-----|\n'
    printf '| Source type | dp |\n'
    printf '| Source ID | %s |\n' "$dp"
    printf '| Task ID | %s-%s |\n' "$dp" "$suffix"
    printf '| JIRA key | N/A |\n'
    printf '| Base branch | main |\n'
    [[ -n "$branch" ]] && printf '| Task branch | %s |\n' "$branch"
    printf '\n## Allowed Files\n\n'
    printf -- '- `%s`\n' "$allowed"
    printf '\n## Test Environment\n\n- **Level**: static\n'
  } >"$dir/tasks/$suffix/index.md"
}

valid_verify_marker() {
  local path="$1" ticket="$2" head="$3"
  cat >"$path" <<JSON
{"ticket":"${ticket}","head_sha":"${head}","writer":"run-verify-command.sh","exit_code":0,"at":"2026-06-05T00:00:00Z","status":"PASS"}
JSON
}

# DP-360 T7: write a STRAY (torn-down) completion-gate marker. The closeout must
# IGNORE it — the task.md deliverable.head_sha is the sole non-override head
# authority. Used only to prove the retired marker does not influence the head.
write_stray_completion_gate_marker() {
  local repo="$1" work_item_id="$2" head="$3"
  local dir="$repo/.polaris/evidence/completion-gate"
  mkdir -p "$dir"
  cat >"$dir/${work_item_id}-${head}.json" <<JSON
{"schema_version":1,"marker_kind":"completion_gate","writer":"engineering","work_item_id":"${work_item_id}","status":"PASS","freshness":{"head_sha":"${head}"},"at":"2026-06-05T00:00:00Z"}
JSON
}

run_closeout() {
  local scripts_dir="$1"; shift
  set +e
  CLOSEOUT_OUT="$(POLARIS_STUB_LOG="$STUB_LOG" \
    bash "$scripts_dir/framework-release-closeout.sh" "$@" 2>&1)"
  CLOSEOUT_RC=$?
  set -e
}

# ===========================================================================
# Case A1 (AC1 / AC-NEG1 / AC-NEG2, DP-360 T7): polluted task/* ref + stray
# torn-down completion-gate marker — head comes from the task.md
# deliverable.head_sha block, NOT from the branch ref and NOT from the marker.
# No --task-head-sha given.
# ===========================================================================
{
  WS="$TMPROOT/a1-ws"
  SCRIPTS="$TMPROOT/a1-scripts"
  STUB_LOG="$TMPROOT/a1-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  # The genuine delivery head: a commit on the task branch.
  git -C "$WS" checkout -q -b task/DP-901-T1-x
  mkdir -p "$WS/scripts"
  echo work >"$WS/scripts/feature-a1.sh"
  git -C "$WS" add scripts/feature-a1.sh
  git -C "$WS" commit -qm "genuine delivery head"
  DELIVERY_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # The release commit on main contains the delivery (ancestor of workspace).
  git -C "$WS" checkout -q main
  git -C "$WS" merge -q --no-ff task/DP-901-T1-x -m "merge delivery"
  # task.md carries the GENUINE delivery head in its deliverable block.
  write_task_container "$WS" DP-901 T1 implementation task/DP-901-T1-x '' 'scripts/feature-a1.sh' T "$DELIVERY_HEAD"
  git -C "$WS" add docs-manager
  git -C "$WS" commit -qm "container"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  # POLLUTE the task/* ref to a DIFFERENT commit than the delivery head.
  git -C "$WS" checkout -q task/DP-901-T1-x
  echo poison >"$WS/scripts/poison.sh"
  git -C "$WS" add scripts/poison.sh
  git -C "$WS" commit -qm "ref pollution"
  POLLUTED_HEAD="$(git -C "$WS" rev-parse HEAD)"
  git -C "$WS" checkout -q main

  # AC-NEG2: a STRAY torn-down completion-gate marker at the POLLUTED head must
  # be ignored — only the task.md deliverable.head_sha may be the authority.
  write_stray_completion_gate_marker "$WS" DP-901-T1 "$POLLUTED_HEAD"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-901-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/a1-verify.json"
  valid_verify_marker "$MARKER" DP-901-T1 "$DELIVERY_HEAD"

  [[ "$DELIVERY_HEAD" != "$POLLUTED_HEAD" ]] \
    || echo "[setup-error] A1 delivery head == polluted head" >&2

  # No --task-head-sha: head MUST come from the task.md delivery block, not the
  # polluted ref and not the stray marker.
  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "A1 closeout exits 0 (delivery-block head resolved)"
  # The extension deliverable is written against the resolved head; assert the
  # GENUINE delivery head (from task.md block) was used, not the polluted ref /
  # stray-marker head.
  _assert_contains "$(cat "$STUB_LOG")" "$DELIVERY_HEAD" "A1 closeout used task.md delivery-block head"
  _assert_not_contains "$(cat "$STUB_LOG")" "$POLLUTED_HEAD" "A1 closeout did NOT use polluted ref / stray-marker head"
}

# ===========================================================================
# Case A2 (AC1): no --task-head-sha, no marker, but task.md carries a
# deliverable.head_sha delivery block → head resolved from the delivery block.
# ===========================================================================
{
  WS="$TMPROOT/a2-ws"
  SCRIPTS="$TMPROOT/a2-scripts"
  STUB_LOG="$TMPROOT/a2-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  git -C "$WS" checkout -q -b task/DP-902-T1-x
  mkdir -p "$WS/scripts"
  echo work >"$WS/scripts/feature-a2.sh"
  git -C "$WS" add scripts/feature-a2.sh
  git -C "$WS" commit -qm "delivery head"
  DELIVERY_HEAD="$(git -C "$WS" rev-parse HEAD)"

  git -C "$WS" checkout -q main
  git -C "$WS" merge -q --no-ff task/DP-902-T1-x -m "merge delivery"
  write_task_container "$WS" DP-902 T1 implementation task/DP-902-T1-x '' 'scripts/feature-a2.sh' T "$DELIVERY_HEAD"
  git -C "$WS" add docs-manager
  git -C "$WS" commit -qm "container"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-902-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/a2-verify.json"
  valid_verify_marker "$MARKER" DP-902-T1 "$DELIVERY_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "A2 closeout exits 0 (delivery-block head)"
  _assert_contains "$(cat "$STUB_LOG")" "$DELIVERY_HEAD" "A2 closeout used task.md delivery-block head"
}

# ===========================================================================
# Case NEG2 (AC-NEG2, DP-360 T7): no --task-head-sha, no task.md delivery block →
# fail-closed. resolve_branch_sha is NOT an authority fallback (the head-sha
# completion-gate marker is retired and never a fallback either).
# ===========================================================================
{
  WS="$TMPROOT/neg2-ws"
  SCRIPTS="$TMPROOT/neg2-scripts"
  STUB_LOG="$TMPROOT/neg2-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  git -C "$WS" checkout -q -b task/DP-903-T1-x
  mkdir -p "$WS/scripts"
  echo work >"$WS/scripts/feature-neg2.sh"
  git -C "$WS" add scripts/feature-neg2.sh
  git -C "$WS" commit -qm "branch head (must NOT be used as authority)"

  git -C "$WS" checkout -q main
  write_task_container "$WS" DP-903 T1 implementation task/DP-903-T1-x '' 'scripts/feature-neg2.sh'
  git -C "$WS" add docs-manager
  git -C "$WS" commit -qm "container"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-903-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/neg2-verify.json"
  valid_verify_marker "$MARKER" DP-903-T1 "$(git -C "$WS" rev-parse HEAD)"

  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "2" "NEG2 closeout fail-closed (no marker / no delivery head)"
  _assert_not_contains "$CLOSEOUT_OUT" "PASS: framework release closeout completed" "NEG2 no silent pass"
}

# ===========================================================================
# Case V (AC6): a --task-md with task_kind=V is rejected at argument parsing
# with a parent-closeout hint.
# ===========================================================================
{
  WS="$TMPROOT/v-ws"
  SCRIPTS="$TMPROOT/v-scripts"
  STUB_LOG="$TMPROOT/v-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  write_task_container "$WS" DP-904 V1 confirmation '' '' 'scripts/feature-v.sh' V
  git -C "$WS" add docs-manager
  git -C "$WS" commit -qm "container"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-904-fixture/tasks/V1/index.md"
  MARKER="$TMPROOT/v-verify.json"
  valid_verify_marker "$MARKER" DP-904-V1 "$RELEASE_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "2" "V closeout fail-closed (task_kind=V rejected)"
  _assert_contains "$CLOSEOUT_OUT" "parent-closeout" "V closeout hints parent-closeout"
}

# ===========================================================================
# Case AGG (AC7): aggregate task (bundle_branch_alias) WITHOUT a matching
# --task-head-sha → fail-closed; the bundle path never auto-resolves the head.
# ===========================================================================
{
  WS="$TMPROOT/agg-ws"
  SCRIPTS="$TMPROOT/agg-scripts"
  STUB_LOG="$TMPROOT/agg-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  git -C "$WS" checkout -q -b task/DP-905-T1-x
  mkdir -p "$WS/scripts"
  echo work >"$WS/scripts/feature-agg.sh"
  git -C "$WS" add scripts/feature-agg.sh
  git -C "$WS" commit -qm "per-task head"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  git -C "$WS" checkout -q main
  mkdir -p "$WS/scripts"
  echo bundled >"$WS/scripts/feature-agg.sh"
  write_task_container "$WS" DP-905 T1 implementation task/DP-905-T1-x bundle-DP-905-v1.0.0 'scripts/feature-agg.sh'
  git -C "$WS" add scripts/feature-agg.sh docs-manager
  git -C "$WS" commit -qm "bundle release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-905-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/agg-verify.json"
  valid_verify_marker "$MARKER" DP-905-T1 "$TASK_HEAD"

  # Even if a stray (torn-down) marker exists, the AGGREGATE path must require
  # --task-head-sha and must never auto-resolve a head from it.
  write_stray_completion_gate_marker "$WS" DP-905-T1 "$TASK_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "2" "AGG aggregate without --task-head-sha fail-closed"
  _assert_contains "$CLOSEOUT_OUT" "--task-head-sha" "AGG hints required per-task SHA"
}

# ===========================================================================
# Case AGG_OK (AC7 happy path): aggregate task WITH a matching --task-head-sha
# closes out fine (the fail-closed only triggers when the head is absent).
# ===========================================================================
{
  WS="$TMPROOT/aggok-ws"
  SCRIPTS="$TMPROOT/aggok-scripts"
  STUB_LOG="$TMPROOT/aggok-stub.log"
  : >"$STUB_LOG"
  build_stub_scripts_dir "$SCRIPTS"
  init_workspace_repo "$WS"

  git -C "$WS" checkout -q -b task/DP-906-T1-x
  mkdir -p "$WS/scripts"
  echo work >"$WS/scripts/feature-aggok.sh"
  git -C "$WS" add scripts/feature-aggok.sh
  git -C "$WS" commit -qm "per-task head"
  TASK_HEAD="$(git -C "$WS" rev-parse HEAD)"

  git -C "$WS" checkout -q main
  mkdir -p "$WS/scripts"
  echo bundled >"$WS/scripts/feature-aggok.sh"
  write_task_container "$WS" DP-906 T1 implementation task/DP-906-T1-x bundle-DP-906-v1.0.0 'scripts/feature-aggok.sh'
  git -C "$WS" add scripts/feature-aggok.sh docs-manager
  git -C "$WS" commit -qm "bundle release"
  RELEASE_HEAD="$(git -C "$WS" rev-parse HEAD)"

  TASK_MD="$WS/docs-manager/src/content/docs/specs/design-plans/DP-906-fixture/tasks/T1/index.md"
  MARKER="$TMPROOT/aggok-verify.json"
  valid_verify_marker "$MARKER" DP-906-T1 "$TASK_HEAD"

  run_closeout "$SCRIPTS" \
    --task-md "$TASK_MD" --task-head-sha "DP-906-T1=${TASK_HEAD}" \
    --verify-evidence "$MARKER" \
    --workspace-commit "$RELEASE_HEAD" --template-commit "$RELEASE_HEAD" \
    --version-tag v1.0.0 --release-url N/A --repo "$WS"

  _assert_eq "$CLOSEOUT_RC" "0" "AGG_OK aggregate with --task-head-sha exits 0"
}

# ---------------------------------------------------------------------------
printf '\n[framework-release-closeout-head-authority-selftest] PASS=%d FAIL=%d TOTAL=%d\n' \
  "$PASS" "$FAIL" "$TOTAL"
[[ "$FAIL" -eq 0 ]]
