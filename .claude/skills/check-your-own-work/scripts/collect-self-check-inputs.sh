#!/usr/bin/env bash
# Description: 把「交出去之前的八問」各自需要的輸入蒐集起來，逐問印出來；拿不到的那幾問
#              指名說出為什麼拿不到。它不判定、不擋人，只負責讓「沒問到」與「問了沒事」
#              長得不一樣。
# Args: [--repo <path>] [--base <ref>] [--pr <number>]
# Exit: 0 = 蒐集完了（不論八問答得出幾問）；2 = 連蒐集都做不到（不是 git repo）。
#
# 它刻意不認得任何一套流程、任何一家公司、任何一個工作區設定檔：唯一的輸入是「當次執行
# 的那個 git repo」。規範從那個 repo 現場讀，不從記憶讀，也不抄一份放在這支 skill 底下
# ——抄下來的那一份會漂，而漂掉那天沒有人在看。
set -euo pipefail
# 這支唯讀，但它仍然要在死掉的時候大聲——一份印到一半就停的自檢，讀起來跟印完的一模一樣。
trap 'rc=$?; echo; echo "COLLECTOR ABORTED: 第 $LINENO 行非 0（exit ${rc}）。上面印出來的那幾問是全部——後面的沒有跑。" >&2; exit "$rc"' ERR

REPO="."
BASE=""
PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --pr)   PR="$2"; shift 2 ;;
    -h|--help)
      echo "usage: collect-self-check-inputs.sh [--repo <path>] [--base <ref>] [--pr <number>]"
      exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "UNMEASURABLE: $REPO 不是一個 git repo——八問全部建立在「我改了什麼」上，沒有它就沒有輸入。" >&2
  exit 2
}

UNANSWERED=""

show_capped() {  # $1 = 上限；stdin = 內容。印前 N 行，並說出被截掉幾行。
  local cap="$1" body total
  body="$(cat)"
  total="$(printf '%s\n' "$body" | grep -c . || true)"
  [ "$total" = "0" ] && { echo "  （沒有）"; return; }
  printf '%s\n' "$body" | grep . | head -"$cap" | sed 's/^/  /'
  if [ "$total" -gt "$cap" ]; then
    echo "  … 還有 $((total - cap)) 行沒印出來。**這是截斷，不是「就這些」**——要看全部就直接讀 diff。"
  fi
}
note_unanswerable() {  # $1 = 問題編號, $2 = 為什麼
  echo "UNANSWERABLE $1: $2"
  UNANSWERED="$UNANSWERED $1"
}

# ── 先決定「我改了什麼」。三種來源，由近到遠，取第一個非空的。 ──────────────────
resolve_base() {
  if [ -n "$BASE" ]; then echo "$BASE"; return; fi
  local head
  head="$(git -C "$REPO" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$head" ]; then echo "${head#refs/remotes/}"; return; fi
  local candidate
  for candidate in origin/main origin/master origin/develop main master develop; do
    if git -C "$REPO" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
      echo "$candidate"; return
    fi
  done
  echo ""
}

BASE_REF="$(resolve_base)"
DIFF_RANGE=""
DIFF_SOURCE=""
if [ -n "$BASE_REF" ] && git -C "$REPO" merge-base --is-ancestor "$BASE_REF" HEAD 2>/dev/null; then
  DIFF_RANGE="$BASE_REF...HEAD"
  DIFF_SOURCE="這條分支相對於 $BASE_REF"
elif [ -n "$BASE_REF" ] && git -C "$REPO" rev-parse --verify --quiet "$BASE_REF" >/dev/null 2>&1; then
  DIFF_RANGE="$BASE_REF...HEAD"
  DIFF_SOURCE="這條分支相對於 ${BASE_REF}（沒有共同祖先，範圍可能偏大）"
fi

CHANGED=""
if [ -n "$DIFF_RANGE" ]; then
  CHANGED="$(git -C "$REPO" diff --name-only "$DIFF_RANGE" 2>/dev/null || true)"
