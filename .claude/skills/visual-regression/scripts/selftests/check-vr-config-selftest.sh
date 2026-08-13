#!/usr/bin/env bash
# check-vr-config-selftest.sh — 餵紅 check-vr-config.sh 的三個子命令。
#
# 正負兩表都跑：只驗反例的話，一個永遠判紅的檢查也全綠；只驗正例的話，一個永遠回 0 的
# 檢查也全綠。
#
# 三種離場碼各自都要被驗到：0 對得起來、1 量到了而且是紅的、2 量不到。**第三種最容易被
# 弄丟**——一個掃到 0 個目標的檢查，輸出跟「掃過了、都對」長得一模一樣。
#
# 連網那一半靠注入的探測器（`--prober`），不打任何真的站台：判定邏輯（跟到最終位置之後
# 是不是 2xx、連不上算什麼）要能在沒有網路的地方被驗，否則它的紅控只能靠某個外部站台
# 今天剛好是什麼樣子。
#
# Usage: check-vr-config-selftest.sh
# Exit:  0 全部如預期 / 1 有一種沒被抓到

set -uo pipefail

SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELFTEST_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
CHECKER="$SCRIPTS_DIR/check-vr-config.sh"

PREFIX="[selftest check-vr-config]"
PASS=0
FAIL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$CHECKER" ]] || { echo "$PREFIX 量不到：$CHECKER 不在。" >&2; exit 2; }

# expect <想要的 exit code> <輸出裡要有的字串（空字串＝不比）> <說明> -- <命令...>
expect() {
  local want="$1" needle="$2" what="$3"; shift 4
  local out got=0
  out="$("$@" 2>&1)" || got=$?
  if [[ "$got" == "$want" ]] && { [[ -z "$needle" ]] || [[ "$out" == *"$needle"* ]]; }; then
    PASS=$((PASS + 1))
    echo "$PREFIX PASS ${what}"
  else
    FAIL=$((FAIL + 1))
    echo "$PREFIX FAIL ${what}：想要 exit ${want}" >&2
    [[ -n "$needle" ]] && echo "$PREFIX       且輸出含「${needle}」" >&2
    echo "$PREFIX       實際 exit ${got}" >&2
    echo "$out" | sed "s/^/$PREFIX       /" >&2
  fi
}

# ── 設定樹：公司設定 + root defaults，跟真樹同一個形狀 ───────────────────────
mk_tree() {
  local root="$1" browsers="$2"
  mkdir -p "$root/acme"
  cat > "$root/workspace-config.yaml" <<YAML
defaults:
  visual_regression:
    browsers: [$browsers]
YAML
  cat > "$root/acme/workspace-config.yaml" <<'YAML'
visual_regression:
  domains:
    - name: "www.example.invalid"
      server:
        sit_url: "https://www.example.invalid"
      locales: ["zh-tw"]
      pages:
        - name: "homepage"
          path: "/"
        - name: "gone"
          path: "/gone"
YAML
}

mk_pw() {
  local dir="$1" body="$2"
  mkdir -p "$dir/www.example.invalid"
  printf '%s\n' "$body" > "$dir/www.example.invalid/playwright.config.ts"
}

# ── browsers：正向 ───────────────────────────────────────────────────────────
T="$WORK/ok"; mk_tree "$T" '"chromium"'
mk_pw "$T/vr" "projects: [{ name: 'desktop', use: { ...devices['Desktop Chrome'] } }]"
expect 0 "mismatch=0 undecided=0" "宣告 chromium ＋ Desktop Chrome → 0" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

# ── browsers：反向一，具名 device 解出來的引擎不在宣告裡 ─────────────────────
T="$WORK/webkit"; mk_tree "$T" '"chromium"'
mk_pw "$T/vr" "projects: [{ name: 'mobile', use: { ...devices['iPhone 13'] } }]"
expect 1 "解出 webkit" "宣告 chromium ＋ iPhone 13 → 1，並說出解出什麼" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"
expect 1 "不在宣告的" "紅的時候要說出宣告的集合是什麼" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

expect 1 "不是去裝一顆瀏覽器" "紅的時候要說出修法不是裝瀏覽器" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

