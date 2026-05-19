# Skill Routing

## Core Rule: Skill Tool First

當使用者訊息符合某個 skill 的 trigger pattern 時，**必須立刻 invoke Skill tool**，
不得先做其他 tool call、research、或前置處理。

這是 Claude Code 平台層的硬限制：當 skill 符合使用者需求時，必須在產生任何其他任務相關回應前，
先 invoke 對應的 Skill tool。

### What This Means in Practice

- **Do not pre-process inputs**: if the user provides a Slack URL and says "review 這些 PR", invoke `Skill("review-pr", "<slack_url>")` immediately. The skill's own flow (e.g., Step 0) handles Slack URL parsing.
- **Do not read files first**: if the user says "估這張 PROJ-500", invoke the estimation skill immediately. The skill reads the JIRA ticket itself.
- skill match 已明確時，**不要先問澄清問題**。技能本身有自己的 disambiguation logic。

### Exception: Ambiguous Input

If the input could match multiple skills (e.g., "幫我處理這個 PR" could be engineering or review-pr), resolve ambiguity first by asking the user — but do this **before** any tool calls, not after reading the PR.

### Zero-input Triggers in Active Skill Session

當主對話處於 **active skill session**（最近的 tool call 歷史包含一次 Skill tool invocation，且該 skill 尚未產出終局輸出）時，zero-input triggers（「下一步」「繼續」「然後呢」「接下來」「what's next」「next」）**不自動 route 到 `my-triage`**，而由當前 skill 的 context 主導解釋。

例如：
- 在 `refinement DP-NNN` ticketless session 中使用者說「接下來呢」→ 指該 DP 討論的下一個議題，不跑 my-triage
- 在 `engineering` session 中使用者說「繼續」→ 指該 ticket 的下一步，不跑 my-triage
- 在 `breakdown` session 中使用者說「下一步」→ 指 breakdown 流程下一步，不跑 my-triage

Zero-input trigger 只有在「**無 active skill + 無明確 topic keyword**」時才 route 到 `my-triage`。Strategist 判斷當前是否在 skill session 的方式：檢查最近 tool calls 是否剛 invoke 過 Skill，且 skill 的流程尚未抵達終點（未產出 dashboard / PR URL / final summary）。

### Pre-Processing: Hotfix Without JIRA Ticket

當使用者訊息同時具備 fix intent（「修這個」、「幫我修」、「fix this」）與 Slack URL，但**沒有 JIRA ticket key** 時，Strategist 必須先建 ticket，再 route 到 `bug-triage`：

1. **Read Slack thread**：擷取問題描述、受影響版本/元件、回報者、以及若有提到的 source PR
2. **Resolve JIRA project key**：優先執行 `bash scripts/resolve-company-context.sh --format json`
   建立 company context。若 routing 仍有歧義，就直接詢問使用者，不要手工再寫第二套 config matching
3. **Create JIRA Bug ticket**：透過 `createJiraIssue` MCP：
   - `issueTypeName`: Bug
   - `summary`: from Slack thread problem description (concise, one line)
   - `description`: structured with Root Cause / Impact / Source (Slack link, source PR)
4. **Route to `bug-triage`** with the new ticket key

這是 **Strategist 層級的 pre-processing rule**，不是 skill。它會在 skill routing 前先觸發。
關鍵訊號是：fix intent + Slack URL + 使用者訊息內沒有 JIRA key pattern（`[A-Z]+-\d+`）。

> **為什麼不放進 `bug-triage`？**
> `bug-triage` skill 預期輸入是 ticket key。把建票留在 Strategist 層，能讓 `bug-triage`
> 專注在自己的核心工作（analyze → plan），並確保 skill 開始前 ticket 已經存在。

## Routing Quick Reference