fi
if [ -z "$CHANGED" ]; then
  CHANGED="$(git -C "$REPO" diff --name-only HEAD 2>/dev/null || true)"
  [ -n "$CHANGED" ] && { DIFF_RANGE="HEAD"; DIFF_SOURCE="工作目錄相對於 HEAD（還沒 commit）"; }
fi

echo "=============================================="
echo " 交出去之前，先對一次自己寫的東西"
echo "=============================================="
echo "repo:   $(cd "$REPO" && pwd)"
echo "diff:   ${DIFF_SOURCE:-（找不到任何改動）}"
if [ -n "$CHANGED" ]; then
  echo "檔案:   $(printf '%s\n' "$CHANGED" | grep -c . || true) 個"
  printf '%s\n' "$CHANGED" | sed 's/^/          /'
fi
echo

# ── gh 與 PR 解析一次就好：Q1 要 PR 描述，Q5 要上一輪意見，兩問問的是同一件事。 ──────
GH_STATE=""   # ok | no-binary | no-auth | no-pr
if ! command -v gh >/dev/null 2>&1; then
  GH_STATE="no-binary"
elif ! gh auth status >/dev/null 2>&1; then
  GH_STATE="no-auth"
else
  if [ -z "$PR" ]; then
    PR="$(cd "$REPO" && gh pr view --json number --jq .number 2>/dev/null || true)"
  fi
  if [ -z "$PR" ]; then GH_STATE="no-pr"; else GH_STATE="ok"; fi
fi
NWO=""
[ "$GH_STATE" = "ok" ] && NWO="$(cd "$REPO" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"

gh_unavailable_why() {
  case "$GH_STATE" in
    no-binary) echo "gh 不在 PATH 上。裝了 GitHub CLI 並登入之後再問一次。" ;;
    no-auth)   echo "gh 在，但沒有登入——跑 gh auth login。" ;;
    no-pr)     echo "這條分支還沒有對應的 PR。" ;;
    *)         echo "" ;;
  esac
}

# ── Q1 我寫下的每一句宣稱，在 diff 裡都找得到對應的改動嗎 ────────────────────────
echo "── Q1 宣稱與 diff 對不上 ──"
if [ -z "$CHANGED" ]; then
  note_unanswerable Q1 "diff 是空的——沒有改動就沒有宣稱要對照。"
else
  echo "[宣稱來源零：PR 描述——**最常出事的就是這一份**]"
  if [ "$GH_STATE" = "ok" ]; then
    body="$(cd "$REPO" && gh pr view "$PR" --json body --jq .body 2>/dev/null || true)"
    if [ -z "$body" ]; then
      echo "  （PR #$PR 沒有描述）"
    else
      printf '%s\n' "$body" | show_capped 80
    fi
  else
    echo "  拿不到：$(gh_unavailable_why)"
    echo "  **這一項空著不等於沒有宣稱**——手上有 PR 描述的話自己貼進來對一次。"
  fi
  echo
  echo "[宣稱來源一：這條分支的 commit message]"
  if [ -n "$DIFF_RANGE" ] && [ "$DIFF_RANGE" != "HEAD" ]; then
    git -C "$REPO" log --format='  %h %s%n%w(78,4,4)%b' "${DIFF_RANGE%...*}..HEAD" 2>/dev/null | sed '/^$/d' || true
  else
    echo "  （還沒 commit，這一項沒有內容）"
  fi
  echo
  echo "[宣稱來源二：diff 裡新增的敘述性文字——註解、docstring、型別宣告、名字]"
  git -C "$REPO" diff -U0 "$DIFF_RANGE" 2>/dev/null \
    | grep -E '^[+]' | grep -Ev '^[+]{3}' \
    | grep -E '(//|#|/[*]|[*] |"""|<!--|@param|@returns|@description|:[[:space:]]*(string|number|boolean|Array|Record))' \
    | show_capped 60 || true
  echo
  echo "[宣稱來源三：diff 裡的版本／發佈說明檔]"
  printf '%s\n' "$CHANGED" | grep -Ei '(changeset|changelog|release-notes)' | sed 's/^/  /' || echo "  （沒有）"
  echo
  echo "對照方式：上面每一句話都是一個承諾。逐句問「這句現在還是真的嗎」，"
  echo "拿 diff 的實際內容回答，不要拿記憶回答。"
