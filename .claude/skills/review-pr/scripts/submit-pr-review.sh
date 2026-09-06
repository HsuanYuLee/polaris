#!/usr/bin/env bash
# Purpose: resolve the head a review is being written against, read the diff pinned
#   to that head, and build/submit the canonical GitHub pull-request review payload.
# Inputs: repository, pull number, reviewed head, review event, body file, optional comments.
# Outputs: the head sha (--print-head), the pinned diff (--print-diff), validated JSON
#   on stdout, or the GitHub API response with --submit.
#
# 綁定即為所見（DP-459）。head 只從 REST repos/{o}/{r}/pulls/{n} 的 .head.sha 取——
# gh 的 pr 子命令（view/diff）走 GraphQL 與可能的快取層，2026-07-27 實測它們比 REST 慢了
# 34 分鐘，而那一次的 review 因此被綁在舊 head 上，還對作者已經修好的東西再提了一次。
#
# 送出去的 commit_id 恆等於呼叫者用 --reviewed-head 宣告的那一顆，這支腳本沒有任何
# 自行推導一顆 sha 的路徑：宣告不出來就不送。head 在 review 期間前進是 review 的正常
# 生命週期，不是缺陷——偵測到只在 stderr 揭露，由讀的人判斷要不要補一則新的。
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  # 1. 取這一次 review 依據的 head
  submit-pr-review.sh --repository OWNER/REPO --pull-number N --print-head

  # 2. 讀釘在那一顆 sha 上的 diff
  submit-pr-review.sh --repository OWNER/REPO --pull-number N --reviewed-head SHA --print-diff

  # 3. 送出，綁在同一顆 sha 上。head 在這中間前進的話，預設照送並在 review body 尾巴
  #    附註它讀的是哪一顆、新增了哪幾顆；要它改成不送就加 --on-head-advanced abort。
  submit-pr-review.sh --repository OWNER/REPO --pull-number N --reviewed-head SHA \
    --event EVENT --body-file PATH [--comments-file PATH] \
    [--tool-identity github.pull_request_review.submit] [--submit]
USAGE
  exit 2
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_BIN="${POLARIS_GH_BIN:-gh}"
repository="" pull_number="" event="" body_file="" comments_file="" submit=0
reviewed_head="" print_head=0 print_diff=0
# 預設是揭露不攔截，那是這支腳本本來的決定（見下面送出前那一段的註解）。要「head 動了
# 就不要送」的呼叫端明講一次——把它做成預設會讓一則已經寫完的 review 被作者的 push 取消，
# 而作者何時 push 不是 reviewer 控制得了的。
on_head_advanced="disclose"
tool_identity="github.pull_request_review.submit"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository) repository="${2:-}"; shift 2 ;;
    --pull-number) pull_number="${2:-}"; shift 2 ;;
    --reviewed-head) reviewed_head="${2:-}"; shift 2 ;;
    --on-head-advanced) on_head_advanced="${2:-}"; shift 2 ;;
    --print-head) print_head=1; shift ;;
    --print-diff) print_diff=1; shift ;;
    --event) event="${2:-}"; shift 2 ;;
    --body-file) body_file="${2:-}"; shift 2 ;;
    --comments-file) comments_file="${2:-}"; shift 2 ;;
    --tool-identity) tool_identity="${2:-}"; shift 2 ;;
    --submit) submit=1; shift ;;
    -h|--help) usage ;;
    *) echo "POLARIS_SUBMIT_PR_REVIEW_UNKNOWN_ARGUMENT:$1" >&2; usage ;;
  esac
done