| User Intent | Trigger Patterns | Skill |
|-------------|-----------------|-------|
| Review someone's PR | "review PR", "review 這個 PR", "幫我 review", PR URL + review | `review-pr` |
| Fix review comments on own PR | "fix review", "修 PR", "修正 review", "你沒修好" + PR URL, "沒修好", PR URL + 否定語氣, "CI 沒過", "CI failed" | `engineering` (revision mode — accepts ticket key or PR URL directly) |
| Pick up PR from Slack | "pr-pickup", "pickup", Slack URL + PR intent ("pickup <slack_url>", "處理 <slack_url>", "同仁貼的 <slack_url>", "接這個 PR <slack_url>") | `pr-pickup` |
| Check own PR approvals | "我的 PR", "PR 狀態", "催 review" | `check-pr-approvals` |
| Scan PRs needing review | "掃 PR", "大家的 PR", "review inbox" | `review-inbox` |
| Review PRs in Slack thread | Slack thread URL + review intent ("review <slack_url>", "幫我看這串", "這串 PR review 一下") | `review-inbox` (Thread mode) |
| Estimate a ticket | "估點", "estimate", "評估" + ticket | `breakdown` (Story/Task/Epic) or `bug-triage` (Bug) |
| Work on a ticket | "做", "work on", "engineering" + ticket | `engineering` (requires existing plan — if no plan, routes to planning skill first) |
| Verify Epic AC | "驗 {EPIC}", "verify {TICKET}", "verify AC", "跑驗收", "AC 驗證" | `verify-AC` |
| Triage/plan a bug | "修 bug", "fix bug", "分析 bug", "triage bug" + ticket | `bug-triage` |
| Triage a bug (no ticket) | "修這個", "fix this" + Slack URL, no JIRA key | Strategist pre-processing → create Bug ticket → `bug-triage` |
| SA/SD design doc | "SASD", "SA/SD", "寫 SA", "出 SA/SD", "架構文件", "design doc", "技術設計", "異動範圍", "dev scope" | `sasd-review` |
| Break down an epic | "拆單", "拆解", "epic breakdown" | `breakdown` |
| Batch converge all work | "收斂", "converge", "推進", "全部推到 review", "把我的單收一收" | `converge` |
| Epic progress / gap analysis | "epic 進度", "epic 狀態", "離 merge 還多遠", "還差什麼", "補全" | `converge` (Epic-only mode) |
| 完整 framework 開發流程 | "完整流程", "完整 workflow", "走完整開發流程", "建 DP", "建一個 DP", "DP -> PR -> 升版", "發 PR 然後升版", "快速通關 DP-NNN", "framework-release" + "建 DP" | 依 source-state matrix route：無 DP / 未 LOCK / artifact stale → `refinement`；LOCKED + current DP-backed source → `auto-pass`；`framework-release` 只作驗證後 terminal-only tail |
| Create/open a PR (framework/docs repo) | "開 PR", "create PR", "發 PR" | 若已有 DP-backed `task.md`，走 `engineering`；若沒有，fail-stop 並要求先跑 `refinement` / `breakdown` |
| Triage my work / zero-input next | "我的 epic", "my epics", "盤點", "triage", "手上有什麼", "my work", "我的工作", "排優先"；以及 zero-input 詞：「下一步」、「next」、「繼續」、「continue」、「然後呢」、「what's next」、「接下來」、「推進手上的事情」（後面無 topic keyword；「繼續 DP-015」這類帶 topic 的走 CLAUDE.md § Cross-Session Continuity） | `my-triage` |
| Batch intake from PM | "收單", "排工", "intake", "這批單幫我看", "PM 開了一堆單", "幫我排優先", "prioritize this batch" + 多張 ticket key | `intake-triage` |
| Daily standup / end-of-day | "standup", "站會", "daily", "寫 standup", "下班", "收工", "準備明天的工作", "end of day", "EOD", "明天 standup", "今天結束了", "總結一下", "結束今天", "wrap up", "今天做了什麼" | `standup` |
| Sprint planning | "sprint planning", "sprint 規劃" | `sprint-planning` |
| Refinement / ticketless design discussion | "refinement", "grooming", "討論需求", "想討論", "怎麼設計", "重構", "重新設計", "要怎麼改", "要怎麼重做", "design plan", "ADR", "design-plan DP-NNN", "/design-plan DP-NNN" | `refinement` |
| Create a skill | "建 skill", "create skill", "skill-creator" | `skill-creator` |
| Learn from external | "學習", "learning", "深入學", "deep dive", "像 gstack 那樣學", "全面研究", PR URL + 學到什麼 | `learning` |
| Validate (mechanisms + isolation) | "validate mechanisms", "validate isolation", "檢查機制", "檢查隔離" | `validate` |
| Save/resume session state | "checkpoint", "存檔", "save checkpoint", "resume", "恢復", "list checkpoints", "列出存檔" | `checkpoint` |
| Visual regression check | "跑 visual regression", "檢查畫面", "頁面有沒有壞", "visual test", "截圖比對", "有沒有跑版", "畫面壞了嗎", "UI 有沒有問題" | `visual-regression` |
| Log work time | "worklog", "記工時", "log time", "log hours" | `jira-worklog` |
| Backfill worklogs | "補工時", "backfill worklog", "工時回填" + date range | `jira-worklog` (batch mode) |
| Auto worklog (daily) | (auto-triggered by `/standup` post-step) | `jira-worklog` via `standup` |
| 補寫 Bug RCA | "補 RCA", "bug RCA", "補根因", "backfill RCA", "補 root cause", "幫我補 root cause" | `bug-rca` |

