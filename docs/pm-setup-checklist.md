# PM Setup Checklist

English | [中文](./pm-setup-checklist.zh-TW.md)

> This checklist is for PMs and Scrum Masters who want to use Polaris. You don't need to run any terminal commands — ask a developer on your team to handle the setup.

## What you need (your part)

- [ ] A **Claude Pro, Team, or Enterprise** account — sign up at [claude.ai](https://claude.ai)
  - Most PM skills require the **Max plan** ($100/month) or API access
- [ ] Access to your team's **JIRA** and **Confluence** workspace
- [ ] Access to your team's **Slack** workspace
- [ ] (Optional) **Google Calendar** access — adds meeting context to standup reports

## What to ask your developer (their part)

Send this to a developer on your team:

> **Hi, can you set up Polaris for me? Here's what's needed:**
>
> 1. Clone the Polaris workspace and ask Polaris to "onboard our company"
> 2. Make sure these MCP connections are set up in Claude Code:
>    - **Atlassian MCP** (connects to our JIRA + Confluence)
>    - **Slack MCP** (for notifications and reports)
>    - **Google Calendar MCP** (optional, for standup meeting context)
> 3. Confirm the onboarding dashboard is `ready` or has only accepted `partial` follow-ups, then type `"standup"` and confirm it reads our JIRA data
>
> It should take about 10 minutes. Thanks!

## After setup: verify it works

Open Claude Code (your developer can show you how — it's in VS Code, the terminal, or the desktop app). Then try:

1. Type `"standup"` — you should see a standup report with JIRA activity
2. Type `"排 sprint"` — you should see your team's JIRA backlog

If either fails, check with your developer that the Atlassian MCP connection is active.

## Your daily commands

| When | Say this | What happens |
|------|----------|-------------|
| Before standup meeting | `"standup"` | Generates YDY/TDT/BOS report from JIRA + git + calendar |
| Sprint planning | `"sprint planning"` or `"排 sprint"` | Pulls backlog, calculates capacity, suggests priority |
| Refining an Epic | `"refinement EPIC-100"` | Reads the Epic, identifies gaps, drafts AC and scope |
| Breaking down an Epic | `"work on EPIC-100"` or `"做 EPIC-100"` | Splits into sub-tasks with story point estimates |
| End of sprint | `"worklog report 2w"` | Shows completed tickets grouped by assignee |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Skill doesn't respond or gives an error | Check that Atlassian MCP and Slack MCP are connected in Claude Code settings |
| "Sub-agents not available" | You need the Max plan ($100/mo) — most PM skills use sub-agents |
| Standup report is empty | Verify your JIRA project keys are configured (ask your developer to check `workspace-config.yaml`) |
| Can't find Claude Code | It's a separate app from claude.ai — ask your developer to install it for you |
