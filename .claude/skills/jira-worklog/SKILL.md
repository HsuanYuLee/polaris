---
name: jira-worklog
description: >
  Logs work time to JIRA using daily quota allocation — 8h per workday split among
  tickets that were In Development that day. Two modes: (1) auto-log triggered by
  standup or other skills after ticket completion, (2) batch backfill for a date range.
  Trigger keywords: "worklog", "log time", "記工時", "記錄工時", "log hours",
  "補工時", "backfill worklog", "工時回填".
metadata:
  author: Polaris
  version: 2.0.0
---

# JIRA Worklog — Daily Quota Allocation

Logs work hours to JIRA based on a simple principle: each workday has 8h, split evenly among tickets that were "In Development" that day. This reflects the real time allocation rather than artificial per-ticket estimates.

The approach is designed for compliance reporting — producing reasonable daily records tied to actual tickets worked on.

## Prerequisite: Read workspace config

Read workspace config (see `references/workspace-config-reader.md`).
Required values: `jira.instance`, `jira.projects[].key`.
If config doesn't exist, use `references/shared-defaults.md` fallback values.

## Modes

| Mode | Trigger | What it does |
|------|---------|-------------|
| **Single-day** | `/standup` post-step, or skill delegation | Log worklog for today (or a specified date) |
| **Batch backfill** | User says "補工時 3月" or "backfill March" | Log worklog for a date range |

## Workflow

### Step 0: Determine target dates

| Mode | Target dates |
|------|-------------|
| Single-day | Today (or user-specified date) |
| Batch backfill | User-specified range (e.g., 2026-03-01 ~ 2026-04-08) |

For batch mode, generate the list of **eligible dates** in the range. This includes all weekdays (Mon-Fri) and any weekend day that has tickets In Development — weekend work still counts as work time and must be logged.

**Holiday detection**: query Google Calendar for all-day events in the date range. Taiwan national holidays appear as all-day events in the "台灣的節日" (Holidays in Taiwan) calendar. Weekday national holidays are excluded from the eligible list — no worklog is generated. However, if a holiday has tickets In Development (someone chose to work), log it anyway.

```
mcp__claude_ai_Google_Calendar__gcal_list_events
  timeMin: {start_date}T00:00:00
  timeMax: {end_date}T23:59:59
  timeZone: Asia/Taipei
```

Filter: events where `allDay: true` AND the event title matches known holiday patterns (e.g., contains "紀念日", "節", "假", or comes from a holidays calendar). Collect these dates as `holiday_dates`.

Eligible dates = (all Mon-Fri − `holiday_dates`) ∪ (any Sat/Sun/holiday with tickets In Dev).

> **Makeup workdays (補班)**: Taiwan occasionally has Saturday makeup workdays. These appear as regular workdays on the government calendar. If a Saturday has tickets In Development AND is not in `holiday_dates`, it will be included automatically. However, Google Calendar doesn't reliably flag makeup workdays — if the user mentions a specific makeup workday, include it manually.

### Step 1: Query In Development periods

For each target date, find which tickets were "In Development" on that day. Two approaches depending on mode:

**Single-day mode** — query current state:

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: assignee = currentUser() AND status WAS "In Development" ON "{date}" AND project in ({jira_project_keys})
  # storyPointsFieldId：依 references/jira-story-points.md Step 0 探測
  fields: ["summary", "status", "<storyPointsFieldId>"]
  maxResults: 20
```

> **JQL `status WAS ... ON` limitation**: some JIRA instances don't support `WAS ... ON` syntax. If the query fails, fall back to the changelog approach below.

**Batch mode / fallback** — use changelog:

For the date range, first get all tickets that were ever In Development during the period:

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: assignee = currentUser() AND status CHANGED TO "In Development" DURING ("{start_date}", "{end_date}") AND project in ({jira_project_keys})
  # storyPointsFieldId：依 references/jira-story-points.md Step 0 探測
  fields: ["summary", "status", "<storyPointsFieldId>"]
  maxResults: 50
```

Then for each ticket, fetch changelog to extract exact In Development periods:

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: {ticket_key}
  expand: "changelog"
  # storyPointsFieldId：依 references/jira-story-points.md Step 0 探測
  fields: ["summary", "<storyPointsFieldId>"]