# ── browsers：反向二，直接宣告 browserName ───────────────────────────────────
T="$WORK/explicit"; mk_tree "$T" '"chromium"'
mk_pw "$T/vr" "projects: [{ name: 'ff', use: { browserName: 'firefox' } }]"
expect 1 "經 browserName 解出 firefox" "直接宣告引擎的 project 也判得到" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

# 直接宣告而且落在集合裡 → 綠。少了這一條，上面那條紅可能只是「凡 browserName 就判紅」。
T="$WORK/explicit-ok"; mk_tree "$T" '"chromium", "firefox"'
mk_pw "$T/vr" "projects: [{ name: 'ff', use: { browserName: 'firefox' } }]"
expect 0 "mismatch=0" "直接宣告且在集合裡 → 0" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

# ── browsers：反向三，兩者都沒有＝吃執行時預設，不得靜靜算成通過 ────────────
T="$WORK/default"; mk_tree "$T" '"chromium"'
mk_pw "$T/vr" "projects: [{ name: 'bare', use: { viewport: { width: 1280, height: 900 } } }]"
expect 1 "由執行時的預設決定" "既沒 device 也沒 browserName → 不判綠" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

# 認不出來的 device 名字要說出來，不要當成 chromium。
T="$WORK/unknown"; mk_tree "$T" '"chromium"'
mk_pw "$T/vr" "projects: [{ name: 'weird', use: { ...devices['Some New Device'] } }]"
expect 1 "認不出它的引擎" "認不出的 device 不當成 chromium" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

# ── browsers：量不到 ─────────────────────────────────────────────────────────
T="$WORK/empty"; mk_tree "$T" '"chromium"'; mkdir -p "$T/vr"
expect 2 "一份 playwright 設定都沒有" "0 份設定 → 量不到，不是綠" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

T="$WORK/nodecl"; mkdir -p "$T/acme" "$T/vr"
printf 'visual_regression:\n  domains: []\n' > "$T/acme/workspace-config.yaml"
mk_pw "$T/vr" "projects: [{ name: 'd', use: { ...devices['Desktop Chrome'] } }]"
expect 2 "找不到 browsers 宣告" "沒有 browsers 宣告 → 量不到" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml" --vr-root "$T/vr"

T="$WORK/ok"
expect 2 "--vr-root" "沒給 --vr-root → 量不到（那棵樹的位置只有這台機器知道）" -- \
  bash "$CHECKER" browsers --config "$T/acme/workspace-config.yaml"

expect 2 "設定檔不在" "設定檔不在 → 量不到" -- \
  bash "$CHECKER" browsers --config "$WORK/nope.yaml" --vr-root "$T/vr"

# ── pages：注入探測器 ────────────────────────────────────────────────────────
ALL_OK="$WORK/prober-ok.sh"
printf '#!/usr/bin/env bash\necho "200 $1"\n' > "$ALL_OK"; chmod +x "$ALL_OK"

# 跟到最終位置才判：第一跳是 301、最後停在錯誤頁的那一種，是 2026-08-13 量到的四個裡的兩個。
REDIRECT_DEAD="$WORK/prober-redirect.sh"
cat > "$REDIRECT_DEAD" <<'SH'
#!/usr/bin/env bash
case "$1" in
  */gone) echo "404 https://www.example.invalid/errorpage" ;;
  *)      echo "200 $1" ;;
esac
SH
chmod +x "$REDIRECT_DEAD"

DOWN="$WORK/prober-down.sh"
printf '#!/usr/bin/env bash\nexit 7\n' > "$DOWN"; chmod +x "$DOWN"

T="$WORK/ok"
expect 0 "pages=2 dead=0" "每一頁都 2xx → 0" -- \
  bash "$CHECKER" pages --config "$T/acme/workspace-config.yaml" --prober "$ALL_OK"
expect 1 "dead=1" "有一頁轉去錯誤頁 → 1" -- \
  bash "$CHECKER" pages --config "$T/acme/workspace-config.yaml" --prober "$REDIRECT_DEAD"
expect 1 "errorpage" "紅的時候要說出它最後停在哪" -- \
  bash "$CHECKER" pages --config "$T/acme/workspace-config.yaml" --prober "$REDIRECT_DEAD"
