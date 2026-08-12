#!/usr/bin/env bash
# gate-skill-script-references.sh 的 selftest。
#
# 正負兩向都要驗：只驗「乾淨的 repo 會綠」的話，一支永遠回 0 的閘也會全綠。
#
# DP-513 把管轄從「同目錄與四個子目錄、限 .sh/.py/.mjs」放寬成「值追得回這支腳本自己位置的
# 變數算起、任何具名的目標」。放寬之後每一類都要有正反兩例，因為**這道閘現在會判的東西比它
# 以前多**，而多出來的每一類都可能噴假紅——一道會噴假紅的閘會在幾次之後被關掉，那比看不見更糟。
#
# **有兩類真樹上沒有實例**，只能靠 fixture 驗，寫在這裡免得下一站把「真樹綠了」讀成驗過了：
#   - 兩個以上不同目標的候選群組，全部落空（樹上唯一的兩組就是這一輪修掉的 fetch-pr-info）。
#   - 同上，但至少一條命中。
# 單一目標的候選群組真樹上有 4 組（`polaris-doctor.sh` 那種先問再用），全部命中；而它們
# 落空的那一格不判定，理由寫在下面那一格自己的註解裡。

set -uo pipefail

GATE="$(cd "$(dirname "$0")/.." && pwd)/gate-skill-script-references.sh"
WORK="$(mktemp -d -t polaris-gate-refs-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# Description: 比對實際 exit code 與期望值，印一行結果。
# Args: $1 = actual, $2 = expected, $3 = case name
assert_eq() {
  if [[ "$1" == "$2" ]]; then
    echo "  ok  $3"; pass=$((pass + 1))
  else
    echo "  FAIL $3 — want=$2 got=$1"; fail=$((fail + 1))
  fi
}

# Description: 造一個只有 .claude/skills/ 的最小 repo。
# Args: $1 = repo path
make_repo() {
  local repo="$1"
  mkdir -p "$repo/.claude/skills/probe/scripts/lib"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
}

# Description: 跑閘，把 exit code 放進 $rc、合併輸出放進 $out。
# Args: $@ = 傳給閘的參數
run_gate() {
  out="$(bash "$GATE" "$@" 2>&1)"; rc=$?
}

repo="$WORK/clean"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/main.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/helper.sh"
. "$SCRIPT_DIR/lib/shared.sh"
EOF
touch "$repo/.claude/skills/probe/scripts/helper.sh" \
      "$repo/.claude/skills/probe/scripts/lib/shared.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" "0" "引用都在時回 0"

# 反例一：同目錄的檔案不見了
rm "$repo/.claude/skills/probe/scripts/helper.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm "drop helper"
run_gate --repo "$repo"
assert_eq "$rc" "1" "同目錄引用斷掉時回 1"
printf '%s' "$out" | grep -q 'helper.sh'
assert_eq "$?" "0" "訊息指名斷掉的那個檔"

# 反例二：lib/ 底下的檔案不見了
repo2="$WORK/broken-lib"
make_repo "$repo2"
cat > "$repo2/.claude/skills/probe/scripts/main.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/tool-resolution.sh"
EOF
git -C "$repo2" add -A && git -C "$repo2" commit -qm init
run_gate --repo "$repo2"
assert_eq "$rc" "1" "lib/ 引用斷掉時回 1"

# 未被版控的檔案不算——閘看的是會被送出去的東西
repo3="$WORK/untracked"
make_repo "$repo3"
touch "$repo3/.claude/skills/probe/scripts/placeholder.sh"
git -C "$repo3" add -A && git -C "$repo3" commit -qm init
cat > "$repo3/.claude/skills/probe/scripts/scratch.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/nowhere.sh"
EOF
run_gate --repo "$repo3"
assert_eq "$rc" "0" "未版控的檔案不參與判定"

