#!/usr/bin/env bash
# scan-unreviewed-prs.sh — 不等任何人對我做動作，直接問 GitHub：
# 指名的那幾個 repo 裡，哪幾顆 open PR 我一票都還沒投。
#
# 存在的理由：另外兩條路徑都錨在「有人針對我做了動作」。Slack 那條要有人把 PR 貼進頻道；
# scan-my-stale-reviews.sh 的定義域是「我投過票、而 head 已經推進」——**它的第一步就把
# 我沒投過票的那些排除掉了**，所以兩條的輸出結構上不可能包含任何一顆首次 review。
# 補「有人指名要我」也不夠：review request 常常指到 team 而不是個人，那時
# `review-requested:<me>` 一樣看不到它。
#
# 用法：
#   scan-unreviewed-prs.sh --my-user <username> --org <org> \
#     --repo <name> [--repo <name>]... [--updated-within-seconds N] [--merge-with <file>]
#     [--open-prs-out <file>]
#
# --repo：**至少要有一個，而且沒有預設。** 一個都沒給就拒絕執行，不退回掃整個 org
#   ——org-wide 的搜尋會被單頁上限靜靜截斷（2026-09-16 實測：一次 org-wide 查詢在某個
#   repo 上只回 9 顆，單問那個 repo 是 35 顆），而那個誤差方向是「比較少」，沒有人會來報。
#   要問哪幾個 repo 是呼叫者的知識，不是這支腳本的。
#
# --updated-within-seconds：只收最近這麼久之內更新過的（預設 604800 ＝ 7 天，跟頻道掃描
#   的預設窗一致）。給 0 表示不設窗。**窗由呼叫者傳、腳本不硬編**，理由跟 probe 的
#   --stale-seconds 是同一個：窗有多長只能有一個答案，而那個答案由這一趟的人決定。
#   沒有窗的話長尾會淹掉清單：同一天實測三個 repo 共 40 顆，其中 15 顆七天內更新過，
#   其餘 25 顆最舊的一顆是兩年前開的。
#
# 輸出（stdout）：JSON 陣列，欄位 repo, number, title, url, author, created_at,
#   review_status, review_detail——後兩個由 check-my-review-status.sh 補，這支自己不判
#   （同一個判斷寫第二份的話，錯的那一份可以永遠錯）。所以輸出跟另外兩條路徑的
#   candidates 同形，**不要再接一次 check-my-review-status.sh**。
# 進度（stderr）。
#
# --merge-with <file>：另一條路徑的同形 JSON 陣列，兩邊取聯集。實作在
#   lib/merge-candidates.sh，跟 scan-my-stale-reviews.sh 是同一份。
#
# 離場碼：
#   0  問到了（可能是 0 顆，那是一個答案）
#   1  參數不對——含一個 repo 都沒指名
#   2  問不到上游。**不回空陣列**：問不到與沒有是兩件事，而它們的下一步相反。三種都算
#      問不到——清單端點離場碼非 0（限流回的 403 是這一種）、回應的形狀不對、某一顆的
#      票數問不到（那一顆不得當成「我沒投過」混進去）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/merge-candidates.sh
source "${SCRIPT_DIR}/lib/merge-candidates.sh"

MY_USER=""
ORG=""
MERGE_WITH=""
OPEN_PRS_OUT=""
UPDATED_WITHIN="604800"
REPOS=()

usage() {
  sed -n '2,50p' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --my-user) MY_USER="${2:-}"; shift 2 ;;
    --org) ORG="${2:-}"; shift 2 ;;
    --repo) REPOS+=("${2:-}"); shift 2 ;;
    --updated-within-seconds) UPDATED_WITHIN="${2:-}"; shift 2 ;;
    --merge-with) MERGE_WITH="${2:-}"; shift 2 ;;
    --open-prs-out) OPEN_PRS_OUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "scan-unreviewed-prs.sh: 不認得的參數 $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$MY_USER" ]] || { echo "ERROR: --my-user 必填" >&2; exit 1; }
[[ -n "$ORG" ]] || { echo "ERROR: --org 必填" >&2; exit 1; }

if [[ "${#REPOS[@]}" -eq 0 ]]; then
  cat >&2 <<'MSG'
POLARIS_UNREVIEWED_SCAN_NO_REPO_LIST
ERROR: --repo 至少要有一個。這支不掃整個 org。
  理由：org-wide 的搜尋會被單頁上限截斷，而截斷的方向是「比較少」——整批候選安靜地少一截，
  沒有人會來報。要問哪幾個 repo 是呼叫者的知識。
  修法：從這個工作區的公司設定讀那份清單（github.review_repos），逐個用 --repo 傳進來。
MSG
  exit 1
fi

[[ "$UPDATED_WITHIN" =~ ^[0-9]+$ ]] || { echo "ERROR: --updated-within-seconds 要是數字，收到的是 ${UPDATED_WITHIN}" >&2; exit 1; }