[[ "$repository" =~ ^[^/]+/[^/]+$ ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_REPOSITORY_INVALID:$repository" >&2; exit 2; }
[[ "$pull_number" =~ ^[1-9][0-9]*$ ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_NUMBER_INVALID:$pull_number" >&2; exit 2; }
[[ "$on_head_advanced" == "disclose" || "$on_head_advanced" == "abort" ]] || {
  echo "POLARIS_SUBMIT_PR_REVIEW_ON_HEAD_ADVANCED_INVALID:$on_head_advanced" >&2
  echo "--on-head-advanced 只吃 disclose（預設）或 abort。" >&2
  exit 2
}
[[ -z "$reviewed_head" || "$reviewed_head" =~ ^[0-9a-f]{40}$ ]] || {
  echo "POLARIS_SUBMIT_PR_REVIEW_REVIEWED_HEAD_INVALID:$reviewed_head" >&2
  echo "--reviewed-head 要一顆完整的 40 字元 sha；縮寫比不出「head 有沒有前進」。" >&2
  exit 2
}

# 這三種模式都要打 GitHub。工具不在就在這裡停——不安裝、不 silent skip。
if [[ "$print_head" -eq 1 || "$print_diff" -eq 1 || "$submit" -eq 1 ]]; then
  command -v "$GH_BIN" >/dev/null 2>&1 || { echo "POLARIS_TOOL_MISSING:gh" >&2; exit 2; }
fi

# Description: read the PR object once and print "<head_sha> <base_sha>".
# Args:        none (uses $repository / $pull_number).
# Side effects: one REST call. Prints nothing and returns 1 when the read fails or
#   the object carries no head sha — the caller decides what that means.
resolve_pr_refs() {
  local pr_json=""
  pr_json="$("$GH_BIN" api "repos/$repository/pulls/$pull_number" 2>/dev/null)" || return 1
  printf '%s' "$pr_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
head = (data.get("head") or {}).get("sha") or ""
base = (data.get("base") or {}).get("sha") or ""
if not head:
    raise SystemExit(1)
print(f"{head} {base}")
'
}

if [[ "$print_head" -eq 1 ]]; then
  refs="$(resolve_pr_refs)" || {
    echo "POLARIS_PR_HEAD_UNRESOLVED:$repository#$pull_number" >&2
    exit 2
  }
  printf '%s\n' "${refs%% *}"
  exit 0
fi

if [[ "$print_diff" -eq 1 ]]; then
  [[ -n "$reviewed_head" ]] || {
    echo "POLARIS_PR_REVIEW_REVIEWED_HEAD_REQUIRED:--print-diff" >&2
    echo "diff 要釘在一顆宣告出來的 sha 上，否則讀到的內容與送出時綁的可能不是同一版。" >&2
    echo "先跑 --print-head 取得那一顆，再把它傳進來。" >&2
    exit 2
  }
  refs="$(resolve_pr_refs)" || {
    echo "POLARIS_PR_BASE_UNRESOLVED:$repository#$pull_number" >&2
    exit 2
  }
  base_sha="${refs##* }"
  [[ -n "$base_sha" ]] || { echo "POLARIS_PR_BASE_UNRESOLVED:$repository#$pull_number" >&2; exit 2; }
  # 三點比較的語意與 PR diff 相同（對 merge base 取），差別是它釘得住 sha——
  # gh 的 pr diff 子命令沒有吃 sha 的口，而那正是 2026-07-27 讀到舊內容的那條路。
  exec "$GH_BIN" api -H "Accept: application/vnd.github.v3.diff" \
    "repos/$repository/compare/$base_sha...$reviewed_head"
fi

[[ "$event" == "APPROVE" || "$event" == "COMMENT" || "$event" == "REQUEST_CHANGES" ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_EVENT_INVALID:$event" >&2; exit 2; }
[[ -f "$body_file" ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_BODY_MISSING:$body_file" >&2; exit 2; }
[[ "$tool_identity" == "github.pull_request_review.submit" ]] || { echo "POLARIS_EXTERNAL_WRITE_TOOL_IDENTITY_INVALID:$tool_identity" >&2; exit 2; }

# 沒宣告讀的是哪一版就不准送。不宣告而送出去的話，GitHub 會把這則 review 綁在它認為
# 的當下 head 上——那是一顆 reviewer 從來沒有讀過的 commit，比綁到舊的那顆更糟。
if [[ "$submit" -eq 1 && -z "$reviewed_head" ]]; then
  echo "POLARIS_PR_REVIEW_REVIEWED_HEAD_REQUIRED:--submit" >&2
  echo "先跑 --print-head 取得這次 review 依據的 sha，用 --print-diff 對它讀 diff，再原樣傳回來。" >&2
  exit 2
fi

# Description: 列出 reviewed head 之後才進來的那幾顆 commit，一行一顆。
# Params: $1 = 從哪一顆算起、$2 = 算到哪一顆。
# Returns: 0 並印出清單；問不到就回 1，不印。
list_commits_between() {
  "$GH_BIN" api "repos/$repository/compare/$1...$2" \
    --jq '.commits[] | "\(.sha[0:8]) \(.commit.message | split("\n")[0])"' 2>/dev/null
}

# 送出前再問一次當下 head。**這一段刻意排在 external write gate 前面**：它會往 body 尾巴
# 接一段附註，而那段字必須跟 body 的其餘部分走同一道語言與 payload 檢查——接在閘後面的話，
# 送出去的內容就有一段沒有人驗過。
# 署名。**這一段跟下面的 head 附註一樣要排在 external write gate 前面**：閘會要求
# body 帶著這個標記（宣告源在 polaris-external-write-gate.sh 的 POLARIS_ATTRIBUTED_SURFACES
# 那一段），而接在閘後面的字沒有過語言與 payload 檢查。
#
# 這則 review 掛在一個人的 GitHub 帳號底下，而 GitHub 沒有原生標示。不署名的話它讀起來
# 就是那個人自己寫的——然後下一輪讀回來，它是那個人的意圖。
# 標記字串問閘，不在這裡重寫一份——閘等一下就要拿它檢查這份 body，兩份字面值對不上的
# 那一刻沒有任何輸出說得出來。
POLARIS_ATTRIBUTION_MARK="$(bash "$ROOT/scripts/polaris-external-write-gate.sh" --print-attribution-mark)"
if [[ "$submit" -eq 1 && -n "$POLARIS_ATTRIBUTION_MARK" ]] \
   && ! grep -qF "$POLARIS_ATTRIBUTION_MARK" "$body_file"; then
  signed_body="$(mktemp -t polaris-pr-review-signed.XXXXXX.md)"
  {
    cat "$body_file"
    printf '\n\n_（%s）_\n' "$POLARIS_ATTRIBUTION_MARK"
  } > "$signed_body"
  body_file="$signed_body"
fi

head_note=""
head_advanced=0
head_unresolved=0
current_head=""
if [[ "$submit" -eq 1 ]]; then
  if current_refs="$(resolve_pr_refs)"; then
    current_head="${current_refs%% *}"
    [[ "$current_head" != "$reviewed_head" ]] && head_advanced=1
  else
    head_unresolved=1
  fi
fi

if [[ "$head_advanced" -eq 1 ]]; then
  # **附註要進 body，不只進 stderr。** 這張單回報的傷害是「讀 review 的人會以為那一則看過
  # 現在的 head」——而 stderr 只有跑這支腳本的那一端看得到，讀 review 的人看不到。
  new_commits="$(list_commits_between "$reviewed_head" "$current_head" || true)"
  merged_body="$(mktemp -t polaris-pr-review-body.XXXXXX.md)"
  {
    cat "$body_file"
    printf '\n\n---\n\n'
    printf '這則 review 讀的是 `%s`。送出的這一刻 head 已經是 `%s`。\n' \
      "${reviewed_head:0:8}" "${current_head:0:8}"
    if [[ -n "$new_commits" ]]; then
      printf '\n中間新增的 commit：\n\n'
      printf '%s\n' "$new_commits" | sed 's/^/- /'
      printf '\n上面的意見沒有看過這幾顆。\n'
    else
      printf '\n中間新增了哪幾顆問不到，所以上面的意見涵蓋到哪裡說不準。\n'
    fi
  } > "$merged_body"
  body_file="$merged_body"
fi

tmp="$(mktemp -t polaris-pr-review.XXXXXX.json)"
trap 'rm -f "$tmp" "${merged_body:-}" "${signed_body:-}"' EXIT
python3 - "$repository" "$pull_number" "$event" "$body_file" "$comments_file" "$reviewed_head" "$tmp" <<'PY'
import json, sys
from pathlib import Path
repository, pull_number, event, body_path, comments_path, reviewed_head, output = sys.argv[1:]
owner, repo = repository.split("/", 1)
comments = []
if comments_path:
    try:
        comments = json.loads(Path(comments_path).read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"POLARIS_EXTERNAL_WRITE_PAYLOAD_INVALID:comments:{exc}", file=sys.stderr)
        raise SystemExit(2)
payload = {
    "owner": owner,
    "repo": repo,
    "pull_number": int(pull_number),
    "event": event,
    "body": Path(body_path).read_text(encoding="utf-8"),
    "comments": comments,
}
# commit_id 只有這一個來源。腳本裡沒有第二條算得出 sha 的路徑，所以「綁到沒讀過的
# commit」不是被規則勸阻，是在結構上做不到。
if reviewed_head:
    payload["commit_id"] = reviewed_head
Path(output).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

POLARIS_EXTERNAL_WRITE_WRITER=review-pr:github-review \
  bash "$ROOT/scripts/polaris-external-write-gate.sh" \
    --surface github-review --body-file "$body_file" \
    --tool-identity "$tool_identity" --payload-file "$tmp" \
    --workspace-root "$ROOT" >/dev/null

if [[ "$submit" -eq 0 ]]; then
  cat "$tmp"
  exit 0
fi

# 預設揭露，不攔截。作者何時 push 是 reviewer 無法預期也無法控制的事件，不該讓它中止一則
# 已經寫完的 review；這裡只把「你讀的不是最新版」講出來，處置由讀的人決定。**要它擋，
# 呼叫端明講 --on-head-advanced abort。**
if [[ "$head_advanced" -eq 1 ]]; then
  echo "POLARIS_PR_HEAD_ADVANCED: $reviewed_head -> $current_head" >&2
  if [[ -n "${new_commits:-}" ]]; then
    echo "  中間新增的 commit：" >&2
    printf '%s\n' "$new_commits" | sed 's/^/    /' >&2
  else
    echo "  中間新增了哪幾顆問不到。" >&2
  fi
  if [[ "$on_head_advanced" == "abort" ]]; then
    echo "POLARIS_PR_REVIEW_ABORTED_HEAD_ADVANCED:$reviewed_head -> $current_head" >&2
    echo "  --on-head-advanced abort：一則都沒有送出。重看上面那幾顆再送。" >&2
    exit 3
  fi
elif [[ "$head_unresolved" -eq 1 ]]; then
  echo "POLARIS_PR_HEAD_UNRESOLVED: 送出前這一趟沒問到當下 head，無法判斷它有沒有前進；" >&2
  echo "  這則 review 仍綁在 ${reviewed_head}——那是它實際讀過的那一版。" >&2
  if [[ "$on_head_advanced" == "abort" ]]; then
    # 問不到的答案不得比答得出來的答案寬。呼叫端要的是「動了就不要送」，而這一趟答不出
    # 它有沒有動——照樣送出去等於把那個要求靜靜地取消掉。
    echo "POLARIS_PR_REVIEW_ABORTED_HEAD_UNRESOLVED:$reviewed_head" >&2
    echo "  --on-head-advanced abort：問不到當下 head，一則都沒有送出。" >&2
    exit 3
  fi
fi

# 恰一次。被拒絕（例如 reviewed head 已經被 force-push 掉）就原樣回報，不改綁當下 head
# 重送——那會把一則對 X 做的 review 掛到 Y 身上。
"$GH_BIN" api --method POST "repos/$repository/pulls/$pull_number/reviews" --input "$tmp"
