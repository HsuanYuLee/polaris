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

**一格綠的檢查，先問它跑過這條 branch 沒有。** CI 狀態在 review 裡被當成一項證據讀，而它
只有在相關的 job 真的在這顆 PR 的 base 上跑過的時候才是證據。**沒跑過的綠與跑過而通過的綠，
在 `statusCheckRollup` 裡長得一模一樣**——那張表列的是「有哪幾格」，不是「哪幾格該有」。

**問的對象是這顆 sha 上的 commit status，不是那張 rollup 表、也不是那份 workflow 設定檔：**

```bash
gh api repos/{owner}/{repo}/commits/{head_sha}/statuses --paginate \
  --jq '.[] | "\(.context)\t\(.state)\t\(.created_at)"' | sort
```

逐個 context 看兩件事，它們是兩種形狀、要人做的事不同：

- **pending 到 success 的秒數差。** 太短就是沒真的跑。**不要用寫死的門檻**——同一顆 sha 上
  本來就有 7 秒跑完的 job。對照拿同名 context 在別顆真的跑完的 sha 上要多久。
- **那個 context 在不在。** 整組缺席跟「跑很快」不一樣：缺席的那幾條在 rollup 上根本沒有
  格子，而剩下真的跑完的那幾格讓整張表看起來全綠。

兩種都不是綠，是**沒有量**。要在意見裡說出來，而且那條相關的檢查要自己跑一次。

**statuses 問不到的時候**（權限、API 失敗）說出這一趟沒問到，並退回舊那招：把這顆 PR 的
base 拿去對那份 workflow 的觸發條件（`when.branch`／path 過濾）。**問不到不是全綠的溫和
版本。**

2026-09-16／17 在一個走 woodpecker 的 repo 上量到的：同一個 context 名
`continuous-integration/drone/pr/woodpecker/lint-frontend`，在一顆真的跑完的 sha 上
pending→success 是 **689 秒**；在四顆沒跑的上面是 **9／22／11／20 秒**。第五顆更難看——
整個 woodpecker 家族一條 context 都沒出現，rollup 上只剩兩條真的跑完的 `b2c-ci/*`，
看起來全綠。

更早那一顆的形狀是同一件事：一顆 sync PR 兩格 check 全綠，而它帶著一份有 3 個重複 mapping
key 的 lockfile，`pnpm install --frozen-lockfile` 直接紅。那份 lint workflow 的 `when.branch`
只有兩條主線分支，那顆 PR 的 base 不在裡面，所以它從來沒有跑過 `pnpm install`。
**誤差方向是「看起來比較安全」，所以沒有人會來報。**

這跟「同名 check 重跑之後舊的失敗還留在表上」是兩個不同的失效模式：那一個是結果過期，
取最新那筆就解得掉；這一個是那份 job 根本不存在，取最新那筆不會讓它出現。

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
把它寫成「註解與程式碼自相矛盾」的 nit。**同一個發現，一個判 must-fix，一個判 nit。**

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

那則 comment 長什麼樣子，由 packet 裡〈一則 review 寫成什麼形狀〉那一段決定——它是
`review-pr/references/review-comment-form.md` 的內容，由 `build-review-prompt.sh` 原樣放進來。

## Submit Action

送哪一個 event 照 packet 裡〈Review Action〉那張表——它是 `review-pr` 的
`references/review-pr-submit-flow.md`，由 `build-review-prompt.sh` 原樣放進來，**這裡不抄
第二份**。

**哪一個 event 配哪一種發現，只有那張表說了算，這裡不重講一次。** 派工的人本身沒有擋人的
授權：使用者沒有對這一顆說過話的話，must-fix 照樣逐條寫出來，那一票不擋人。使用者明說要擋
這一顆的時候，照那張表最後一列帶 `--blocking-authorized '<他的原話>'`——那段原話會出現在送出
去的 review 正文裡，所以下一個讀到它的人分得出這一票是誰授權的。沒有那段話腳本會拒送
（`POLARIS_SUBMIT_PR_REVIEW_BLOCKING_NOT_AUTHORIZED`）。Keep the review body short and concrete.
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
  --reviewed-head "$REVIEWED_HEAD" --event EVENT \
  --body-file /tmp/review-inbox-runs/{run_id}/pr-N-body.md --submit
```

**Do not pick the body path yourself.** One run dispatches several reviewers into the same
`{run_id}` directory, so every artifact path carries the PR number — the packet lists them.
The body's first line must be `<!-- polaris-review-target: OWNER/REPO#N -->`, written by you
while you still know which PR you are reading. The pre-submit gate compares that anchor with
the PR the payload is bound for and refuses a mismatch.

Submitting without `--reviewed-head` is refused. `POLARIS_PR_HEAD_ADVANCED` on stderr
means the author pushed while you were reviewing: the review was submitted and is
correctly bound to what you read. It is a message for you, not a failure.

**Every write to a review goes through this script — the first submit and every later
correction.** To fix a review you already submitted, pass its id back to the same script
instead of calling `gh api` yourself:

```bash
bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N \
  --update-review-id REVIEW_ID --body-file /path/to/corrected-body.md
```

A hand-rolled `gh api -X PUT` has already destroyed one delivered review: `-f body=@file`
sends the literal string `@file`, so an 11-character body replaced 4483 bytes of findings
and nothing on this side reported a failure. The script reads the review back after every
write and exits non-zero when what GitHub returns does not match what was sent.

## Completion Envelope

Return exactly:

```markdown
Status: DONE | ERROR
Artifacts: {pr_url, number, title, author, repo, result, must_fix, should_fix, nit, approve_status, summary}
Detail: /tmp/polaris-agent-{timestamp}.md
Summary: <= 3 sentences
```
