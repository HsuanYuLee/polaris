#!/usr/bin/env bash
# Purpose: Branch-sweep runner (DP-360 D10 / AC9). 對 workspace 內現有 active
#          `task/*` branch head 跑「新的 affected-scoped gate」
#          (scripts/selftest-affected-runner.sh)，產出 hit-rate 報告——
#          affected 接住 (affected-caught) vs 漏到 full 才爆 (leaked-to-full)——
#          並把 surfaced 失敗轉成一份 `/auto-pass` drain 清單供下游 intake 消費。
#          同時作為 marker -> task.md evidence 的 migration 載具：在 --run mode
#          下某 branch 的 affected gate 全綠且能解析到 task.md 時，可選擇性
#          (--migrate-evidence) 透過既有 canonical writer
#          (scripts/write-deliverable.sh) 把交付 head/PASS 寫回該 task.md 的
#          delivery block，不手寫 frontmatter。
#
#          本 runner 不重做 changed->affected 的 mapping：closure 計算一律委派
#          selftest-affected-runner.sh（單一 classifier，D8）。它也 NEVER 直接
#          shell out 到 run-aggregate-selftests.sh / check-framework-pr-gate.sh
#          ——只呼叫 affected-runner，由 affected-runner 自己決定 emit/run，並在
#          change set escalate 時印出 / 比對 full-corpus sentinel。
#
# Inputs:  [--repo <path>]          workspace root（預設 cwd）。用來列 branch head
#                                   與算每個 branch 的 changed files。
#          [--base <ref>]           每個 branch 的 diff base（預設 main）。
#          [--branch-prefix <p>]    只掃 `<p>*` 的 branch（預設 task/）。
#          [--run]                  RUN MODE：除了分類外，對每個 branch 額外跑
#                                   affected-runner --run 記 pass/fail。預設只 emit
#                                   分類（不執行 gate）。
#          [--migrate-evidence]     RUN MODE 下，對 affected gate 全綠且可解析到
#                                   task.md（且該 task.md 已有 deliverable.pr_url）
#                                   的 branch，把 head/PASS 寫回 task.md delivery
#                                   block（經 write-deliverable.sh）。
#          env BRANCH_SWEEP_AFFECTED_RUNNER  覆寫 affected-runner 路徑（selftest
#                                   用來注入 stub，使真實 corpus 不被觸發）。
#          env BRANCH_SWEEP_WRITE_DELIVERABLE  覆寫 write-deliverable.sh 路徑。
# Outputs: stdout — hit-rate 報告（穩定、greppable 格式）+ `/auto-pass` drain 清單。
#          exit 0 PASS、1 failure（emit/run 中有 surfaced failure 仍視為成功掃描，
#          以 report 呈現；exit 1 僅保留給 sweep 自身執行錯誤）、2 usage / contract。
# Side effects: --migrate-evidence 下對 fixture/live task.md 經 write-deliverable.sh
#          寫 delivery block；其餘為 read-only。
set -euo pipefail

# --- Named constants ---------------------------------------------------------
# affected-runner 在 change set escalate 到 full corpus 時印出的 sentinel。與
# selftest-affected-runner.sh 的 FULL_CORPUS_SENTINEL 必須字面一致；本 runner 只
# 比對、不重算 escalation 判斷。
readonly FULL_CORPUS_SENTINEL="POLARIS_AFFECTED_FULL_CORPUS"

# Hit-rate bucket 標籤：穩定、greppable，下游 report parser 依賴這兩個 token。
readonly BUCKET_AFFECTED_CAUGHT="affected-caught"
readonly BUCKET_LEAKED_TO_FULL="leaked-to-full"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO_DIR="$(pwd)"
BASE_REF="main"
BRANCH_PREFIX="task/"
RUN_MODE=0
MIGRATE_EVIDENCE=0

# affected-runner / write-deliverable 路徑（env 覆寫供 selftest 注入 stub）。
AFFECTED_RUNNER="${BRANCH_SWEEP_AFFECTED_RUNNER:-$ROOT_DIR/scripts/selftest-affected-runner.sh}"
WRITE_DELIVERABLE="${BRANCH_SWEEP_WRITE_DELIVERABLE:-$ROOT_DIR/scripts/write-deliverable.sh}"

# die — 印 POLARIS_* contract error 到 stderr 後 exit 2（usage / contract 違反）。
# Args: $1 = 訊息。Side effects: exit 2。
die() {
  printf '%s\n' "$1" >&2
  exit 2
}

