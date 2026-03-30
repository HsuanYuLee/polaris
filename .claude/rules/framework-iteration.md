# Framework Self-Iteration

How Polaris improves itself. Three cadences, each with its own mechanism.

## Iteration Cadence Map

| Cadence | When | Mechanism | Source |
|---------|------|-----------|--------|
| Micro | After every task | Post-task reflection → feedback memory / backlog | `rules/feedback-and-memory.md` |
| Meso | After every PR | review-lessons → graduation to rules | skill: `review-lessons-graduation` |
| Macro | Pre-release only | Challenger Audit → polaris-backlog | This file § Challenger Audit |

Daily iteration is driven by **real usage** (Micro + Meso), not simulated review.

## Challenger Audit: Milestone Self-Check

Challenger Audit (see `skills/references/challenger-audit.md`) launches 6 persona sub-agents to review the framework from external-user perspectives. It is **expensive** (6 parallel sonnet sub-agents) and produces **simulated** signals (AI reviewing AI).

**When to run:**
- Before a major version release that will be publicly shared
- Before sharing the repo with a new team or audience
- When the user explicitly says "challenger", "跑挑戰者", "audit UX"

**When NOT to run:**
- After individual PRs or daily tasks
- As a substitute for post-task reflection
- As a routine iteration driver

Findings flow into `polaris-backlog.md` per the severity rules in `challenger-audit.md`.

## Framework Experience Collection

The Micro cadence collects **pain points** (corrections, blocks, failures). This section adds **positive signal** collection — what framework patterns work and why.

### Storage

`type: framework-experience` memory files in the workspace memory directory. No `company:` field (framework experience is always workspace-wide). Indexed in MEMORY.md with `[fx]` tag.

### When to Write

During the existing post-task reflection pass (feedback-and-memory.md § item 6), if the signal is **framework-level** (not project code quality), write a `type: framework-experience` memory instead of `type: feedback`:

| Signal | What to record |
|--------|---------------|
| Skill flow completes with zero user corrections | Which skill, what flow design held up, why |
| Feedback memory graduates successfully | Pipeline validation — topic, graduation latency |
| User explicitly praises framework behavior | What the Strategist did, which rule/skill enabled it |
| Mechanism canary NOT triggered when it could have been | Mechanism ID, the condition that was correctly handled |
| Same skill works across 2+ companies unmodified | Skill name, universality evidence |

### Constraints

- **At most 1 framework-experience memory per task** — if multiple signals fire, combine into one entry
- **Optional, not mandatory** — only write when the signal is clear and non-obvious. If in doubt, skip
- **No graduation** — framework-experience memories do NOT trigger the `trigger_count >= 3` graduation workflow. They are observations, not corrections

### Frontmatter

```yaml
---
name: Descriptive title
description: One-line summary
type: framework-experience
last_triggered: YYYY-MM-DD
---

Pattern: [what the framework element is]
Evidence: [the concrete task/signal that validated it]
Why it works: [one-sentence hypothesis]
```

## Version Bump Reminder

During post-task reflection, if the completed task modified files under `rules/` or `skills/`:

- Remind the user: "這次改動涉及框架規則/技能，要升版嗎？"
- If user confirms → bump `VERSION`, update `CHANGELOG.md`, commit, then `sync-to-polaris.sh --push` runs automatically
- If user declines → no action. Multiple small changes can be batched into one version later

This is a **reminder**, not an automatic bump. The user decides when and how to group changes into a release.

## Validated Pattern Promotion

During `organize-memory` / `clean up memory` runs:

1. Scan all `type: framework-experience` entries
2. If >= 3 entries describe the **same pattern** across different tasks → surface to user as a "Validated Pattern" candidate
3. User confirms → write a rationale note into the appropriate rule file (not as an imperative rule, but as a "this works because..." annotation)
4. After promotion, delete the consolidated framework-experience memories
