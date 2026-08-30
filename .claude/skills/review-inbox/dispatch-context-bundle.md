# Review Inbox Dispatch Context v1

## Review Flow

Review the PR from the supplied URL and local repo path. Fetch PR metadata,
changed files, diff, existing reviews, approval state, and re-review signal with
the repo script or `gh`. Read only the verified project handbook paths listed in
the prompt. If no handbook paths are listed, record `project_handbook: none` and
continue without scanning repo guideline folders.

## The Shared Checkout Is Not Yours

`local path` 指的那棵樹是別人也在用的——這台機器的主人、並行的 session、以及這一輪其他每
一個 reviewer。**它的狀態不得被改動。** 不要 `git checkout`、`git switch`、`git stash`、
`git reset`，也不要在那裡切分支。

**「切走再還原」不是一條合法的做法。** 還原本身就會 race：你要切回去的那一刻，樹可能已經
被第三個人切到別的地方了。2026-08-27 那一輪三個 reviewer 這樣做，其中一個因此放棄還原，
那一輪結束時該 repo 停在 detached HEAD。

讀某個 commit 上的東西，兩條路都不動樹：

    git -C <local path> show <sha>:<path>
    gh api repos/<owner>/<repo>/contents/<path>?ref=<sha> --jq .content | base64 -d

真的需要一棵可以動的樹的時候（要跑測試、要實際跑起來看行為），開你自己的 worktree：

    wt="$(mktemp -d)/pr-<number>"
    git -C <local path> worktree add --detach "$wt" <sha>
    # ……用完清掉
    git -C <local path> worktree remove --force "$wt"

`worktree add` 不動原本那棵樹的 HEAD，也不動它的工作目錄。用完要清掉——留下來的會出現在
下一個人的 `git worktree list` 裡。

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
- **測試是不是恆真。** 一條永遠會過的 assertion 跟沒有那條測試的差別只有執行時間。

給修法比描述問題有用：能貼上去就直接貼一段可用的 code，不要只說「這裡有問題」。

## Severity And Write Rules

Prioritize bugs, regressions, security, type safety, key rule violations, and
missing tests. `must-fix` requires evidence from code, diff, or an explicit rule.
Unverified library behavior or style preference is at most `should-fix`. Do not
repeat existing reviewer comments with the same meaning.

**嚴重度由執行期行為決定的時候，實際跑一次再判。** 上面那條說「沒驗過的 library 行為最多
`should-fix`」——那條的另一半是：**驗它通常只要一行。** repo 裡就有那個 library，`node -e`／
`php -r` 跑一次就知道那個值是 `undefined` 還是 `null`，而那一個字的差別就是 nit 與 must-fix
的差別。

2026-08-26 與 2026-08-27 對同一顆 sha 各跑一次同一張 PR，量到的：`get(obj, path, null)` 這處
兩次都被看到，但只有跑過 lodash 的那一次追到「商品價格會塌成 0」而判 must-fix；沒跑的那一次
把它寫成「註解與程式碼自相矛盾」的 nit。**同一個發現，一個會擋 merge，一個不會。**

所以看到一個改動的對錯取決於某個運算式在執行期回什麼，不要用讀的推——跑它，然後把輸出貼進
意見裡。

**`suggestion` 區塊只能貼在它真的要取代的那幾行上。** 貼之前對兩件事各驗一次，2026-08-26
兩次都差一點送出去：

- **意見錨在哪一行，取代的就要是哪一行。** 錨在 `:78` 的 docblock、程式碼要換的是
  `:183-185`，掛成 `suggestion` 會覆蓋錯的行。錨與取代範圍對不上就改成一般的程式碼區塊
  （改用 ```ts 這種一般的圍籬），不要用 `suggestion`。
- **錨的那一行必須是 diff 裡的 added line。** 掛在 context line 上 GitHub 會回 422，整則
  review 送不出去。往下移到最近的 added line，或用 `start_line` 把範圍框起來。

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
