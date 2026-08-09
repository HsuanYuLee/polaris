#!/usr/bin/env bash
# Selftest for gate-skill-knowledge-locality.sh —— 這道閘以前沒有 selftest，而它的判定會
# 因為在誰的機器上跑而不同。兩件事是同一件事：沒有東西紅得起來的地方，缺陷就住在那裡。
#
# 所以第一個 case 是「同一棵樹、兩台機器、同一個答案」。它不是附帶檢查，它是這支 selftest
# 存在的理由：2026-08-07 那次，寫下五行環境宣告的人機器上全部 exit 0，撞到的人全部非 0，
# 而閘看的是前者。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-skill-knowledge-locality.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# fixture：一個工作區，`/vendor/` 與 `/acme/` 被版控排除。`acme` 同時是一支公司 skill 的
# 命名空間——那個碰撞是真的存在的形狀（`acme/` 既是被 ignore 的 checkout，也是 skill 名）。
reset_fixture() {
  rm -rf "$tmp/repo"
  mkdir -p "$tmp/repo/.claude/skills/one" "$tmp/repo/.claude/skills/acme/two"
  # `/build/out/` 是刻意的：這條樣式命中的是引用的**最後**一段，而目錄樣式要成立，git 得
  # 先知道那一段是目錄。`/vendor/` 那種命中中間段的，光看「後面還有東西」就推得出來。
  printf '/vendor/\n/acme/\n/build/out/\nnode_modules/\n' > "$tmp/repo/.gitignore"
  {
    echo '# one'
    echo '<!-- PROSE-EXTERNAL-PATHS: vendor/checkout — 動手對象：那是被改的 repo -->'
    echo '施工的時候動 `vendor/checkout` 底下的東西。'
  } > "$tmp/repo/.claude/skills/one/SKILL.md"
  echo '# two：一支公司 skill。' > "$tmp/repo/.claude/skills/acme/two/SKILL.md"
  git -C "$tmp/repo" init -q
  git -C "$tmp/repo" config user.email t@t; git -C "$tmp/repo" config user.name t
  git -C "$tmp/repo" add -A; git -C "$tmp/repo" commit -qm init
}

check() {
  local name="$1" want="$2" needle="${3:-}"; shift 3 || shift 2
  local out rc
  out="$(bash "$SCRIPT" --repo "$tmp/repo" "$@" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: 期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL $name: 訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  echo "PASS $name"; pass=$((pass+1))
}

# ── 判定不得因為在誰的機器上跑而不同 ───────────────────────────────
# 同一棵樹跑兩次，唯一的差別是本機有沒有那個被排除的目錄。輸出要逐字相同——不是「都紅」
# 而已：看得到哪幾筆也不能變，否則兩台機器會各自修各自看得到的那一半。
# 兩種形狀都要在裡面。第二種（引用的就是那個被排除的目錄本身，後面沒有東西）是 2026-08-10
# 真的漏掉的那一種：`.gitignore` 寫 `/vendor/` 是目錄樣式，而 git 要判斷一條光禿的路徑是不是
# 目錄就得去看檔案系統——於是它在有那個目錄的機器上是紅的，在沒有的機器上是綠的。
reset_fixture
{
  echo '設定讀 `vendor/undeclared/config.yaml`。'
  echo '產出丟到 `build/out`。'
} >> "$tmp/repo/.claude/skills/one/SKILL.md"
absent="$(bash "$SCRIPT" --repo "$tmp/repo" 2>&1)" && absent_rc=0 || absent_rc=$?
mkdir -p "$tmp/repo/vendor/undeclared" "$tmp/repo/vendor/checkout" "$tmp/repo/build/out"
echo 'x' > "$tmp/repo/vendor/undeclared/config.yaml"
present="$(bash "$SCRIPT" --repo "$tmp/repo" 2>&1)" && present_rc=0 || present_rc=$?
if [[ "$absent" == "$present" && "$absent_rc" == "$present_rc" && "$absent_rc" == 1 ]]; then
  echo "PASS 同一棵樹在兩台機器上答案相同"; pass=$((pass+1))