## Complexity Tier — Route by Task Size

在 invoke skill 之前，先判斷任務複雜度，再 route 到對應的 execution depth。
這能避免小任務承受完整 workflow 的 overhead，也避免大任務跳過必要規劃。

| Tier | Signal | Execution Depth | Example |
|------|--------|----------------|---------|
| **Fast** | ≤ 3 lines, 1 file, no architecture decision | Direct edit in main session, no skill needed | Fix a typo, update a config value, add an import |
| **Standard** | Single skill handles end-to-end | Invoke the matching skill normally | Estimate a ticket, review a PR, fix a bug |
| **Full** | > 3 files affected, or architectural decision required, or cross-module changes | Skill + plan-first sub-agent (explore → plan → implement → verify) | New feature spanning multiple components, large refactor |

### How to Assess

1. **Check file count**: if the change touches > 3 files → Full tier
2. **Check decision weight**: if it requires choosing between approaches (new component vs extend existing, new API vs modify existing) → Full tier
3. **Otherwise** → Standard (let the skill handle it)

Fast tier 原本隱含在 `CLAUDE.md` 的 delegation table（「Small edit ≤ 3 lines, 1 file → Do it directly」）裡；
這一節只是把完整光譜明文化。

## Semantic Code Change Flow Gate

當使用者修正、設計決策、或 agent judgment 會改到 code、rules、skills、scripts、hooks、
validators、delivery semantics，或任何會改變 framework 行為的文件時，一律視為
**semantic code change**：

1. **立刻把決策寫回** active DP plan / decision record。
2. **不要直接在 main session 補 patch 改行為。**
3. 應 resolve 或建立 DP-backed `task.md`，再把 implementation route 給 `engineering`，
   讓 worktree isolation、task scope、verification、PR、與 release metadata 全部生效。

純 mechanical 的修改可以維持 lightweight：例如 typo fix、純 formatting 變更、
generated parity outputs、或既有 task scope 內的 deterministic script output，都不需要新的
design decision。真正的判準不是大小，而是這個修改是否需要 semantic judgment；只要需要，
就必須走正式流程。

## Deprecated Admin Entrypoint Guard

舊的無 task.md Admin PR entrypoint 已 sunset。當使用者要求 framework/docs repo 直接「開 PR」或「發 PR」時，先確認是否能 resolve 到 DP-backed `task.md`：

1. **有 DP-backed task.md**：route to `engineering`，由 `engineering-branch-setup.sh` 建 task worktree 並走完整 delivery flow。
2. **沒有 task.md**：不要開 branch、不要 commit、不要建立 PR；回覆「framework/docs PR 需要先有 DP-backed work order，請先跑 `refinement DP-NNN` / `breakdown DP-NNN`」。
3. **產品 repo**：仍走一般 `engineering`；若沒有 JIRA / task.md，回上游補規劃，不使用 framework shortcut。

**判定依據**：當前 git repo root + `workspace-config.yaml` projects mapping + `scripts/resolve-task-md.sh` 結果。無法 resolve 單一 work order 時一律 fail-stop。

## Full Development Workflow Route Policy

當使用者要求「完整流程」、「完整 workflow」、「走完整開發流程」、「建 DP」、「建一個 DP」、
「DP -> PR -> 升版」、「發 PR 然後升版」、「快速通關 DP-NNN」，或同一句同時包含
`framework-release` 與「建 DP / 開發 / 發 PR」時，這不是單一 release intent，而是
full main-chain intent。routing rule 只負責把 intent 導入 canonical owning skill；不得以
prose-only rule 自行逐 stage dispatch 或成為第二條 writer path。

### Trigger × Source-State Matrix

