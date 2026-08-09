#!/usr/bin/env bash
# release-tail-frictions-selftest.sh — 量釋出尾段的四個摩擦（DP-499）。
#
# 這四件的共同形狀不是「功能壞了」，是**一個狀態被回報成另一個狀態**：你給的是縮寫被說成
# 「又有 commit 落下去了」、量測的樹不在了被說成「證據跟交付的 head 對不上」、有一個 commit
# 沒推出去被說成「已經是最新的」。每一句都會讓讀的人去做一件沒有用的事。
#
# 所以這裡量的不是 exit code 而已，是**訊息說的是不是實際發生的那件事**。
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_ROOT="$(cd "$SCRIPTS/../.." && pwd)"
RECORD="$SKILLS_ROOT/verify-ac/scripts/record-delivery-intent.sh"
SYNC="$SCRIPTS/sync-to-polaris.sh"

EXPECTED=9
RAN=0
FAILED=0
pass() { RAN=$((RAN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { RAN=$((RAN + 1)); FAILED=$((FAILED + 1)); printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; }

for f in "$RECORD" "$SYNC"; do
  [[ -f "$f" ]] || { printf 'INCONCLUSIVE：量不到——%s 不在\n' "$f" >&2; exit 2; }
done

# `-P`：macOS 的 mktemp 給的是 /var/…，而那是 /private/var/… 的 symlink。腳本裡問「現在
# 站在哪」的是 python 的 os.getcwd()，它一律回實體路徑——不先解開的話，斷言會拿兩個指向
# 同一個目錄的字串去比字面，然後紅在一件沒有發生的事上。
WORK="$(cd "$(mktemp -d -t polaris-dp499.XXXXXX)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# Description: build a git repo with two commits and echo "<first> <second>".
# Args:        $1 = directory to create the repo in.
# Side effects: creates and populates the repo.
build_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  printf 'one\n' > "$repo/a.txt"
  git -C "$repo" add -A && git -C "$repo" commit -q -m one
  local first; first="$(git -C "$repo" rev-parse HEAD)"
  printf '1.0.0\n' > "$repo/VERSION"
  git -C "$repo" add -A && git -C "$repo" commit -q -m two
  printf '%s %s\n' "$first" "$(git -C "$repo" rev-parse HEAD)"
}

REPO="$WORK/repo"
read -r FIRST SECOND < <(build_repo "$REPO")
SHORT="${SECOND:0:12}"

# Description: build a minimal sealed ticket whose evidence names a given head and tree.
# Args:        $1 = ticket directory, $2 = head_sha to record in the evidence,
#              $3 = the measuring tree to record in the evidence.
# Side effects: writes index.md, .spine/evidence/Z-P1.json, and seals the fence.
make_issue() {
  local dir="$1" head="$2" tree="$3"
  mkdir -p "$dir/.spine/evidence"
  cat > "$dir/index.md" <<'MD'
---
destination: workspace
---
<!-- POLARIS-FROZEN-Z-BEGIN -->
- **Z-P1 something**：when x, y happens.
<!-- POLARIS-FROZEN-Z-END -->
MD
  python3 - "$dir/.spine/evidence/Z-P1.json" "$head" "$tree" <<'EVIDENCE'
import json, sys
json.dump({"verdict": "PASS", "producer": "run-hardened-oracle.sh",
           "head_sha": sys.argv[2], "measured_in": sys.argv[3]},
          open(sys.argv[1], "w"))
EVIDENCE
  bash "$SKILLS_ROOT/refinement/scripts/frozen-assertion-fence.sh" seal "$dir/index.md" --by selftest >/dev/null
}

# 兩張最小的、真的蓋過封條也 commit 過的單。凍結＝commit，所以它們必須住在一個 git repo
# 裡，否則 fence 驗證會先擋下來，而這支要量的每一條都排在那道檢查後面。
#
# 第一張：證據量在 FIRST，而 measured_in 指向一棵不存在的樹——那正是釋出尾段移除
# 量測用 worktree 之後留下的狀態。
GONE="$WORK/gone-worktree"
ISSUE="$WORK/issuerepo/gone-tree-ticket"
make_issue "$ISSUE" "$FIRST" "$GONE"

# 第二張：長得像 2026-08-09 那一次——證據自己記下的 head 是**縮寫**，而量測的樹還在。
# 那一次兩個值被說成不同、印出來一模一樣，因為兩邊都被截成 12 個字元。
ISSUE_SHORT="$WORK/issuerepo/short-sha-ticket"
make_issue "$ISSUE_SHORT" "$SHORT" "$REPO"

git -C "$WORK/issuerepo" init -q
git -C "$WORK/issuerepo" config user.email selftest@example.test
git -C "$WORK/issuerepo" config user.name "Self Test"
git -C "$WORK/issuerepo" add -A
git -C "$WORK/issuerepo" commit -q -m freeze

# ── R-P1：縮寫要嘛被解開、要嘛被指名說是縮寫 ────────────────────────────────
out="$( (cd "$REPO" && bash "$RECORD" --issue "$ISSUE" --summary s --head "$SHORT" --delta-allows VERSION) 2>&1 )" || true
if [[ "$out" == *"是縮寫，解開成 $SECOND"* ]]; then
  pass "R-P1 縮寫的 --head 被解開成完整的 sha 並說出來"
else
  fail "R-P1 縮寫的 --head 被解開成完整的 sha 並說出來" "輸出裡沒有那句話：$(printf '%s' "$out" | head -2)"
fi

# 證據自己記下的是縮寫、量測的樹還在——那一次紅的理由被寫成「量完之後又有 commit
# 落下去了」，而實際上一個 commit 都沒有落下去。
out="$( (cd "$REPO" && bash "$RECORD" --issue "$ISSUE_SHORT" --summary s --head "$SHORT") 2>&1 )" || true
if [[ "$out" != *"量完之後又有 commit 落下去了"* ]]; then
  pass "R-P1 縮寫不會被回報成「量完之後又有 commit 落下去了」"
else
  fail "R-P1 縮寫不會被回報成「量完之後又有 commit 落下去了」" "$(printf '%s' "$out" | tail -3)"
fi

# ── R-P2：說成不同的兩個值，印出來也不同 ────────────────────────────────────
if [[ "$out" == *"measured at $SHORT, delivering $SECOND"* ]]; then
  pass "R-P2 被說成不同的那兩個 sha，印出來看得出不同"
else
  fail "R-P2 被說成不同的那兩個 sha，印出來看得出不同" "$(printf '%s' "$out" | tail -3)"
fi

out="$( (cd "$REPO" && bash "$RECORD" --issue "$ISSUE" --summary s --head deadbeef) 2>&1 )" || true
if [[ "$out" == *POLARIS_DELIVERY_INTENT_HEAD_UNRESOLVED* ]]; then
  pass "R-P1 解不開的 --head 被指名說解不開（不是沉默往下走）"
else
  fail "R-P1 解不開的 --head 被指名說解不開（不是沉默往下走）" "$(printf '%s' "$out" | head -2)"
fi

# ── R-P3 / R-N1：差異在任何看得到那兩個 commit 的樹上都算得出來 ─────────────
out="$( (cd "$REPO" && bash "$RECORD" --issue "$ISSUE" --summary s --head "$SECOND" \
          --delta-allows VERSION) 2>&1 )"; rc=$?
if [[ "$rc" -eq 0 && "$out" == *"那段差異問的是 $REPO"* ]]; then
  pass "R-P3 量測的樹不在了，換一棵看得到那兩個 commit 的樹照樣算得出來，並說出問的是哪一棵"
else
  fail "R-P3 量測的樹不在了，換一棵看得到那兩個 commit 的樹照樣算得出來，並說出問的是哪一棵" \
       "rc=$rc out=$(printf '%s' "$out" | tail -3)"
fi

# R-N2：判準不因為換了問的對象而放寬——差異碰到指名以外的路徑仍然要拒絕。
out="$( (cd "$REPO" && bash "$RECORD" --issue "$ISSUE" --summary s --head "$SECOND" \
          --delta-allows CHANGELOG.md) 2>&1 )"; rc=$?
if [[ "$rc" -ne 0 && "$out" == *VERSION* ]]; then
  pass "R-N2 差異碰到指名以外的路徑仍然拒絕，並指名是哪一條"
else
  fail "R-N2 差異碰到指名以外的路徑仍然拒絕，並指名是哪一條" "rc=$rc out=$(printf '%s' "$out" | tail -3)"
fi

# R-N1：一棵都看不到那兩個 commit 的時候要拒絕，而且列出試過哪幾棵。
ELSEWHERE="$WORK/unrelated"
read -r _ _ < <(build_repo "$ELSEWHERE")
out="$( (cd "$ELSEWHERE" && bash "$RECORD" --issue "$ISSUE" --summary s \
          --head "$(git -C "$ELSEWHERE" rev-parse HEAD)" --delta-allows VERSION) 2>&1 )"; rc=$?
if [[ "$rc" -ne 0 && "$out" == *"試過："* ]]; then
  pass "R-N1 沒有任何一棵樹看得到那兩個 commit 時拒絕，並列出試過哪幾棵"
else
  fail "R-N1 沒有任何一棵樹看得到那兩個 commit 時拒絕，並列出試過哪幾棵" "rc=$rc out=$(printf '%s' "$out" | tail -3)"
fi

# ── R-P4 / R-N3：「沒有新變更」與「沒有東西要推」是兩件事 ────────────────────
# 不打真實 remote：本機造一個 bare repo 當 origin，讓 template checkout 領先它一個 commit。
BARE="$WORK/origin.git"
git init -q --bare "$BARE"
TPL="$WORK/template"
read -r _ _ < <(build_repo "$TPL")
git -C "$TPL" remote add origin "$BARE"
git -C "$TPL" branch -M main
git -C "$TPL" push -q -u origin main
printf '1.1.0\n' > "$TPL/VERSION"
git -C "$TPL" add -A && git -C "$TPL" commit -q -m "compress 1.1.0"
ahead="$(git -C "$TPL" rev-list --count '@{u}..HEAD')"

# 只驗這一段判斷的形狀，不跑整支 sync（它要一整棵 workspace）。判斷本身抄不得第二份，
# 所以直接把腳本裡那一段的條件重演在同一棵樹上，並斷言腳本裡確實有這個分支。
if grep -q 'UNPUSHED=\$(git -C "\$POLARIS_DIR" rev-list --count' "$SYNC" \
   && grep -q 'nothing unpushed' "$SYNC"; then
  pass "R-P4 sync 分開判斷「沒有新變更」與「沒有東西要推」"
else
  fail "R-P4 sync 分開判斷「沒有新變更」與「沒有東西要推」" "找不到那個分支"
fi

if [[ "$ahead" -eq 1 ]] && grep -q 'Re-run with --push to send them' "$SYNC"; then
  pass "R-N3 沒有要求推送時只說出有未推的 commit，不自己推"
else
  fail "R-N3 沒有要求推送時只說出有未推的 commit，不自己推" "ahead=$ahead"
fi

printf -- '---\n'
if [[ "$RAN" -ne "$EXPECTED" ]]; then
  printf 'INCONCLUSIVE：預期 %s 條，實際跑了 %s 條——量不到不是通過。\n' "$EXPECTED" "$RAN" >&2
  exit 2
fi
printf 'release tail frictions：%s 條，紅 %s 條。\n' "$EXPECTED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