# heredoc 裡的東西是要寫到別處的資料，不是這個檔自己的引用——不排掉的話這道閘會擋下
# 自己的 selftest。
repo4="$WORK/heredoc"
make_repo "$repo4"
cat > "$repo4/.claude/skills/probe/scripts/writer.sh" <<'OUTER'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat > /tmp/generated.sh <<'INNER'
bash "$SCRIPT_DIR/does-not-exist.sh"
INNER
OUTER
git -C "$repo4" add -A && git -C "$repo4" commit -qm init
run_gate --repo "$repo4"
assert_eq "$rc" "0" "heredoc 內容不算這個檔的引用"

echo ""

# 變數用 `/..` 定義時，指的是上一層，不是自己那一層。selftest 幾乎都長這樣。
# 這一版之前會把一批寫得完全正確的 selftest 判紅，而那個錯誤被一份重複的檔遮著。
repo="$WORK/parentdir_ok"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/probe/scripts/selftests"
cat > "$repo/.claude/skills/probe/scripts/selftests/x-selftest.sh" <<'EOF'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$script_dir/resolver.sh"
EOF
touch "$repo/.claude/skills/probe/scripts/resolver.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "變數帶 /.. 時往上一層解析，正確的引用不判紅"

# 但往上退之後還是找不到的，仍然要紅——修掉假紅不可以順手修成瞎的。
repo="$WORK/parentdir_broken"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/probe/scripts/selftests"
cat > "$repo/.claude/skills/probe/scripts/selftests/x-selftest.sh" <<'EOF'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$script_dir/gone.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 1 "往上退之後仍然不存在的引用，還是要紅"

echo ""

# ── A-P1：跨目錄的具名引用進得了管轄（放寬之前這一整類是隱形的）────────────
repo="$WORK/crossdir_ok"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/other/scripts"
touch "$repo/.claude/skills/other/scripts/tool.sh"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/../../other/scripts/tool.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "跨目錄引用指到存在的東西 → 綠"

repo="$WORK/crossdir_broken"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/../../other/scripts/tool.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 1 "跨目錄引用指到不存在的東西 → 紅"
printf '%s' "$out" | grep -q 'other/scripts/tool.sh'
assert_eq "$?" 0 "訊息指名那條跨目錄的引用"

# ── A-P5：目標是目錄、或是散文，一樣算 ───────────────────────────────
repo="$WORK/dir_target"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/other/scripts"
touch "$repo/.claude/skills/other/scripts/keep.sh"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/../../other/scripts"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "目標是存在的目錄 → 綠"

rm -rf "$repo/.claude/skills/other"
git -C "$repo" add -A && git -C "$repo" commit -qm "drop dir"
run_gate --repo "$repo"
assert_eq "$rc" 1 "目標是不存在的目錄 → 紅（沒有副檔名不是放它過的理由）"

repo="$WORK/md_target"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/../references/context.md"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 1 "目標是不存在的 .md → 紅"
mkdir -p "$repo/.claude/skills/probe/references"
touch "$repo/.claude/skills/probe/references/context.md"
git -C "$repo" add -A && git -C "$repo" commit -qm "add md"
run_gate --repo "$repo"
assert_eq "$rc" 0 "那份 .md 補上之後 → 綠"

# ── A-P2：純往上爬沒有指名任何東西，不判定 ───────────────────────────
# `$X/../..` 一定指得到工作區的某一層，對它做存在性檢查永遠是綠的。判它等於量了一個
# 恆真的東西，而那會讓「判了幾條」這個數字說謊。
repo="$WORK/pure_ascent"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/../../.."
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "純往上爬不判定 → 綠"
printf '%s' "$out" | grep -q '純往上爬（沒指名任何東西） 1'
assert_eq "$?" 0 "而且它被算進 DISCLOSURE，不是靜默跳過"

# ── A-P3：被存在性檢查包住的是候選，不是要求 ─────────────────────────
# 這一類真樹上沒有實例（這一輪修掉的那兩組就是唯二的），所以只能靠 fixture。
repo="$WORK/candidates_allmiss"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB=""
for candidate in \
  "$SCRIPT_DIR/../../../scripts/lib/shared.sh" \
  "$SCRIPT_DIR/../../scripts/lib/shared.sh" \
  "$SCRIPT_DIR/../scripts/lib/shared.sh"
do
  if [[ -f "$candidate" ]]; then
    LIB="$candidate"
    break
  fi
