# Framework Iteration Procedures

> **When to load**: when executing the version bump chain, backlog hygiene, or validated pattern promotion. Contains detailed procedures extracted from `rules/framework-iteration.md`. Loaded on-demand.

## Iteration Cadence Map

| Cadence | When | Mechanism | Source |
|---------|------|-----------|--------|
| Micro | After every task | Post-task reflection → feedback memory / backlog | `rules/feedback-and-memory.md` |
| Meso | After every PR | PR review → handbook direct write | `repo-handbook.md` Step 3b + `review-lesson-extraction.md` |
| Macro | Pre-release only | Challenger Audit → polaris-backlog | `rules/framework-iteration.md` § Challenger Audit |

Daily iteration is driven by **real usage** (Micro + Meso), not simulated review.

## Framework Experience Frontmatter Template

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

## Post-Version-Bump Chain

After a VERSION bump is committed, execute these steps in order — no user confirmation needed:

1. **docs-lint** — run `python3 scripts/readme-lint.py --fix` as a fast deterministic check: skill counts, phantom skills, undocumented skills, chinese-triggers table, mermaid diagram nodes. Auto-fixes counts; reports other issues
2. **docs-sync** — if docs-lint reported issues beyond count fixes (phantom skills, missing entries, stale diagrams), invoke `/docs-sync` to fix them. The skill's Step 0 uses docs-lint output + git diff to scope the sync. If changes are found, commit as a separate `docs:` commit
3. **backlog-staleness-scan** — scan `polaris-backlog.md` for stale items (see § Backlog Hygiene below)
4. **sync-to-polaris.sh --push** — sync all changes (including the docs commit) to the template repo

This chain ensures documentation is always up-to-date and backlog stays clean at release boundaries.

## Backlog Hygiene

`polaris-backlog.md` items carry a date tag `(YYYY-MM-DD)` and optional exemption tags (`[platform]`, `[next-epic]`).

**Triggers:**
1. **Post-version-bump chain** (primary) — Step 3 above
2. **Monthly standup fallback** — first `/standup` of each month, if no version bump happened that month

**Scan rules:**

| Condition | Action |
|-----------|--------|
| `[ ]` item with no exemption tag, date > 60 days ago | Suggest closing — present to user |
| `[ ]` item with `[platform]` or `[next-epic]` tag, date > 90 days ago | Ask user to confirm tag is still valid |
| `[ ]` item with no date tag | Add today's date (backfill) |

**Execution:** scan is silent — only surface items that match a rule. If nothing is stale, no output. Present stale candidates as a numbered list; user says which to close or keep (with updated date).

## Validated Pattern Promotion

During `organize-memory` / `clean up memory` runs:

1. Scan all `type: framework-experience` entries
2. If >= 3 entries describe the **same pattern** across different tasks → surface to user as a "Validated Pattern" candidate
3. User confirms → write a rationale note into the appropriate rule file (not as an imperative rule, but as a "this works because..." annotation)
4. After promotion, delete the consolidated framework-experience memories