```

From the changelog, extract all In Development windows:
- Entry: status changed TO "In Development" → record start date
- Exit: status changed FROM "In Development" → record end date
- If still In Development (no exit) → end date = today

Build a map: `{ date → [ticket_keys] }` showing which tickets were In Dev on each workday.

### Step 1a: Smart filtering (batch mode)

Raw In Dev queries often return 50+ tickets per day (verification sub-tasks, parked tickets). Apply these filters before allocation:

**1. Exclude verification tickets**: tickets with `[驗證]` or `[驗收]` in summary are batch checks, not sustained development. Skip them.

**2. Epic aggregation**: when an Epic (GT-xxx) and its KB2CW sub-tasks are both In Dev on the same day, keep only the KB2CW sub-tasks. If no sub-tasks are active that day, keep the Epic.

**3. GT/KB2CW dedup**: GT tickets marked 已關閉 that have KB2CW equivalents (same summary) are duplicates — skip the GT version.

**4. Daily entry cap**: maximum 7 entries per day (each gets at least 1h). If more than 7 tickets remain after filtering:
   - Pick one representative sub-task per active Epic (highest SP or most recently transitioned)
   - Standalone tickets (no parent Epic) get their own slot
   - If still > 7, prioritize by JIRA priority or recency

**5. Weekend handling**: skip weekends by default — tickets being In Dev over the weekend is status inertia, not evidence of work. Only include a weekend day if there are git commits or JIRA status transitions on that specific day.

After filtering, the typical result is 3-7 entries per day, each receiving 1-2.5h.

### Step 2: Check for existing worklogs (dedup)

Before writing, check if the user already has worklogs on the target dates to avoid double-logging.

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

If a worklog already exists for that user + date + ticket → **skip** (don't double-log).

> **Batch optimization**: in batch mode, fetch worklogs once per ticket (not per date). Parse all existing worklog dates from the response, then skip matching dates in bulk.

### Step 2a: Query meetings for the target date(s)

To calculate accurate available hours, subtract meeting time and lunch break from the workday.

**Single-day mode** (called from standup): standup Step 4 already fetched today's calendar events. Reuse that data — do not query again.

**Batch mode**: for each target date, query Google Calendar:

```
mcp__claude_ai_Google_Calendar__gcal_list_events
  timeMin: {date}T00:00:00
  timeMax: {date}T23:59:59
  timeZone: Asia/Taipei
```

Calculate meeting hours for each date:
- Sum the duration of all non-all-day events
- Exclude events the user declined (if status available)
- Round to nearest 30 minutes

### Step 3: Calculate daily allocation

For each workday in the target range:

```
gross_hours = 8h
lunch_break = 1h
meeting_hours = [from Step 2a, rounded to nearest 30m]
available_hours = gross_hours - lunch_break - meeting_hours

filtered_tickets = [list from Step 1a]  # after smart filtering
already_logged_today = [list from Step 2]
tickets_to_log = filtered_tickets - already_logged_today

if len(tickets_to_log) == 0:
    skip this day (already fully logged)
elif available_hours <= 0:
    skip this day (full meeting day — no dev time to allocate)
else:
    hours_per_ticket = available_hours / len(tickets_to_log)
```

**Available hours floor**: minimum 0h (a day with 7+ hours of meetings = no dev time to log). This is intentional — full meeting days shouldn't produce artificial worklog entries.

Round `hours_per_ticket` to the nearest 30 minutes. Minimum 1h per entry (the daily entry cap in Step 1a ensures this is achievable). Format as JIRA time string (e.g., "4h", "2h 30m").

**Remainder distribution**: when `available_hours` doesn't divide evenly, distribute the remainder to earlier entries in 30m increments. Example: 7h / 3 entries = 2h, 2.5h, 2.5h.

**Target**: every weekday should total exactly `available_hours` (typically 7h). Verify the sum before writing.

### Step 4: Write worklogs

For each (date, ticket, hours) tuple:

```
mcp__claude_ai_Atlassian__addWorklogToJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: {ticket_key}
  timeSpent: "{hours}"
  started: "{date}T09:00:00.000+0800"
  commentBody: "{ticket_summary}"
  contentFormat: "markdown"
```

**Batch mode — use JIRA REST API directly**: for batch operations (> 10 worklogs), use curl with credentials from `{company}/.env.secrets` (`JIRA_EMAIL` + `JIRA_API_TOKEN`) instead of MCP tools. This is significantly faster and allows parallelization.

```bash
# Add worklog
curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -d '{"timeSpent":"1h","started":"2026-03-24T09:00:00.000+0800","comment":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"ticket summary"}]}]}}' \
  "https://{jira_instance}/rest/api/3/issue/{ticket_key}/worklog"

# Delete worklog
curl -s -X DELETE \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://{jira_instance}/rest/api/3/issue/{ticket_key}/worklog/{worklog_id}"
```

Rate limit: ~5 requests/sec (sleep 1s every 5 requests). Write a batch script to `/tmp/` for execution.

### Step 5: Report

Present a summary table:

```markdown
## Worklog Summary

| Date | Ticket | Hours | Status |
|------|--------|------:|:------:|
| 03-24 | KB2CW-3486 | 4h | logged |
| 03-24 | KB2CW-3487 | 4h | logged |
| 03-25 | (no tickets in dev) | — | skipped |
| 03-26 | KB2CW-3488 | 8h | logged |
| ... | ... | ... | ... |

**Total**: Xh logged across Y days, Z tickets
**Skipped**: N days (no tickets in dev / already logged)
```

For batch mode, also show a weekly summary:

```markdown
### Weekly Breakdown
| Week | Days Logged | Total Hours | Avg Hours/Day |
|------|------------|-------------|---------------|
| W13 (03-24~03-28) | 4 | 32h | 8h |
| W14 (03-31~04-04) | 5 | 40h | 8h |
```

## Logging Hierarchy

Worklogs are logged at the **sub-task level** (KB2CW-xxxx), not the Epic level. JIRA automatically rolls up sub-task time spent to the parent. This matches the existing story point structure: Epic SP = sum of sub-task SP.

If a ticket has no sub-tasks (standalone Task or Bug), log directly on that ticket.

## No-Ticket Days

Days where no tickets are In Development are **silently skipped** — no placeholder worklog is created. These are assumed to be meeting/planning/review days where time isn't tracked to specific tickets. This is a deliberate design choice for compliance: the worklog record shows what was worked on, and gaps are explainable as non-ticket work.

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