done
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 1 "一組候選全部落空 → 紅"
lines="$(printf '%s' "$out" | grep -c 'caller.sh')"
assert_eq "$lines" 1 "而且只紅一行，不是三行——三行會讓人以為有三個洞"
printf '%s' "$out" | grep -q '這一組候選 3 條全部落空'
assert_eq "$?" 0 "訊息說出這是一組候選、共幾條"

repo="$WORK/candidates_onehit"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/probe/scripts/lib"
touch "$repo/.claude/skills/probe/scripts/lib/shared.sh"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB=""
for candidate in \
  "$SCRIPT_DIR/../../../scripts/lib/shared.sh" \
  "$SCRIPT_DIR/../../scripts/lib/shared.sh" \
  "$SCRIPT_DIR/lib/shared.sh"
do
  if [[ -f "$candidate" ]]; then
    LIB="$candidate"
    break
  fi
done
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "一組候選裡有一條命中 → 綠（前兩條落空不算洞）"

# `if [[ -f X ]]; then . X; fi`：兩行問的是同一個東西，所以判一次。
#
# 這一格的判定在 DP-513 施工中被實測推翻過一次，經過留在這裡：原本寫成「唯一的候選落空
# → 紅」，理由是一條永遠走不到的分支就是這張單在講的病。真樹上立刻噴出一個假紅——
# `visual-regression/scripts/polaris-toolchain.sh:18` 問的是「這個 skill 目錄自己是不是
# workspace 根」，在這棵樹上答案就是不是，而 `polaris-toolchain.yaml` 真的存在、在 repo 根。
# 它跟 `fetch-pr-info.sh` 那種死 fallback 的形狀一模一樣，差別只在意圖。所以只有一個目標的
# 時候不判定，進 DISCLOSURE——A-N2 明文允許的第二條路，不是靜默縮小管轄。
repo="$WORK/guard_ifthen"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/optional.sh" ]]; then
  . "$SCRIPT_DIR/lib/optional.sh"
fi
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "只有一個目標的候選落空 → 不判定"
printf '%s' "$out" | grep -q '只有一條候選而它落空（死 fallback 與該落空的探測分不出來） 1'
assert_eq "$?" 0 "而且它被算進 DISCLOSURE，不是靜默跳過"
touch "$repo/.claude/skills/probe/scripts/lib/optional.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm "add optional"
run_gate --repo "$repo"
assert_eq "$rc" 0 "那個候選補上之後 → 綠"
printf '%s' "$out" | grep -q '只有一條候選而它落空（死 fallback 與該落空的探測分不出來） 0'
assert_eq "$?" 0 "補上之後那一類歸零——它是真的被判了，不是永遠被跳過"

# 兩個以上不同的目標全部落空才判得出來：作者自己寫下了「我預期其中一個在這裡」，而沒有
# 一個在，所以那是矛盾。同一個目標寫兩次不算兩個候選。
repo="$WORK/guard_two_targets"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/a.sh" ]]; then
  . "$SCRIPT_DIR/lib/a.sh"
elif [[ -f "$SCRIPT_DIR/lib/b.sh" ]]; then
  . "$SCRIPT_DIR/lib/b.sh"
fi
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 1 "兩個不同的候選都落空 → 紅"

# ── A-P4：判不了的每一類都說出數量 ───────────────────────────────────
repo="$WORK/disclosure"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 這一行是註解：$SCRIPT_DIR/never-existed.sh
bash "$SCRIPT_DIR/$CHOSEN.sh"
mkdir -p "$SCRIPT_DIR/../generated"
OUTSIDE="$SCRIPT_DIR/../../../../../../../../elsewhere/thing.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "四類判不了的東西都不判紅"
printf '%s' "$out" | grep -q '註解裡 1'
assert_eq "$?" 0 "註解裡的斷引用被算進去"
printf '%s' "$out" | grep -q '路徑不自明（變數解不出來、帶展開或 glob） 1'
assert_eq "$?" 0 "帶變數展開的路徑被算進去"
printf '%s' "$out" | grep -q '解析後落到 repo 之外 1'
assert_eq "$?" 0 "解到 repo 外的被算進去"
printf '%s' "$out" | grep -q '這一行在建立它，不是在讀它 1'
assert_eq "$?" 0 "建立型的被算進去（要求它先存在會噴假紅）"

