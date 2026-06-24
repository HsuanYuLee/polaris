#!/usr/bin/env bash
# Purpose: Hermetic selftest for scripts/branch-sweep-runner.sh (DP-360 D10 / AC9).
#          建一個 throwaway fixture git repo（mktemp -d），造出已知 changed file 的
#          fixture `task/*` branch，並 STUB affected-runner（經
#          BRANCH_SWEEP_AFFECTED_RUNNER 注入）使 **真實 selftest / corpus 完全不執行**。
#          斷言：
#            (1) hit-rate 報告 shape（affected-caught vs leaked-to-full 計數 +
#                per-branch 分類行）；
#            (2) surfaced 失敗（affected gate RED）出現在 /auto-pass drain 清單；
#            (3) --migrate-evidence 把 head/PASS 寫進 fixture task.md delivery block
#                （非 live specs）；
#            (4) ≥1 negative / fail-closed 斷言（缺 git -> POLARIS marker；sentinel
#                branch 正確歸 leaked-to-full）。
#          所有 Polaris child 一律以 fixture-anchored env 執行；selftest 自身不依賴
#          live workspace（hermeticity lint 要求 spawn Polaris child 時 unset
#          POLARIS_WORKSPACE_ROOT / POLARIS_SPECS_ROOT 或注入 fixture）。
# Inputs:  無（builds isolated fixture repo under $TMPDIR）。
# Outputs: `pass=N fail=M` summary 行；任一 fail 時 exit 非 0。
# Exit code: 0 = all pass, 非 0 = 有 fail。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT_DIR/scripts/branch-sweep-runner.sh"
WRITE_DELIVERABLE="$ROOT_DIR/scripts/write-deliverable.sh"

[[ -f "$RUNNER" ]] || { echo "FAIL: runner missing: $RUNNER" >&2; exit 1; }
[[ -f "$WRITE_DELIVERABLE" ]] || { echo "FAIL: write-deliverable.sh missing: $WRITE_DELIVERABLE" >&2; exit 1; }

TMPROOT="$(mktemp -d -t branch-sweep-runner-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
TOTAL=0

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
    printf '       in: %s\n' "$1" >&2
  else
    PASS=$((PASS + 1))
  fi
}

_assert_eq() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d] %s: expected=%q got=%q\n' "$TOTAL" "$3" "$2" "$1" >&2
  fi
}

# ---------------------------------------------------------------------------
# STUB affected-runner — 完全不跑真實 selftest / corpus。它依 changed files
# 決定行為，與真實 affected-runner 的 CLI 契約對齊（--emit / --run、full-corpus
# sentinel）：
#   - changed 含 'CAUGHT'      -> emit 一個具體 affected member（affected-caught）；
#                                 --run exit 0（green）。
#   - changed 含 'LEAKED'      -> emit full-corpus sentinel（leaked-to-full）；
#                                 --run exit 0（sentinel branch 視為 backstop green）。
#   - changed 含 'REDGATE'     -> emit 一個具體 affected member（affected-caught）；
#                                 --run exit 1（surfaced failure）。
# 寫一行 log 到 $STUB_LOG 證明 sweep 只呼叫此 stub、never 真實 corpus。
# ---------------------------------------------------------------------------
make_stub_affected_runner() {
  local bin="$1"
  cat >"$bin" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
log="${STUB_AFFECTED_LOG:?}"
mode="emit"
# 蒐集 stdin changed list（sweep 以 stdin 餵 changed files）。
changed="$(cat || true)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --emit) mode="emit"; shift ;;
    --run) mode="run"; shift ;;
    --root) shift 2 ;;
    *) shift ;;
  esac
done
printf 'stub %s :: %s\n' "$mode" "$(printf '%s' "$changed" | tr '\n' ',')" >>"$log"

if printf '%s' "$changed" | grep -q 'LEAKED'; then
  if [[ "$mode" == "emit" ]]; then
    printf 'POLARIS_AFFECTED_FULL_CORPUS\n'
  fi
  # leaked branch 的 backstop 視為 green（不真的跑 corpus）。
  exit 0
fi
if printf '%s' "$changed" | grep -q 'REDGATE'; then
  if [[ "$mode" == "emit" ]]; then
    printf 'scripts/selftests/redgate-selftest.sh\n'
    exit 0
  fi
  # --run -> red（surfaced failure）。
  echo 'POLARIS_AFFECTED_SELFTEST_RED:scripts/selftests/redgate-selftest.sh' >&2
  exit 1
fi
# 預設 CAUGHT：具體 affected member + green run。
if [[ "$mode" == "emit" ]]; then
  printf 'scripts/selftests/caught-selftest.sh\n'
fi
exit 0
STUB
  chmod +x "$bin"
}

