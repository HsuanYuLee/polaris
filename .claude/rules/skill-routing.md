# Skill Routing

## Core Rule: Skill Tool First

When the user's message matches a skill's trigger pattern, **invoke the Skill tool immediately** — before any other tool call, research, or pre-processing.

This is a hard constraint from the Claude Code platform: "When a skill matches the user's request, this is a BLOCKING REQUIREMENT: invoke the relevant Skill tool BEFORE generating any other response about the task."

### What This Means in Practice

- **Do not pre-process inputs**: if the user provides a Slack URL and says "review 這些 PR", invoke `Skill("review-pr", "<slack_url>")` immediately. The skill's own flow (e.g., Step 0) handles Slack URL parsing.
- **Do not read files first**: if the user says "估這張 PROJ-500", invoke the estimation skill immediately. The skill reads the JIRA ticket itself.
- **Do not ask clarifying questions** when a skill match is clear. Skills have their own disambiguation logic.

### Exception: Ambiguous Input

If the input could match multiple skills (e.g., "幫我處理這個 PR" could be engineering or review-pr), resolve ambiguity first by asking the user — but do this **before** any tool calls, not after reading the PR.

### Zero-input Triggers in Active Skill Session

當主對話處於 **active skill session**（最近的 tool call 歷史包含一次 Skill tool invocation，且該 skill 尚未產出終局輸出）時，zero-input triggers（「下一步」「繼續」「然後呢」「接下來」「what's next」「next」）**不自動 route 到 `my-triage`**，而由當前 skill 的 context 主導解釋。

例如：
- 在 `design-plan` session 中使用者說「接下來呢」→ 指 design plan 的下一個議題，不跑 my-triage
- 在 `engineering` session 中使用者說「繼續」→ 指該 ticket 的下一步，不跑 my-triage
- 在 `breakdown` session 中使用者說「下一步」→ 指 breakdown 流程下一步，不跑 my-triage

Zero-input trigger 只有在「**無 active skill + 無明確 topic keyword**」時才 route 到 `my-triage`。Strategist 判斷當前是否在 skill session 的方式：檢查最近 tool calls 是否剛 invoke 過 Skill，且 skill 的流程尚未抵達終點（未產出 dashboard / PR URL / final summary）。

### Pre-Processing: Hotfix Without JIRA Ticket

When the user's message has fix intent (「修這個」、「幫我修」、「fix this」) + a Slack URL but **no JIRA ticket key**, the Strategist must create a ticket before routing to `bug-triage`:

1. **Read Slack thread** — extract problem description, affected version/component, reporter, source PR if mentioned
2. **Resolve JIRA project key** — read `workspace-config.yaml` → `jira.projects`. If only one project → use it. If multiple → infer from context (e.g., repo name, component mentioned in Slack), or ask the user
3. **Create JIRA Bug ticket** — via `createJiraIssue` MCP:
   - `issueTypeName`: Bug
   - `summary`: from Slack thread problem description (concise, one line)
   - `description`: structured with Root Cause / Impact / Source (Slack link, source PR)
4. **Route to `bug-triage`** with the new ticket key

This is a **Strategist-level pre-processing rule**, not a skill. It fires before skill routing. The key signal is: fix intent + Slack URL + absence of a JIRA key pattern (`[A-Z]+-\d+`) in the user's message.

> **Why not inside `bug-triage`?** The `bug-triage` skill expects a ticket key as input. Creating the ticket at the Strategist layer keeps `bug-triage` focused on its core job (analyze → plan) and ensures the ticket exists before any skill step begins.

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
| Work on a ticket | "做", "work on", "engineering" + ticket | `engineering` (formerly work-on, requires existing plan — if no plan, routes to planning skill first) |
| Verify Epic AC | "驗 {EPIC}", "verify {TICKET}", "verify AC", "跑驗收", "AC 驗證" | `verify-AC` |
| Triage/plan a bug | "修 bug", "fix bug", "分析 bug", "triage bug" + ticket | `bug-triage` |
| Triage a bug (no ticket) | "修這個", "fix this" + Slack URL, no JIRA key | Strategist pre-processing → create Bug ticket → `bug-triage` |
| SA/SD design doc | "SASD", "SA/SD", "寫 SA", "出 SA/SD", "架構文件", "design doc", "技術設計", "異動範圍", "dev scope" | `sasd-review` |
| Break down an epic | "拆單", "拆解", "epic breakdown" | `breakdown` |
| Batch converge all work | "收斂", "converge", "推進", "全部推到 review", "把我的單收一收" | `converge` |
| Epic progress / gap analysis | "epic 進度", "epic 狀態", "離 merge 還多遠", "還差什麼", "補全" | `converge` (Epic-only mode) |
| Create/open a PR (framework/docs repo) | "開 PR", "create PR", "發 PR" | `git-pr-workflow`（Admin — 產品 repo 引導走 `engineering`） |
| Triage my work / zero-input next | "我的 epic", "my epics", "盤點", "triage", "手上有什麼", "my work", "我的工作", "排優先"；以及 zero-input 詞：「下一步」、「next」、「繼續」、「continue」、「然後呢」、「what's next」、「接下來」、「推進手上的事情」（後面無 topic keyword；「繼續 DP-015」這類帶 topic 的走 CLAUDE.md § Cross-Session Continuity） | `my-triage` |
| Batch intake from PM | "收單", "排工", "intake", "這批單幫我看", "PM 開了一堆單", "幫我排優先", "prioritize this batch" + 多張 ticket key | `intake-triage` |
| Daily standup / end-of-day | "standup", "站會", "daily", "寫 standup", "下班", "收工", "準備明天的工作", "end of day", "EOD", "明天 standup", "今天結束了", "總結一下", "結束今天", "wrap up", "今天做了什麼" | `standup` |
| Sprint planning | "sprint planning", "sprint 規劃" | `sprint-planning` |
| Refinement | "refinement", "grooming", "討論需求" | `refinement` |
| Non-ticket design discussion | "想討論", "怎麼設計", "重構", "重新設計", "要怎麼改", "要怎麼重做", "design plan", "ADR" | `design-plan` |
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

