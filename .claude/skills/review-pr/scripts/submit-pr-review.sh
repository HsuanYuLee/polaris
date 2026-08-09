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

  # 3. 送出，綁在同一顆 sha 上
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
tool_identity="github.pull_request_review.submit"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository) repository="${2:-}"; shift 2 ;;
    --pull-number) pull_number="${2:-}"; shift 2 ;;
    --reviewed-head) reviewed_head="${2:-}"; shift 2 ;;
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

tmp="$(mktemp -t polaris-pr-review.XXXXXX.json)"
trap 'rm -f "$tmp"' EXIT
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

# 揭露，不攔截。作者何時 push 是 reviewer 無法預期也無法控制的事件，不該讓它中止一則
# 已經寫完的 review；這裡只把「你讀的不是最新版」講出來，處置由讀的人決定。
if current_refs="$(resolve_pr_refs)"; then
  current_head="${current_refs%% *}"
  if [[ "$current_head" != "$reviewed_head" ]]; then
    echo "POLARIS_PR_HEAD_ADVANCED: $reviewed_head -> $current_head" >&2
  fi
else
  echo "POLARIS_PR_HEAD_UNRESOLVED: 送出前這一趟沒問到當下 head，無法判斷它有沒有前進；" >&2
  echo "  這則 review 仍綁在 ${reviewed_head}——那是它實際讀過的那一版。" >&2
fi

# 恰一次。被拒絕（例如 reviewed head 已經被 force-push 掉）就原樣回報，不改綁當下 head
# 重送——那會把一則對 X 做的 review 掛到 Y 身上。
"$GH_BIN" api --method POST "repos/$repository/pulls/$pull_number/reviews" --input "$tmp"