expect 2 "連不上" "連不上 → 量不到，不是「頁面死了」" -- \
  bash "$CHECKER" pages --config "$T/acme/workspace-config.yaml" --prober "$DOWN"

T="$WORK/nodecl"
expect 2 "頁面 0 個" "一個頁面都沒列到 → 量不到" -- \
  bash "$CHECKER" pages --config "$T/acme/workspace-config.yaml" --prober "$ALL_OK"

# ── knowledge：真樹綠，抽掉內容要紅 ─────────────────────────────────────────
expect 0 "VR-KNOWLEDGE-CHECKED" "真樹綠" -- bash "$CHECKER" knowledge --skill-dir "$SKILL_DIR"

for name in tooling-tree-unversioned readiness-selector-per-tree; do
  d="$WORK/drop-$name"
  rm -rf "$d"; mkdir -p "$d/references"
  cp "$SKILL_DIR/references/visual-regression-config.md" "$d/references/"
  python3 - "$d/references/visual-regression-config.md" "$name" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    re.sub(r"<!--\s*VR-CONTRACT:\s*" + re.escape(name) + r"\s*-->\n?", "", src))
PY
  expect 1 "$name" "拔掉錨 ${name}" -- bash "$CHECKER" knowledge --skill-dir "$d"

  d="$WORK/gut-$name"
  rm -rf "$d"; mkdir -p "$d/references"
  cp "$SKILL_DIR/references/visual-regression-config.md" "$d/references/"
  python3 - "$d/references/visual-regression-config.md" "$name" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
anchor = re.compile(r"<!--\s*VR-CONTRACT:\s*([a-z0-9-]+)\s*-->")
hit = next(m for m in anchor.finditer(src) if m.group(1) == name)
nxt = anchor.search(src, hit.end())
end = nxt.start() if nxt else len(src)
open(path, "w", encoding="utf-8").write(src[:hit.end()] + "\n\n這一段照規矩辦。\n\n" + src[end:])
PY
  expect 1 "沒有說" "掏空 ${name}（錨還在）" -- bash "$CHECKER" knowledge --skill-dir "$d"
done

d="$WORK/noanchor"
rm -rf "$d"; mkdir -p "$d/references"
python3 - "$SKILL_DIR/references/visual-regression-config.md" "$d/references/visual-regression-config.md" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(
    re.sub(r"<!--\s*VR-CONTRACT:[^>]*-->\n?", "", src))
PY
expect 2 "一個錨都沒有" "一個錨都沒有 → 量不到，不得判綠" -- bash "$CHECKER" knowledge --skill-dir "$d"

mkdir -p "$WORK/empty-skill/references"
expect 2 "散文檔不在" "目錄在但散文檔不在 → 量不到" -- bash "$CHECKER" knowledge --skill-dir "$WORK/empty-skill"
expect 2 "skill 目錄不在" "目錄整個不在 → 量不到，而且理由不一樣" -- bash "$CHECKER" knowledge --skill-dir "$WORK/no-such-skill"

# ── 這支檢查自己不得安裝任何東西 ────────────────────────────────────────────
# 「宣告不符」最順手的錯誤修法就是去裝那顆瀏覽器，而那等於偷偷擴充工具鏈、宣告仍然是錯的。
# 所以連檢查自己都不准帶安裝動作——這一條掃它自己的原始碼。
if grep -nE '(npx |pnpm |npm )?playwright[[:space:]]+install|brew install|npm -g|pip install|curl[^|]*\| *sh' "$CHECKER" >/dev/null 2>&1; then
  FAIL=$((FAIL + 1))
  echo "$PREFIX FAIL 檢查自己帶了安裝動作" >&2
  grep -nE '(npx |pnpm |npm )?playwright[[:space:]]+install|brew install|npm -g|pip install' "$CHECKER" >&2
else
  PASS=$((PASS + 1))
  echo "$PREFIX PASS 檢查自己不安裝任何東西"
fi

# ── 不認得的子命令不得靜靜地過 ──────────────────────────────────────────────
expect 2 "用法" "不給子命令 → 量不到" -- bash "$CHECKER"

echo "$PREFIX PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]] || exit 1
