# Cross-Session Learnings

A JSONL knowledge base that accumulates insights across conversations. Each entry captures something non-obvious learned during a task — patterns, pitfalls, preferences, architecture decisions, or tool usage.

## Why This Exists

Claude Code conversations start with a blank slate (beyond CLAUDE.md and rules). Memory files capture behavioral rules, but **project-specific technical knowledge** (e.g., "this repo's tests need `--forceExit`", "the payment module has a circular dependency with auth") gets lost between sessions. Learnings bridge that gap.

## Entry Schema

```jsonl
{"key":"vue-ref-setup","type":"pattern","content":"Vue composables must call useRoute() at setup top-level, not inside callbacks","confidence":8,"source":"PR #2049 review","company":"acme","created":"2026-04-01","last_confirmed":"2026-04-01"}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | yes | Short kebab-case identifier for dedup (e.g., `vitest-force-exit`) |
| `type` | enum | yes | `pattern` / `pitfall` / `preference` / `architecture` / `tool` |
| `content` | string | yes | The learning — one or two sentences, actionable |
| `confidence` | int | yes | 1-10, initial value set by writer |
| `source` | string | yes | Where it was learned (PR number, ticket, conversation context) |
| `company` | string | no | Company scope (omit for workspace-wide learnings) |
| `created` | date | yes | ISO date of creation |
| `last_confirmed` | date | yes | ISO date of last confirmation/use |

### Types

| Type | When to use | Example |
|------|-------------|---------|
| `pattern` | Recurring code/workflow pattern that works | "Nuxt 3 server routes need `defineEventHandler` wrapper" |
| `pitfall` | Something that breaks unexpectedly | "Running vitest in monorepo root picks up wrong config" |
| `preference` | User or team preference not in rules | "This team prefers named exports over default exports" |
| `architecture` | Structural decision or constraint | "Payment module depends on auth via event bus, not direct import" |
| `tool` | CLI/tool usage insight | "gh pr merge needs --delete-branch to clean up remote" |

## Confidence Decay

Confidence decays over time to surface fresh, relevant knowledge:

```
effective_confidence = confidence - floor((today - last_confirmed) / 30)
```

- Decays 1 point per 30 days since last confirmed
- Minimum effective confidence: 0 (entry becomes invisible but not deleted)
- **Confirmation** resets `last_confirmed` to today and optionally boosts `confidence`

## Dedup Rules

When adding a new entry:
1. Check if an entry with the same `key` AND `type` exists
2. If found: **merge** — update `content` (if new content provided), set `confidence` to max(existing, new), update `last_confirmed` to today
3. If not found: append new entry

## Preamble Injection

At conversation start (or after context compression), the Strategist should:

1. Run `polaris-learnings.sh query --top 5 --min-confidence 3`
2. If results exist, mentally note them as project context (do not output to user unless asked)
3. Use these learnings to inform decisions throughout the conversation

The top 5 are selected by effective confidence (after decay), filtered by active company context.

## When to Write Learnings

Integrated into the post-task reflection (see `rules/feedback-and-memory.md`):

| Signal | Action |
|--------|--------|
| A non-obvious technical fact was discovered during the task | Write a `pattern` or `architecture` entry |
| A command/approach failed unexpectedly | Write a `pitfall` entry |
| User corrected a technical assumption (not a behavioral preference) | Write a `pitfall` or `pattern` entry |
| User expressed a technical preference not covered by rules | Write a `preference` entry |
| A tool trick or CLI flag made a difference | Write a `tool` entry |

**Constraints:**
- At most 2 learnings per task (avoid noise)
- Only write when the insight is **non-obvious** — don't record things derivable from package.json, README, or existing rules
- Learnings are NOT feedback memories — feedback captures behavioral corrections for the Strategist; learnings capture technical knowledge about the codebase/tools

## Script Interface

See `scripts/polaris-learnings.sh` for the CLI:

```bash
# Add or merge a learning
polaris-learnings.sh add --key "vue-ref-setup" --type pattern \
  --content "Vue composables must call useRoute() at setup top-level" \
  --confidence 8 --source "PR #2049"

# Query top N entries (with decay applied)
polaris-learnings.sh query --top 5 --min-confidence 3

# Confirm an entry (reset decay)
polaris-learnings.sh confirm --key "vue-ref-setup"

# List all entries with effective confidence
polaris-learnings.sh list
```

Environment variables:
- `POLARIS_WORKSPACE_ROOT` — workspace root path (required)
- `POLARIS_PROJECT_SLUG` — override slug (optional)
- `POLARIS_COMPANY` — filter by company (optional, used by query)