# require_tool — 缺 Polaris-runtime binary 時 fail-stop（不靜默安裝）。
# Args: $1 = tool 名。Side effects: 缺工具時 exit 2 + POLARIS_TOOL_MISSING。
require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'POLARIS_TOOL_MISSING:%s — run `mise install` to restore the Polaris runtime toolchain\n' "$tool" >&2
    exit 2
  fi
}

# --- Arg parsing -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "POLARIS_BRANCH_SWEEP_ARG: --repo requires a value"
      REPO_DIR="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || die "POLARIS_BRANCH_SWEEP_ARG: --base requires a value"
      BASE_REF="$2"
      shift 2
      ;;
    --branch-prefix)
      [[ $# -ge 2 ]] || die "POLARIS_BRANCH_SWEEP_ARG: --branch-prefix requires a value"
      BRANCH_PREFIX="$2"
      shift 2
      ;;
    --run)
      RUN_MODE=1
      shift
      ;;
    --migrate-evidence)
      MIGRATE_EVIDENCE=1
      shift
      ;;
    -h | --help)
      sed -n '2,40p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      die "POLARIS_BRANCH_SWEEP_ARG: unknown argument: $1"
      ;;
  esac
done

# --- Tool / input preflight (fail-closed) ------------------------------------
require_tool git
[[ -d "$REPO_DIR" ]] || die "POLARIS_BRANCH_SWEEP_REPO_MISSING: repo not found: $REPO_DIR"
REPO_DIR="$(cd "$REPO_DIR" && pwd)"
# affected-runner 是本 runner 的硬依賴：缺了就 fail-stop（不能假裝全部 leaked）。
[[ -f "$AFFECTED_RUNNER" ]] \
  || die "POLARIS_BRANCH_SWEEP_AFFECTED_RUNNER_MISSING: $AFFECTED_RUNNER (set BRANCH_SWEEP_AFFECTED_RUNNER or restore the T3 affected-runner)"

# --migrate-evidence 只在 --run mode 有意義（需要先確認 gate 全綠才寫 PASS）。
if [[ "$MIGRATE_EVIDENCE" -eq 1 && "$RUN_MODE" -eq 0 ]]; then
  die "POLARIS_BRANCH_SWEEP_ARG: --migrate-evidence requires --run (evidence migration only after a green gate)"
fi

# --- Helpers -----------------------------------------------------------------

# list_active_branches — 列出符合 --branch-prefix 的 local branch short name。
# 用 git for-each-ref（穩定機械輸出），輸出每行一個 short name。
# Args: 無（讀 REPO_DIR / BRANCH_PREFIX）。Side effects: 無（read-only）。
list_active_branches() {
  git -C "$REPO_DIR" for-each-ref --format='%(refname:short)' \
    "refs/heads/${BRANCH_PREFIX}*" 2>/dev/null || true
}

# changed_files_for_branch — 印出某 branch head 相對 BASE_REF 的 changed file
# 清單（一行一路徑）。用 three-dot diff（merge-base...head）對齊 affected-runner
# 對「branch 帶進來的 change set」的語意。Args: $1 = branch short name。
# Side effects: 無（read-only）。
changed_files_for_branch() {
  local branch="$1"
  git -C "$REPO_DIR" diff --name-only "${BASE_REF}...${branch}" 2>/dev/null || true
}

# classify_branch — 把某 branch 的 changed set 餵給 affected-runner --emit，
# 依輸出判定 hit-rate bucket。印一行 `<bucket> <branch> <detail>`：
#   - full-corpus sentinel 出現  -> leaked-to-full（只有 DP-iteration / release
#                                   backstop 會接住）
#   - 非空 concrete affected set -> affected-caught（push 時會跑的具體 subset）
#   - 空 set（無 changed files / 無 closure）-> affected-caught，detail=empty
# Args: $1 = branch short name。回傳 bucket 透過 stdout 第一個 token。
# Side effects: 呼叫 affected-runner --emit（read-only closure 計算）。
classify_branch() {
  local branch="$1"
  local changed affected rc
  changed="$(changed_files_for_branch "$branch")"

  if [[ -z "$changed" ]]; then
    # 無 changed files：沒有 push delta，視為 affected-caught（empty closure）。
    printf '%s %s %s\n' "$BUCKET_AFFECTED_CAUGHT" "$branch" "no-changed-files"
    return 0
  fi

  # affected-runner --emit：印 affected set，或在 escalate 時印 full-corpus sentinel。
  # 空 change set 會被 affected-runner fail-closed（exit 2），但這裡 changed 非空。
  set +e
  affected="$(printf '%s\n' "$changed" | bash "$AFFECTED_RUNNER" --root "$REPO_DIR" --emit 2>/dev/null)"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    # affected-runner 自身錯誤（malformed source 等）-> 不靜默吞，標 leaked-to-full
    # 並附 detail，讓 report reader 看得到 closure 無法計算（保守歸到 backstop）。
    printf '%s %s %s\n' "$BUCKET_LEAKED_TO_FULL" "$branch" "affected-runner-error-rc${rc}"
    return 0
  fi

  if printf '%s\n' "$affected" | grep -qF "$FULL_CORPUS_SENTINEL"; then
    printf '%s %s %s\n' "$BUCKET_LEAKED_TO_FULL" "$branch" "full-corpus-sentinel"
    return 0
  fi

  # 具體 affected subset（可能多行）；detail 記 member 數量。
  local count
  count="$(printf '%s\n' "$affected" | grep -cv '^$' || true)"
  printf '%s %s affected-members=%s\n' "$BUCKET_AFFECTED_CAUGHT" "$branch" "$count"
}