# 綠的那一次也要印 DISCLOSURE——綠的時候才是最容易被讀成「掃完了」的時候。
repo="$WORK/disclosure_on_green"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/there.sh"
EOF
touch "$repo/.claude/skills/probe/scripts/there.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "一棵沒有任何判不了的東西的樹是綠的"
printf '%s' "$out" | grep -q 'DISCLOSURE'
assert_eq "$?" 0 "綠的時候一樣印出 DISCLOSURE"

# 哪個變數算「從自己的位置算起」，由賦值的形狀決定，不由名字決定。`WORKSPACE_ROOT` 不在
# 任何名字白名單上，但它自己就是 `$(cd "$(dirname "$0")/.." && pwd)`——接下去的 `SCRIPT_DIR`
# 追得回這支腳本自己的位置，所以那條引用判得出來。
repo="$WORK/chained_base"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$WORKSPACE_ROOT/scripts"
bash "$SCRIPT_DIR/worker.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 1 "透過另一個變數接起來的 base 也要解得出來（目標不存在 → 紅）"
touch "$repo/.claude/skills/probe/scripts/worker.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm "add worker"
run_gate --repo "$repo"
assert_eq "$rc" 0 "那個目標補上之後 → 綠"

# 但同一個變數在 case 分支裡被重新指派過，它的值就是 runtime 才知道的——不得猜。
# 綁行首的賦值偵測會漏掉 `--repo) REPO_PATH="$2"` 這種形狀，然後把它當成解出來了。
repo="$WORK/reassigned_base"
make_repo "$repo"
cat > "$repo/.claude/skills/probe/scripts/caller.sh" <<'EOF'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --scripts) SCRIPT_DIR="$2"; shift 2 ;;
esac
bash "$SCRIPT_DIR/nowhere.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 0 "被重新指派過的變數不判定"
printf '%s' "$out" | grep -q '路徑不自明（變數解不出來、帶展開或 glob） 1'
assert_eq "$?" 0 "而且算進 DISCLOSURE"

echo ""

# `--skill` 是 L-P1 的機制：這道閘量的東西有擁有者（一支 skill 的腳本指向自己位置算起的
# 東西），所以那一支要能單獨叫它檢查自己。範圍收得對不對要驗兩向——只驗「單支會綠」的話，
# 一個把範圍收成空集合的實作也會綠。
repo="$WORK/skill_scope"
make_repo "$repo"
mkdir -p "$repo/.claude/skills/clean/scripts" "$repo/.claude/skills/broken/scripts"
cat > "$repo/.claude/skills/clean/scripts/ok.sh" <<'EOF'
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/there.sh"
EOF
touch "$repo/.claude/skills/clean/scripts/there.sh"
cat > "$repo/.claude/skills/broken/scripts/bad.sh" <<'EOF'
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/gone.sh"
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 1 "全掃會看到壞掉的那一支"
run_gate --repo "$repo" --skill clean
assert_eq "$rc" 0 "--skill 只看那一支，乾淨的那支是綠的"
run_gate --repo "$repo" --skill broken
assert_eq "$rc" 1 "--skill 指到壞掉的那支要紅——範圍不是被收成空集合"
run_gate --repo "$repo" --skill nosuch
assert_eq "$rc" 2 "--skill 指到不存在的 skill 是量不到，不是綠"

# 掃不到任何腳本要用 2 停下來，不是回綠——一道掃不到東西而回綠的閘，跟一道掃過了沒問題
# 的閘，在輸出上長得一樣。
repo="$WORK/nothing"
make_repo "$repo"
echo '# 這棵樹裡沒有腳本' > "$repo/.claude/skills/probe/SKILL.md"
git -C "$repo" add -A && git -C "$repo" commit -qm init
run_gate --repo "$repo"
assert_eq "$rc" 2 "一支腳本都掃不到 → 量不到，不是綠"

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]] || exit 1
echo "PASS: gate-skill-script-references-selftest.sh"
