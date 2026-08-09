#!/usr/bin/env bash
# Selftest for gate-source-destination.sh —— 每個 case 先做出一個已知的位置再看它判什麼。
#
# 這道閘的價值全在「說不準的時候判紅」。所以下面有兩個 case 專門餵它沒見過的路徑：
# 一個放行的版本會在那兩個 case 上變綠，而在其餘每一個 case 上都跟現在一樣。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-source-destination.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# fixture：一個帶著公司目錄與一支公司 skill 的工作區，外加一張走過脊椎的單。
reset_fixture() {
  local destination="${1:-workspace}"
  rm -rf "$tmp/repo"
  mkdir -p "$tmp/repo/.claude/skills/shared" "$tmp/repo/.claude/skills/acme/one" \
           "$tmp/repo/acme" "$tmp/repo/issues/ns/T-1/.spine" "$tmp/repo/tools"
  echo 'company: acme' > "$tmp/repo/acme/workspace-config.yaml"
  printf -- '---\nname: shared\nscope: standalone\n---\n# 會出去的那一支\n' \
    > "$tmp/repo/.claude/skills/shared/SKILL.md"
  printf -- '---\nname: one\nscope: company-only\n---\n# 不會出去的那一支\n' \
    > "$tmp/repo/.claude/skills/acme/one/SKILL.md"
  echo 'echo hi' > "$tmp/repo/tools/helper.sh"
  echo 'runtime-state/' > "$tmp/repo/.gitignore"
  mkdir -p "$tmp/repo/runtime-state"
  echo 'local' > "$tmp/repo/runtime-state/notes.md"
  printf -- '---\ntitle: T-1\ndestination: %s\n---\n\n# T-1\n' "$destination" \
    > "$tmp/repo/issues/ns/T-1/index.md"
  echo '{"schema_version":2,"station":"engineering"}' \
    > "$tmp/repo/issues/ns/T-1/.spine/loop-state.json"
  git -C "$tmp/repo" init -q
  git -C "$tmp/repo" config user.email t@t; git -C "$tmp/repo" config user.name t
  git -C "$tmp/repo" add -A; git -C "$tmp/repo" commit -qm init
}

check() {
  local name="$1" want="$2" needle="${3:-}"; shift 3 || shift 2
  local out rc
  out="$(bash "$SCRIPT" --repo "$tmp/repo" --issue issues/ns/T-1 "$@" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: 期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL $name: 訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  echo "PASS $name"; pass=$((pass+1))
}

# ── 正例：改到的都是確定不會出去的位置 ─────────────────────────────
reset_fixture
check "公司 skill 底下的改動留得住" 0 "全部留得住" \
  --changed .claude/skills/acme/one/SKILL.md
reset_fixture
check "公司自己的目錄留得住" 0 "全部留得住" --changed acme/workspace-config.yaml
reset_fixture
check "沒有版控的檔案留得住" 0 "全部留得住" --changed runtime-state/notes.md

# ── 反例：位置會出去 ───────────────────────────────────────────────
reset_fixture
check "共用 skill 的改動要被指名" 1 ".claude/skills/shared/SKILL.md" \
  --changed .claude/skills/shared/SKILL.md

# 說不準不等於沒事。一條沒見過的頂層路徑要判紅——放行的版本只在這裡跟現在不一樣。
reset_fixture
check "沒見過的位置判紅，不放行" 1 "tools/helper.sh" --changed tools/helper.sh
reset_fixture
check "根目錄檔案判紅" 1 ".gitignore" --changed .gitignore

# 逐條說出是哪幾個：只說「有東西不對」的訊息，看的人不知道該改宣告還是該拆單。
reset_fixture
out="$(bash "$SCRIPT" --repo "$tmp/repo" --issue issues/ns/T-1 \
  --changed .claude/skills/shared/SKILL.md --changed tools/helper.sh \
  --changed .claude/skills/acme/one/SKILL.md 2>&1)" || true
if [[ "$out" == *"shared/SKILL.md"* && "$out" == *"tools/helper.sh"* \
      && "$out" == *"認不出來 2"* ]]; then
  echo "PASS 混在一起時逐條說出是哪幾個"; pass=$((pass+1))
else
  echo "FAIL 混在一起時逐條說出是哪幾個"; echo "$out" | sed 's/^/     /'; fail=$((fail+1))
fi

# ── 不代人改宣告 ───────────────────────────────────────────────────
reset_fixture
before="$(shasum "$tmp/repo/issues/ns/T-1/index.md" | cut -d' ' -f1)"
bash "$SCRIPT" --repo "$tmp/repo" --issue issues/ns/T-1 \
  --changed .claude/skills/shared/SKILL.md >/dev/null 2>&1 || true
after="$(shasum "$tmp/repo/issues/ns/T-1/index.md" | cut -d' ' -f1)"
if [[ "$before" == "$after" ]]; then
  echo "PASS 判紅之後宣告一個字都沒被動過"; pass=$((pass+1))
else
  echo "FAIL 判紅之後宣告被改寫了"; fail=$((fail+1))
fi

# ── 不適用的兩種，各自說出理由 ─────────────────────────────────────
reset_fixture template
check "template 的單不受位置限制" 0 "不適用" --changed .claude/skills/shared/SKILL.md
reset_fixture
rm "$tmp/repo/issues/ns/T-1/.spine/loop-state.json"
check "沒開過輪次的單不適用" 0 "沒有在這個工作區開過輪次" \
  --changed .claude/skills/shared/SKILL.md

# ── 量不到不是通過 ─────────────────────────────────────────────────
reset_fixture
printf -- '---\ntitle: T-1\n---\n\n# T-1\ndestination: workspace 這一行是散文\n' \
  > "$tmp/repo/issues/ns/T-1/index.md"
check "沒有宣告時 exit 2" 2 "沒有 destination" --changed .claude/skills/shared/SKILL.md
reset_fixture nowhere
check "不認得的宣告值 exit 2" 2 "不認得的 destination" --changed .claude/skills/shared/SKILL.md
reset_fixture
check "推不出清單時 exit 2" 2 "看不到" --head deadbeefdeadbeefdeadbeefdeadbeefdeadbeef

echo "gate-source-destination selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
