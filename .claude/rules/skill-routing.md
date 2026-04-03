# Skill Routing

## Core Rule: Skill Tool First

When the user's message matches a skill's trigger pattern, **invoke the Skill tool immediately** — before any other tool call, research, or pre-processing.

This is a hard constraint from the Claude Code platform: "When a skill matches the user's request, this is a BLOCKING REQUIREMENT: invoke the relevant Skill tool BEFORE generating any other response about the task."

### What This Means in Practice

- **Do not pre-process inputs**: if the user provides a Slack URL and says "review 這些 PR", invoke `Skill("review-pr", "<slack_url>")` immediately. The skill's own flow (e.g., Step 0) handles Slack URL parsing.
- **Do not read files first**: if the user says "估這張 PROJ-500", invoke the estimation skill immediately. The skill reads the JIRA ticket itself.
- **Do not ask clarifying questions** when a skill match is clear. Skills have their own disambiguation logic.

### Exception: Ambiguous Input

If the input could match multiple skills (e.g., "幫我處理這個 PR" could be fix-pr-review or review-pr), resolve ambiguity first by asking the user — but do this **before** any tool calls, not after reading the PR.

### Pre-Processing: Hotfix Without JIRA Ticket

When the user's message has fix intent (「修這個」、「幫我修」、「fix this」) + a Slack URL but **no JIRA ticket key**, the Strategist must create a ticket before routing to `fix-bug`:

1. **Read Slack thread** — extract problem description, affected version/component, reporter, source PR if mentioned
2. **Resolve JIRA project key** — read `workspace-config.yaml` → `jira.projects`. If only one project → use it. If multiple → infer from context (e.g., repo name, component mentioned in Slack), or ask the user
3. **Create JIRA Bug ticket** — via `createJiraIssue` MCP:
   - `issueTypeName`: Bug
   - `summary`: from Slack thread problem description (concise, one line)
   - `description`: structured with Root Cause / Impact / Source (Slack link, source PR)
4. **Route to `fix-bug`** with the new ticket key

This is a **Strategist-level pre-processing rule**, not a skill. It fires before skill routing. The key signal is: fix intent + Slack URL + absence of a JIRA key pattern (`[A-Z]+-\d+`) in the user's message.

> **Why not inside `fix-bug`?** The `fix-bug` skill expects a ticket key as input. Creating the ticket at the Strategist layer keeps `fix-bug` focused on its core job (analyze → fix → PR) and ensures the ticket exists before any skill step begins. It also means the branch name includes the ticket key from the start.

## Routing Quick Reference

| User Intent | Trigger Patterns | Skill |
|-------------|-----------------|-------|
| Review someone's PR | "review PR", "review 這個 PR", "幫我 review", PR URL + review | `review-pr` |
| Fix review comments on own PR | "fix review", "修 PR", "修正 review" | `fix-pr-review` |
| Check own PR approvals | "我的 PR", "PR 狀態", "催 review" | `check-pr-approvals` |
| Scan PRs needing review | "掃 PR", "大家的 PR", "review inbox" | `review-inbox` |
| Estimate a ticket | "估點", "estimate", "評估" + ticket | `jira-estimation` |
| Auto-determine next action | "下一步", "next", "繼續", "continue", "然後呢", "接下來" (no ticket key) | `next` |
| Work on a ticket | "做", "work on" + ticket | `work-on` |
| Fix a bug | "修 bug", "fix bug" + ticket | `fix-bug` |
| Fix a bug (no ticket) | "修這個", "fix this" + Slack URL, no JIRA key | Strategist pre-processing → create Bug ticket → `fix-bug` |
| Break down an epic | "拆單", "拆解", "epic breakdown" | `epic-breakdown` |
| Batch converge all work | "收斂", "converge", "推進", "全部推到 review", "把我的單收一收" | `converge` |
| Epic progress / gap analysis | "epic 進度", "epic 狀態", "離 merge 還多遠", "還差什麼", "補全" | `converge` (Epic-only mode) |
| Create/open a PR | "開 PR", "create PR", "發 PR" | `git-pr-workflow` |
| Triage my work | "我的 epic", "my epics", "盤點", "triage", "手上有什麼", "my work", "我的工作" | `my-triage` |
| Batch intake from PM | "收單", "排工", "intake", "這批單幫我看", "PM 開了一堆單", "幫我排優先", "prioritize this batch" + 多張 ticket key | `intake-triage` |
| Daily standup / end-of-day | "standup", "站會", "daily", "寫 standup", "下班", "收工", "準備明天的工作", "end of day", "EOD", "明天 standup", "今天結束了", "總結一下", "結束今天", "wrap up", "今天做了什麼" | `standup` |
| Sprint planning | "sprint planning", "sprint 規劃" | `sprint-planning` |
| Refinement | "refinement", "grooming", "討論需求" | `refinement` |
| Create a skill | "建 skill", "create skill", "skill-creator" | `skill-creator` |
| Learn from external | "學習", "learning", "深入學", "deep dive", "像 gstack 那樣學", "全面研究", PR URL + 學到什麼 | `learning` |
| Validate mechanisms | "validate mechanisms", "檢查機制" | `validate-mechanisms` |
| Validate isolation | "validate isolation", "檢查隔離" | `validate-isolation` |
| Save/resume session state | "checkpoint", "存檔", "save checkpoint", "resume", "恢復", "list checkpoints", "列出存檔" | `checkpoint` |

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

## Anti-Patterns

1. **Reading Slack/JIRA before invoking skill** — the skill handles data fetching
2. **Launching sub-agents before Skill invocation** — skill defines the delegation strategy
3. **Partially executing skill steps manually** — always let the Skill tool load the full SKILL.md
4. **Skipping skill because "I already know how"** — skills encode quality gates and side effects (lesson extraction, Slack notifications) that manual execution misses
5. **Manually fixing PR review comments without `fix-pr-review` skill** — when PR review comments (from human reviewers or bots) need fixing, always use `fix-pr-review`. Manual fix-and-push skips comment replies, quality checks, and lesson extraction, causing review patterns to never enter the learning pipeline
