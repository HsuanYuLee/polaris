---
title: "Memory Tiering Contract"
description: "Hot/Warm/Cold memory lifecycle rules, write discipline, decay flow, and boundaries with cross-session learnings."
---

# Memory Tiering Contract

Memory files follow a three-tier lifecycle to cap per-conversation loading cost
and keep `MEMORY.md` under the 200-line truncation risk. This contract graduated
from `DP-015 Part B` on 2026-04-20.

## Tier Definitions

| Tier | Location | Load behavior | Eligibility |
|------|----------|---------------|-------------|
| Hot | `memory/*.md` + pointer in `MEMORY.md` | Loaded into every session | `pinned: true` OR `last_triggered >= today-30d` OR `trigger_count >= 5` |
| Warm | `memory/{topic}/*.md` + pointer in `memory/{topic}/index.md` | Loaded on demand when Strategist pulls the topic folder | `last_triggered >= today-90d`, grouped by `topic` |
| Cold | `memory/archive/*.md` | Never loaded automatically; available for retrospective reads | Older than 90 days OR strikethrough in `MEMORY.md` |

## Write Discipline

When creating a new memory file:

1. Check topic folder: if `memory/{topic}/` exists for the relevant topic, write
   the file inside that folder and add the pointer to `{topic}/index.md`, not
   `MEMORY.md`.
2. Otherwise write flat at `memory/` root with a pointer in `MEMORY.md` Hot.
3. Do not create new topic folders on the fly. Folder creation is reserved for
   `scripts/memory-hygiene-tiering.py apply`. If a clear topic exists but no
   folder, write flat and set `topic: <slug>` in frontmatter so the next
   migration picks it up.

After writing, if `MEMORY.md` Hot exceeds 15 entries, surface an advisory:
`MEMORY.md Hot 已達 {N} 項，建議跑 /memory-hygiene 降級最舊的 N-15 項到 Warm.`
Do not auto-move; demotion is deliberate.

## Frontmatter Fields

| Field | Type | Purpose |
|-------|------|---------|
| `pinned` | bool | `true` = always Hot regardless of decay. Reserved for user-declared entries. Do not auto-set |
| `topic` | string | Warm folder slug, for example `cwv-epics` or `polaris-framework`. Consumed by the tiering script |

Both fields are optional. The baseline frontmatter spec remains: `name`,
`description`, `type`, optional `company`, optional `trigger_count`, and optional
`last_triggered`.

## Decay And Migration

- Advisory scan: `.claude/hooks/memory-decay-scan.sh` calls
  `scripts/memory-hygiene-tiering.py decay-scan` once per day. It lists candidate
  demotions and does not move files.
- Manual hygiene: `/memory-hygiene` offers scan, dry-run, and apply. Apply writes
  `.migration-log.md` recording every move.
- Archive is forever: Cold entries go to `memory/archive/` and are never deleted.
  Historical context supports future framework self-evolution.

## Boundary With `polaris-learnings.sh`

- `polaris-learnings.sh`: technical knowledge such as patterns, pitfalls,
  confidence, key dedup, and decay.
- `memory/`: session state, preferences, and behavior corrections.
- Overlap case: if a PR lesson is both a technical pattern and a behavior
  correction, prefer learnings for the technical part.

## References

- User-level rules: `~/.claude/CLAUDE.md` Memory Tiering Rules
- Script: `scripts/memory-hygiene-tiering.py`
- Manual skill: `.claude/skills/memory-hygiene/SKILL.md`
- Session hook: `.claude/hooks/memory-decay-scan.sh`
- Design plan: `specs/design-plans/DP-015-polaris-context-efficiency/plan.md`