# ---------------------------------------------------------------------------
# Fixture repo：一個真實 git repo，base=main，外加四個 task/* branch：
#   task/DP-aa-caught   -> changed 含 CAUGHT.txt    (affected-caught)
#   task/DP-bb-leaked   -> changed 含 LEAKED.txt    (leaked-to-full)
#   task/DP-cc-red      -> changed 含 REDGATE.txt   (surfaced failure)
#   task/DP-dd-migrate  -> changed 含 CAUGHT.txt + 一個帶 deliverable.pr_url 的
#                          fixture task.md（--migrate-evidence 目標）
# ---------------------------------------------------------------------------
setup_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init --quiet
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" symbolic-ref HEAD refs/heads/main

  # base main commit（含 migrate 目標 task.md，帶 deliverable.pr_url）。
  local task_dir="$repo/docs-manager/src/content/docs/specs/design-plans/DP-dd/tasks/T1"
  mkdir -p "$task_dir"
  cat >"$task_dir/index.md" <<'TASKMD'
---
title: "DP-dd T1"
task_kind: T
deliverable:
  pr_url: "https://github.com/exampleco/exampleco-framework/pull/777"
  pr_state: OPEN
  head_sha: 0000000
---

# DP-dd T1
TASKMD
  printf 'seed\n' >"$repo/README-seed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit --quiet -m "seed main"

  # 每個 branch 從 main 切出、加一個 marker file、commit。
  _make_branch() {
    local br="$1" marker="$2"
    git -C "$repo" checkout --quiet -b "$br" main
    printf 'change\n' >"$repo/$marker"
    git -C "$repo" add -A
    git -C "$repo" commit --quiet -m "$br change"
    git -C "$repo" checkout --quiet main
  }
  _make_branch "task/DP-aa-caught" "CAUGHT.txt"
  _make_branch "task/DP-bb-leaked" "LEAKED.txt"
  _make_branch "task/DP-cc-red" "REDGATE.txt"

  # migrate branch：同時 touch CAUGHT marker（caught + green）與 task.md（讓
  # resolve_task_md_for_branch 對 'DP-dd' 命中該 task index.md）。
  git -C "$repo" checkout --quiet -b "task/DP-dd-migrate" main
  printf 'change\n' >"$repo/CAUGHT.txt"
  # 對 task.md 做無語意改動使其進入 branch changed set（branch->task.md 關聯不靠
  # changed set，但保持 branch 帶 CAUGHT marker 以走 caught/green 路徑）。
  git -C "$repo" add -A
  git -C "$repo" commit --quiet -m "migrate branch change"
  git -C "$repo" checkout --quiet main
}

# ===========================================================================
# Case A — emit mode hit-rate 報告 shape（不執行 gate）。
# ===========================================================================
REPO_A="$TMPROOT/repo-a"
setup_fixture_repo "$REPO_A"
STUB_A="$TMPROOT/stub-a.sh"
make_stub_affected_runner "$STUB_A"
LOG_A="$TMPROOT/stub-a.log"
: >"$LOG_A"

# Hermetic：unset live workspace env，注入 stub affected-runner。
OUT_A="$(env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT \
  STUB_AFFECTED_LOG="$LOG_A" \
  BRANCH_SWEEP_AFFECTED_RUNNER="$STUB_A" \
  bash "$RUNNER" --repo "$REPO_A" --base main 2>&1)" || true

_assert_contains "$OUT_A" "=== hit-rate report ===" "AC9: emit mode prints hit-rate report"
# 4 個 branch：caught + migrate(caught) = 2 affected-caught；leaked = 1；red 的
# changed 含 REDGATE -> emit 具體 member -> affected-caught（gate 未執行所以不算 red）。
# 因此 affected-caught=3, leaked-to-full=1, total=4。
_assert_contains "$OUT_A" "hit-rate affected-caught=3 leaked-to-full=1 total=4" \
  "AC9: hit-rate counts (3 caught / 1 leaked / 4 total)"
_assert_contains "$OUT_A" "affected-caught task/DP-aa-caught" "AC9: per-branch line for caught branch"
_assert_contains "$OUT_A" "leaked-to-full task/DP-bb-leaked full-corpus-sentinel" \
  "AC9 (negative-ish): sentinel branch classified leaked-to-full"
_assert_contains "$OUT_A" "auto-pass-drain-count=0" "AC9: emit mode has no drain (gate not run)"
# 證明只呼叫 stub，never 真實 corpus。
_assert_contains "$(cat "$LOG_A")" "stub emit" "AC9: sweep invoked the stubbed affected-runner only"

# ===========================================================================
# Case B — run mode：surfaced failure (REDGATE) 進 /auto-pass drain 清單。
# ===========================================================================
REPO_B="$TMPROOT/repo-b"
setup_fixture_repo "$REPO_B"
STUB_B="$TMPROOT/stub-b.sh"
make_stub_affected_runner "$STUB_B"
LOG_B="$TMPROOT/stub-b.log"
: >"$LOG_B"

OUT_B="$(env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT \
  STUB_AFFECTED_LOG="$LOG_B" \
  BRANCH_SWEEP_AFFECTED_RUNNER="$STUB_B" \
  bash "$RUNNER" --repo "$REPO_B" --base main --run 2>&1)" || true