fi
echo

# ── Q2 這個 repo 自己的規範說了什麼 ──────────────────────────────────────────────
echo "── Q2 repo 既有規範沒套用 ──"
RULES=""
for spot in CLAUDE.md AGENTS.md GEMINI.md .cursorrules .windsurfrules; do
  [ -f "$REPO/$spot" ] && RULES="$RULES$spot"$'\n'
done
# 只找宣告規範的地方。**不掃 .claude/skills/**——一支 skill 是一份可執行的流程，
# 不是這個 repo 對程式碼下的規矩；把它們算進來會讓「這個 repo 有幾份規範」變成一個
# 跟問題無關的大數字，而讀的人分不出哪幾份才是要去讀的。
for dir in .claude/rules .cursor/rules; do
  if [ -d "$REPO/$dir" ]; then
    found="$(cd "$REPO" && find "$dir" -maxdepth 2 \( -name '*.md' -o -name '*.mdc' \) 2>/dev/null | head -40 || true)"
    [ -n "$found" ] && RULES="$RULES$found"$'\n'
  fi
done
if [ -d "$REPO/.github" ]; then
  found="$(cd "$REPO" && find .github -maxdepth 1 -name '*.md' 2>/dev/null | head -10 || true)"
  [ -n "$found" ] && RULES="$RULES$found"$'\n'
fi
if [ -z "$(printf '%s' "$RULES" | tr -d '[:space:]')" ]; then
  note_unanswerable Q2 "這個 repo 一份規範檔都沒有宣告（找過 CLAUDE.md、AGENTS.md、GEMINI.md、.cursorrules、.windsurfrules、.claude/rules/、.cursor/rules/、.github/ 頂層）。沒有規範不等於沒有慣例——那就去讀鄰近的既有程式碼。"
else
  echo "[這個 repo 現場宣告的規範，$(printf '%s\n' "$RULES" | grep -c . || true) 份]"
  printf '%s\n' "$RULES" | grep . | sed 's/^/  /'
  echo
  echo "[這次動到的副檔名]"
  printf '%s\n' "$CHANGED" | sed 's/.*\.//' | sort -u | tr '\n' ' ' | sed 's/^/  /'; echo
  echo
  echo "**去讀它們，不要從記憶答。** 規範會翻面：同一份檔案上個月說 A、這個月說 B，"
  echo "而記得舊版本的那個人不會發現自己記錯了。"
fi
echo

# ── Q3 只改一半／姊妹檔沒對齊 ────────────────────────────────────────────────────
echo "── Q3 只改一半／姊妹檔沒對齊 ──"
if [ -z "$CHANGED" ]; then
  note_unanswerable Q3 "diff 是空的——沒有改動就沒有同型的地方要找。"