Before invoking a skill, assess the task's complexity and route to the appropriate execution depth. This prevents small tasks from incurring full-workflow overhead, and large tasks from skipping necessary planning.

| Tier | Signal | Execution Depth | Example |
|------|--------|----------------|---------|
| **Fast** | ≤ 3 lines, 1 file, no architecture decision | Direct edit in main session, no skill needed | Fix a typo, update a config value, add an import |
| **Standard** | Single skill handles end-to-end | Invoke the matching skill normally | Estimate a ticket, review a PR, fix a bug |
| **Full** | > 3 files affected, or architectural decision required, or cross-module changes | Skill + plan-first sub-agent (explore → plan → implement → verify) | New feature spanning multiple components, large refactor |

### How to Assess

1. **Check file count**: if the change touches > 3 files → Full tier
2. **Check decision weight**: if it requires choosing between approaches (new component vs extend existing, new API vs modify existing) → Full tier
3. **Otherwise** → Standard (let the skill handle it)

The Fast tier is implicit in CLAUDE.md's delegation table ("Small edit ≤ 3 lines, 1 file → Do it directly"). This section makes the full spectrum explicit.

## Admin-Only Skill Guard

Skills with `admin_only: true` in their frontmatter (e.g., `git-pr-workflow`) are restricted to framework/docs repos. When the user triggers an admin-only skill in a **product repo** (identified by `workspace-config.yaml` → `projects[]` mapping):

1. **Do not invoke** the admin-only skill
2. **Redirect**: "這是產品 repo，發 PR 請走 `engineering`（會包含完整品質檢查和驗證流程）。"
3. If the user has no JIRA ticket, suggest: "沒有 ticket？先建一張，或用 `engineering` 的 bypass mode。"

**判定依據**：當前 git repo root。若 repo 出現在 `workspace-config.yaml` 的 `projects[]`（有 `base_dir`、`repo` 欄位）→ 產品 repo。否則（如 `~/work/` 本身）→ 框架 repo，允許 admin skill。

## Negative-Tone Trigger Recognition

User messages with negative tone about a previous action (「沒修好」「壞了」「不對」「又出問題」) + a PR URL or ticket key are **fix intents**, not analysis requests. Route to the appropriate fix skill immediately:

- PR URL + negative tone → `engineering` (revision mode)
- Ticket key + negative tone (Bug) → `bug-triage` (if no plan) or `engineering` (if plan exists)
- Ticket key + negative tone (Story/Task) → `engineering`
- No URL/key + negative tone → ask what to fix, then route

**Do not** interpret negative tone as "let me investigate what went wrong" and start reading diffs/comments manually. The skill's own flow handles investigation.

## Anti-Patterns

1. **Reading Slack/JIRA before invoking skill** — the skill handles data fetching
2. **Launching sub-agents before Skill invocation** — skill defines the delegation strategy
3. **Partially executing skill steps manually** — always let the Skill tool load the full SKILL.md
4. **Skipping skill because "I already know how"** — skills encode quality gates and side effects (lesson extraction, Slack notifications) that manual execution misses
5. **Manually fixing PR review comments without `engineering` revision mode** — when PR review comments (from human reviewers or bots) need fixing, always use `engineering` (which enters revision mode automatically when a PR exists). Manual fix-and-push skips comment replies, quality checks, and lesson extraction, causing review patterns to never enter the learning pipeline
6. **Investigating before routing** — when the user says "沒修好" + PR URL, do NOT run `gh pr view`, `gh api`, or `gh pr diff` to "understand the problem first". Invoke `engineering` immediately. The skill reads review comments and CI status itself. (Graduated from prior session analysis: 2 sessions, 4+ occurrences)
