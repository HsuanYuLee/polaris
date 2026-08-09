#!/usr/bin/env bash
# Selftest for gate-layer-vocabulary.sh —— 三層各自先做出一個已知的落差再看它抓不抓得到。
#
# 三層一起判、卻只有一層紅得起來的閘，會在報告裡看起來像三層都管到了。所以每一層都有
# 自己的紅控，而且是分開的 case：其中一層失效時，垮掉的是那一個名字，不是總數少一。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-layer-vocabulary.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

DECL_SWE='<!-- PROSE-LAYER: SWE-ONLY — 不得出現在 core-a,core-b — branch|pull request|PR|codecov -->'
DECL_CORE='<!-- PROSE-LAYER: CORE-ONLY — 不得出現在 scope:company-only — assertion_wrong|loop-state.json|凍結塊 -->'
DECL_COMPANY='<!-- PROSE-LAYER: COMPANY-ONLY — 不得出現在 pack — @company-patterns -->'

# fixture：三層各一支 skill，外加一家公司的 workspace-config——公司樣式由那份檔案推出來，
# 所以連 @company-patterns 那一層也在沙箱裡判得動，不必去碰真的工作區。
reset_fixture() {
  rm -rf "$tmp/repo"
  mkdir -p "$tmp/repo/.claude/skills/core-a" "$tmp/repo/.claude/skills/core-b" \
           "$tmp/repo/.claude/skills/pack" "$tmp/repo/.claude/skills/acme/one" \
           "$tmp/repo/acme"
  {
    echo '# core-a'
    echo "$DECL_SWE"
    echo "$DECL_CORE"
    echo "$DECL_COMPANY"
  } > "$tmp/repo/.claude/skills/core-a/SKILL.md"
  echo '# core-b：這一層不認得任何一個領域。' > "$tmp/repo/.claude/skills/core-b/SKILL.md"
  echo '# pack：這一層不認得任何一家公司。' > "$tmp/repo/.claude/skills/pack/SKILL.md"
  printf -- '---\nname: one\nscope: company-only\n---\n# 一支公司 skill\n' \
    > "$tmp/repo/.claude/skills/acme/one/SKILL.md"
  echo 'company: acme' > "$tmp/repo/acme/workspace-config.yaml"
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

# ── 正例：三層都乾淨 ───────────────────────────────────────────────
reset_fixture
check "三層乾淨時判綠" 0 "declared rules: 3   evaluated: 3"

# ── 反例一：核心的散文出現只有軟體工程才成立的詞 ───────────────────
reset_fixture
echo '這一輪要開一條 branch 再送 PR。' >> "$tmp/repo/.claude/skills/core-b/SKILL.md"
check "layer1 核心出現領域詞" 1 "core-b/SKILL.md"

# ── 反例二：公司 skill 自己重講核心的機制 ─────────────────────────
reset_fixture
echo '判不過就記一個 assertion_wrong，狀態寫回 loop-state.json。' \
  >> "$tmp/repo/.claude/skills/acme/one/SKILL.md"
check "layer3 公司 skill 重講核心的詞" 1 "assertion_wrong"

# ── 反例三：領域 pack 出現只有某一家才成立的東西 ──────────────────
reset_fixture
echo 'acme 的門檻是 80%。' >> "$tmp/repo/.claude/skills/pack/SKILL.md"
check "layer2 領域 pack 帶進公司樣式" 1 "pack/SKILL.md"

# ── 宣告真的被讀了：往那一行加一個詞，立刻多抓到一處 ───────────────
# 這是 SWE-ONLY 那一行從「零個讀者」變成「有讀者」的證據。詞表寫死在腳本裡的話，
# 下面這個 case 會維持綠色——那正是它要擋的形狀。
reset_fixture
echo '這一段講的是 rollout 怎麼排。' >> "$tmp/repo/.claude/skills/core-b/SKILL.md"
check "詞表裡沒有的詞不算犯規" 0 ""
sed -i.bak 's/branch|pull request|PR|codecov/branch|pull request|PR|codecov|rollout/' \
  "$tmp/repo/.claude/skills/core-a/SKILL.md"
check "往宣告加一個詞就多抓到一處" 1 "rollout"

# ── 縮小詞表買不到綠 ───────────────────────────────────────────────
reset_fixture
base="$(git -C "$tmp/repo" rev-parse HEAD)"
echo '這一輪要開一條 branch。' >> "$tmp/repo/.claude/skills/core-b/SKILL.md"
sed -i.bak 's/branch|pull request|PR|codecov/pull request|PR|codecov/' \
  "$tmp/repo/.claude/skills/core-a/SKILL.md"
check "拿掉一個詞讓它變綠會被抓到" 1 "詞表少了「branch」" --baseline "$base"

# ── 量不到不是通過 ─────────────────────────────────────────────────
reset_fixture
rm "$tmp/repo/.claude/skills/core-a/SKILL.md"
check "一條宣告都沒有時 exit 2" 2 "一條 PROSE-LAYER 宣告都沒有"

reset_fixture
sed -i.bak 's/不得出現在 core-a,core-b/不得出現在 core-a,core-nowhere/' \
  "$tmp/repo/.claude/skills/core-a/SKILL.md"
check "範圍指向不存在的 skill 時 exit 2" 2 "解不出任何目錄"

echo "gate-layer-vocabulary selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
