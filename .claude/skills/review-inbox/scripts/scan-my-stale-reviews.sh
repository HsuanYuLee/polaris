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
# 輸出（stdout）：JSON 陣列，欄位與 scan-need-review-prs.sh / fetch-prs-by-url.sh 相同
#   （repo, number, title, url, author, created_at），可以直接接 check-my-review-status.sh。
# 進度（stderr）。
#
# --merge-with <file>：另一個來源的同形 JSON 陣列，兩邊取聯集、以 url 去重。聯集在這裡做，
#   不寫成散文裡的一行 jq——那一行沒被跑的時候，少掉的那一半跟「沒有」長得一樣。
#
# 離場碼：
#   0  問到了（可能是 0 顆，那是一個答案）
#   1  參數不對
#   2  問不到上游（搜尋失敗）。**不回空陣列**：問不到與沒有是兩件事，而它們的下一步相反。

set -uo pipefail

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
  printf '%s' "$mine" | jq -s --slurpfile other "$MERGE_WITH" \
    'add + $other[0] | unique_by(.url) | sort_by(.created_at)'
  echo "🔗 聯集：這條路徑 ${moved} 顆 ＋ 另一條 ${other_count} 顆，去重後如上" >&2
else
  printf '%s\n' "$mine"
fi

echo "✅ 完成：比過 ${checked} 顆，${moved} 顆的 head 已經不是我最後一票綁的那顆；${unreadable} 顆問不到" >&2