else
  CHANGED_LIST="$(printf '%s\n' "$CHANGED" | grep . || true)"
  # 帶 context 抓：reviewer 指的常常不是被改掉的那一行，是**它旁邊那個沒被改的東西**
  # ——「這個檔案有五個 import 站點，你只掛了三個」，那五個都在 context 裡。
  HUNKS="$(git -C "$REPO" diff -U3 "$DIFF_RANGE" 2>/dev/null | grep -Ev '^(diff |index |[-]{3}|[+]{3}|@@)' || true)"

  count_others() {  # stdin = token 一行一個；印出「還有幾個檔案也有」
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      # 逐字撈出來的東西裡混著 regex 與 sed 的碎片（`s/.` 這種）。它們對得上很多檔案，
      # 於是排在最前面，把真正的候選擠下去。要求至少三個英數字元就濾掉絕大多數。
      [ "$(printf '%s' "$tok" | tr -cd 'A-Za-z0-9' | wc -c | tr -d ' ')" -ge 3 ] || continue
      hits="$(git -C "$REPO" grep -l -F -- "$tok" 2>/dev/null || true)"
      [ -n "$hits" ] || continue
      others="$(printf '%s\n' "$hits" | grep -vxF -f <(printf '%s\n' "$CHANGED_LIST") 2>/dev/null | grep -c . || true)"
      [ "${others:-0}" -ge 1 ] && [ "${others:-0}" -le 40 ] || continue
      printf '%s\t%s\n' "$others" "$tok"
    done | sort -rn | head -12 \
      | awk -F'\t' '{ printf "  %-46s 另外 %s 個檔案也有\n", $2, $1 }'
  }

  echo "[一：這一段程式碼附近指名的檔案／路徑，整棵樹還有哪些地方也指到，但這次沒動]"
  printf '%s\n' "$HUNKS" \
    | grep -oE "[A-Za-z0-9_@.-]+/[A-Za-z0-9_@./-]+|[A-Za-z0-9_-]+\.[a-z]{2,4}\b" \
    | sort -u | head -60 | count_others || true
  echo
  echo "[二：這次改到的識別字，整棵樹還有哪些地方也有，但這次沒動]"
  printf '%s\n' "$HUNKS" | grep -E '^[-+]' \
    | grep -oE "[A-Za-z_][A-Za-z0-9_-]{5,}" \
    | sort | uniq -c | sort -rn | awk '{print $2}' | head -40 | count_others || true
  echo "  （這兩份都是從 diff 逐字撈出來的 token，不是語意分析——**它會漏，也會吵**。）"
  echo
  echo "[三：每個動到的檔案，它旁邊還有幾個同副檔名的沒動]"
  printf '%s\n' "$CHANGED" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    d="$(dirname "$f")"; ext="${f##*.}"
    [ -d "$REPO/$d" ] || continue
    # find 的輸出對頂層檔案會帶 ./ 前綴，剝掉再比——不剝的話它把自己算成鄰居，
    # 於是每一個頂層檔案都多出一個不存在的「還有 1 個沒動」。
    sib="$(cd "$REPO" && find "$d" -maxdepth 1 -name "*.$ext" 2>/dev/null | sed 's|^\./||' | grep -vxF "$f" | wc -l | tr -d ' ' || true)"
    if [ "${sib:-0}" != "0" ]; then
      printf '  %-60s 同目錄還有 %s 個 .%s\n' "$f" "$sib" "$ext"
    fi
  done || true
  echo "  （上面是空的就表示同目錄沒有同副檔名的鄰居——**那不代表整棵樹沒有同型的地方**。）"
  echo
  echo "這是一個下界，不是答案。真正要做的是：**把這次的修法講成一句 pattern，"
  echo "然後 grep 整棵樹找同型的地方**，說出還有幾處、以及為什麼那幾處不改。"
  echo "「我只改了我看到的那一處」不是理由。"
fi
echo

# ── Q4 我講的 runtime 行為，哪些是實測的 ────────────────────────────────────────
echo "── Q4 源碼推論未經實測 ──"
RUNNERS=""
for m in package.json Makefile justfile Cargo.toml pyproject.toml go.mod composer.json mise.toml .mise.toml; do
  [ -f "$REPO/$m" ] && RUNNERS="$RUNNERS  $m"$'\n'
done
if [ -z "$RUNNERS" ]; then
  note_unanswerable Q4 "這個 repo 沒有任何一份跑得起來的宣告檔（package.json / Makefile / justfile / Cargo.toml / pyproject.toml / go.mod / composer.json / mise.toml），所以「怎麼實測」這裡答不出來——去問這個專案的人，或讀它的 README。"
else
  echo "[這個 repo 有這些可以真的跑起來的入口]"
  printf '%s' "$RUNNERS"
  if [ -f "$REPO/package.json" ]; then
    echo "[package.json 的 scripts]"
    (cd "$REPO" && sed -n '/"scripts"/,/}/p' package.json | grep -E '^\s+"' | head -25 | sed 's/^/  /') || true
  fi
  echo
  echo "把這一輪講過的每一句 runtime 行為列出來，逐句標「實測」或「從源碼推的」。"
  echo "推的那幾句要嘛去跑一次，要嘛在交出去的時候明講它是推的。"
fi
echo

# ── Q5 上一輪 review 的每一則，現在是什麼狀態 ───────────────────────────────────
echo "── Q5 上一輪講過仍未修 ──"
if [ "$GH_STATE" != "ok" ]; then
  note_unanswerable Q5 "拿不到上一輪的意見：$(gh_unavailable_why) 在那之前，這一問沒有答案，不是「沒有意見」。"
