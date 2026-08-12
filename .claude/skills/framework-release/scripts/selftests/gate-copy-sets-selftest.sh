#!/usr/bin/env bash
# Selftest for gate-copy-sets.sh —— 每個 case 先做出一棵已知狀態的假樹再看它判什麼。
#
# 這道閘的價值在三件事上：**漂了要紅、無主要紅、掃不到要用 2 停下來而不是回綠。** 所以
# 下面每一類都有一個「注入之後必須變紅」的 case，以及一個「一開始就是對的」的正例——只有
# 反例的話，一個永遠回 1 的閘也會全綠。
#
# 另外三組 case 守的是判準本身：
#   - 不得被放寬（A-N2）：`scripts/` 與 `scripts/lib/` 底下的同名檔仍然算同一組——改用相對
#     路徑當鍵會弄丟它，而那正是 A-P4 第一版簽錯的地方。
#   - 不得噴假紅：`SKILL.md` 與 handbook 底下各對象一份的 `index.md` 不得被算成副本。
#   - 看不見的那一類要說出來（A-P4 (f)）：鍵是檔名，所以「同一份東西被抄成另一個名字」這道
#     閘抓不到。**綠的那一次也要印出這個盲區**——綠的時候才是最容易被讀成「掃完了」的時候。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-copy-sets.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# fixture：一棵最小但形狀齊全的假樹——兩支 skill 各帶一份同名腳本與一份同名 reference，
# 加上足夠多的填充檔讓 preflight 過得去（下限 50）。
reset_fixture() {
  rm -rf "$tmp/repo"
  local a="$tmp/repo/.claude/skills/alpha" b="$tmp/repo/.claude/skills/beta"
  mkdir -p "$a/scripts/lib" "$a/references/handbook/one" \
           "$b/scripts/lib" "$b/references/handbook/two"
  printf -- '---\nname: alpha\n---\n# alpha 自己的身分檔\n' > "$a/SKILL.md"
  printf -- '---\nname: beta\n---\n# beta 自己的身分檔，內容跟 alpha 不一樣\n' > "$b/SKILL.md"

  # 真副本：同名、逐位元相同。刻意讓兩邊的目錄深度不同（scripts/ vs scripts/lib/）。
  echo 'echo shared' > "$a/scripts/shared-helper.sh"
  echo 'echo shared' > "$b/scripts/lib/shared-helper.sh"
  # 真副本：references/ 直屬的散文。
  echo '# 同一份權威定義' > "$a/references/shared-note.md"
  echo '# 同一份權威定義' > "$b/references/shared-note.md"
  # 假副本：handbook 底下各對象一份，同名但不是同一個東西。
  echo '# one 的手冊' > "$a/references/handbook/one/index.md"
  echo '# two 的手冊' > "$b/references/handbook/two/index.md"

  # 填充：讓管轄內的檔案數過得了 preflight 下限。
  local i
  for i in $(seq 1 30); do
    echo "echo $i" > "$a/scripts/filler-a-$i.sh"
    echo "echo $i" > "$b/scripts/filler-b-$i.sh"
  done

  cat > "$tmp/decl.json" <<'JSON'
{
  "copy_groups": [
    { "why": "測試用：這兩組是刻意的副本。", "scripts": ["shared-helper.sh", "shared-note.md"] }
  ],
  "not_copy_sets": []
}
JSON
}

check() {
  local name="$1" want="$2" needle="${3:-}"
  local out rc
  out="$(bash "$SCRIPT" --repo "$tmp/repo" --declaration "$tmp/decl.json" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL ${name}：期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'
    fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL ${name}：訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'
    fail=$((fail+1)); return
  fi
  echo "PASS ${name}"; pass=$((pass+1))
}

# ── 正例：一棵本來就對的樹 ─────────────────────────────────────
reset_fixture
check "都一致、都有理由 → 綠" 0 "2 組副本逐位元一致"

# ── 反例一：漂了 ──────────────────────────────────────────────
reset_fixture
echo 'echo drifted' > "$tmp/repo/.claude/skills/beta/scripts/lib/shared-helper.sh"
check "腳本副本被改掉一份 → 紅" 1 "POLARIS_COPY_SET_DRIFTED"

reset_fixture
echo '# 被改過的權威定義' > "$tmp/repo/.claude/skills/beta/references/shared-note.md"
check "散文副本被改掉一份 → 紅" 1 "POLARIS_COPY_SET_DRIFTED"

# ── 反例二：無主 ──────────────────────────────────────────────
reset_fixture
echo 'echo orphan' > "$tmp/repo/.claude/skills/alpha/scripts/orphan.sh"
echo 'echo orphan' > "$tmp/repo/.claude/skills/beta/scripts/orphan.sh"
check "多出一組沒有理由的副本 → 紅" 1 "POLARIS_COPY_SET_UNDECLARED"

# ── 反例三：宣告過期 ──────────────────────────────────────────
reset_fixture
rm "$tmp/repo/.claude/skills/beta/scripts/lib/shared-helper.sh"
check "宣告源指向只剩一份的 → 紅" 1 "POLARIS_COPY_SET_STALE_DECLARATION"

reset_fixture
python3 - "$tmp/decl.json" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d["not_copy_sets"] = [{"name": "nothing-like-this.sh", "why": "測試用：指名一個樹上沒有的名字。"}]
p.write_text(json.dumps(d, ensure_ascii=False))
PY
check "排除清單指名一個不是副本的名字 → 紅" 1 "排除清單指名了這幾個名字"

# ── 看不見的那一類要說出來，綠的時候也要說（A-P4 (f)）───────────
reset_fixture
check "綠的時候也印出改名副本這個盲區" 0 "DISCLOSURE"

reset_fixture
cp "$tmp/repo/.claude/skills/alpha/scripts/shared-helper.sh" \
   "$tmp/repo/.claude/skills/beta/scripts/renamed-helper.sh"
check "同一份東西被抄成另一個名字 → 閘看不見，但盲區有說出來" 0 "DISCLOSURE"

# ── 判準不得被放寬 ────────────────────────────────────────────
reset_fixture
check "scripts/ 與 scripts/lib/ 的同名檔算同一組" 0 "2 組副本"

reset_fixture
# 把兩支 skill 的身分檔與 handbook 索引都改成同一個內容也不該讓它們變成「副本」——
# 它們一開始就不在管轄內，內容一不一樣都不影響。
echo '# 一樣的內容' > "$tmp/repo/.claude/skills/alpha/SKILL.md"
echo '# 一樣的內容' > "$tmp/repo/.claude/skills/beta/SKILL.md"
check "SKILL.md 不進管轄，內容相同也不算副本" 0 "2 組副本"

reset_fixture
echo '# 一樣的手冊' > "$tmp/repo/.claude/skills/alpha/references/handbook/one/index.md"
echo '# 一樣的手冊' > "$tmp/repo/.claude/skills/beta/references/handbook/two/index.md"
check "handbook 底下的 index.md 不進管轄" 0 "2 組副本"

# ── 量不到：要用 2 停下來，不是回綠也不是判紅 ──────────────────
reset_fixture
rm -rf "$tmp/repo/.claude/skills"
check "skills 樹不在 → 量不到" 2 "量不到"

reset_fixture
rm "$tmp/decl.json"
check "宣告源不在 → 量不到" 2 "量不到"

reset_fixture
rm -rf "$tmp/repo/.claude/skills/beta"
find "$tmp/repo/.claude/skills/alpha/scripts" -name 'filler-a-*' -delete
check "管轄內檔案少到掃描本身壞了 → 量不到" 2 "下限"

echo
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