# 窗算成一個 ISO 時間戳，底下拿它跟每一顆的 updated_at 比。
UPDATED_CUTOFF_ISO=""
if [[ "$UPDATED_WITHIN" -gt 0 ]]; then
  cutoff_epoch=$(( $(date +%s) - UPDATED_WITHIN ))
  if UPDATED_CUTOFF_ISO="$(date -u -r "$cutoff_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
    :
  else
    UPDATED_CUTOFF_ISO="$(date -u -d "@${cutoff_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
  fi
  echo "🪟 窗：${UPDATED_WITHIN} 秒 ＝ 只收 ${UPDATED_CUTOFF_ISO} 之後更新過的" >&2
else
  echo "🪟 窗：不設（--updated-within-seconds 0）" >&2
fi

search_err="$(mktemp)"
tmpfile="$(mktemp)"
openprs_tmp="$(mktemp)"
trap 'rm -f "$search_err" "$tmpfile" "$openprs_tmp"' EXIT

unavailable() {
  echo "POLARIS_UNREVIEWED_SCAN_UNAVAILABLE" >&2
  echo "問不到上游：$1" >&2
  cat "$search_err" >&2
  exit 2
}

# **不走搜尋端點，走 repo 自己的 pulls 清單。** 搜尋那一版一句話就問得到答案，但它的次級
# 限流極緊：2026-09-16 實測，三個 repo 連著問在第三個撞 403，隔 3 秒再問還是撞。**而撞到
# 的代價是整批候選消失**——這一支照設計離場 2，那是對的行為，但收件匣那一天就是空的。
#
# `repos/{owner}/{repo}/pulls` 走的是另一個額度桶（每小時 5000 次），代價是「我投過票沒」
# 要逐顆問。三個 repo、七天窗，實測是十幾次呼叫，離那個上限很遠。
#
# 逐個 repo 各問一次，不併。併起來的那一版只有搜尋端點做得到，而那正是上面不走的那一條。
found=0
for repo in "${REPOS[@]}"; do
  [[ -n "$repo" ]] || { echo "ERROR: --repo 收到一個空值" >&2; exit 1; }
  echo "🔍 ${ORG}/${repo}：我一票都沒投過的 open PR..." >&2

  # --paginate 走完所有頁，所以不會有「這一頁不是全部」那種安靜的截斷。--slurp 把每一頁
  # 包成一個陣列，所以底下用 .[][] 攤平。
  raw="$(gh api "repos/${ORG}/${repo}/pulls?state=open&per_page=100" --paginate --slurp 2>"$search_err")"
  rc=$?
  [[ "$rc" -eq 0 ]] || unavailable "${ORG}/${repo}：gh api repos/.../pulls 離場碼 ${rc}"

  printf '%s' "$raw" | jq -e 'type == "array" and (all(.[]; type == "array"))' >/dev/null 2>&1 \
    || unavailable "${ORG}/${repo}：輸出不是一份分頁過的清單"

  # **head 表取濾網之前這一份。** 底下三道濾網（draft、作者、更新窗）各濾掉一種真的當過
  # parent 的 PR：2026-09-17 那條 9 層 stack 裡，#3224／#3229 被「我投過票」濾掉、最底下
  # 的 #3133 是 draft。判「這一顆疊在誰身上」問的是「誰是 open PR」，不是「誰該被派」。
  if [[ -n "$OPEN_PRS_OUT" ]]; then
    default_branch="$(gh api "repos/${ORG}/${repo}" --jq '.default_branch' 2>/dev/null)" || default_branch=""
    # 問不到預設分支就留空，讓下游說出它不知道——**不要猜一個 main 或 master**。
    # **只收 head 跟 base 住在同一個 repo 的那幾顆。** 一顆 PR 的 base 只可能是它自己那個
    # repo 的 branch，所以 fork 來的 head 永遠不會是任何人的 base——收進來只會讓同名的
    # 兩條 branch 互相冒充。b2c-web #3264 是實例：base 與 head 同名（一個在 upstream、
    # 一個在 fork），這張表因此把那顆 PR 記成它自己的 parent。
    #
    # `.head.repo` 是 null 的那幾顆一起排除。**推得出來，但沒有實例驗過**：head repo 跟
    # base repo 同一個的時候那個 repo 一定還在（PR 就住在裡面），所以 null 應該只出現在
    # fork 被刪掉的時候。2026-09-22 掃過手上三個 repo 的 78 顆 open PR，一顆 null 都沒有
    # ——沒有實例，也沒有反例。**這一句是推論，不是量到的。**
    #
    # 排掉的方向是安全的那一邊：收進來的話，一條分不出住在哪裡的 branch 會被當成同一個
    # repo 的 head。真的是同 repo 而被排掉的話，配對那一支會說它問不到（那一支自己也問
    # 一次 head_repo），不會說成「沒有疊」。
    printf '%s' "$raw" | jq -c --arg repo "$repo" --arg db "$default_branch" '
      {($repo): {default_branch: $db,
                 heads: ([.[][]
                          | select((.head.repo.full_name // "") == .base.repo.full_name)
                          | {key: .head.ref,
                             value: {number, url: .html_url,
                                     head_repo: .head.repo.full_name}}] | from_entries)}}' \
      >>"$openprs_tmp"
  fi

  # 窗、draft、作者三道過濾在這裡做。判 updated_at，不判 created_at——一顆兩年前開、
  # 昨天才被推新 commit 的 PR 是這一批要抓的，反過來不是。
  cands="$(printf '%s' "$raw" | jq -c --arg me "$MY_USER" --arg cut "$UPDATED_CUTOFF_ISO" '
    [ .[][]
      | select(.draft == false)
      | select(.user.login != $me)
      | select($cut == "" or .updated_at >= $cut)
      | {number, title, url: .html_url, author: .user.login, created_at, updated_at} ]')"
  n_open="$(printf '%s' "$cands" | jq 'length')"
  echo "   窗內、非 draft、非我開的：${n_open} 顆，逐顆問我投過票沒" >&2

  repo_found=0
  while IFS=$'\t' read -r num title url author created_at; do
    [[ -n "$num" ]] || continue
    voted="$(gh api "repos/${ORG}/${repo}/pulls/${num}/reviews" --paginate --slurp 2>/dev/null \
      | jq -r --arg me "$MY_USER" '[.[][] | select(.user.login == $me)] | length' 2>/dev/null)" || voted=""
    # **問不到這一顆不算「我沒投過」。** 那個方向會把一顆我看過的 PR 再送一次，而它跟
    # 真的沒看過長得一樣。整支停下來，不讓這一顆安靜地混進去。
    [[ "$voted" =~ ^[0-9]+$ ]] \
      || unavailable "${ORG}/${repo}#${num}：問不到我在這顆上投過幾票"
    [[ "$voted" -eq 0 ]] || continue
    repo_found=$((repo_found + 1))
    jq -n --arg repo "$repo" --argjson number "$num" --arg title "$title" \
      --arg url "$url" --arg author "$author" --arg created_at "$created_at" \
      '{repo: $repo, number: $number, title: $title, url: $url, author: $author, created_at: $created_at}' \
      >>"$tmpfile"
  done < <(printf '%s' "$cands" | jq -r '.[] | [(.number|tostring), .title, .url, .author, .created_at] | @tsv')

  echo "   ${repo_found} 顆我一票都沒投過" >&2
  found=$((found + repo_found))
done

if [[ -n "$OPEN_PRS_OUT" ]]; then
  # 每個 repo 一個物件，合成一份。一個 repo 都沒寫出來就是一個空物件——**那跟檔案不存在
  # 要分得開**：下游對空物件說「沒有這個 repo 的清單」，對不存在的檔案說同一句話，兩種
  # 都往完整 review 走，所以這裡不需要第三種狀態。
  jq -s 'add // {}' "$openprs_tmp" >"$OPEN_PRS_OUT"
  echo "🧬 open PR head 表：$(jq 'to_entries | map(.value.heads | length) | add // 0' "$OPEN_PRS_OUT") 條 head，$(jq 'length' "$OPEN_PRS_OUT") 個 repo → ${OPEN_PRS_OUT}" >&2
fi

if [[ -s "$tmpfile" ]]; then
  mine="$(jq -s 'sort_by(.created_at)' "$tmpfile")"
else
  mine='[]'
fi

# 補上 review_status／review_detail。**不在這裡自己判**——那個判斷
# check-my-review-status.sh 已經有一份，在這裡重寫一次就是同一個判斷的第二份實作，而錯的
# 那一份可以永遠錯。下游 build-review-prompt.sh 讀 review_status 讀不到就中斷。
#
# 這一批照定義都是「我一票都沒投過」，所以正常會全部回 needs_first_review。真的被濾掉的
# 那幾顆，就是那一顆本來就不該進這一批。
if [[ "$mine" != "[]" ]]; then
  enriched="$(printf '%s' "$mine" \
    | "$SCRIPT_DIR/check-my-review-status.sh" --my-user "$MY_USER" --org "$ORG" 2>/dev/null)" || enriched=""
  if [[ -n "$enriched" ]] && printf '%s' "$enriched" | jq -e 'type == "array"' >/dev/null 2>&1; then
    mine="$enriched"
  else
    echo "⚠️ POLARIS_UNREVIEWED_STATUS_UNAVAILABLE：check-my-review-status.sh 沒有回一個陣列，這 $(printf '%s' "$mine" | jq 'length') 顆沒有 review_status，下游會在第一顆就中斷" >&2
  fi
fi

if [[ -n "$MERGE_WITH" ]]; then
  merge_candidate_arrays "$mine" "$MERGE_WITH" "$found" || exit 1
else
  printf '%s\n' "$mine"
fi

echo "✅ 完成：${#REPOS[@]} 個 repo，共 ${found} 顆我一票都沒投過" >&2
