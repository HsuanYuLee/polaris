#!/usr/bin/env python3
"""把一批 PR candidates 標上「這一輪要不要看」。

輸入（stdin）：review-inbox discovery 產出的 candidates JSON array，每筆至少要有
`repo`、`number`，通常還有 `url`、`title`、`author`、`review_status`。

輸出（stdout）：同一批，每筆多三個欄位——
  effective_approvals  以目前 head 為準、還算數的 approve 數（查不到時為 null）
  sweep_decision       "review" 或 "skip"
  sweep_skip_reason    skip 時的原因，給表格直接用

跳過的兩種：作者是自己，以及有效 approve 已達門檻。查不到 review 資料的不跳過——
讓人去看一個可能不用看的 PR，比安靜漏掉一個要看的便宜。
"""
import argparse
import json
import subprocess
import sys

# 一筆 review 是否覆蓋同一個人先前的 approve。COMMENTED 不算表態，不參與這個排序。
DECISIVE_STATES = ("APPROVED", "CHANGES_REQUESTED", "DISMISSED")


def gh_json(path, paginate=False):
    """呼叫 gh api 取 JSON；失敗回 None（讓呼叫端自己決定怎麼辦，不在這裡吞掉）。"""
    cmd = ["gh", "api", path] + (["--paginate"] if paginate else [])
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"[sweep] gh api {path} 失敗：{exc}", file=sys.stderr)
        return None
    if not paginate:
        return json.loads(out)
    # --paginate 把每一頁各輸出成一個 JSON array，串在一起不是合法的單一文件，逐個解。
    decoder, idx, merged = json.JSONDecoder(), 0, []
    out = out.strip()
    while idx < len(out):
        page, idx = decoder.raw_decode(out, idx)
        merged.extend(page)
        while idx < len(out) and out[idx].isspace():
            idx += 1
    return merged


def inspect(org, repo, number):
    """回 (作者 login, 以目前 head 為準還算數的 approve 數, 已經關掉了沒有)。查不到的回 None。

    作者以 API 為準，不用 candidate 帶進來的那一欄——那一欄可能根本不存在，而「沒有這一欄」
    與「作者不是我」在後面長得一模一樣，於是自己的 PR 會被安靜地送進 review 名單。
    """
    pr = gh_json(f"repos/{org}/{repo}/pulls/{number}")
    if not pr:
        return None, None, None
    author = (pr.get("user") or {}).get("login")
    # 頻道裡的訊息不會因為 PR 被合掉而消失，所以每一輪都會再撈到它。
    closed = pr.get("state") != "open"
    head_sha = pr.get("head", {}).get("sha")
    reviews = gh_json(f"repos/{org}/{repo}/pulls/{number}/reviews", paginate=True)
    if reviews is None or not head_sha:
        return author, None, closed

    latest_by_user = {}
    for review in reviews:
        if review.get("state") not in DECISIVE_STATES:
            continue
        login = (review.get("user") or {}).get("login")
        if login:
            latest_by_user[login] = review

    approvals = sum(
        1 for review in latest_by_user.values()
        if review["state"] == "APPROVED" and review.get("commit_id") == head_sha
    )
    return author, approvals, closed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--org", required=True, help="GitHub org，PR 都在它底下")
    parser.add_argument("--my-user", required=True, help="執行的人自己的 GitHub login")
    parser.add_argument("--threshold", type=int, default=2, help="幾個有效 approve 就不用再看")
    args = parser.parse_args()

    candidates = json.load(sys.stdin)
    if not candidates:
        print("[sweep] 這一輪沒有 candidate", file=sys.stderr)
        print("[]")
        return

    for pr in candidates:
        author, count, closed = inspect(args.org, pr["repo"], pr["number"])
        pr.setdefault("author", author)
        pr["effective_approvals"] = count

        if closed:
            pr["sweep_decision"] = "skip"
            pr["sweep_skip_reason"] = "已經合併或關閉"
        elif author is None:
            # PR 本身查不到（權限、被刪、network）。不跳過——讓人去看一個可能不用看的，
            # 比安靜漏掉一個要看的便宜。
            pr["sweep_decision"] = "review"
            pr["sweep_skip_reason"] = ""
        elif author == args.my_user:
            pr["sweep_decision"] = "skip"
            pr["sweep_skip_reason"] = "自己是作者"
        elif count is not None and count >= args.threshold:
            pr["sweep_decision"] = "skip"
            pr["sweep_skip_reason"] = f"已有 {count} 個有效 approve"
        else:
            pr["sweep_decision"] = "review"
            pr["sweep_skip_reason"] = ""

    reviewing = sum(1 for pr in candidates if pr["sweep_decision"] == "review")
    print(f"[sweep] {len(candidates)} 個 candidate：{reviewing} 個要看、"
          f"{len(candidates) - reviewing} 個跳過", file=sys.stderr)
    print(json.dumps(candidates, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
