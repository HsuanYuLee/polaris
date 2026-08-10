#!/usr/bin/env bash
# Purpose: 證明散文對照閘三種形狀都擋得到，而且不擋對的東西。
# Inputs:  mktemp 底下的假 skills 樹。
# Outputs: PASS 當「指向不存在的檔／不存在的子命令／不存在的旗標」各自變紅，
#          全部對得上時變綠，而沒有目錄的檔名被算進不管轄的那一堆而不是判紅。

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gate-prose-matches-behaviour.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()   { echo "PASS $*"; PASS=$((PASS + 1)); }
bad()  { echo "FAIL $*" >&2; FAIL=$((FAIL + 1)); }

# Description: 造一棵只有一支 skill 的假 repo，回傳它的路徑。
# Args: $1 = case 名字, $2 = 要寫進 SKILL.md 的內文
new_repo() {
  local repo="$WORK/$1" body="$2"
  mkdir -p "$repo/.claude/skills/demo/scripts" "$repo/.claude/skills/demo/references"
  git init -q "$repo"
  cat > "$repo/.claude/skills/demo/scripts/tool.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  show) echo show ;;
  record) echo record ;;
esac
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) shift 2 ;;
    *) shift ;;
  esac
done
EOF
  echo "reference" > "$repo/.claude/skills/demo/references/real.md"
  printf '%s\n' "$body" > "$repo/.claude/skills/demo/SKILL.md"
  printf '%s' "$repo"
}

# 全部對得上：一個真的存在的檔、一個真的存在的子命令、一個真的認得的旗標。
repo="$(new_repo green '# demo

前置必讀：`.claude/skills/demo/references/real.md`。

```bash
bash .claude/skills/demo/scripts/tool.sh show --state x
```')"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  ok "全部對得上時是綠的"
else
  bad "全部對得上卻判紅：$(bash "$GATE" --repo "$repo" 2>&1)"
fi

# 一：指向不存在的檔。engineering / verify-ac 的「前置必讀」就是這個形狀。
repo="$(new_repo missing_doc '# demo

前置必讀：`.claude/skills/demo/references/gone.md`。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "指向不存在的檔沒被擋"
elif printf '%s' "$out" | grep -q 'gone.md'; then
  ok "指向不存在的檔會紅，而且說得出是哪一個"
else
  bad "紅了但沒說出是哪一個檔：$out"
fi

# 二：指名不存在的子命令。執行才炸，而且炸在流程中間。
repo="$(new_repo missing_sub '# demo

```bash
bash .claude/skills/demo/scripts/tool.sh teleport --state x
```')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "不存在的子命令沒被擋"
elif printf '%s' "$out" | grep -q 'teleport'; then
  ok "不存在的子命令會紅"
else
  bad "紅了但沒說出是哪個子命令：$out"
fi

# 三：指名不存在的旗標。三站改名之後整批 --source 對不上就是這個。
repo="$(new_repo missing_flag '# demo

```bash
bash .claude/skills/demo/scripts/tool.sh show --source x
```')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "不存在的旗標沒被擋"
elif printf '%s' "$out" | grep -q -- '--source'; then
  ok "不存在的旗標會紅"
else
  bad "紅了但沒說出是哪個旗標：$out"
fi

# 沒有目錄的檔名分兩種，而且分界要兩邊都紅得起來——只驗一邊的話，另一邊悄悄改掉沒有人知道。
#
# 裸的 `.md`：判。一份住在 skill 裡的散文寫 `foo.md`，在它自己那一棵樹底下解得出唯一位置，
# 而 SKILL.md 的 Reference Loading 表整張都是這個寫法。
repo="$(new_repo bare_md '# demo

分類規則在 `shared-defaults.md`。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "裸的 .md 指向不存在的檔案沒被擋"
elif printf '%s' "$out" | grep -q 'shared-defaults.md'; then
  ok "裸的 .md 解不到就判紅"
else
  bad "紅了但沒說出是哪一個：$out"
fi

# 裸的設定檔：讓。`package.json`、`workspace-config.yaml` 是使用者自己的檔或別的 repo 的
# 根檔，這個 repo 裡本來就不會有。但讓出去的精度要被數出來——它必須出現在「不在管轄內」
# 那一堆裡，否則下一次有人會以為那些也檢查過了。
repo="$(new_repo bare_config '# demo

