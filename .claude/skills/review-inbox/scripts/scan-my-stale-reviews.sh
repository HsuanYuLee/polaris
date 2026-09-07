#!/usr/bin/env bash
# scan-my-stale-reviews.sh — 不靠任何人在 Slack 說話，直接問 GitHub：
# 哪幾顆 open PR 我投過票，而我最後一票綁的那顆 commit 已經不是現在的 head。
#
# 存在的理由：頻道掃描只看得到「有人貼出來」的 PR。這個團隊的「我改好了，再看一次」
# 多半是回在原本那條 thread 裡，甚至根本沒有再說一次——2026-09-04 兩輪 discovery 都
# 空手，而同一時間有五顆 PR 擋在我方舊票上、作者早就推了修正。這條路徑問的是 GitHub
# 自己記得的事實（我的票綁在哪顆 commit、現在的 head 是哪顆），跟誰有沒有說話無關。
#
# 用法：
#   scan-my-stale-reviews.sh --my-user <username> --org <org> [--limit N] [--merge-with <file>]
#
# 輸出（stdout）：JSON 陣列，欄位是 repo, number, title, url, author, created_at,
#   review_status, review_detail——後兩個由 check-my-review-status.sh 補，這支自己不判
#   （同一個判斷寫第二份的話，錯的那一份可以永遠錯）。所以輸出跟 Slack 那條路徑的
#   candidates 同形，**不要再接一次 check-my-review-status.sh**。補不到時印
#   POLARIS_STALE_REVIEW_STATUS_UNAVAILABLE 並說出有幾顆沒有狀態。
# 進度（stderr）。
#
# --merge-with <file>：另一個來源的同形 JSON 陣列，兩邊取聯集。聯集在這裡做，不寫成散文裡
#   的一行 jq——那一行沒被跑的時候，少掉的那一半跟「沒有」長得一樣。
#   同一個 url 在兩邊都有時合併的是**欄位**，不是挑一整列留下：挑一列保留的是輸入順序的
#   第一列，而這裡固定把自己掃出來的那一列放在前面，於是欄位比較多的那一列每次都輸。
#
# 離場碼：
#   0  問到了（可能是 0 顆，那是一個答案）
#   1  參數不對
#   2  問不到上游（搜尋失敗）。**不回空陣列**：問不到與沒有是兩件事，而它們的下一步相反。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MY_USER=""
ORG=""
LIMIT="100"
MERGE_WITH=""

usage() {
  sed -n '2,22p' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --my-user) MY_USER="${2:-}"; shift 2 ;;
    --org) ORG="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --merge-with) MERGE_WITH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "scan-my-stale-reviews.sh: 不認得的參數 $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$MY_USER" ]] || { echo "ERROR: --my-user 必填" >&2; exit 1; }
[[ -n "$ORG" ]] || { echo "ERROR: --org 必填" >&2; exit 1; }

echo "🔍 問 GitHub：${ORG} 底下我投過票、還 open 的 PR..." >&2

# `gh search prs` 走搜尋 API：打錯的 owner 會回 [] 而且離場 0，所以「空的」不能拿來當
# 「問到了而且沒有」。這裡用離場碼分開兩者，回非 0 就當成問不到。
# stderr 不併進 stdout：併進去的話 gh 的一行警告就會讓底下那個「是不是 JSON 陣列」的
# 檢查判紅，而那跟真的問不到分不開。
search_err="$(mktemp)"
search_out="$(gh search prs \
  --owner "$ORG" \
  --state open \
  --reviewed-by "$MY_USER" \
  --limit "$LIMIT" \
  --json repository,number,title,url,author,createdAt 2>"$search_err")"
search_rc=$?

if [[ "$search_rc" -ne 0 ]]; then
  echo "POLARIS_STALE_REVIEW_SCAN_UNAVAILABLE" >&2
  echo "問不到上游：gh search prs 離場碼 ${search_rc}" >&2
  cat "$search_err" >&2
  rm -f "$search_err"
  exit 2
fi

if ! printf '%s' "$search_out" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "POLARIS_STALE_REVIEW_SCAN_UNAVAILABLE" >&2
  echo "問不到上游：gh search prs 的輸出不是一個 JSON 陣列" >&2
  cat "$search_err" >&2
  rm -f "$search_err"
  exit 2
fi

rm -f "$search_err"
total="$(printf '%s' "$search_out" | jq 'length')"
echo "📦 我投過票的 open PR 共 ${total} 顆，逐顆比我最後一票綁的 commit 與現在的 head" >&2

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

checked=0
moved=0
unreadable=0

