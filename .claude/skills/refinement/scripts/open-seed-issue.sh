#!/usr/bin/env bash
# open-seed-issue.sh — 開發途中長出來的東西，一個命令就有載體。
#
# 為什麼要有這一支：開發途中會問出、查出、撞出一些只有當下知道的東西。那個東西現在沒有
# 地方住——它要嘛被寫進一個進不了主線的角落，要嘛消失。而「開一張正式的單」在那個
# 當下太貴：assertion 還簽不出來，因為怎麼算成功還沒想清楚。
#
# 所以這一支只做一件事：把前因後果變成一張找得到的單，然後就結束。它**不**簽 assertion、
# **不**決定領域、**不**開 worktree、**不**碰你現在正在做的那張單。assertion 是下一個 session
# 在 refinement 的事，而那時候才有人真的想過怎麼算成功。
#
# 開出來的東西不再是一張筆記，是一張該填的格子都有答案、只等簽 assertion 的單。
#
# 兩種單，開單的人自己宣告是哪一種（`--kind`），這一支不從名字、標題或內容推：
#
#   report   舉發實作途中撞到的問題。撞到的人當下就知道自己是誰、剛剛在讀哪個檔，所以
#            這一種要 6W；而 `--where` 那一格同時就是查重的鍵——要求它，查重的鍵就機械
#            地產生了。
#   feature  開發新功能。沒有「撞到」這件事，who 與 where 答不出來，硬要填會填出一個編的
#            ——而編過的格子看不出來，空著的看得出來。所以這一種不問，也不查重。
#
# 查重不擋內容：撞到十張而開單的人判定都不是同一件，單照樣開得出來。擋人的只有「沒宣告
# 種類」「舉發缺格」「撞到了卻沒寫判斷」三件——它們擋的是沒有回答問題，不是答案的內容。
#
# Usage:
#   open-seed-issue.sh --issues <單的根目錄> --namespace <命名空間> --slug <名字>
#                      --kind report --who <誰、在做什麼工作時撞到的>
#                      --what <做什麼> --when <什麼時候要> --why <想解決什麼> --how <拿什麼測>
#                      --where <撞到的檔案> [--where <另一個>]...
#                      --note <前因後果> [--vs <單號>=<判斷>]...
#                      [--prefix <前綴>] [--no-commit]
#
#   open-seed-issue.sh --issues … --namespace … --slug … --kind feature
#                      --what … --when … --why … --how … --note <前因後果>
#
# 號自己會算：`--slug the-thing` 開出來的是 `DP-488-the-thing`。號從哪裡來由那個命名空間
# 現有的東西決定，不需要另外宣告——細節見 next-ticket-number.sh 的檔頭。
# Exit:
#   0 開好了，印出單的路徑
#   2 參數不對、缺格、那張單已經在了
#   3 舉發那一種撞到了還沒出去的單，而其中有幾張沒有寫下判斷（印出缺哪幾張與怎麼補）

set -euo pipefail

PREFIX="[open-seed-issue]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_STATE="$SCRIPT_DIR/../../driving-work-to-done/scripts/spine-loop-state.sh"
NEXT_NUMBER="$SCRIPT_DIR/../../driving-work-to-done/scripts/next-ticket-number.sh"

ISSUES=""
NAMESPACE=""
SLUG=""
NOTE=""
KIND=""
WHO=""
WHAT=""
WHEN=""
WHY=""
HOW=""
COMMIT=1
PREFIX_OVERRIDE=""
WHERE=()
VS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues) ISSUES="${2:-}"; shift 2 ;;
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --slug) SLUG="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    --kind) KIND="${2:-}"; shift 2 ;;
    --who) WHO="${2:-}"; shift 2 ;;
    --what) WHAT="${2:-}"; shift 2 ;;
    --when) WHEN="${2:-}"; shift 2 ;;
    --why) WHY="${2:-}"; shift 2 ;;
    --how) HOW="${2:-}"; shift 2 ;;
    --where) WHERE+=("${2:-}"); shift 2 ;;
    --vs) VS+=("${2:-}"); shift 2 ;;
    --no-commit) COMMIT=0; shift ;;
    --prefix) PREFIX_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

for pair in "--issues:$ISSUES" "--namespace:$NAMESPACE" "--slug:$SLUG" "--note:$NOTE"; do
  if [[ -z "${pair#*:}" ]]; then
    echo "$PREFIX 缺 ${pair%%:*}。" >&2
    echo "  用法看 open-seed-issue.sh --help。" >&2
    exit 2
  fi
