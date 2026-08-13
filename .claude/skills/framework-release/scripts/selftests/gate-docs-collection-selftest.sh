#!/usr/bin/env bash
# Selftest for gate-docs-collection.sh —— 每個 case 先做出一棵已知狀態的假內容樹再看它判什麼。
#
# 這道閘的價值在四件事上：**缺 frontmatter 要紅並指名、收哪些檔案要從既有的設定讀、被排除
# 的要數出來、以及一份都收不到時要停在量不到而不是回綠。** 所以下面每一類都有一個「注入
# 之後必須變紅」的 case，以及一個「一開始就是對的」的正例——只有反例的話，一個永遠回 1 的
# 閘也會全綠。
#
# 另外兩組 case 守的是這道閘存在的理由本身：
#   - 不得需要裝任何東西（J-N1）：檢查自己的原始碼裡不得出現安裝動詞，也不得呼叫 astro。
#   - 設定改了它要跟著改（J-P2）：同一棵樹，只改設定裡的排除規則，判定就要不一樣——那證明
#     清單真的是從那份設定讀出來的，不是在腳本裡另外抄了一份。

set -euo pipefail

GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-docs-collection.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; echo "  ---- 實際輸出 ----"; sed 's/^/  /' <<< "${2:-}"; }

# 假的內容集合設定。形狀刻意跟真的那一份一樣：base 是變數、pattern 第一條 include 自己
# 含著一個 `]`（`[^_]`）、副檔名由模板字串展開。剖析器在這三個地方都出過錯。
write_config() {
  local root="$1" extra_exclude="${2:-}"
  mkdir -p "$root/src"
  cat > "$root/src/content.config.ts" <<TS
import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

const docsExtensions = ['markdown', 'md', 'mdx'];
const docsContentRoot = process.env.SOME_ENV
  ? path.dirname(process.env.SOME_ENV)
  : './src/content/docs';

export const collections = {
  docs: defineCollection({
    loader: glob({
      base: docsContentRoot,
      pattern: [
        \`**/[^_]*.{\${docsExtensions.join(',')}}\`,
        '!**/{escalations,tests}/**',
${extra_exclude}
      ],
    }),
    schema: docsSchema(),
  }),
};
TS
}

titled()   { mkdir -p "$(dirname "$1")"; printf -- '---\ntitle: 有標題\n---\n\n內文\n' > "$1"; }
untitled() { mkdir -p "$(dirname "$1")"; printf -- '# 只有一個標題行，沒有 frontmatter\n' > "$1"; }

# 一棵都對的樹：三份都帶著 title，外加一份落在排除規則裡的、一份底線開頭的。
reset_fixture() {
  rm -rf "$tmp/repo"
  local d="$tmp/repo/docs-manager/src/content/docs"
  write_config "$tmp/repo/docs-manager"
  titled "$d/one.md"
  titled "$d/sub/two.md"
  titled "$d/sub/three.mdx"
  untitled "$d/sub/tests/fixture.md"   # 被排除規則排掉，不判定
  untitled "$d/_draft.md"              # 底線開頭，不收
}

run() { bash "$GATE" --repo "$tmp/repo" 2>&1; }

# ── J-P1 缺 frontmatter 要紅，而且要指名是哪一份 ──────────────────────────────
reset_fixture
untitled "$tmp/repo/docs-manager/src/content/docs/sub/broken.md"
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'MISSING sub/broken.md' <<< "$out"; then
  ok '缺 frontmatter → 1，並指名是哪一份'
else
  bad '缺 frontmatter → 1，並指名是哪一份' "rc=$rc
$out"
fi

# frontmatter 在但缺 title 是另一種形狀——「沒有 frontmatter」的判斷放過它的話，最常見的
# 那一種（有 description 沒 title）就從來不會被抓到。
reset_fixture
mkdir -p "$tmp/repo/docs-manager/src/content/docs/sub"
printf -- '---\ndescription: 有描述沒標題\n---\n\n內文\n' \
  > "$tmp/repo/docs-manager/src/content/docs/sub/no-title.md"
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'no-title.md: frontmatter 在，但缺 title' <<< "$out"; then
  ok 'frontmatter 在但缺 title → 1，而且說出缺的是哪個欄位'
else
  bad 'frontmatter 在但缺 title → 1，而且說出缺的是哪個欄位' "rc=$rc
$out"
fi

# ── 正例：都帶著就要綠。只有反例的話一個永遠回 1 的閘也會全綠 ─────────────────
reset_fixture
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'collected=3 missing=0' <<< "$out"; then
  ok '都帶著 → 0，並說出收了幾份'
else
  bad '都帶著 → 0，並說出收了幾份' "rc=$rc
$out"
fi

# ── J-P3 被排除規則排掉的要數出來，不得靜靜地消失在通過裡 ─────────────────────
if grep -q '被排除規則排掉 1 份、底線開頭 1 份' <<< "$out"; then
  ok '不判定的那些要說出數量'
else
  bad '不判定的那些要說出數量' "$out"
fi

# ── J-P2 收哪些由既有的設定決定：只改設定，判定就要跟著變 ─────────────────────
# 同一棵樹、同一份缺 title 的檔案，設定多一條排除規則之後它就不該被判定了。這是「清單真的
# 從那份設定讀出來」唯一能被觀察到的樣子；腳本裡另抄一份清單的話，這個 case 會是紅的。
reset_fixture
untitled "$tmp/repo/docs-manager/src/content/docs/sub/broken.md"
out="$(run)" && rc=0 || rc=$?
[[ "$rc" -eq 1 ]] || bad '前置：加了壞檔應該先是紅的' "rc=$rc
$out"
write_config "$tmp/repo/docs-manager" "        '!**/sub/**',"
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q '被排除規則排掉 4 份' <<< "$out"; then
  ok '設定多一條排除規則 → 同一棵樹的判定跟著變'
else
  bad '設定多一條排除規則 → 同一棵樹的判定跟著變' "rc=$rc
$out"
fi

# ── J-P4 一份都沒收到時停在量不到，不回 0 ────────────────────────────────────
reset_fixture
rm -rf "$tmp/repo/docs-manager/src/content/docs"
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q '內容根不在' <<< "$out"; then
  ok '內容根不在 → 2，不是綠'
else
  bad '內容根不在 → 2，不是綠' "rc=$rc
$out"
fi

reset_fixture
find "$tmp/repo/docs-manager/src/content/docs" -name '*.md' -o -name '*.mdx' | while read -r f; do rm -f "$f"; done
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q '收到 0 份' <<< "$out"; then
  ok '收到 0 份 → 2，不是綠'
else
  bad '收到 0 份 → 2，不是綠' "rc=$rc
$out"
fi

# 設定整份不在是第三種：那棵樹沒有這個入口，不是我量不到。兩者混成同一個離場碼的話，
# template repo（不帶 docs-manager/）每次跑都會紅，然後這道閘就會被關掉。
reset_fixture
rm -f "$tmp/repo/docs-manager/src/content.config.ts"
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 3 ]] && grep -q '不適用' <<< "$out"; then
  ok '設定整份不在 → 3（不適用），跟量不到分開'
else
  bad '設定整份不在 → 3（不適用），跟量不到分開' "rc=$rc
$out"
fi

# 三種不綠的離場碼要互相分辨得出來——只看「非 0」的話，讀的人會把它們當成同一件事。
reset_fixture
untitled "$tmp/repo/docs-manager/src/content/docs/bad.md"
bash "$GATE" --repo "$tmp/repo" >/dev/null 2>&1 && a=0 || a=$?
reset_fixture; rm -rf "$tmp/repo/docs-manager/src/content/docs"
bash "$GATE" --repo "$tmp/repo" >/dev/null 2>&1 && b=0 || b=$?
reset_fixture; rm -f "$tmp/repo/docs-manager/src/content.config.ts"
bash "$GATE" --repo "$tmp/repo" >/dev/null 2>&1 && c=0 || c=$?
if [[ "$a" -ne "$b" && "$b" -ne "$c" && "$a" -ne "$c" ]]; then
  ok "三種不綠各有自己的離場碼（$a / $b / ${c}）"
else
  bad '三種不綠各有自己的離場碼' "有缺=$a 量不到=$b 不適用=$c"
fi

# ── J-P2 剖析器看不懂就要停，不得略過 ────────────────────────────────────────
reset_fixture
python3 - "$tmp/repo/docs-manager/src/content.config.ts" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("base: docsContentRoot,", "base: someUnknownThing,")
open(p, "w").write(s)
PY
out="$(run)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q '讀不出它的預設值' <<< "$out"; then
  ok '設定看不懂 → 2，不是「沒有檔案要收」'
else
  bad '設定看不懂 → 2，不是「沒有檔案要收」' "rc=$rc
$out"
fi

# ── J-N1 不裝任何東西、不跑建置 ──────────────────────────────────────────────
if grep -nE '(brew install|npm (i|install)|pnpm (add|install)|pip install|curl [^|]*\| *sh|npx )' "$GATE" >/dev/null; then
  bad '檢查自己不安裝任何東西' "$(grep -nE '(brew install|npm (i|install)|pnpm (add|install)|pip install|curl [^|]*\| *sh|npx )' "$GATE")"
else
  ok '檢查自己不安裝任何東西'
fi

build="$(grep -nE '^[^#]*(\bastro\b|pnpm |npm run|yarn |node )' "$GATE" || true)"
if [[ -n "$build" ]]; then
  bad '檢查自己不跑建置' "$build"
else
  ok '檢查自己不跑建置'
fi

# node_modules 唯一合法的出現方式是「走訪的時候跳過它」——任何拿它當前提的用法（存在性
# 檢查、路徑串接）都會讓這道閘在沒裝依賴的機器上永遠量不到，而那跟沒有這道閘一樣。
nm="$(grep -n 'node_modules' "$GATE" | grep -v 'dirnames\[:\]' | grep -vE '^[0-9]+: *#' || true)"
if [[ -n "$nm" ]]; then
  bad '檢查自己不要求 node_modules' "$nm"
else
  ok '檢查自己不要求 node_modules'
fi

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
