---
title: "Memory Tiering Contract"
description: "Hot/Warm/Cold memory lifecycle rules, write discipline, decay flow, and boundaries with cross-session learnings."
---

# Memory Tiering Contract

memory files 採三層 lifecycle，用來控制每次對話的載入成本，並避免 `MEMORY.md`
超過 200 行後被截斷。這份 contract 於 `2026-04-20` 從 `DP-015 Part B` 正式收斂。

## Tier Definitions

| Tier | Location | Load behavior | Eligibility |
|------|----------|---------------|-------------|
| Hot | `memory/*.md` + pointer in `MEMORY.md` | Loaded into every session | `pinned: true` OR `last_triggered >= today-30d` OR `trigger_count >= 5` |
| Warm | `memory/{topic}/*.md` + pointer in `memory/{topic}/index.md` | Loaded on demand when Strategist pulls the topic folder | `last_triggered >= today-90d`, grouped by `topic` |
| Cold | `memory/archive/*.md` | Never loaded automatically; available for retrospective reads | Older than 90 days OR strikethrough in `MEMORY.md` |

## Write Discipline

When creating a new memory file:

1. 先檢查 topic folder：若對應主題已存在 `memory/{topic}/`，就把檔案寫進該資料夾，
   並把 pointer 加到 `{topic}/index.md`，不要加到 `MEMORY.md`。
2. Otherwise write flat at `memory/` root with a pointer in `MEMORY.md` Hot.
3. 不得在日常寫入時臨時建立新的 topic folder。建立 folder 的權限保留給
   `scripts/memory-hygiene-tiering.py apply`。如果主題很明確但 folder 尚不存在，先平寫在 root，
   並在 frontmatter 設 `topic: <slug>`，讓下次 migration 再接手。

After writing, if `MEMORY.md` Hot exceeds 15 entries, surface an advisory:
`MEMORY.md Hot 已達 {N} 項，建議跑 /memory-hygiene 降級最舊的 N-15 項到 Warm.`
Do not auto-move; demotion is deliberate.

## Frontmatter Fields

| Field | Type | Purpose |
|-------|------|---------|
| `pinned` | bool | `true` = always Hot regardless of decay. Reserved for user-declared entries. Do not auto-set |
| `topic` | string | Warm folder slug, for example `cwv-epics` or `polaris-framework`. Consumed by the tiering script |

這兩個欄位都是 optional。baseline frontmatter spec 仍維持：
`name`、`description`、`type`，以及 optional 的 `company`、`trigger_count`、`last_triggered`。

## Decay And Migration

- Advisory scan：`.claude/hooks/memory-decay-scan.sh` 每天會呼叫一次
  `scripts/memory-hygiene-tiering.py decay-scan`。它只列出 candidate demotions，不會真的移動檔案。
- Manual hygiene: `/memory-hygiene` offers scan, dry-run, and apply. Apply writes
  `.migration-log.md` recording every move. Canonical apply chain is
  `dry-run --json | validate-memory-hygiene-plan.sh | apply`.
- Archive 是永久層：Cold entries 進 `memory/archive/` 後不會被刪除，保留歷史 context 供未來 framework 演化使用。

## Boundary With `polaris-learnings.sh`

- `polaris-learnings.sh`: technical knowledge such as patterns, pitfalls,
  confidence, key dedup, and decay.
- `memory/`: session state, preferences, and behavior corrections.
- 若一條 PR lesson 同時兼具 technical pattern 與 behavior correction，優先把 technical 部分放進 learnings。

## References

- User-level rules: `~/.claude/CLAUDE.md` Memory Tiering Rules
- Script: `scripts/memory-hygiene-tiering.py`
- Manual skill: `.claude/skills/memory-hygiene/SKILL.md`
- Session hook: `.claude/hooks/memory-decay-scan.sh`
- Design plan: `specs/design-plans/DP-015-polaris-context-efficiency/plan.md`
