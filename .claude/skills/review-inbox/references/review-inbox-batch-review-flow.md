---
title: "Review Inbox Batch Review Flow"
description: "review-inbox 的 candidates list、派工、per-PR review packet execution 與 result fan-in。"
---

# Batch Review Contract

這份 reference 負責 candidates list 呈現、派工、review 執行、結果收斂。

本 flow 受 `context-budget-contract.md` 的 review-inbox concrete instance 約束。Main session
只保留決策、路由、fan-in 與 Completion Envelope summary；raw diff、raw comments、PASS CI
rollup 與 raw Slack channel messages 預設不得進 main context。

## Candidate List

Candidates 依 PR created time 升序排序，最早發出的 PR 優先。顯示欄位：

| Field | Purpose |
|---|---|
| number | user selection |
| repo | review scope |
| PR number and title | identification |
| author | notification routing |
| review status | first review / re-approve / re-review |

表格下方附統計：first review、re-approve、re-review counts。

**清單列完就全部進入 review。** 不等人選編號、不取前幾張、不因為張數多或 diff 大自行縮小
範圍。以前這裡寫著「若 `skill_defaults.review-inbox.confirm` 為 false 就自動選取，若為 true
就等使用者輸入」——而那個旋鈕全樹只有這一行提到，兩份 `workspace-config.yaml` 都沒有它，
沒有任何一支腳本讀過它。**一個從來沒有人設定過的旋鈕不是設定，是散文**，而讀它的人只能猜
它預設哪一邊。2026-08-26 猜的結果是停下來問人。

停下來只有兩種理由，而且要說出是哪一種：**來源拿不到**，或是**需要授權而授權不存在**。

## 一張 PR 交給一個 sub-agent

**用哪一種 agent、幾個並行、先跑哪一張，由執行的人當下判斷。** 這一支給的是判斷需要的
事實——`cluster_role`、`cluster_size`、`model_tier`、授權狀態——不是結論。

以前這裡規定了三層：預設 adapter 叫什麼、禁止用 general-purpose sub-agent、以及一份
`build-review-runtime-plan.py` 產生的 runtime plan。三層一起拿掉了（DP-575），理由分別是：

- **禁令的根據是一句不實的引用。** 它寫著「DP-094 AC1 量到 general-purpose envelope 會壓過
  prompt-side 的節省」，而 DP-094 AC1 量的是 `main_session_sequential` 這個模式本身——
  6 張 PR、平均 6,111.5 tokens。**禁令是那次量測的前提，不是它的發現**，從頭到尾沒有跑過
  一組 general-purpose 當對照。DP-094 自己把它登記成 measurement gap 交給 DP-113，而
  DP-113 那份證據後來連同它的整層一起沒了。
- **那份 runtime plan 買到的接近零。** plan step 的 19 個欄位裡 12 個是逐字從 candidates
  抄過來的，2 個是那條禁令。238 + 148 行買到一次資料重排。
- **一支 `scope: universal` 的 skill 指名一個它不 ship 的 agent 型別**，本來就違反「不依賴
  環境」。規定拿掉之後，沒有東西可以依賴。

**那條禁令原本要保護的東西留下來：主 session 不讀完整 diff。** 那件事
`context-budget-contract.md` 本來就直接規定，任何 sub-agent 都滿足它。代理消失，被代理的
不消失。

## Per-PR Review Dispatch

每個 PR 使用獨立 review packet。Dispatch 前 candidates 必須已由
`annotate-review-candidates.py` 補上 `model_tier` 與 cluster metadata。Prompt 必須包含：

- PR URL。
- `review_status`。
- Current GitHub username。
- Workspace config base directory。
- `review-inbox/dispatch-context-bundle.md` 的 inline 內容。
- deterministic handbook resolver 輸出的 verified project handbook paths；空清單時明確寫
  no project handbook，且不可掃 repo guideline folders。
- `model_tier` semantic class hint。
- `cluster_role`, `cluster_key`, `root_ticket_key`, `root_topic_key`, `cluster_lead_url`，
  以及 sibling PR 可用的 lead summary。
