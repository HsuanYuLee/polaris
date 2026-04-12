---
name: jira-worklog
description: >
  Logs work time to JIRA using daily quota allocation — each workday modeled as
  8h = meetings + 1h lunch + ticket work. Queries calendar for meeting hours,
  splits remaining dev time across In Development tickets.
  Primary mode: monthly batch (last workdays of month).
  Trigger keywords: "worklog", "log time", "記工時", "補工時", "backfill worklog", "工時回填",
  "worklog report", "done report", "sprint report", "完成報告".
metadata:
  author: Polaris
  version: 3.0.0
---

# JIRA Worklog — Daily Quota Allocation

Each workday from the company's perspective:

```
8h = meetings + 1h lunch + ticket work
```

This skill fills the "ticket work" portion with JIRA worklogs, split evenly across In Development tickets. Designed for monthly compliance — run once near month-end to fill the entire month.

## Prerequisite: Read workspace config

Read workspace config (see `references/workspace-config-reader.md`).
Required values: `jira.instance`, `jira.projects[].key`.
If config doesn't exist, use `references/shared-defaults.md` fallback values.

## Trigger Cadence

| When | How |
|------|-----|
| **Month-end** | User runs `/jira-worklog` or says "補工時 4月". Primary usage |
| **Standup reminder** | Handbook rule: last 5 workdays of month, standup reminds if no worklogs found |
| **On-demand** | User requests a specific date or range anytime |

## Step 0: Determine target dates

| Input | Target dates |
|-------|-------------|
| "補工時 4月" | 2026-04-01 ~ 2026-04-30 |
| "log time for last week" | Mon~Fri of last week |
| Specific date | That date only |

Generate the list of **weekdays (Mon-Fri)** in the range. Weekends are always skipped — status inertia (ticket staying In Dev over weekend) is not evidence of work.

No holiday detection needed. If a weekday has no In Dev tickets, it's naturally skipped in Step 3.

## Step 1: Query meetings

For each target date, query Google Calendar to get meeting hours:

```
mcp__claude_ai_Google_Calendar__gcal_list_events
  timeMin: {date}T00:00:00
  timeMax: {date}T23:59:59
  timeZone: Asia/Taipei
```

Calculate meeting hours per date:
- Sum duration of all non-all-day events
- Exclude events the user declined (if status available)
- Round to nearest 30 minutes

**Batch optimization**: for a full month, query the entire range once, then group events by date.

## Step 2: Query In Development tickets

For the date range, get all tickets that were In Development during the period:

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: assignee = currentUser() AND status WAS "In Development" DURING ("{start_date}", "{end_date}") AND project in ({jira_project_keys})
  fields: ["summary", "status"]
  maxResults: 50
```

Then for each ticket, fetch changelog to extract exact In Development periods:

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: {ticket_key}
  expand: "changelog"
  fields: ["summary"]
```

From the changelog, extract all In Development windows:
- Entry: status changed TO "In Development" → start date
- Exit: status changed FROM "In Development" → end date
- Still In Development (no exit) → end date = today

Build a map: `{ date → [ticket_keys] }`

### Filtering (keep it simple)

Only 2 rules:

1. **Exclude verification tickets**: tickets with `[驗證]` or `[驗收]` in summary → skip
2. **Epic/sub-task dedup**: when an Epic (GT-xxx) and its TASK sub-tasks are both In Dev on the same day → keep only TASK sub-tasks. If no sub-tasks active that day → keep the Epic

## Step 3: Dedup — check existing worklogs

Before writing, check for existing worklogs to avoid double-logging.

For each ticket that needs a worklog:

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: {ticket_key}
  fields: ["worklog"]
```

Check `worklog.worklogs[]` for entries where:
- `author.accountId` matches the current user
- `started` date matches the target date

If a worklog exists for that user + date + ticket → **skip**.

**Batch optimization**: fetch worklogs once per ticket (not per date). Parse all existing worklog dates from the response, then skip matching dates in bulk.

## Step 4: Allocate and write

For each workday:

```
meeting_hours = [from Step 1, rounded to 30m]
dev_hours = 8h - 1h (lunch) - meeting_hours
tickets = [from Step 2, after filtering and dedup]

if dev_hours <= 0 → mark as "gap day" (Phase 2 handles)
if len(tickets) == 0 → mark as "gap day" (Phase 2 handles)

hours_per_ticket = dev_hours / len(tickets)
→ round to nearest 30m, minimum 1h per entry
```

**Remainder distribution**: when `dev_hours` doesn't divide evenly, distribute remainder to earlier entries in 30m increments. Example: 5h / 3 entries = 2h, 1.5h, 1.5h.

**Verify**: each day's total must equal `dev_hours` before writing.

Write worklogs:

```
mcp__claude_ai_Atlassian__addWorklogToJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: {ticket_key}
  timeSpent: "{hours}"
  started: "{date}T09:00:00.000+0800"
  commentBody: "{ticket_summary}"
  contentFormat: "markdown"
```

**Batch mode (> 10 worklogs)**: use JIRA REST API directly with curl for speed. Credentials from `{company}/.env.secrets` (`JIRA_EMAIL` + `JIRA_API_TOKEN`).

```bash
curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -d '{"timeSpent":"2h","started":"2026-04-01T09:00:00.000+0800","comment":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"ticket summary"}]}]}}' \
  "https://{jira_instance}/rest/api/3/issue/{ticket_key}/worklog"
```

Rate limit: ~5 requests/sec (sleep 1s every 5 requests). Write a batch script to `/tmp/` for execution.

## Step 5: Monthly reconciliation (Phase 2)

After Phase 1, scan for **gap days** — workdays with 0h logged:

| Gap reason | Fix |
|------------|-----|
| Full meeting day (dev_hours ≤ 0) | Borrow ticket list from nearest workday with tickets, fill 1h (meeting prep/followup) |
| No In Dev tickets (sprint boundary, planning day) | Same — borrow nearest ticket list, fill 1h |

**Reconciliation check**:

```
expected_hours = workdays_in_month × 7h
actual_hours = sum(all worklogs written)
diff = expected - actual

if diff > 3h → warn user, present gap days for manual decision
if diff <= 3h → auto-distribute remainder across highest-ticket-count days (+30m each)
if diff <= 0 → done, no adjustment needed
```

## Step 6: Report

Present a summary table:

```markdown
## Worklog Summary — 2026-04

| Date | Meetings | Dev Hours | Tickets | Hours/Ticket | Status |
|------|----------|-----------|---------|--------------|--------|
| 04-01 | 2h | 5h | TASK-123, TASK-123 | 2.5h | logged |
| 04-02 | 4h | 3h | TASK-123 | 3h | logged |
| 04-03 | 7h | 0h | (borrowed TASK-123) | 1h | gap-filled |
| ... | | | | | |

### Monthly Summary
- Working days: 22
- Expected: 154h (22 × 7h)
- Logged: 153.5h
- Gap: -0.5h (within tolerance)
- Gap days filled: 2
```

## Logging Hierarchy

Worklogs are logged at the **sub-task level** (TASK-xxxx), not the Epic level. JIRA automatically rolls up sub-task time spent to the parent.

If a ticket has no sub-tasks (standalone Task or Bug), log directly on that ticket.

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
