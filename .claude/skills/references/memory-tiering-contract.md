---
title: "Memory Tiering Contract"
description: "Hot/Warm/Cold memory lifecycle、寫入紀律、decay flow、fresh-write grace 與 cross-session learnings 邊界。"
---

# Memory Lifecycle Rules

memory files 採三層 lifecycle，用來控制每次對話的載入成本，並避免 `MEMORY.md`
超過 200 行後被截斷。這份 contract 於 `2026-04-20` 從 `DP-015 Part B` 正式收斂。

## Tier Definitions

| Tier | Location | Load behavior | Eligibility |
|------|----------|---------------|-------------|
| Hot | `memory/*.md` + pointer in `MEMORY.md` | Loaded into every session | `pinned: true` OR `last_triggered >= today-30d` OR `trigger_count >= 5` OR new write within 7-day fresh-write grace |
| Warm | `memory/{topic}/*.md` + pointer in `memory/{topic}/index.md` | Loaded on demand when Strategist pulls the topic folder | `last_triggered >= today-90d`, grouped by `topic` |
| Cold | `memory/archive/*.md` | Never loaded automatically; available for retrospective reads | Older than 90 days OR strikethrough in `MEMORY.md` |

## Write Discipline

When creating a new memory file:

0. 新檔 frontmatter 必須寫 `created: YYYY-MM-DD`。這是 fresh-write grace 的主要 baseline；
   既有檔若缺 `created`，hygiene apply 只能 backfill original file mtime date，不可用 apply 當天。
1. 先檢查 topic folder：若對應主題已存在 `memory/{topic}/`，就把檔案寫進該資料夾，
   並把 pointer 加到 `{topic}/index.md`，不要加到 `MEMORY.md`。
2. Otherwise write flat at `memory/` root with a pointer in `MEMORY.md` Hot.
3. 不得在日常寫入時臨時建立新的 topic folder。建立 folder 的權限保留給
   `scripts/memory-hygiene-tiering.py apply`。如果主題很明確但 folder 尚不存在，先平寫在 root，
   並在 frontmatter 設 `topic: <slug>`，讓下次 migration 再接手。

Fresh-write grace 只是一個短期緩衝：缺 `last_triggered` / `trigger_count` 的新 flat file
在 `created` 起 7 天內可留在 Hot；超過 7 天仍未被引用時，依 topic / age 降到 Warm 或 Cold。
它不代表 routing value 已被驗證，dry-run JSON 會以 `fresh_write_hot` 分開計數。

After writing, if `MEMORY.md` Hot exceeds 15 entries, surface an advisory:
`MEMORY.md Hot 已達 {N} 項，建議跑 /memory-hygiene 降級最舊的 N-15 項到 Warm.`
Do not auto-move; demotion is deliberate.

## Frontmatter Fields

| Field | Type | Purpose |
|-------|------|---------|
| `created` | date | Fresh-write grace baseline. New memory writers must set it; hygiene apply backfills missing values from original mtime |
| `pinned` | bool | `true` = always Hot regardless of decay. Reserved for user-declared entries. Do not auto-set |
| `pinned_reason` | string | Required when `pinned: true`; documents the user-declared reason |
| `topic` | string | Warm folder slug, for example `cwv-epics` or `polaris-framework`. Consumed by the tiering script |
| `snapshot_of` | string | Optional DP / ticket identifier for project status snapshots |
| `snapshot_taken` | date | Snapshot date; snapshots older than 14 days become stale candidates |
| `graduated_to` | path | Explicit marker that feedback has been promoted to a rule / reference and can leave Hot |
| `originSessionId` | string | Optional debug-only field. Tiering does not consume it |

除 `created` 與 pinned companion rule 外，其餘欄位依情境 optional。baseline frontmatter spec 仍維持：
`name`、`description`、`type`，以及 optional 的 `company`、`trigger_count`、`last_triggered`。

`snapshot_of` status lookup 只把 `IMPLEMENTED`、`SUPERSEDED`、`ABANDONED` 視為 terminal。
`LOCKED` 代表 active delivery，不可被當成 terminal stale。

`metadata:` nested frontmatter 不再是支援的 steady-state shape。Hygiene dry-run 會以
`nested_frontmatter` 標記；normalization 後若 apply plan 仍含 nested frontmatter，validator
會 fail-stop。

## Decay And Migration

- Advisory scan：`.claude/hooks/memory-decay-scan.sh` 每天會呼叫一次
  `scripts/memory-hygiene-tiering.py decay-scan`。它只列出 candidate demotions，不會真的移動檔案。
  Output includes time-decay candidates, stale snapshot candidates, and graduated feedback candidates.
- Manual hygiene: `/memory-hygiene` offers scan, dry-run, and apply. Apply writes
  `.migration-log.md` recording every move. Canonical apply chain is
  `dry-run --json | validate-memory-hygiene-plan.sh | apply`.
- Apply 會依 `last_triggered desc` 重寫 `MEMORY.md` Hot entries；沒有 `last_triggered`
  的 Hot entries 放在有 triggered entries 之後。Daily write 不重排 index。
- Archive 是永久層：Cold entries 進 `memory/archive/` 後不會被刪除，保留歷史 context 供未來 framework 演化使用。

## Local Mirror Boundary

Tracked framework PR 只更新本 reference 與 `.claude/rules/feedback-and-memory.md`。
`~/.claude/CLAUDE.md` 這類 user runtime mirror 與 live memory files 是 local verification /
follow-up surface，不是 engineering Allowed Files。Release 或 verification step 可以提醒使用者同步
local mirror，但 implementation task 不得把這些 runtime-local paths 放進 PR scope。

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