版本寫在 `package.json`。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if ! bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "裸的設定檔被判紅了，那是猜的"
elif printf '%s' "$out" | grep -q 'package.json'; then
  ok "裸的設定檔不判紅，但有被列進不管轄的那一堆"
else
  bad "裸的設定檔安靜地消失了：$out"
fi

# 四：`$SKILL_DIR/...` 這種寫法。變數的值是自明的（就是這支 skill 自己的目錄），
# 而這一整類原本一個都沒被檢查——gate-skill-script-references 只看腳本引用腳本。
repo="$(new_repo skill_dir_ref '# demo

解析結果由 `$SKILL_DIR/scripts/gone.sh` 定義。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "\$SKILL_DIR 指向不存在的腳本沒被擋"
elif printf '%s' "$out" | grep -q 'gone.sh'; then
  ok "\$SKILL_DIR 指向不存在的腳本會紅"
else
  bad "紅了但沒說出是哪一個：$out"
fi

repo="$(new_repo skill_dir_ok '# demo

解析結果由 `$SKILL_DIR/scripts/tool.sh` 定義。')"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  ok "\$SKILL_DIR 指向真的存在的腳本是綠的"
else
  bad "\$SKILL_DIR 指向存在的腳本卻判紅：$(bash "$GATE" --repo "$repo" 2>&1)"
fi

# 樣板不是指路。`{issue}/index.md` 是要被代換的東西，不是磁碟上的位置。
repo="$(new_repo placeholder '# demo

```bash
bash .claude/skills/demo/scripts/tool.sh show --state {issue}/.spine/loop-state.json
```')"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  ok "樣板佔位符不被當成指路"
else
  bad "樣板佔位符被判紅：$(bash "$GATE" --repo "$repo" 2>&1)"
fi

# 目錄型指路。四種寫法都要驗，因為這一格以前是**兩道閘中間的空隙**：
# gate-skill-knowledge-locality 只判版控之外的引用（`.claude/` 開頭直接出局），而這一道
# 當時只判有副檔名的檔案。於是一個指向被拆掉的目錄的指標兩邊都是綠的，活了好幾個月。
repo="$(new_repo dir_missing '# demo

跨 repo 的事在 `.claude/rules/nosuch/handbook/`。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "指向不存在的目錄沒被擋"
elif printf '%s' "$out" | grep -q 'nosuch/handbook'; then
  ok "指向不存在的目錄會紅，而且說得出是哪一個"
else
  bad "紅了但沒說出是哪一個目錄：$out"
fi

repo="$(new_repo dir_present '# demo

腳本在 `.claude/skills/demo/scripts/`。')"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  ok "指向真的存在的目錄是綠的"
else
  bad "存在的目錄被判紅：$(bash "$GATE" --repo "$repo" 2>&1)"
fi

# 沒有結尾斜線、也沒有副檔名的寫法。這一種在真的那棵樹上一筆都沒有（量過），所以它的
# 紅控只能長在這裡——一條只在剛好有人這樣寫時才存在的檢查，等於沒有檢查。
repo="$(new_repo dir_noslash '# demo

規範在 `.claude/rules/nosuch`。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "不帶結尾斜線的目錄指標沒被擋"
elif printf '%s' "$out" | grep -q 'rules/nosuch'; then
  ok "不帶結尾斜線的目錄指標一樣會紅"
else
  bad "紅了但沒說出是哪一個：$out"
fi

# 判定的前綴之外一律不判——但要被數出來。這一條擋的是「把判準改成解不到就判紅」：
# 那樣改會讓 `issues/`、`snapshots/`、`apps/main/` 這一整批全紅，然後這道閘被關掉。
repo="$(new_repo dir_outside '# demo

產物落在 `test-results/`。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if ! bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "前綴之外的目錄被判紅了，那是猜的"
elif printf '%s' "$out" | grep -q 'test-results/'; then
  ok "前綴之外的目錄不判紅，但有被列進不管轄的那一堆"
else
  bad "前綴之外的目錄安靜地消失了：$out"
fi

# 宣告過的目錄走既有的機制，不另開一條路。
repo="$(new_repo dir_declared '# demo

