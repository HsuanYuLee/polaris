#!/usr/bin/env bash
# run-selftests.sh — 跑 selftest，範圍由「動到了哪幾支 skill」決定。
#
# 為什麼需要這一支：2026-08-10 量到 `.github/workflows/ci.yml` 從來沒有跑過一次
# （`actions/workflows/{id}/runs` 回 `total_count=0`，釋出的那個 commit 上 0 個 check-run），
# 而它是全 repo 唯一會跑 selftest 的地方。33 支 selftest 當時沒有任何執行者——
# `gate-prose-matches-behaviour-selftest.sh` 就這樣紅著跟 v4.17.0 一起出去。
#
# 全套 68.6 秒，每個 commit 跑它會被學會跳過。但按動到的 skill 切之後，一次 commit 通常
# 只碰一兩支——而「各 skill 自己帶著自己的東西」正是這件事成立的原因。
#
# Usage: run-selftests.sh --repo <工作區> [--all | --staged | --changed <路徑>...]
#          --all      全部。pre-push 用這個。
#          --staged   staged 的改動動到哪幾支 skill，就跑那幾支。pre-commit 用這個。
#          --changed  自己指定路徑，行為與 --staged 相同。
# Exit:  0 都過 / 1 有紅的 / 2 量不到（範圍算不出來、或該跑的檔案讀不到）

set -uo pipefail

PREFIX="[polaris run-selftests]"
REPO_ROOT=""
MODE=""
CHANGED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --all) MODE=all; shift ;;
    --staged) MODE=staged; shift ;;
    --changed) MODE=changed; shift; while [[ $# -gt 0 && "$1" != --* ]]; do CHANGED+=("$1"); shift; done ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE \
  git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
[[ -n "$MODE" ]] || MODE=all

SKILLS_DIR="$REPO_ROOT/.claude/skills"
if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "$PREFIX 量不到：$SKILLS_DIR 不存在——根可能解錯了。空掃回綠比紅還糟。" >&2
  exit 2
fi

if [[ "$MODE" == staged ]]; then
  # 不用 mapfile：macOS 內建的是 bash 3.2，沒有它。一支 hook 要能在使用者真的那台跑。
  staged_list="$(env -u GIT_DIR -u GIT_WORK_TREE \
    git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR)" || {
    echo "$PREFIX 量不到：問不出 staged 的檔案。" >&2; exit 2; }
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHANGED+=("$line")
  done <<< "$staged_list"
fi

# Description: 一條 repo 相對路徑屬於哪一支 skill。公司 skill 多包一層，那一層也算。
# Args: $1 = repo 相對路徑
# Outputs: skill 名（`framework-release` 或 `{公司}/{名字}`），不屬於任何一支就不輸出。
skill_of() {
  local rel="${1#.claude/skills/}"
  [[ "$rel" != "$1" ]] || return 0
  local first="${rel%%/*}" rest="${rel#*/}"
  local second="${rest%%/*}"
  if [[ "$rest" != "$rel" && -f "$SKILLS_DIR/$first/$second/SKILL.md" ]]; then
    echo "$first/$second"
  else
    echo "$first"
  fi
}

TARGETS=()
OUTSIDE=0
if [[ "$MODE" == all ]]; then
  TARGETS=("$SKILLS_DIR")
else
  declare -a seen=()
  for path in ${CHANGED+"${CHANGED[@]}"}; do
    skill="$(skill_of "$path")"
    if [[ -z "$skill" ]]; then OUTSIDE=$((OUTSIDE + 1)); continue; fi
    [[ -d "$SKILLS_DIR/$skill" ]] || continue   # 被刪掉的 skill 沒有東西可跑
    for s in ${seen+"${seen[@]}"}; do [[ "$s" == "$skill" ]] && continue 2; done
    seen+=("$skill")
    TARGETS+=("$SKILLS_DIR/$skill")
  done
fi

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  echo "$PREFIX 這次的改動沒有動到任何一支 skill（另有 ${OUTSIDE} 個改動落在 skill 目錄外，" \
       "那些由閘掃全樹負責）。沒有 selftest 要跑。"
  exit 0
fi

# 樣式是 `*-selftest.sh`，不是 `*selftest*.sh`。後者會比中**這支腳本自己**——它拿沒有參數
# 的自己再跑一次，預設 `--all`，於是無限遞迴。全 repo 34 支 selftest 都叫 `X-selftest.sh`，
# 這個樣式一支都沒少比到。
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find "${TARGETS[@]}" -name '*-selftest.sh' -not -path '*/node_modules/*' | sort)

RAN=0
FAILED=()
UNREADABLE=()
for f in ${FILES+"${FILES[@]}"}; do
  if [[ ! -r "$f" ]]; then UNREADABLE+=("$f"); continue; fi
  RAN=$((RAN + 1))
  # `env -u` 不是保險，是必要條件。git 跑 hook 時環境裡有 GIT_DIR，而 selftest 幾乎都會
  # `git init` 一棵臨時的 fixture 樹——那些 git 指令會照著 GIT_DIR 走，於是動到的是**真的
  # repo**。2026-08-10 實測：這一步漏掉的時候，一次 pre-commit 把工作區的索引從 499 個檔
  # 清成 2 個，並且把 `core.bare=true` 寫進了真的 .git/config。
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash "$f" >/dev/null 2>&1 || FAILED+=("$f")
done

# 該跑的與真的跑了的對不上，就是量不到——不是通過。一支讀不到的 selftest 安靜地被跳過，
# 跟它綠了在輸出上長得一樣。
if [[ "${#UNREADABLE[@]}" -gt 0 ]]; then
  echo "$PREFIX 量不到：${#UNREADABLE[@]} 支 selftest 讀不到——" >&2
  printf '  %s\n' "${UNREADABLE[@]}" >&2
  exit 2
fi

scope="全部"
[[ "$MODE" == all ]] || scope="${#TARGETS[@]} 支動到的 skill"
echo "$PREFIX 範圍：${scope}，跑了 ${RAN} 支 selftest，紅 ${#FAILED[@]} 支。"

if [[ "${#FAILED[@]}" -gt 0 ]]; then
  printf '%s\n' "$PREFIX 紅的是這幾支，各自跑一次看訊息：" >&2
  printf '  bash %s\n' "${FAILED[@]}" >&2
  exit 1
fi
