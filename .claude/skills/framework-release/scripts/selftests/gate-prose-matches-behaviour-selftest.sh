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

# 讓出去的精度要被數出來，不能安靜。一個沒有目錄的檔名解不出唯一位置，所以不判紅——
# 但它必須出現在「不在管轄內」那個數字裡，否則下一次有人會以為那些也檢查過了。
repo="$(new_repo bare_name '# demo

分類規則在 `shared-defaults.md`。')"
out="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
if ! bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  bad "沒有目錄的檔名被判紅了，那是猜的"
elif printf '%s' "$out" | grep -q 'shared-defaults.md'; then
  ok "沒有目錄的檔名不判紅，但有被列進不管轄的那一堆"
else
  bad "沒有目錄的檔名安靜地消失了：$out"
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

echo "gate-prose-matches-behaviour selftest: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