| Trigger | Source state | Route |
|---------|--------------|-------|
| `建 DP` / `建一個 DP` | no DP source | `refinement` |
| `完整流程 DP-NNN` / `快速通關 DP-NNN` | `DISCUSSION` / missing artifact / stale artifact | `refinement DP-NNN` |
| `完整流程 DP-NNN` / `快速通關 DP-NNN` | `LOCKED` + current DP-backed source | `auto-pass DP-NNN` |
| `DP -> PR -> 升版 DP-NNN` | `LOCKED` + current DP-backed source | `auto-pass DP-NNN`；report tail 提示 `framework-release` |
| `framework-release DP-NNN` | workspace PR opened + verification current | `framework-release` |
| `framework-release DP-NNN` | workspace PR opened + verification stale | `auto-pass DP-NNN` refresh verify-AC，不重跑 breakdown |
| `framework-release` without PR / task | missing terminal precondition | fail-stop 回 `refinement` / `breakdown` / `engineering` |

`auto-pass` 是 locked/current DP-backed source 的 canonical main-chain orchestrator；它只
dispatch `breakdown -> engineering -> verify-AC`，每段 mutation 仍由 owning skill 產生。
`framework-release` 在這類語句中是 terminal-only tail，不得搶主流程入口，也不得補開 PR、
補 task.md、或追認 source-less branch。

## Framework Release Generic Publisher Hard-Stop

Polaris framework 的「走流程升版」、「framework release」、「修上一版升版 PR」、「開 framework
workspace PR」、「sync to Polaris」、「發版」等語意不是 generic GitHub publish intent。

遇到這類 intent 時：

1. 若尚未有 locked DP 與 DP-backed `task.md`，先 route 到
   `refinement -> breakdown`，不得使用 `github:yeet`、generic publisher、或 bare
   `gh pr create`。
2. 若已有 DP-backed `task.md`，route 到 `engineering`，由 task worktree、scope gate、
   verification gate 與 `polaris-pr-create.sh` 建立 workspace PR。
3. `framework-release` 只能在 engineering workspace PR ready / merged 並完成 verification 後作為
   local extension tail；同一句若包含「建 DP / 開發 / 發 PR」，必須先走 full workflow orchestration。
   它不負責 implementation、不補開 PR、不追認 source-less PR。
4. 已由 generic publisher 建出的 PR 不得靠補 PR body、改 title、補 VERSION / CHANGELOG
   追認為 canonical output；必須 close / supersede，或把需要的 diff 回到新的 DP-backed
   task 重新施工。

這條 guard 專門防止 `github:yeet` 或其他 GitHub plugin publisher 搶走 framework release
主鏈。GitHub 工具仍可用於 read-only 查 PR 狀態、CI、review comments；不得作為 Polaris
framework release PR 的 publish entrypoint。

## Plugin Workflow Quarantine

Canonical contract 在 `.claude/skills/references/plugin-workflow-quarantine.md`。
本 rule 只擁有 routing pointer；quarantine 語意以該 reference 為準。

## Negative-Tone Trigger Recognition

User messages with negative tone about a previous action (「沒修好」「壞了」「不對」「又出問題」) + a PR URL or ticket key are **fix intents**, not analysis requests. Route to the appropriate fix skill immediately:

- PR URL + negative tone → `engineering`（revision mode）
- Ticket key + negative tone（Bug）→ `bug-triage`（若尚無 plan）或 `engineering`（若已有 plan）
- Ticket key + negative tone（Story/Task）→ `engineering`
- 沒有 URL/key + negative tone → 先問清楚要修什麼，再 route

**不要**把負面語氣解讀成「先讓我研究一下哪裡出錯」，然後手動去看 diff/comment。
調查流程應由 skill 自己處理。

## Anti-Patterns

1. **Reading Slack/JIRA before invoking skill** — the skill handles data fetching
2. **Launching sub-agents before Skill invocation** — skill defines the delegation strategy
3. **Partially executing skill steps manually** — always let the Skill tool load the full SKILL.md
4. **因為「我已經知道怎麼做」就跳過 skill**：skills 內含 quality gates 與 side effects（例如 lesson extraction、Slack notifications），手工執行很容易漏掉
5. **不經 `engineering` revision mode 就手動修 PR review comments**：只要是 reviewer 或 bot 留下的 PR review comments，要修就一律走 `engineering`。手動 fix-and-push 會跳過 comment reply、quality checks、與 lesson extraction
6. **先調查再 routing**：當使用者說「沒修好」+ PR URL 時，不要先跑 `gh pr view`、`gh api`、`gh pr diff` 想「先看懂問題」。應立刻 invoke `engineering`，由 skill 自己去讀 review comments 與 CI state
