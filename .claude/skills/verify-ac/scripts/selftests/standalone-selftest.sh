#!/usr/bin/env bash
# Purpose: 這支 skill 被單獨下載到一個只有它自己的地方，還跑得動。
# Inputs:  把整個 skill 目錄複製到 mktemp 底下——沒有這個 repo、沒有 .claude/rules/、
#          沒有姊妹 skill、不是 git repo。反向對照組用的 fixture 也在 mktemp 底下。
# Outputs: PASS 當一支「伸手到姊妹 skill」的假 skill 在那裡變紅，而這支 skill 自己
#          每一支 selftest 都還是綠的。
#
# 為什麼要這一支：`scope: standalone` 是一句宣告，而宣告不會自己成立。一個指向
# `.claude/skills/別支/...` 或指向這個 repo 某個位置的引用，在這裡永遠是綠的，到了
# claude.ai 或 Cowork 就是一個不存在的路徑——而那時候沒有人在看。
#
# 搬過去之後排除自己（照名字），不然複製過去的那一份會再複製一次，一路遞迴下去。這是
# 唯一的一個排除，而且就寫在這裡。

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SELF="$(basename "$0")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

# Description: 把一個 skill 目錄搬到一個跟這個 repo 無關的地方，跑它自己的每一支
#   selftest。結果放進 RC（0 全綠 / 1 有紅的 / 2 一支都沒找到），訊息放進 OUT。
# Args: $1 = skill 目錄, $2 = 這一趟的名字
run_away() {
  local src="$1" label="$2" ran=0 red=() log away
  away="$WORK/$label/$(basename "$src")"
  mkdir -p "$(dirname "$away")"
  cp -R "$src" "$away"
  find "$away" -name '__pycache__' -type d -prune -exec rm -rf {} +
  rm -f "$away/scripts/selftests/$SELF"
  for selftest in "$away/scripts/selftests"/*-selftest.sh; do
    [[ -f "$selftest" ]] || continue
    ran=$((ran + 1))
    log="$WORK/$label.$ran.out"
    bash "$selftest" >"$log" 2>&1 || red+=("$(basename "$selftest"): $(tail -1 "$log")")
  done
  if [[ "$ran" -eq 0 ]]; then
    RC=2; OUT="空跑：搬過去之後一支 selftest 都沒找到，這不是「都會過」"; return
  fi
  if [[ ${#red[@]} -gt 0 ]]; then
    RC=1; OUT="${#red[@]} 支變紅：$(printf '%s；' "${red[@]}")"; return
  fi
  RC=0; OUT="搬過去之後 $ran 支 selftest 都還是綠的"
}

echo "standalone selftest"

# 反向對照組：一支伸手到姊妹 skill 的假 skill。它在這個 repo 裡是綠的，搬走就不是——那正是
# 這一支要抓的形狀，而且抓得到才有資格說下面那句「這支 skill 是綠的」。
FAKE="$WORK/fixture-src/reaches-out"
mkdir -p "$FAKE/scripts/selftests"
# 伸手的寫法就是這一種：從自己的位置往上走兩層，去拿姊妹 skill 的東西。在這個 repo 裡
# 那個位置有東西，搬到別的地方就沒有——而絕對路徑不算，它搬到哪裡都還指得到這台機器。
printf '#!/usr/bin/env bash\nset -e\ntest -f "$(dirname "$0")/../../../refinement/SKILL.md"\necho ok\n' \
  > "$FAKE/scripts/selftests/reach-selftest.sh"
run_away "$FAKE" fixture
[[ "$RC" -eq 1 ]] || fail "伸手到姊妹 skill 的假 skill 應該在別的地方變紅；拿到 ${RC}：$OUT"
ok "伸手到姊妹 skill 的東西，搬走之後會紅"

# 一支 selftest 都沒有的目錄是量不到，不是「都會過」。
mkdir -p "$WORK/fixture-empty/empty/scripts/selftests"
run_away "$WORK/fixture-empty/empty" fixture-empty
[[ "$RC" -eq 2 ]] || fail "沒有 selftest 應該是量不到；拿到 ${RC}：$OUT"
ok "一支都沒找到是量不到，不是綠的"

# 真的那一支。
run_away "$SKILL_DIR" real
[[ "$RC" -eq 0 ]] || fail "$OUT"
ok "只有這支 skill 自己的時候，$OUT"

echo "PASS: standalone（$PASS 項；搬過去之後排除 $SELF 自己，不然會遞迴）"
