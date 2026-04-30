# Refinement Return Inbox Contract

`breakdown` is the translator between execution-side escalation evidence and
`refinement`. `refinement` must not read engineering escalation sidecars
directly.

## Purpose

When `breakdown` decides that a scope escalation cannot be repaired by
task-md changes, new work orders, waiting, or baseline approval, it writes a
refinement-facing inbox record. The record contains the planner decision and
the architecture/spec questions to reopen. It does not contain raw gate output.

This keeps ownership clear:

| Producer | Artifact | Consumer |
|----------|----------|----------|
| `engineering` | `escalations/T{n}-{count}.md` raw sidecar | `breakdown` only |
| `breakdown` | `refinement-inbox/{id}.md` decision record | `refinement` only |
| `refinement` | `refinement.md` + `refinement.json` | `breakdown` |

## Location

JIRA-backed specs:

```text
{company_specs_dir}/{EPIC}/refinement-inbox/{TASK_ID}-{COUNT}-{timestamp}.md
```

Example:

```text
specs/companies/kkday/GT-478/refinement-inbox/T3a-2-20260429T093000Z.md
```

Ticketless / DP specs:

```text
{workspace_root}/specs/design-plans/DP-NNN-{slug}/refinement-inbox/{TASK_ID}-{COUNT}-{timestamp}.md
```

## Schema

```markdown
---
skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
epic: GT-478             # JIRA Epic key, or DP-NNN for ticketless / DP-backed work
source_task: T3a
source_ticket: KB2CW-3711
source_sidecar: specs/companies/kkday/GT-478/escalations/T3a-2.md
escalation_count: 2
created_at: 2026-04-29T09:30:00Z
consumed: false
---

## Decision

re-classified to refinement: the failed gate cannot be closed by task.md
repair because the selected technical approach / AC boundary must be re-decided.

## Refinement Context

- Gate summary: ci-local type baseline remains over threshold after approved
  task-level scope fixes.
- Current planning gap: AC does not define whether vendor chunk budget is a
  hard requirement or diagnostic target.
- Breakdown disposition: stop task-md loop; reopen refinement.

## Decisions Needed

1. Decide whether the AC budget remains mandatory.
2. Decide whether the current technical approach should change.
3. Decide which downstream tasks must be regenerated after the decision.

## Source Audit

- Source sidecar path is kept for audit only.
- Refinement must not open `source_sidecar`; ask breakdown for a revised inbox
  record if the context is insufficient.
```

## Hard Rules

- `refinement` reads `refinement-inbox/*.md`, never
  `escalations/T{n}-{count}.md`.
- A direct sidecar path given to `refinement` is a routing error. Route to
  `breakdown` scope-escalation intake first.
- `source_sidecar` is an audit pointer only. It is not a permission for
  `refinement` to read raw evidence.
- The inbox body must not include `## Raw Evidence` or full command logs.
  `breakdown` should summarize gate facts into planning language.
- `breakdown` may mark the source sidecar `processed: true` only after the
  inbox record is written and passes validation.
- `refinement` marks `consumed: true` only after it has updated
  `refinement.md` / `refinement.json` or explicitly rejected the decision as
  insufficient and asked `breakdown` to rewrite the inbox record.

## Validator

```bash
scripts/validate-refinement-inbox-record.sh \
  {company_specs_dir}/{EPIC}/refinement-inbox/{record}.md
```

The validator blocks:

- producer other than `skill: breakdown`
- target other than `target_skill: refinement`
- `route` other than `refinement`
- missing source id in `epic`（JIRA Epic key or DP-NNN）
- missing required sections
- `## Raw Evidence` sections
- records over the 8 KB body cap