- 送出授權狀態：人已授權時帶著授權的人與原話，未授權時明講未授權。
- 延伸參考的路徑（`review-pr/references/` 底下那幾份），要不要讀由執行者判斷。
- Completion Envelope requirement。

Review mode：

| Status | Review behavior |
|---|---|
| `needs_first_review` | normal review |
| `needs_re_approve` | review commits since last valid approve；無實質變更時可直接 re-approve |
| `needs_re_review` | check previous comments and author fixes |

Review packet 自帶執行 review 需要的全部內容：inline dispatch context、verified handbook
paths、PR diff、existing comments。**執行者不需要讀任何 skill 就做得完**——這一條沒有變。

變的是另一半：packet 另外附上 `review-pr/references/` 底下那幾份的**路徑**，讀不讀、讀多少
由執行者自己判斷。以前 review-inbox 底下躺著它們逐字相同的第二份（453 行、6 個檔），而
review-inbox 的 frontmatter 早就宣告了 `requires: review-pr`——**相依已經成立，副本買不到
任何獨立性，只買到兩份會漂的東西**。

Prompt envelope 必須包含：

- `review-inbox/dispatch-context-bundle.md` inline bundle。
- Verified project handbook paths。
- Main-session 100 raw diff line hard cap 的提醒。
- Completion Envelope schema。
- 送出授權狀態。
- 延伸參考的路徑。

Cluster scheduling：

- `cluster_lead` 必須先於同 cluster siblings 完成，並在 Detail artifact 提供一句
  lead review summary。
- `cluster_sibling` 使用 sibling-diff mode：比較 sibling diff 與 lead PR diff，只 review
  行為差異、平台差異，以及 lead findings 是否適用。
- 若 `cluster_sibling` 發現行為不一致、風險升級、lead summary 缺失，或無法 confidence 判斷，
  result 用 `COMMENT` 並在 summary 標記 `needs_standard_review`，主流程再用
  `standard_coding` 重跑該 PR。

## 一張 PR 交給 sub-agent 看要花多少

**這一節是給判斷的人讀的事實，不是一道關卡。** 沒有任何東西會拿這幾個數字擋人。

| 什麼時候 | 幾張 | 每張大約 | 那個價錢買到了什麼 |
|---|---|---|---|
| 2026-05-01（觸發 DP-094 的那次） | 17 | 86K | 當時被判定成「太貴」 |
| 2026-05-05（DP-094 AC1，`main_session_sequential`） | 6 | 6.1K | 只看得到 diff |
| 2026-08-26 | 12 | 183K | 讀後端 PHP repo 對照欄位、本機 node 實跑 lodash 折疊、拿 stage 憑證打三發 request 推翻 PR 描述的歸因 |

2026-08-26 那一輪是 2026-05-01 那個「問題」的兩倍多，而它抓到的東西是 6.1K 那一版結構上
拿不到的——**那些正是「讀 diff 以外的檔案」**，而那正是把成本壓到 6.1K 時一併壓掉的能力。

所以要問的不是哪一種便宜，是**便宜買到了什麼、貴買到了什麼**。DP-094 當時的結論是那個
時空的答案，不是今天的根據。

## 什麼時候取那份 diff

<!-- REVIEW-INBOX-CONTRACT: fetch-at-review-time -->

**每張 PR 的 head 與完整 diff，都在那張 PR 的 review 開始的那一刻才取。批次計畫時不整批
預取。** 這一條約束的是主流程——決定「什麼時候去拿」的是它，不是執行 packet 的那一端。

規則本體不在這裡：**這一次 review 依據哪一顆 sha、diff 對誰取、送出時綁哪一顆**，寫在
`dispatch-context-bundle.md` 的 Reviewed Head 那一段，`build-review-prompt.sh` 把它原樣放進
每個 packet。這裡只回答一個它沒有回答的問題——**那一刻是什麼時候**。

2026-08-19 的 run `20260819-160509`（17 張 PR、約 52 分鐘）量到的形狀：16:10:15 一口氣把
17 顆 head 寫進一個檔、16:10:17 落下 `pr-2965.diff`，全部在計畫時；那張 PR 的作者之後又
push 了一版，而它排到 46 分鐘後才被 review。手上的 diff 已經舊了 22 分鐘，缺了整批 store
改動與一支 208 行的測試。**接到是因為執行的人自己多抓了一次，不是因為流程要求。**