while IFS=$'\t' read -r nwo repo number title url author created_at; do
  [[ -n "$nwo" ]] || continue
  # 自己開的 PR 不算（B-N2）。gh search 的 --reviewed-by 會把自我 review 的也帶回來。
  if [[ "$author" == "$MY_USER" ]]; then
    continue
  fi
  checked=$((checked + 1))

  head_sha="$(gh api "repos/${nwo}/pulls/${number}" --jq '.head.sha' 2>/dev/null || echo "")"
  # --paginate --slurp 之後用管線接 jq：只帶 --paginate 的話 gh 逐頁套用 --jq，票數跨頁
  # 時會吐出每頁一個陣列。--slurp 不能跟 --jq 併用（gh 自己會拒絕）。
  my_last_commit="$(gh api "repos/${nwo}/pulls/${number}/reviews" --paginate --slurp 2>/dev/null \
    | jq -r --arg me "$MY_USER" \
        '[.[][] | select(.user.login == $me)] | sort_by(.submitted_at) | last | .commit_id // ""' 2>/dev/null || echo "")"

  if [[ -z "$head_sha" || -z "$my_last_commit" ]]; then
    # 問不到這一顆的事實。不當成「沒有變動」——那個方向永遠往「比較少」錯。
    unreadable=$((unreadable + 1))
    echo "  ⚠️ ${nwo}#${number}：head 或我最後一票的 commit 問不到，這一顆沒有結論" >&2
    continue
  fi

  if [[ "$my_last_commit" != "$head_sha" ]]; then
    moved=$((moved + 1))
    jq -n \
      --arg repo "$repo" \
      --argjson number "$number" \
      --arg title "$title" \
      --arg url "$url" \
      --arg author "$author" \
      --arg created_at "$created_at" \
      '{repo: $repo, number: $number, title: $title, url: $url, author: $author, created_at: $created_at}' >>"$tmpfile"
  fi
done < <(printf '%s' "$search_out" \
  | jq -r '.[] | [.repository.nameWithOwner, .repository.name, (.number|tostring), .title, .url, .author.login, .createdAt] | @tsv')

if [[ -s "$tmpfile" ]]; then
  mine="$(jq -s 'sort_by(.created_at)' "$tmpfile")"
else
  mine='[]'
fi

# 補上 review_status／review_detail。到這裡為止這條路徑只答得出「head 動過了」，答不出
# 「我上次投的是哪一種票」——而下游 build-review-prompt.sh 讀 review_status 讀不到就中斷，
# 整批 packet 從那一顆起停掉。
#
# **不在這裡自己判。** 那個判斷 check-my-review-status.sh 已經有一份（APPROVED 走
# approval-staleness、CHANGES_REQUESTED 與 COMMENTED 各自的分支），在這裡重寫一次就是同一
# 個判斷的第二份實作，而錯的那一份可以永遠錯——兩份都在跑，沒有東西會說它們不一樣。
#
# 它會濾掉 valid_approve 與 waiting_for_author。這條路徑只送 head 已經動過的那幾顆進去，
# 所以正常不會有；真的濾掉了就是那一顆本來就不該進這一批。
if [[ "$mine" != "[]" ]]; then
  enriched="$(printf '%s' "$mine" \
    | "$SCRIPT_DIR/check-my-review-status.sh" --my-user "$MY_USER" --org "$ORG" 2>/dev/null)" || enriched=""
  if [[ -n "$enriched" ]] && printf '%s' "$enriched" | jq -e 'type == "array"' >/dev/null 2>&1; then
    mine="$enriched"
  else
    # 補不到就說出來，不要安靜地送一批下游接不住的列出去。
    echo "⚠️ POLARIS_STALE_REVIEW_STATUS_UNAVAILABLE：check-my-review-status.sh 沒有回一個陣列，這 $(printf '%s' "$mine" | jq 'length') 顆沒有 review_status，下游會在第一顆就中斷" >&2
  fi
fi

if [[ -n "$MERGE_WITH" ]]; then
  if [[ ! -r "$MERGE_WITH" ]]; then
    echo "ERROR: --merge-with 指的檔案讀不到：${MERGE_WITH}" >&2
    exit 1
  fi
  if ! jq -e 'type == "array"' "$MERGE_WITH" >/dev/null 2>&1; then
    echo "ERROR: --merge-with 指的檔案不是一個 JSON 陣列：${MERGE_WITH}" >&2
    exit 1
  fi
  other_count="$(jq 'length' "$MERGE_WITH")"
  # 兩邊都有同一個 url 時，合併的是**欄位**，不是挑一整列留下。挑一列的寫法
  # （`unique_by(.url)`）保留的是輸入順序的第一列——而這條路徑固定把自己掃出來的那一列
  # 放在前面，那一列沒有 review_status，於是欄位比較多的另一列每次都輸。下游
  # build-review-prompt.sh 讀 review_status 讀不到就中斷，整批 packet 從那一顆起停掉。
  #
  # 每一個鍵取「兩邊非空的值排序後的第一個」：非空優先，所以少一邊沒填不會蓋掉有填的；
  # 排序後取第一個，所以兩邊值不同時結果由值本身決定，不由誰先進陣列決定。兩邊都是空的
  # 就照樣留那個空值，不要換成 null。
  printf '%s' "$mine" | jq -s --slurpfile other "$MERGE_WITH" '
    add + $other[0]
    | group_by(.url)
    | map(
        (map(to_entries) | add)
        | group_by(.key)
        | map({
            key: .[0].key,
            value: (
              [.[].value] as $vs
              | ([$vs[] | select(. != null and . != "")] | unique) as $filled
              | if ($filled | length) > 0 then $filled[0] else ($vs | unique | .[0]) end
            )
          })
        | from_entries
      )
    | sort_by(.created_at)'
  echo "🔗 聯集：這條路徑 ${moved} 顆 ＋ 另一條 ${other_count} 顆，去重後如上" >&2
else
  printf '%s\n' "$mine"
fi

echo "✅ 完成：比過 ${checked} 顆，${moved} 顆的 head 已經不是我最後一票綁的那顆；${unreadable} 顆問不到" >&2
