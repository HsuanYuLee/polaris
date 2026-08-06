# Session Timeline

A JSONL event log that records significant actions within a conversation. Timeline data feeds into standup reports, retrospectives, and the `/checkpoint` skill for session recovery.

## Why This Exists

After a long session or across multiple sessions in a day, it's hard to reconstruct what happened, in what order, and how long things took. The timeline provides a structured log that the standup skill can read for accurate daily reports, and that `/checkpoint` can use for session state recovery.

## Entry Schema

```jsonl
{"ts":"2026-04-02T06:30:00Z","event":"skill_invoked","skill":"engineering","ticket":"PROJ-500","branch":"task/PROJ-500-feature","outcome":"success","duration_s":180,"note":"implementation + PR opened"}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ts` | string | yes | ISO 8601 UTC timestamp with `Z` suffix (e.g., `2026-04-02T06:30:00Z`) |
| `event` | enum | yes | Event type (see table below) |
| `skill` | string | no | Skill name (for skill_invoked events) |
| `ticket` | string | no | JIRA ticket key |
| `branch` | string | no | Git branch name |
| `pr_url` | string | no | PR URL (for pr_opened/pr_merged events) |
| `outcome` | enum | no | `success` / `fail` / `partial` / `skipped` |
| `duration_s` | int | no | Duration in seconds (if measurable) |
| `note` | string | no | Free-text context |
| `company` | string | no | Company context |

### Event Types

| Event | When logged | Key fields |
|-------|-------------|------------|
| `session_start` | Conversation begins | company |
| `skill_invoked` | A skill is invoked | skill, ticket, branch |
| `skill_completed` | A skill finishes | skill, outcome, duration_s |
| `branch_created` | New git branch | branch, ticket |
| `commit` | Git commit made | branch, note (commit msg summary) |
| `pr_opened` | PR created | pr_url, branch, ticket |
| `pr_merged` | PR merged | pr_url |
| `error` | Significant error encountered | note (error description) |
| `checkpoint` | `/checkpoint save` invoked | note (checkpoint description) |
| `learning_recorded` | Learning written to learnings.jsonl | note (learning key) |

## When to Log Events

The Strategist logs timeline events at natural boundaries — not for every tool call, but for meaningful actions:

| Action | Log? | Why |
|--------|------|-----|
| Skill invocation | Yes | Core workflow tracking |
| PR opened/merged | Yes | Key milestone |
| Branch created | Yes | Workflow start marker |
| Commit | Yes (summary only) | Progress marker |
| File read/grep | No | Too granular |
| Sub-agent dispatch | No | Internal detail |
| Error that changes the plan | Yes | Important for retro |

**Constraints:**
- Timeline events are **append-only** — never edit or delete entries
- Keep `note` fields under 100 characters
- Log at most 20 events per conversation (avoid timeline bloat)

## Script Interface

See `scripts/polaris-timeline.sh` for the CLI:

```bash
# Append an event
polaris-timeline.sh append --event skill_invoked --skill engineering \
  --ticket PROJ-500 --branch task/PROJ-500 --company acme

# Query recent events
polaris-timeline.sh query --since today
polaris-timeline.sh query --since "2h"
polaris-timeline.sh query --since 2026-04-01

# List checkpoints
polaris-timeline.sh checkpoints --last 5
```

Environment variables:
- `POLARIS_WORKSPACE_ROOT` — workspace root path (required)
- `POLARIS_PROJECT_SLUG` — override slug (optional)

## Integration with Standup

The standup skill (Step 1) can read timeline events for the reporting period:

```bash
polaris-timeline.sh query --since "$YESTERDAY"
```

This supplements git log and JIRA data with skill-level activity that doesn't appear in commits (e.g., time spent on estimation, review, debugging).

## Integration with /checkpoint

The `/checkpoint` skill writes `checkpoint` events to the timeline and reads them back for resume. See `skills/checkpoint/SKILL.md`.