對著舊 diff 寫出來的 review 沒有任何外觀特徵——它跟正常的 review 一模一樣，而它落在別人的
PR 上。一個 52 分鐘的批次裡有 7 張 PR 的 head 動過，命中率隨批次長度上升。

**擋這件事不需要新的機制**：不加腳本、不加關卡、不加 artifact 格式。晚一點才取那一份，手上就
只會有一顆 sha——沒有第二顆要跟它比對，所以也沒有要不要停下來問人的問題。

Token budget rules：

- 先執行 `gh pr diff <PR_URL> --name-only` 取得完整 changed-file list。
- 主 session raw diff output 以單 PR 累積 100 行為 hard cap。超過後該 PR 立即進入
  hunk-only / sample-only，直到該 PR review 完成前不得 reset；這不是單次工具呼叫額度，
  也不是整批共享額度。
- 完整 diff 取回來之後先落到 `/tmp/review-inbox-runs/{run_id}/pr-{number}.diff`，再用
  `inspect-pr-section.sh` 取 bounded section，不用 Read 工具回讀完整 diff。**這個「先」是
  「先落檔再讀片段」，不是「批次開始前先全部備好」**——什麼時候去取寫在〈什麼時候取那份
  diff〉那一節。
- Debug 也受同一條 raw evidence policy 約束。不得在 main session 執行
  `gh pr diff ... 2>&1` 或任何會把 full diff 直接印回 stdout/stderr 的命令；錯誤診斷必須把
  full output redirect 到 artifact，再只輸出 bounded summary。
- Sub-agent envelope 內用 DP-094 量過的 sampling：整體 diff 不超過 2000 行時可讀完整 diff；
  超過時每個檔案只讀 hunk headers、changed lines 與前後約 20 行 context。
- 單檔 diff 小於 200 行只適用於 sub-agent envelope。主 session 仍受
  100 行 per-PR raw output cap 約束。import/export、routing、API contract、schema、
  test expectation、security/auth、payment/booking 等 cross-file 風險才升級讀相關檔案全文。
- Existing inline comments 只抓 metadata 用於 dedup：`user`, `path`, `line`, `side`,
  `head = body[:80]`。不得把完整 comment body 放進 sub-agent context。

CI rollup rules：

- 預設只輸出 `FAILURE` / `ERROR` checks。
- PASS checks 不進 main context。
- 只有使用者明確需要診斷完整 CI 狀態時，才使用 `--show-all-checks` override。

Telemetry rules：

- Completion 後執行 `measure-review-inbox-session.sh`。
- Required metadata path：`metadata.review_inbox_run`。
- Required query：`polaris-learnings.sh query --type telemetry --tag review-inbox`。
- Required keys：`run_id`, `candidate_count`, `reviewed_count`,
  `main_session_input_tokens`, `main_session_output_tokens`, `sub_agent_tokens`,
  `duration_seconds`, `estimator_kind`。
- `runtime_plan_kind` 拿掉了：它記的是呼叫端自己傳進去的字串，10 筆歷史裡已經有一筆是假的
  （2026-08-24 記成 `constrained_code_reviewer`，而那個 agent 到 08-26 才存在）。規定怎麼派
  的那一層不在了，這個欄位跟著走。

## Result Envelope

每個 sub-agent 回傳：

| Field | Meaning |
|---|---|
| `pr_url`, `number`, `title`, `repo`, `author` | PR identity |
| `result` | `APPROVE`, `REQUEST_CHANGES`, or `COMMENT` |
| `must_fix`, `should_fix`, `nit` | finding counts |
| `approve_status` | threshold summary |
| `summary` | one-line result |
| `Detail` | temp artifact path with full comments |

Fan-in 後統計 result counts，並保留每個 PR 的 most important must-fix summary for Slack。

## Re-approve Boundaries

Re-approve 不等於略過 review。必須確認 last approve 後的新 diff。只有 CI/bot-only 或
non-substantive changes 時，才可 concise approve。

若作者尚未回覆上一輪 REQUEST_CHANGES comments，即使有新 push，也應維持
`waiting_for_author` 並 skip。
