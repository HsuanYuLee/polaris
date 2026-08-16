# Review Inbox Dispatch Context v1

## Review Flow

Review the PR from the supplied URL and local repo path. Fetch PR metadata,
changed files, diff, existing reviews, approval state, and re-review signal with
the repo script or `gh`. Read only the verified project handbook paths listed in
the prompt. If no handbook paths are listed, record `project_handbook: none` and
continue without scanning repo guideline folders.

## What To Actually Look For

改對了不等於有用。**先問這段程式走不走得到，再問它對不對**——一個值改對了、但沒有任何地方
讀它的改動，正確的意見是「這一整組已經是死碼」，不是「這個值改對了」。

逐項走過去，每一項都要能指到具體的 `path:line`：

- **可達性。** 這個改動的消費端在哪？把 prop、事件、export 追到真的有人讀它的地方。追不到就
  是發現。
- **這個改動讓什麼變成 dead code。** 改完之後有沒有東西再也走不到、再也沒人 import、註冊被
  註解掉。
- **註解、文件、PR 描述與程式碼對不對得上。** 這一項要讀**未改動**的區域——對不上的那一句
  通常不在 diff 裡。PR 自己的描述與 QA notes 也算。
- **同一個 pattern 的其他出現處。** 這裡改了一個，其他幾個呢？`grep` 一次，說出還有幾個沒改
  以及為什麼那幾個不用改。
- **姊妹 repo / 同類型既有實作當對照組。** 新增元件、API、composable、store 時，看 1–2 個既有
  的同類型實作；跨 repo 的同一段兩端行為對不上時，先判斷哪一邊是對的。
- **cross-file consistency。** 一個結論需要哪幾個檔案才站得住，就讀哪幾個——**不需要先落進
  某一類風險**。讀了什麼列在 Detail artifact 裡。
- **測試是不是恆真。** 一條永遠會過的斷言跟沒有那條測試的差別只有執行時間。

給修法比描述問題有用：能貼上去就直接貼一段可用的 code，不要只說「這裡有問題」。

## Severity And Write Rules

Prioritize bugs, regressions, security, type safety, key rule violations, and
missing tests. `must-fix` requires evidence from code, diff, or an explicit rule.
Unverified library behavior or style preference is at most `should-fix`. Do not
repeat existing reviewer comments with the same meaning. Suggested changes are
allowed only when the diff range can be replaced exactly.

**severity 決定 submit event，不決定 comment 長什麼樣子。** 它是給第 `## Submit Action`
那一步用的分類，不是每則 comment 開頭要貼的標籤。強度寫在句子裡就好——「這支不擋，但⋯」
「順手一提」「想跟你 confirm 一下」，而**不確定的時候把判斷交還給作者比猜一個嚴重度誠實**。

## Submit Action

Choose `REQUEST_CHANGES` for any must-fix, `COMMENT` for should-fix only, and
`APPROVE` for no issues or only nits. Keep the review body short and concrete.
Run the language gate before any GitHub review or Slack reply. After submit,
query valid approvals, stale approvals, current requested changes, and remaining
approval count.

Read and bind against the same sha — resolve it first, take the diff pinned to it,
and hand the same value back at submit time:

```bash
REVIEWED_HEAD="$(bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N --print-head)"
bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N \
  --reviewed-head "$REVIEWED_HEAD" --print-diff
bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N \
  --reviewed-head "$REVIEWED_HEAD" --event EVENT --body-file BODY --submit
```

Submitting without `--reviewed-head` is refused. `POLARIS_PR_HEAD_ADVANCED` on stderr
means the author pushed while you were reviewing: the review was submitted and is
correctly bound to what you read. It is a message for you, not a failure.

## Completion Envelope

Return exactly:

```markdown
Status: DONE | ERROR
Artifacts: {pr_url, number, title, author, repo, result, must_fix, should_fix, nit, approve_status, summary}
Detail: /tmp/polaris-agent-{timestamp}.md
Summary: <= 3 sentences
```