<!-- PROSE-EXTERNAL-PATHS: .claude/rules/theirs/ — 那是別人 repo 的規範 -->

規範在 `.claude/rules/theirs/`。')"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  ok "宣告成住在別處的目錄不判紅"
else
  bad "宣告過的目錄仍然被判紅：$(bash "$GATE" --repo "$repo" 2>&1)"
fi

# `--skill` 是 L-P1 的機制。兩向都要驗：一個把範圍收成空集合的實作，只驗「乾淨的那支會綠」
# 是抓不到的。
repo="$(new_repo scope_clean '# demo

規範在 `references/real.md`。')"
mkdir -p "$repo/.claude/skills/other"
printf '# other\n\n看 `references/gone.md`。\n' > "$repo/.claude/skills/other/SKILL.md"
# `$?` 直接接在命令後面會被 `set -e` 先殺掉，所以每一次都用 `|| rc=$?` 接住。
scoped() {
  local rc=0
  bash "$GATE" --repo "$repo" "$@" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}
[[ "$(scoped)" == 1 ]] && ok "全掃會看到別支的斷指標" || bad "全掃應該紅"
[[ "$(scoped --skill demo)" == 0 ]] && ok "--skill demo 只看自己，是綠的" || bad "--skill demo 應該綠"
[[ "$(scoped --skill other)" == 1 ]] && ok "--skill other 要紅——範圍不是被收成空集合" || bad "--skill other 應該紅"
[[ "$(scoped --skill nosuch)" == 2 ]] && ok "--skill 指到不存在的是量不到" || bad "--skill nosuch 應該 exit 2"

# 只寫在註解裡的旗標不算存在。腳本的 `# Usage:` 檔頭是散文的一種，拿散文去驗散文永遠是
# 綠的——一支腳本停掉某個旗標卻沒改檔頭，這道閘從兩邊都看不出來。真的那棵樹上一筆都沒有
# （2026-08-10 量的），所以紅控只能長在這裡。
repo="$(new_repo comment_only_flag '# demo

```bash
bash .claude/skills/demo/scripts/tool.sh show --legacy
```')"
printf '# Usage: tool.sh show --legacy\n' >> "$repo/.claude/skills/demo/scripts/tool.sh"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "只寫在註解裡的旗標被當成存在"
elif printf '%s' "$out" | grep -q -- '--legacy'; then
  ok "只寫在註解裡的旗標會紅"
else
  bad "紅了但沒說出是哪個旗標：$out"
fi

# 上一條的反面：真的在程式碼裡的旗標不能因為剝註解而變紅。剝掉的要正好是註解，不是別的。
repo="$(new_repo real_flag_survives '# demo

```bash
bash .claude/skills/demo/scripts/tool.sh record --state x
```')"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  ok "真的在 case 裡的旗標剝完註解仍然是綠的"
else
  bad "剝註解把真的旗標弄丟了：$(bash "$GATE" --repo "$repo" 2>&1)"
fi

# 殼的第二種寫法：exec 到同目錄 lib/ 底下那一支，位置用 BASH_SOURCE 展開出來，沒有
# SKILL_DIR 這個名字。詞表跟不到被 exec 的那一支的話，殼就只剩檔頭註解可以靠——
# 而註解已經不算數了，於是一批對的散文會變紅。place-issues-by-state.sh 就是這個形狀。
repo="$(new_repo shell_delegate_bash_source '# demo

```bash
bash .claude/skills/demo/scripts/shell.sh --issues x --check
```')"
mkdir -p "$repo/.claude/skills/demo/scripts/lib"
cat > "$repo/.claude/skills/demo/scripts/shell.sh" <<'EOF'
#!/usr/bin/env bash
# Usage: shell.sh --issues <path> --check
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/real.py" "$@"
EOF
cat > "$repo/.claude/skills/demo/scripts/lib/real.py" <<'EOF'
import argparse
parser = argparse.ArgumentParser()
parser.add_argument("--issues")
parser.add_argument("--check", action="store_true")
EOF
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  ok "殼用 BASH_SOURCE 展開時，詞表跟得到被 exec 的那一支"
else
  bad "殼的旗標跟不到，對的散文被判紅：$(bash "$GATE" --repo "$repo" 2>&1)"
fi

echo "gate-prose-matches-behaviour selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