# run_gate_for_branch — RUN MODE：對某 branch changed set 跑 affected-runner --run。
# 回傳 affected-runner 的 exit code（0 green / 1 red / 2 error）。對 leaked-to-full
# branch，affected-runner --run 會自行 delegate 到 backstop——本 runner 不另外
# shell out 任何 corpus runner。Args: $1 = branch short name。
# Side effects: 執行 affected gate（可能執行 selftest，但 corpus 由 affected-runner
# 自己決定 emit/run）。
run_gate_for_branch() {
  local branch="$1"
  local changed rc
  changed="$(changed_files_for_branch "$branch")"
  [[ -n "$changed" ]] || return 0 # 無 changed 無需跑 gate，視為綠。
  set +e
  printf '%s\n' "$changed" | bash "$AFFECTED_RUNNER" --root "$REPO_DIR" --run >/dev/null 2>&1
  rc=$?
  set -e
  return "$rc"
}

# resolve_task_md_for_branch — 嘗試把 branch 對應到單一 task.md。用最小的、
# branch-name 對齊的解析：task/<id>-... 取 <id>，找含該 id 的 tasks/*/index.md
# 或 task.md。回傳 task.md 絕對路徑（找不到 / 多重命中時印空字串）。
# Args: $1 = branch short name。Side effects: 無（read-only find）。
resolve_task_md_for_branch() {
  local branch="$1"
  local id matches
  # task/<id>-desc -> <id>（去掉 prefix 與第一個 '-' 之後的描述）。
  id="${branch#"$BRANCH_PREFIX"}"
  id="${id%%-*}"
  [[ -n "$id" ]] || { printf '' ; return 0; }
  # 找路徑含 <id> 的 task index.md / task.md（限縮在 specs 樹下）。
  matches="$(find "$REPO_DIR" -type f \( -name 'index.md' -o -name 'task.md' \) \
    -path '*/tasks/*' 2>/dev/null | grep -F "$id" || true)"
  # 僅在唯一命中時回傳（多重命中 -> fail-closed 不猜）。
  if [[ "$(printf '%s\n' "$matches" | grep -cv '^$' || true)" == "1" ]]; then
    printf '%s\n' "$matches"
  else
    printf ''
  fi
}