done

# 種類由開單的人宣告，這一支不推。從 slug、標題或正文推導的話，同一件事換個寫法就換一種
# 待遇，而沒有人看得出來換過。
case "$KIND" in
  report|feature) ;;
  "")
    echo "$PREFIX 缺 --kind。這張單是哪一種要你自己說，這一支不從名字或內容推。" >&2
    echo "  --kind report   舉發實作途中撞到的問題（要 6W，而且開之前會查重）" >&2
    echo "  --kind feature  開發新功能（不問 who／where，也不查重）" >&2
    exit 2 ;;
  *)
    echo "$PREFIX --kind 只認得 report 與 feature（收到「${KIND}」）。" >&2
    exit 2 ;;
esac

missing=()
[[ -n "$WHAT" ]] || missing+=("--what（what 做什麼）")
[[ -n "$WHEN" ]] || missing+=("--when（when 什麼時候要）")
[[ -n "$WHY"  ]] || missing+=("--why（why 真正想解決什麼）")
[[ -n "$HOW"  ]] || missing+=("--how（how 拿什麼測）")

if [[ "$KIND" == "report" ]]; then
  [[ -n "$WHO" ]] || missing+=("--who（who 是誰、在做什麼工作的時候撞到的）")
  [[ ${#WHERE[@]} -gt 0 ]] || missing+=("--where（where 撞在哪個檔——這一格同時是查重的鍵）")
else
  # 新功能那一種不是被豁免，是那個機制對它不成立：沒有「撞到」這件事，who 與 where 答不
  # 出來。收下一個編出來的值比拒絕糟——編過的格子看不出來。
  bad=()
  [[ -n "$WHO" ]] && bad+=("--who")
  [[ ${#WHERE[@]} -gt 0 ]] && bad+=("--where")
  [[ ${#VS[@]} -gt 0 ]] && bad+=("--vs")
  if [[ ${#bad[@]} -gt 0 ]]; then
    echo "$PREFIX --kind feature 不收 ${bad[*]}。" >&2
    echo "  新功能沒有「撞到」這件事，who 與 where 答不出來，查重的鍵也產不出來。" >&2
    echo "  這是舉發那一種撞到的問題的話，改用 --kind report。" >&2
    exit 2
  fi
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "$PREFIX --kind $KIND 缺了這幾格，補齊才開得出單：" >&2
  for m in "${missing[@]}"; do echo "  $m" >&2; done
  echo "  一張開出來的單該填的格子都要有答案（或明講不適用並說出為什麼）；只有 assertion" >&2
  echo "  留給 refinement 簽。" >&2
  exit 2
fi

# 名字只吃這些字元：它會變成目錄名，而目錄名之後會被別的東西拿去接。
[[ "$SLUG" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
  # 訊息裡不用反引號：雙引號底下它是命令替換，而這一行正好在講一個不合法的輸入。
  echo "$PREFIX --slug 只能用字母、數字、連字號、底線、點，而且要從字母或數字開頭（收到「${SLUG}」）。" >&2
  exit 2
}

[[ -d "$ISSUES" ]] || { echo "$PREFIX 單的根目錄不存在：$ISSUES" >&2; exit 2; }
[[ -f "$LOOP_STATE" ]] || { echo "$PREFIX 找不到 $LOOP_STATE" >&2; exit 2; }
[[ -f "$NEXT_NUMBER" ]] || { echo "$PREFIX 找不到 $NEXT_NUMBER" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 查重：舉發那一種，在建立任何東西之前把撞到的那幾張端到眼前
#
# 鍵是「正文指名的路徑有交集」，不是標題共用實詞。2026-08-31 拿當天真的重複的 11 對當測資
# 量過：標題那個鍵抓到 6 對，檔案這個鍵抓到 10 對——漏掉的五對裡有三對一個詞都不共用，而
# 那三對用檔案全部抓得到。
#
# 「有交集」比的是整段路徑，判準寫在下面那段 python 的 same_path()。
#
# 分母是**還沒出去的**單：開單的人要看的是「現在還在待辦裡的有沒有同一件」，不是「歷史上
# 有沒有」。終局那幾格（released/、closed/）不進。
# ---------------------------------------------------------------------------
COLLISIONS=""
if [[ "$KIND" == "report" ]]; then
  COLLISIONS="$(python3 - "$ISSUES" "${WHERE[@]}" <<'PY'
import os, re, sys

issues_root = sys.argv[1]
wanted = []
for raw in sys.argv[2:]:
    value = raw.strip().rstrip("/")
    # 行號與區間不是路徑的一部分：`foo.py:128` 與 `foo.py` 指的是同一個檔。
    value = re.split(r"[:#]", value)[0]
    if value:
        wanted.append(value)

# **比對的單位是整段路徑，不是檔名。** 一個單獨的檔名不是身分，它是一個慣例——四十幾支
# skill 各有一份 `SKILL.md`，所以拿 `SKILL.md` 當鍵會撞到每一張提過任何一支 skill 的單
# （2026-09-03 實測五個 --where 撈回 13 張，每一張的理由都是「共用：SKILL.md」，其中四張
# 是別的專案的單）。判準因此是：兩條路徑其中一個是另一個**以 / 對齊**的後綴，而且重疊的
# 部分**多於一段**，或者兩者一字不差相同。
#
# 判準只從手上那兩個字串算，不去掃 --where 指向的那棵樹：這支腳本住在會被帶走的 skill
# 裡，那棵樹在 claude.ai 與 Cowork 不存在。代價是正文裡只寫得出不帶目錄的檔名的那些單撈
# 不到——那是刻意付的，分得開它們的唯一方法就是去掃那棵樹。
PATH_TOKEN = re.compile(r"[A-Za-z0-9_.][A-Za-z0-9_./+-]*")


def segments(value):
    return [seg for seg in value.split("/") if seg]


def same_path(a, b):
    """a 與 b 指的是不是同一個東西：整段對齊的後綴，重疊多於一段，或一字不差。"""
    sa, sb = segments(a), segments(b)
    if not sa or not sb:
        return False
    if sa == sb:
        return True
    short, long_ = (sa, sb) if len(sa) < len(sb) else (sb, sa)
    if len(short) < 2:
        return False
    return long_[-len(short):] == short

TERMINAL = ("released", "closed")

def is_terminal(rel):
    return any(part in TERMINAL for part in rel.split(os.sep))

rows = []
for dirpath, dirnames, filenames in os.walk(issues_root):
    if ".git" in dirnames:
        dirnames.remove(".git")
    if ".spine" not in dirnames or "index.md" not in filenames:
        continue
    rel = os.path.relpath(dirpath, issues_root)
    if is_terminal(rel):
        continue
    try:
        body = open(os.path.join(dirpath, "index.md"), encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    mentioned = set(PATH_TOKEN.findall(body))
    # 印出來的共用值是開單的人原樣給的那一個，不是正文裡那一段——他要認得出自己給了什麼。
    hits = sorted({w for w in wanted if any(same_path(w, m) for m in mentioned)})
    if hits:
        rows.append((os.path.basename(dirpath), rel, hits))

rows.sort()
for name, rel, hits in rows:
    print(f"{name}\t{rel}\t{','.join(hits)}")
PY
)" || {
    echo "$PREFIX 查重跑不起來，沒有開單。" >&2
    echo "  「查不到」與「一張都沒撞到」不是同一件事，所以這裡不往下走。" >&2
    exit 2
  }

  if [[ -z "$COLLISIONS" ]]; then
    # 一張都沒撞到也要說出來——那是一個答案，不是沉默。
    echo "$PREFIX 查重（鍵：正文指名的路徑有交集）：還沒出去的單裡，一張都沒有指名 ${WHERE[*]}。"
  else
    echo "$PREFIX 查重（鍵：正文指名的路徑有交集）：還沒出去的單裡撞到這幾張——"
    while IFS=$'\t' read -r name rel hits; do
      [[ -n "$name" ]] || continue
      echo "  $name"
      echo "      在：$rel"
      echo "      共用：$hits"
    done <<< "$COLLISIONS"

    # 每一張都要有一句判斷才開得出單。擋的是「沒有回答問題」，不是答案的內容——判定「都
    # 不是同一件」的話單照樣開得出來。
    unjudged=()
    while IFS=$'\t' read -r name rel hits; do
      [[ -n "$name" ]] || continue
      # 單號整段取。前綴帶數字的（`AB2CD-3993` 這種）以前對不上 `[A-Za-z]+-`，於是退回
      # `${name%%-*}` 被切在第一個連字號——同一個前綴底下的兩張單因此在清單裡變成同一個
      # 鍵，而下面那張表的判斷欄用整段單號去找，永遠找不到。取不出來的用整個目錄名。
      ticket="$name"
      [[ "$name" =~ ^([A-Za-z][A-Za-z0-9]*-[0-9]+) ]] && ticket="${BASH_REMATCH[1]}"
      found=0
      for entry in ${VS[@]+"${VS[@]}"}; do
        [[ "${entry%%=*}" == "$ticket" ]] && { found=1; break; }
      done
      # 兩張撞到的單算得出同一個單號時，那個鍵只印一次——同一句判斷本來就答完了兩張。
      for u in ${unjudged[@]+"${unjudged[@]}"}; do
        [[ "$u" == "$ticket" ]] && { found=1; break; }
      done
      [[ "$found" -eq 1 ]] || unjudged+=("$ticket")
    done <<< "$COLLISIONS"

    if [[ ${#unjudged[@]} -gt 0 ]]; then
      echo "" >&2
      echo "$PREFIX 這幾張還沒有你的判斷，所以沒有開單：" >&2
      for t in "${unjudged[@]}"; do
        echo "  --vs '$t=是同一件／不是同一件，差別在……'" >&2
      done
      echo "  判斷的內容不決定開不開得成單——說「都不是同一件」照樣開得出來。" >&2
      echo "  沒開得成的原因只有一個：那個問題還沒有被回答。" >&2
      exit 3
    fi
  fi
fi

# 號在名字裡。沒有號的單排不進待辦、也沒有一個穩定的東西給別的單引用——而它會一直長出來，
# 到某次盤點才被發現。2026-08-08 就這樣一次找到五個。
number_args=(--issues "$ISSUES" --namespace "$NAMESPACE")
[[ -n "$PREFIX_OVERRIDE" ]] && number_args+=(--prefix "$PREFIX_OVERRIDE")
if ! NUMBER="$(bash "$NEXT_NUMBER" "${number_args[@]}")"; then
  # 那一支已經把原因與往下走的路印在 stderr 上了，不要在這裡改寫成另一句話。
  exit 2
fi
SLUG="${NUMBER}-${SLUG}"

# backlog 是「立案了，還沒開工」，而一張種子單正是那個狀態。位置是狀態的投影，而重算不搬
# 目錄——它把算出來的那一格寫進 `.spine/placement.json`。所以這裡選的路徑就是這張單會一直
# 待著的地方，選一個合理的起點。
ISSUE_DIR="$ISSUES/$NAMESPACE/backlog/$SLUG"
[[ -e "$ISSUE_DIR" ]] && { echo "$PREFIX 那張單已經在了：$ISSUE_DIR" >&2; exit 2; }

mkdir -p "$ISSUE_DIR"

# `destination` 一格不先填，assertion 也不先簽——它們要人回答，而這一支存在的理由正是
# 「現在還沒有人能回答」。填一個編出來的答案比空著糟：空著看得出來。
#
# `destination` 以前是例外，填的是「最保守的那一個」。那個判準是錯的，而且它教錯了東西：
# 這一格問的是「這批檔案會不會被同步出去」，不是「風險多大」——它不是保守或大膽選出來的，
# 是算出來的，而算它要先知道這張單會動到哪些東西。
#
# 計劃那四格反過來——**它們現在有答案了**，因為開單的人被要求先回答。留白不會讓下游安靜
# 地走過去：真的會讀這一格的地方讀不到值就拒絕，並且指名缺的是它。
{
  printf -- '---\n'
  printf '# destination: 這一格還沒有人回答。它問的是「這批檔案會不會被同步出去」，由第一關的人填。\n'
  printf 'kind: %s\n' "$KIND"
  printf 'plan:\n'
  printf '  what:\n    answer: %s\n    source: human\n' "$(printf '%s' "$WHAT" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read(),ensure_ascii=False))')"
  printf '  when:\n    answer: %s\n    source: human\n' "$(printf '%s' "$WHEN" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read(),ensure_ascii=False))')"
  printf '  why:\n    answer: %s\n    source: human\n' "$(printf '%s' "$WHY" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read(),ensure_ascii=False))')"
  printf '  how:\n    answer: %s\n    source: human\n' "$(printf '%s' "$HOW" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read(),ensure_ascii=False))')"
  printf -- '---\n\n'
  printf '# %s\n\n' "$SLUG"
  printf '## 前因後果\n\n'
  printf '%s\n\n' "$NOTE"
  if [[ "$KIND" == "report" ]]; then
    printf '## 誰、撞在哪\n\n'
    printf -- '- **who**：%s\n' "$WHO"
    printf -- '- **where**：'
    printf '`%s`' "${WHERE[0]}"
    for extra in "${WHERE[@]:1}"; do printf '、`%s`' "$extra"; done
    printf '\n\n'
    printf '## 開之前查了什麼\n\n'
    if [[ -z "$COLLISIONS" ]]; then
      printf '鍵是「正文指名的路徑有交集」，分母是還沒出去的單。**一張都沒有撞到。**\n\n'
    else
      printf '鍵是「正文指名的路徑有交集」，分母是還沒出去的單。撞到的與各自的判斷：\n\n'
      printf '| 撞到 | 在哪 | 共用的檔 | 判斷 |\n|---|---|---|---|\n'
      while IFS=$'\t' read -r name rel hits; do
        [[ -n "$name" ]] || continue
        ticket="$name"
        [[ "$name" =~ ^([A-Za-z][A-Za-z0-9]*-[0-9]+) ]] && ticket="${BASH_REMATCH[1]}"
        judgement=""
        for entry in ${VS[@]+"${VS[@]}"}; do
          [[ "${entry%%=*}" == "$ticket" ]] && { judgement="${entry#*=}"; break; }
        done
        printf '| `%s` | `%s` | `%s` | %s |\n' "$name" "$rel" "$hits" "$judgement"
      done <<< "$COLLISIONS"
      printf '\n'
    fi
  fi
  printf '## 還沒有的東西\n\n'
  printf '這是一張種子單：該填的格子都有答案了，但還沒有人簽過「怎麼算成功」。\n\n'
  printf '接手的人從 `refinement` 開始——填 `destination`、寫 assertion、算校驗值、開輪次。\n'
} > "$ISSUE_DIR/index.md"

bash "$LOOP_STATE" seed --state "$ISSUE_DIR/.spine/loop-state.json" --note "$NOTE" >/dev/null

if [[ "$COMMIT" -eq 1 ]]; then
  # 單的目錄樹是它自己的 git repo。沒 commit 的單只存在於這台機器上，而這一支的整個用途是
  # 「拿給另一個 session 開工」——另一個 session 讀的是 commit 過的那一份。
  if git -C "$ISSUES" rev-parse --git-dir >/dev/null 2>&1; then
    # commit 帶跟 add 同一個 pathspec，而且旗標寫在 `--` 前面（`--` 之後每個 token 都是路徑）。
    #
    # 不帶 pathspec 的話送出去的是**整個索引**——包含任何人先前 stage 而還沒 commit 的東西。
    # 單的目錄樹是多個 session 共用的，而索引是那棵樹上唯一的共用可寫狀態，所以這不是競態，
    # 是預設行為：`3ee83eef5f` 那顆說自己是一張種子單，實際帶走 784 個檔，其中 782 個不是它的。
    #
    # 修法刻意不是「跑之前先看一眼索引」。那是 check-then-act：驗完到 commit 之間的窗由別人
    # 什麼時候打 commit 決定，不由跑的人的仔細程度決定。2026-08-31 量到一次驗完 21 秒後
    # 仍然被掃走。`commit -- <pathspec>` 送的是工作區那幾個路徑，完全不碰索引，所以窗不存在。
    git -C "$ISSUES" add "$NAMESPACE/backlog/$SLUG" >/dev/null
    git -C "$ISSUES" commit -q -m "seed: $NAMESPACE/$SLUG" -m "$NOTE" -- "$NAMESPACE/backlog/$SLUG"
  else
    echo "$PREFIX 單的目錄樹不是 git repo，這張單只留在磁碟上（沒有 commit）。" >&2
  fi
fi

echo "$PREFIX 開好了：$ISSUE_DIR"
echo "  走的是 --kind ${KIND}。$(
  if [[ "$KIND" == "report" ]]; then
    echo '舉發：6W 都填了，開之前查過重。'
  else
    echo '新功能：不問 who 與 where，也沒有查重——那個機制對這一種不成立。'
  fi)"
echo "  接手的人：先走 refinement 簽 assertion，再 init 開輪次。"
