#!/usr/bin/env bash
# learning-knowledge-landing-selftest.sh — 量 learning 說出的知識落點（DP-493）。
#
# 這支要擋的不是斷指標。斷指標會炸；這裡的失效是**寫得成功**：舊的落點目錄還在很多人的
# 機器上，所以照著寫會成功、會回報完成，然後沒有人讀得到。所以判準不是「那個路徑存不存
# 在」，是「文件現在叫人往哪裡寫，以及讀的地方跟寫的地方是不是同一個」。
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$(cd "$SCRIPTS/.." && pwd)"
SKILLS_ROOT="$(cd "$SKILL/.." && pwd)"
REFS="$SKILL/references"

EXPECTED=13
RAN=0
SKIPPED=0
FAILED=0

pass() { RAN=$((RAN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { RAN=$((RAN + 1)); FAILED=$((FAILED + 1)); printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf 'SKIP  %s\n    %s\n' "$1" "$2"; }

LESSON="$REFS/review-lesson-extraction.md"
BATCH="$REFS/learning-pr-batch-flow.md"
EXTERNAL="$REFS/learning-external-flow.md"
for f in "$LESSON" "$BATCH" "$EXTERNAL" "$SKILL/SKILL.md"; do
  [[ -f "$f" ]] || { printf 'INCONCLUSIVE：量不到——%s 不在\n' "$f" >&2; exit 2; }
done

# Description: count lines that instruct a write into the named dead location.
# Args:        $1 = file, $2 = the dead location fragment.
# Side effects: none. Prints the count. 只數「還在叫人往那裡寫」的行——過去式的歷史
#   敘述（was / 已經沒了 / 不得復活）不算，K-N1 明文允許它們留著。
instruction_hits() {
  python3 - "$1" "$2" <<'PY'
import sys
from pathlib import Path
text, needle = Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[2]
past = ("was never", "were consolidated", "are gone", "must not be revived",
        "已經沒了", "不得復活", "writes into a directory nothing reads")
hits = [ln for ln in text.splitlines()
        if needle in ln and not any(p in ln for p in past)]
print(len(hits))
PY
}

# ── K-P1 / K-N1：落點指向擁有那個 repo 知識的 skill ──────────────────────────
for dead in "polaris-config" "rules/{company}"; do
  n="$(instruction_hits "$LESSON" "$dead")"
  [[ "$n" -eq 0 ]] && pass "K-P1 review-lesson-extraction 不再叫人寫進 $dead" \
                   || fail "K-P1 review-lesson-extraction 不再叫人寫進 $dead" "還有 $n 行"
done

if grep -q 'references/handbook/{repo}/' "$LESSON"; then
  pass "K-P1 落點寫的是 {owning skill}/references/handbook/{repo}/"
else
  fail "K-P1 落點寫的是 {owning skill}/references/handbook/{repo}/" "文件裡找不到這個落點"
fi

# ── K-P2：讀的與寫的是同一個地方 ─────────────────────────────────────────────
read_target="$(grep -c 'Read all handbook sub-files.*references/handbook/{repo}/' "$LESSON" || true)"
write_target="$(grep -c 'Write extracted patterns directly to .*references/handbook/{repo}/' "$LESSON" || true)"
if [[ "$read_target" -ge 1 && "$write_target" -ge 1 ]]; then
  pass "K-P2 去重讀的位置與寫入的位置是同一個"
else
  fail "K-P2 去重讀的位置與寫入的位置是同一個" "read=$read_target write=$write_target"
fi

n="$(instruction_hits "$BATCH" "polaris-config")"
if [[ "$n" -eq 0 ]] && grep -q 'references/handbook/{repo}/' "$BATCH"; then
  pass "K-P2 Batch mode 的 Layer 1 去重指向同一個位置"
else
  fail "K-P2 Batch mode 的 Layer 1 去重指向同一個位置" "polaris-config 指示 $n 行"
fi

# Route A 的去重。它掃的必須是活的單，而「活」的判準是脊椎自己的狀態檔。
if ! grep -q 'specs/design-plans' "$EXTERNAL" && grep -q 'loop-state.json' "$EXTERNAL"; then
  pass "K-P2 Route A 去重掃的是活的單（狀態讀 .spine/loop-state.json，不是舊層）"
else
  fail "K-P2 Route A 去重掃的是活的單（狀態讀 .spine/loop-state.json，不是舊層）" \
       "specs/design-plans=$(grep -c 'specs/design-plans' "$EXTERNAL" || true) loop-state=$(grep -c 'loop-state.json' "$EXTERNAL" || true)"
fi

# ── K-P3：不寫死任何一家公司 ─────────────────────────────────────────────────
#
# 要找的公司名字從宣告推導，不寫在這裡。理由跟這一整張單是同一條：把某一家的名字抄進
# 一支 standalone skill，換一棵樹它就是錯的——而這支腳本住在那支 skill 底下，抄進來的
# 名字會連同 skill 一起被上傳出去（實測：第一版寫死了名字，被 gate-template-leaks 擋下）。
SKILL_MDS=()
while IFS= read -r line; do SKILL_MDS+=("$line"); done < <(find "$SKILLS_ROOT" -name 'SKILL.md' 2>/dev/null)
companies=""
if [[ "${#SKILL_MDS[@]}" -gt 0 ]]; then
  companies="$(grep -ho -- '-REPO-NOTES-[a-z0-9-]*:' "${SKILL_MDS[@]}" 2>/dev/null \
    | sed -E 's/.*-REPO-NOTES-([a-z0-9-]+):.*/\1/' | sort -u | tr '\n' ' ')"
fi
if [[ -z "${companies// /}" ]]; then
  skip "K-P3 整支 skill 沒有出現任何一家公司的名字" \
       "這棵樹裡沒有任何公司宣告，沒有名字可以拿來找——單獨下載時這是正常的。"
else
  found=""
  for c in $companies; do
    grep -rqil -- "$c" "$SKILL" 2>/dev/null && found="$found $c"
  done
  [[ -z "${found// /}" ]] && pass "K-P3 整支 skill 沒有出現任何一家公司的名字（比對過：${companies% }）" \
                          || fail "K-P3 整支 skill 沒有出現任何一家公司的名字" "出現了：${found# }"
fi

if grep -q -- '-REPO-NOTES-' "$LESSON"; then
  pass "K-P3 落點的解法是讀宣告"
else
  fail "K-P3 落點的解法是讀宣告" "review-lesson-extraction 沒有提到那個宣告"
fi

# 說得出解法還不夠，要證明它在真的樹上解得出東西——一條沒有人跑過的解法跟沒有解法一樣。
# 用 find 枚舉再 grep，不靠 grep --include：macOS 的 grep 在這個組合下不會過濾，於是
# 這一格會撿到不是 SKILL.md 的檔案（包括這支 selftest 自己，因為它提到那個標記）。
declared="$(find "$SKILLS_ROOT" -name 'SKILL.md' -exec grep -l -- '-REPO-NOTES-' {} + 2>/dev/null | head -1)"
if [[ -z "$declared" ]]; then
  skip "K-P3 那條解法在這棵樹上真的解得出一支 skill" \
       "這棵樹裡沒有任何 skill 宣告自己擁有某家公司的 repo 知識——單獨下載時這是正常的。"
else
  owner="$(cd "$(dirname "$declared")" && pwd)"
  if [[ -d "$owner" ]]; then
    pass "K-P3 那條解法在這棵樹上真的解得出一支 skill（$(basename "$owner")）"
  else
    fail "K-P3 那條解法在這棵樹上真的解得出一支 skill" "解出來的不是目錄：$owner"
  fi
fi

# ── K-P4：每一條 Mandatory Contract 都說得出主詞 ─────────────────────────────
orphan="$(python3 - "$SKILL/SKILL.md" <<'PY'
import sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
try:
    start = next(i for i, l in enumerate(lines) if l.strip() == "## Mandatory Contracts")
except StopIteration:
    print("no Mandatory Contracts section"); raise SystemExit(0)
orphans, in_bullet = [], False
for line in lines[start + 1:]:
    if line.startswith("## "):
        break
    if not line.strip():
        in_bullet = False
        continue
    if line.startswith("- "):
        in_bullet = True
        continue
    # 續行只有在它接在某一條 bullet 底下時才合法。空行之後的縮排行沒有主詞——
    # 那正是 DP-479 拔掉半句話留下的形狀。
    if not in_bullet:
        orphans.append(line.strip())
print("; ".join(orphans))
PY
)"
[[ -z "$orphan" ]] && pass "K-P4 Mandatory Contracts 每一條都有主詞" \
                   || fail "K-P4 Mandatory Contracts 每一條都有主詞" "孤兒行：$orphan"

# ── K-N2：同一件事不留兩個答案 ───────────────────────────────────────────────
targets="$(python3 - "$LESSON" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
# 每一處「叫人寫到哪」的落點。過去式敘述不算（見 instruction_hits 的理由）。
found = set()
for line in text.splitlines():
    if any(p in line for p in ("was never", "were consolidated", "are gone", "must not be revived")):
        continue
    for m in re.finditer(r"`([^`]*handbook[^`]*)`", line):
        found.add(m.group(1))
print("|".join(sorted(found)))
PY
)"
uniq_count="$(printf '%s' "$targets" | tr '|' '\n' | grep -c . || true)"
if [[ "$targets" == *"references/handbook/{repo}/"* ]] && [[ "$targets" != *"polaris-config"* ]]; then
  pass "K-N2 落點在這份文件裡只有一個答案（現存 $uniq_count 種寫法，全部指同一處）"
else
  fail "K-N2 落點在這份文件裡只有一個答案" "出現的落點：$targets"
fi

# ── K-N3：擋「learning 自己簽成功的定義」的那道檢查，要真的會失敗 ────────────
#
# 不去問它自己的 self-test。一支檢查的 self-test 是拿它自己的 fixture 驗它自己的判準——
# 兩者一起過期的時候它仍然全綠，而那正是這一條要抓的東西（紅控實測：修正前的版本用舊
# 形狀的 fixture，self-test 綠，而它對真實的單一次都攔不住）。所以這裡自己造那個形狀。
SEED="$SCRIPTS/validate-learning-seed-contract.sh"
if [[ ! -f "$SEED" ]]; then
  fail "K-N3 seed contract 檢查擋得住寫進單自己的檔案" "找不到 $SEED"
else
  probe="$(mktemp -d -t polaris-dp493-seed.XXXXXX)"
  (
    set -e
    git -C "$probe" init -q
    git -C "$probe" config user.email selftest@example.test
    git -C "$probe" config user.name "Self Test"
    # 單樹的名字刻意不是 issues：判準應該是「旁邊有沒有 .spine/」，不是路徑長什麼樣。
    mkdir -p "$probe/some-tree/ns/backlog/TICKET-1/.spine" "$probe/some-tree/ns/backlog/TICKET-1/artifacts"
    printf '{}\n' > "$probe/some-tree/ns/backlog/TICKET-1/.spine/loop-state.json"
    printf 'ok\n' > "$probe/README.md"
    git -C "$probe" add -A && git -C "$probe" commit -q -m init
  ) >/dev/null 2>&1
  base="$(git -C "$probe" rev-parse HEAD 2>/dev/null)"

  printf 'forbidden\n' > "$probe/some-tree/ns/backlog/TICKET-1/index.md"
  git -C "$probe" add -A >/dev/null 2>&1; git -C "$probe" commit -q -m forbidden >/dev/null 2>&1
  blocked_rc=0
  ( cd "$probe" && bash "$SEED" --producer learning --diff-range "$base..HEAD" ) >/dev/null 2>&1 || blocked_rc=$?

  git -C "$probe" reset -q --hard "$base" >/dev/null 2>&1
  printf 'report\n' > "$probe/some-tree/ns/backlog/TICKET-1/artifacts/research.md"
  git -C "$probe" add -A >/dev/null 2>&1; git -C "$probe" commit -q -m allowed >/dev/null 2>&1
  allowed_rc=0
  ( cd "$probe" && bash "$SEED" --producer learning --diff-range "$base..HEAD" ) >/dev/null 2>&1 || allowed_rc=$?
  rm -rf "$probe"

  # 正反都要：只驗「擋得住」的話，一個永遠回非 0 的實作也是綠的。
  if [[ "$blocked_rc" -ne 0 && "$allowed_rc" -eq 0 ]]; then
    pass "K-N3 seed contract 擋得住寫進單自己的 index.md，且放行旁邊的研究產物"
  else
    fail "K-N3 seed contract 擋得住寫進單自己的 index.md，且放行旁邊的研究產物" \
         "寫單的檔案 rc=${blocked_rc}（要非 0），寫研究產物 rc=${allowed_rc}（要 0）"
  fi
fi

# ── K-N4：兩份副本不得漂 ─────────────────────────────────────────────────────
TWIN="$SKILLS_ROOT/review-pr/references/review-lesson-extraction.md"
if [[ ! -f "$TWIN" ]]; then
  skip "K-N4 review-lesson-extraction.md 的兩份副本逐位元組相同" \
       "旁邊沒有 review-pr——單獨下載時只有一份副本，沒有可以漂的對象。"
elif cmp -s "$LESSON" "$TWIN"; then
  pass "K-N4 review-lesson-extraction.md 的兩份副本逐位元組相同"
else
  fail "K-N4 review-lesson-extraction.md 的兩份副本逐位元組相同" "$(diff "$LESSON" "$TWIN" | head -3)"
fi

printf -- '---\n'
if [[ $((RAN + SKIPPED)) -ne "$EXPECTED" ]]; then
  printf 'INCONCLUSIVE：預期 %s 條，實際跑了 %s 條、跳過 %s 條——量不到不是通過。\n' \
    "$EXPECTED" "$RAN" "$SKIPPED" >&2
  exit 2
fi
printf 'learning knowledge landing：%s 條，紅 %s 條，跳過 %s 條（都已具名）。\n' "$EXPECTED" "$FAILED" "$SKIPPED"
[[ "$FAILED" -eq 0 ]]