# task_deliverable_pr_url — 從 task.md frontmatter 讀 deliverable.pr_url（巢狀
# key），找不到回空字串。Args: $1 = task.md 路徑。Side effects: 無（read-only）。
task_deliverable_pr_url() {
  local file="$1"
  [[ -f "$file" ]] || { printf '' ; return 0; }
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && /^deliverable:/ { in_deliverable = 1; next }
    in_fm && in_deliverable && /^[[:space:]]+pr_url:/ {
      line = $0
      sub(/^[[:space:]]+pr_url:[[:space:]]*/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
    in_fm && in_deliverable && /^[^[:space:]]/ { in_deliverable = 0 }
  ' "$file"
}

# migrate_evidence_for_branch — 把交付 head/PASS 寫回 branch 對應 task.md 的
# delivery block，經唯一 canonical writer write-deliverable.sh（不手寫 frontmatter）。
# 僅在能解析到單一 task.md 且該 task.md 已有 deliverable.pr_url 時動作。
# Args: $1 = branch short name。印一行 migration 結果（migrated / skipped）。
# Side effects: 經 write-deliverable.sh 改寫 task.md delivery block。
migrate_evidence_for_branch() {
  local branch="$1"
  local task_md pr_url head_sha
  task_md="$(resolve_task_md_for_branch "$branch")"
  if [[ -z "$task_md" ]]; then
    printf '  evidence-migration skipped (%s): no single task.md resolved\n' "$branch"
    return 0
  fi
  pr_url="$(task_deliverable_pr_url "$task_md")"
  if [[ -z "$pr_url" ]]; then
    printf '  evidence-migration skipped (%s): task.md has no deliverable.pr_url\n' "$branch"
    return 0
  fi
  head_sha="$(git -C "$REPO_DIR" rev-parse "$branch" 2>/dev/null || true)"
  if [[ -z "$head_sha" ]]; then
    printf '  evidence-migration skipped (%s): unable to resolve branch head\n' "$branch"
    return 0
  fi
  [[ -f "$WRITE_DELIVERABLE" ]] \
    || die "POLARIS_BRANCH_SWEEP_WRITE_DELIVERABLE_MISSING: $WRITE_DELIVERABLE"
  # write-deliverable.sh 是 task.md delivery block 的 canonical writer：寫
  # pr_url + pr_state(OPEN) + head_sha；PASS 由「gate 全綠才呼叫本 function」表達。
  if bash "$WRITE_DELIVERABLE" "$task_md" "$pr_url" "OPEN" "$head_sha" >/dev/null 2>&1; then
    printf '  evidence-migration migrated (%s): head=%s PASS -> %s\n' \
      "$branch" "$head_sha" "$task_md"
  else
    printf '  evidence-migration failed (%s): write-deliverable.sh non-zero\n' "$branch"
  fi
}

# --- Sweep -------------------------------------------------------------------
declare -a BRANCHES=()
while IFS= read -r b; do
  [[ -n "$b" ]] && BRANCHES+=("$b")
done < <(list_active_branches)

printf 'branch-sweep-runner — repo: %s base: %s prefix: %s mode: %s\n' \
  "$REPO_DIR" "$BASE_REF" "$BRANCH_PREFIX" \
  "$([[ "$RUN_MODE" -eq 1 ]] && echo run || echo emit)"
printf 'active branches: %d\n' "${#BRANCHES[@]}"

affected_caught=0
leaked_to_full=0
declare -a DRAIN_QUEUE=()

for branch in "${BRANCHES[@]}"; do
  line="$(classify_branch "$branch")"
  bucket="${line%% *}"
  printf '%s\n' "$line"
  case "$bucket" in
    "$BUCKET_AFFECTED_CAUGHT") affected_caught=$((affected_caught + 1)) ;;
    "$BUCKET_LEAKED_TO_FULL") leaked_to_full=$((leaked_to_full + 1)) ;;
  esac

  if [[ "$RUN_MODE" -eq 1 ]]; then
    if run_gate_for_branch "$branch"; then
      printf '  gate-result %s: PASS\n' "$branch"
      # gate 全綠且要求 evidence migration -> 寫回 task.md delivery block。
      if [[ "$MIGRATE_EVIDENCE" -eq 1 ]]; then
        migrate_evidence_for_branch "$branch"
      fi
    else
      printf '  gate-result %s: FAIL\n' "$branch"
      # surfaced failure -> 進 /auto-pass drain 清單（branch + 對應 task.md 若可解析）。
      DRAIN_QUEUE+=("$branch")
    fi
  fi
done

# --- Hit-rate report ---------------------------------------------------------
printf '=== hit-rate report ===\n'
printf 'hit-rate %s=%d %s=%d total=%d\n' \
  "$BUCKET_AFFECTED_CAUGHT" "$affected_caught" \
  "$BUCKET_LEAKED_TO_FULL" "$leaked_to_full" \
  "${#BRANCHES[@]}"

# --- /auto-pass drain list ---------------------------------------------------
# 穩定、machine-readable 清單：每行一個 surfaced 失敗的 branch（+ 解析到的
# work-item id），供下游 `/auto-pass` intake 消費。本 runner 不 invoke /auto-pass。
printf '=== auto-pass drain ===\n'
if [[ "$RUN_MODE" -eq 1 ]]; then
  printf 'auto-pass-drain-count=%d\n' "${#DRAIN_QUEUE[@]}"
  for branch in "${DRAIN_QUEUE[@]}"; do
    id="${branch#"$BRANCH_PREFIX"}"
    id="${id%%-*}"
    printf 'AUTO_PASS_DRAIN branch=%s work_item=%s\n' "$branch" "$id"
  done
else
  printf 'auto-pass-drain-count=0 (emit mode — gate not executed)\n'
fi

exit 0