else
  COMMENTS="$(cd "$REPO" && gh api "repos/$NWO/pulls/$PR/comments" --paginate \
    --jq '.[] | select(.user.type != "Bot") | "  [\(.path):\(.line // .original_line // "?")] \(.user.login): \(.body | gsub("\n"; " ") | .[0:180])"' 2>/dev/null || true)"
  if [ -z "$COMMENTS" ]; then
    note_unanswerable Q5 "PR #$PR 上目前沒有真人留下的 inline 意見——這一問是空的，不是通過。"
  else
    echo "[PR #$PR 上真人留的 inline 意見，$(printf '%s\n' "$COMMENTS" | grep -c . || true) 則]"
    printf '%s\n' "$COMMENTS"
    echo
    echo "逐則問：**在現在的 HEAD 上**它是什麼狀態——修掉了、還在、還是我判斷不修？"
    echo "「我記得我修過了」不算，去看現在的檔案內容。"
    echo "而且處置要回到那則意見上：提出的人看的是他留言的地方，回在別處他收不到。"
  fi
fi
echo

# ── Q6 我新增的斷言，注入一刀會不會紅 ───────────────────────────────────────────
echo "── Q6 恆真斷言／假綠 ──"
# 認測試檔用「路徑段」與「檔名中綴」，不用裸的子字串——`special-flow` 裡有 spec，
# `latest.json` 裡有 test，兩個都不是測試檔，而把它們算進來會讓 Q6 對著錯的東西問問題。
TESTS="$(printf '%s\n' "$CHANGED" | grep -Ei '(^|/)(__tests__|tests?|specs?)/|[._-](test|spec|selftest)s?\.[A-Za-z0-9]+$|(^|/)[A-Za-z0-9_-]*selftest[A-Za-z0-9_-]*\.[A-Za-z0-9]+$' || true)"
if [ -z "$CHANGED" ]; then
  note_unanswerable Q6 "diff 是空的。"
elif [ -z "$TESTS" ]; then
  note_unanswerable Q6 "這次的 diff 沒有動到看起來像測試的檔案。**這本身是一個 finding**：一個改了行為卻沒有任何新斷言的交付，等著被問「那你怎麼知道它是對的」。"
else
  echo "[這次動到的測試檔]"
  printf '%s\n' "$TESTS" | sed 's/^/  /'
  echo
  echo "[新增的斷言行]"
  git -C "$REPO" diff -U0 "$DIFF_RANGE" -- $(printf '%s ' $TESTS) 2>/dev/null \
    | grep -E '^[+]' | grep -Ev '^[+]{3}' \
    | grep -Ei '(expect|assert|should|toBe|toEqual|toHaveBeen|\[\[|test -)' \
    | show_capped 40 || true
  echo
  echo "逐條問：**把它要守的那件事弄壞，這一條會不會紅？** 整檔會紅證明不了每一條都在守"
  echo "——恆真的那一條躲在同一個區塊裡永遠看不到。要指名跑那一條，而且每一條「回來的路」"
  echo "各注入一次。"
fi
echo

# ── Q7 拿掉的那些東西，原本做的每一件事現在由誰做 ──────────────────────────────
echo "── Q7 拿掉了什麼 ──"
# 撈的是 diff 的**減號那一側**。整個檔案被刪掉、與行被刪掉，兩種都算——前者明顯，
# 後者才是會躲的那一種：一個機制常常是「幾行不見了」，而不是「一個檔案不見了」。
DELETED_FILES="$(git -C "$REPO" diff --name-only --diff-filter=D "$DIFF_RANGE" 2>/dev/null || true)"
DELETED_LINES="$(git -C "$REPO" diff -U0 "$DIFF_RANGE" 2>/dev/null   | grep -E '^-' | grep -Ev '^-{3}' || true)"
if [ -z "$CHANGED" ]; then
  note_unanswerable Q7 "diff 是空的。"
elif [ -z "$DELETED_FILES" ] && [ -z "$DELETED_LINES" ]; then
  note_unanswerable Q7 "這次的 diff 只有新增，沒有刪掉任何東西——沒有被取代的機制要對照。"
else
  if [ -n "$DELETED_FILES" ]; then
    echo "[整個被刪掉的檔案]"
    printf '%s\n' "$DELETED_FILES" | sed 's/^/  /'
    echo
  fi
  echo "[被刪掉的行]"
  printf '%s\n' "$DELETED_LINES" | show_capped 60
  echo
  echo "判準是**一個既有機制不再由原本那條路徑執行**，不是它被叫做什麼——拿掉、取代、"
  echo "簡化、順手收斂，四種說法走到同一題。列一張對照表："
  echo "  1. 那個機制原本做了哪幾件事，逐件列出來（看上面被刪掉的那幾行，不看你記得的）"
  echo "  2. 每一件在新的路徑上落在哪裡，逐件指出來"
  echo "  3. 逐件各跑一次——量過其中一件不算量過其餘"
  echo "**列不出來是一個答案。** 列不完整時把這件事寫進 finding 並回去讀那段程式，"
  echo "不要讓這一問安靜地通過：一個「應該沒有別的了」跟一張列過的表，在報告裡長得一樣。"
fi
echo

# ── Q8 我加的東西誰會跑它、這個 repo 做不做這種東西 ────────────────────────────
echo "── Q8 誰跑它／有沒有先例 ──"
# 撈的是 diff 的**加號那一側裡整個新增的檔案**。改到既有的檔案不算——那個檔案本來就有人
# 跑，本來就有先例；會安靜的是「這個 repo 從來沒有過這種東西，而我加了一個」。
ADDED_FILES="$(git -C "$REPO" diff --name-only --diff-filter=A "$DIFF_RANGE" 2>/dev/null || true)"
if [ -z "$CHANGED" ]; then
  note_unanswerable Q8 "diff 是空的。"
elif [ -z "$ADDED_FILES" ]; then
  note_unanswerable Q8 "這次的 diff 沒有新增任何檔案——沒有新東西要問誰跑它。"
else
  echo "[這次新增的檔案，以及這個 repo 裡同副檔名的有幾個]"
  printf '%s
' "$ADDED_FILES" | while IFS= read -r f; do
    [ -z "$f" ] && continue
    ext="${f##*.}"
    if [ "$ext" = "$f" ]; then
      n="?"
    else
      n="$(git -C "$REPO" ls-files "*.$ext" 2>/dev/null | wc -l | tr -d ' ')"
    fi
    printf '  %s   （同副檔名 %s 個）
' "$f" "$n"
  done
  echo
  echo "**這個數字是一個下界，不是答案。** 同副檔名不等於同形狀——要自己去數的是「這個 repo"
  echo "裡跟我加的這個**同形狀**的有幾個」。零就不要做，不是「小心一點做」。"
  echo
  echo "然後逐個問：**誰會跑它？** 指名一條真的會執行到它的路徑——CI 的哪一個工作、哪一條"
  echo "glob 收得到它、本機哪一條命令。指不出來就是沒有人跑，而一個永遠不執行的檔案跟沒有"
  echo "那個檔案一樣安靜，差別只在它看起來很完整。"
fi
echo
# ── 收尾：答得出幾問，答不出的是哪幾問 ──────────────────────────────────────────
COUNT="$(printf '%s' "$UNANSWERED" | wc -w | tr -d ' ')"
echo "=============================================="
echo "ANSWERABLE: $((8 - COUNT))/8"
if [ "$COUNT" -gt 0 ]; then
  echo "答不出的：${UNANSWERED} —— 每一問的原因印在它自己那一段"
  echo "**答不出不是通過。** 一份沒答滿的自檢，讀起來跟答滿八問的一模一樣——"
  echo "所以它要說出自己少了哪幾問。"
fi
echo "=============================================="
echo
echo "接下來：把上面的材料變成逐條 finding，每一條在這一輪之內處置掉——"
echo "要嘛修，要嘛寫下為什麼不修。兩者都沒有的 finding 存在時，這次自檢還沒跑完。"
