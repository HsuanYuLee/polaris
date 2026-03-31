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

## Routing Quick Reference

| User Intent | Trigger Patterns | Skill |
|-------------|-----------------|-------|
| Review someone's PR | "review PR", "review 這個 PR", "幫我 review", PR URL + review | `review-pr` |
| Fix review comments on own PR | "fix review", "修 PR", "修正 review" | `fix-pr-review` |
| Check own PR approvals | "我的 PR", "PR 狀態", "催 review" | `check-pr-approvals` |
| Scan PRs needing review | "掃 PR", "大家的 PR", "review inbox" | `review-inbox` |
| Estimate a ticket | "估點", "estimate", "評估" + ticket | `jira-estimation` |
| Work on a ticket | "做", "work on" + ticket | `work-on` |
| Fix a bug | "修 bug", "fix bug" + ticket | `fix-bug` |
| Break down an epic | "拆單", "拆解", "epic breakdown" | `epic-breakdown` |
| Create/open a PR | "開 PR", "create PR", "發 PR" | `git-pr-workflow` |
| Daily standup | "standup", "站會", "daily" | `standup` |
| Sprint planning | "sprint planning", "sprint 規劃" | `sprint-planning` |
| Refinement | "refinement", "grooming", "討論需求" | `refinement` |
| Create a skill | "建 skill", "create skill", "skill-creator" | `skill-creator` |
| Learn from external | "學習", "learning", PR URL + 學到什麼 | `learning` |
| Validate mechanisms | "validate mechanisms", "檢查機制" | `validate-mechanisms` |
| Validate isolation | "validate isolation", "檢查隔離" | `validate-isolation` |

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