else
  echo "FAIL 同一棵樹在兩台機器上答案相同: 目錄不在時 exit ${absent_rc}、在時 exit ${present_rc}"
  diff <(echo "$absent") <(echo "$present") | sed 's/^/     /' || true
  fail=$((fail+1))
fi

# ── 正例：每一筆都分類過 ───────────────────────────────────────────
reset_fixture
check "宣告齊全時判綠" 0 "✅"

# ── 反例一：一筆沒有說法的往外引用 ─────────────────────────────────
reset_fixture
echo '設定讀 `vendor/undeclared/config.yaml`。' >> "$tmp/repo/.claude/skills/one/SKILL.md"
check "沒有分類的往外引用會被抓到" 1 "vendor/undeclared/config.yaml"

# ── 反例二：分類成知識、卻住在 skill 目錄外 ────────────────────────
reset_fixture
{
  echo '<!-- PROSE-EXTERNAL-PATHS: vendor/handbook — 知識：判斷怎麼做的依據 -->'
  echo '判準在 `vendor/handbook/rules.md`。'
} >> "$tmp/repo/.claude/skills/one/SKILL.md"
check "知識住在 skill 目錄外會被抓到" 1 "vendor/handbook/rules.md"

# ── 姐妹 skill 的名字不是路徑 ──────────────────────────────────────
# `acme/two` 既是 skill 名、也命中 `/acme/` 這條 ignore 樣式。寫成
# `.claude/skills/acme/two` 本來就豁免，短名不該得到不同的答案。
reset_fixture
echo '規範走 `acme/two`，這裡不複述。' >> "$tmp/repo/.claude/skills/one/SKILL.md"
check "指名姐妹 skill 不算往外引用" 0 "✅"

# ── 長得像路徑、但不是路徑的兩種 ───────────────────────────────────
reset_fixture
echo '版本標在 `@vendor/some-package@1.2.3`。' >> "$tmp/repo/.claude/skills/one/SKILL.md"
check "npm scoped package 不算路徑" 0 "✅"

reset_fixture
echo '執行 `$ROOT/node_modules/.bin/thing`。' >> "$tmp/repo/.claude/skills/one/SKILL.md"
check "裝出來的東西不算往外引用" 0 "✅"

# ── 在 git hook 裡跑，答案要一樣 ───────────────────────────────────
# git 跑 hook 時環境裡一定有 GIT_DIR，而顯式的 GIT_DIR 蓋過 `-C`。這一條 2026-08-10 真的
# 發生過：把這道閘從 pre-push 搬到 pre-commit 的那一刻，它回 `fatal: not a git repository`。
#
# 環境指向**另一個** repo 才是真的危險——linked worktree 的 hook 就是這個形狀，而那時候
# git 會安靜地回答另一棵樹的問題，不會炸。所以這裡故意把它指到一個乾淨的 repo B。
reset_fixture
rm -rf "$tmp/other"
mkdir -p "$tmp/other/.claude/skills/nine"
echo '# nine：另一個 repo，沒有任何往外引用。' > "$tmp/other/.claude/skills/nine/SKILL.md"
git -C "$tmp/other" init -q
git -C "$tmp/other" config user.email t@t; git -C "$tmp/other" config user.name t
git -C "$tmp/other" add -A; git -C "$tmp/other" commit -qm init
plain="$(bash "$SCRIPT" --repo "$tmp/repo" 2>&1)"
hooked="$(GIT_DIR="$tmp/other/.git" GIT_WORK_TREE="$tmp/other" bash "$SCRIPT" --repo "$tmp/repo" 2>&1)"
if [[ "$plain" == "$hooked" ]]; then
  echo "PASS 環境裡有 GIT_DIR 時答案不變"; pass=$((pass+1))
else
  echo "FAIL 環境裡有 GIT_DIR 時答案不變"
  diff <(echo "$plain") <(echo "$hooked") | sed 's/^/     /' || true
  fail=$((fail+1))
fi

# ── 量不到不是通過 ─────────────────────────────────────────────────
reset_fixture
rm -rf "$tmp/repo/.claude/skills"
check "skill 目錄不存在時 exit 2" 2 "量不到"

echo "gate-skill-knowledge-locality selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