_assert_contains "$OUT_B" "gate-result task/DP-cc-red: FAIL" "AC9: red branch gate FAIL recorded"
_assert_contains "$OUT_B" "gate-result task/DP-aa-caught: PASS" "AC9: green branch gate PASS recorded"
_assert_contains "$OUT_B" "=== auto-pass drain ===" "AC9: run mode prints auto-pass drain section"
_assert_contains "$OUT_B" "auto-pass-drain-count=1" "AC9: exactly one surfaced failure drained"
_assert_contains "$OUT_B" "AUTO_PASS_DRAIN branch=task/DP-cc-red work_item=DP" \
  "AC9: surfaced failure appears in machine-readable drain list"
_assert_not_contains "$OUT_B" "AUTO_PASS_DRAIN branch=task/DP-aa-caught" \
  "AC9: green branch must NOT appear in drain list"
# run mode 對 stub 同時呼叫 emit（分類）與 run（gate）。
_assert_contains "$(cat "$LOG_B")" "stub run" "AC9: run mode invoked stub --run"

# ===========================================================================
# Case C — --migrate-evidence：head/PASS 寫進 fixture task.md delivery block。
# ===========================================================================
REPO_C="$TMPROOT/repo-c"
setup_fixture_repo "$REPO_C"
STUB_C="$TMPROOT/stub-c.sh"
make_stub_affected_runner "$STUB_C"
LOG_C="$TMPROOT/stub-c.log"
: >"$LOG_C"

MIGRATE_TASK_MD="$REPO_C/docs-manager/src/content/docs/specs/design-plans/DP-dd/tasks/T1/index.md"
HEAD_DD="$(git -C "$REPO_C" rev-parse task/DP-dd-migrate)"

OUT_C="$(env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT \
  STUB_AFFECTED_LOG="$LOG_C" \
  BRANCH_SWEEP_AFFECTED_RUNNER="$STUB_C" \
  bash "$RUNNER" --repo "$REPO_C" --base main --run --migrate-evidence 2>&1)" || true

_assert_contains "$OUT_C" "evidence-migration migrated (task/DP-dd-migrate)" \
  "AC9: evidence migration ran for the resolvable branch"
# 讀回 fixture task.md：head_sha 應被 write-deliverable.sh 更新成 branch head。
TASK_MD_AFTER="$(cat "$MIGRATE_TASK_MD")"
_assert_contains "$TASK_MD_AFTER" "head_sha: $HEAD_DD" \
  "AC9: head written into FIXTURE task.md delivery block (not live specs)"
_assert_contains "$TASK_MD_AFTER" "pr_url: https://github.com/exampleco/exampleco-framework/pull/777" \
  "AC9: deliverable pr_url preserved in fixture task.md"

# ===========================================================================
# Case D — fail-closed: 缺 git => POLARIS marker（negative assertion）。
#   用一個 PATH 內無 git 的環境跑 runner，斷言 POLARIS_TOOL_MISSING + 非 0 exit。
# ===========================================================================
REPO_D="$TMPROOT/repo-d"
setup_fixture_repo "$REPO_D"
EMPTY_BIN="$TMPROOT/empty-bin"
mkdir -p "$EMPTY_BIN"
# 提供 bash（runner 自身需要）但不提供 git，模擬 git 缺席。
ln -sf "$(command -v bash)" "$EMPTY_BIN/bash"
ln -sf "$(command -v env)" "$EMPTY_BIN/env" 2>/dev/null || true
set +e
OUT_D="$(PATH="$EMPTY_BIN" env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT \
  bash "$RUNNER" --repo "$REPO_D" --base main 2>&1)"
D_EXIT=$?
set -e
_assert_contains "$OUT_D" "POLARIS_TOOL_MISSING:git" "AC9: missing git fail-stops with POLARIS_TOOL_MISSING"
_assert_eq "$([[ "$D_EXIT" -ne 0 ]] && echo nonzero || echo zero)" "nonzero" \
  "AC9: missing git yields non-zero exit (fail-closed)"

# ===========================================================================
# Case E — fail-closed: 缺 affected-runner => POLARIS marker（negative assertion）。
# ===========================================================================
REPO_E="$TMPROOT/repo-e"
setup_fixture_repo "$REPO_E"
set +e
OUT_E="$(env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT \
  BRANCH_SWEEP_AFFECTED_RUNNER="$TMPROOT/no-such-affected-runner.sh" \
  bash "$RUNNER" --repo "$REPO_E" --base main 2>&1)"
E_EXIT=$?
set -e
_assert_contains "$OUT_E" "POLARIS_BRANCH_SWEEP_AFFECTED_RUNNER_MISSING" \
  "AC9: missing affected-runner fail-stops with POLARIS marker"
_assert_eq "$([[ "$E_EXIT" -ne 0 ]] && echo nonzero || echo zero)" "nonzero" \
  "AC9: missing affected-runner yields non-zero exit (fail-closed)"

# ---------------------------------------------------------------------------
printf '\n=== branch-sweep-runner selftest ===\n'
printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
