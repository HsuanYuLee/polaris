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

Hot soft-limit 從 round 3 起改由 PreToolUse hook `.claude/hooks/pre-memory-write.sh`
強制：寫入後若 Hot 條目會 > 15，hook 透過 `scripts/validate-memory-write.sh`
fail-stop（exit 2），stderr 含 current N、soft limit、最舊 3 筆候選降級條目，以及
推薦執行的 `/memory-hygiene` 命令。完整契約見下方 § Hot Soft-Limit Hard Gate。
Demotion 仍是 deliberate action，由 `/memory-hygiene` 持有；hook 不會自動搬檔。

**Hot capacity ceiling**（DP-213）：`scripts/memory-hygiene-tiering.py` 在 `classify()`
之後跑 `apply_hot_capacity_ceiling()` 後處理；當 Hot candidate 數量 > `MEMORY_HOT_CAPACITY`
（default 15，可由 env 覆寫）時，依排序 `pinned > trigger_count desc > recency > mtime desc
> filename asc` 把尾段 entries 降到 Warm（有 topic 進 topic folder，無 topic 留 flat warm），
reason 標 `overflowed-hot-capacity`。pinned + graduated_to 永遠不被擠出；graduated_to
直接落 Cold，不參與 ceiling 排序。Migration log 列出本輪降級檔名 + 新 tier。這讓 hygiene
apply 結束時 Hot 必然 ≤ 15，不再需要使用者手動 pin / 改 last_triggered 收斂。

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
`nested_frontmatter` 標記，但驗證契約已收斂（DP-213）：
`scripts/validate-memory-hygiene-plan.sh` 把 `nested_frontmatter` 從 `issues` 移到
`warnings`（exit code 0），讓 canonical chain `dry-run --json | validate | apply` 可順利走完。
Apply 內部的 `normalize_memory_file()` 是 nested frontmatter 唯一 enforcement path：
攤平 `metadata:` block 並補 `created:`。Validator warnings 段會列出受影響檔名，便於
debug；callers 知道後續 apply 會 normalize。不再需要 `POLARIS_MEMORY_HYGIENE_APPLY=1`
作為 nested_frontmatter bypass。

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

## Hot Soft-Limit Hard Gate

Round 3 起，Hot 條目超量從 advisory log 升級為 **hard gate**：

- 任何 `memory/*.md` 或 `MEMORY.md` 的 Write / Edit / MultiEdit 若會把 Hot 推到 > 15，
  PreToolUse hook `.claude/hooks/pre-memory-write.sh` 透過
  `scripts/validate-memory-write.sh` fail-stop（exit 2），不再只是 advisory log。
- stderr 必須含結構化欄位：current N、soft limit、最舊 3 筆候選降級條目、推薦執行命令
  （通常是 `/memory-hygiene`）。
- 緊急 bypass 使用 env var `POLARIS_MEMORY_HYGIENE_APPLY=1`，僅供 hygiene apply chain
  內部使用；日常 session 不應設定。
- 同一 file path 在同一 session 內被 hook 擋下 3 次後，hook 會 escalate surface 給使用者，
  避免 silent retry loop。

`/memory-hygiene` 與 `scripts/memory-hygiene-tiering.py apply` 是降級的 canonical writer
path；不要用手動 Edit 規避 hard gate。

## Generated MEMORY.md Index

`MEMORY.md` 從 round 3 起是由 `scripts/memory-hygiene-tiering.py --emit-index` 產生的
**generated artifact**：

- 不可直接 Write / Edit / MultiEdit `MEMORY.md`。任何手動寫入會被 PreToolUse hook 擋下
  （exit 2），除非 producer chain 已設 `POLARIS_MEMORY_HYGIENE_APPLY=1`。
- 內容由 `memory/*.md` frontmatter 推導：Hot / Warm 區的條目、count 與 sort order 完全
  deterministic。
- 檔案開頭寫入 generated marker，由 emit-index 維護；annotation 區（`_Last tiered:` 行、
  使用者註記）emit-index 必須 byte-equal preserve，不得改寫。
- Daily writer path：合法 memory file 寫入後，PostToolUse hook
  `.claude/hooks/post-memory-index-regenerate.sh` 以 producer env 呼叫
  `memory-hygiene-tiering.py --emit-index` 同步重生 `MEMORY.md`，避免 generated index stale。
- Apply writer path：`/memory-hygiene apply` 與 `memory-hygiene-tiering.py apply` 自身已設
  producer env，直接 regenerate；hook bypass 透過 `POLARIS_MEMORY_HYGIENE_APPLY=1`。

不論哪條 producer path，emit-index 對既有 hand-maintained `MEMORY.md` 必須產出等價結構
（Hot bullet 內容等價、annotation 區 byte-equal）。

## Hook Ownership

Round 3 memory write enforcement 由兩條 hook 與一個 validator 持有：

| 角色 | Path | 觸發 | 行為 |
|------|------|------|------|
| Validator | `scripts/validate-memory-write.sh` | hook 或 manual | memory file frontmatter / Hot soft-limit / `MEMORY.md` 直寫 contract check；支援 `--hook-json` 從 Write / Edit / MultiEdit payload 重建候選內容；exit 2 + 結構化 stderr |
| PreToolUse hook | `.claude/hooks/pre-memory-write.sh` | `Write` / `Edit` / `MultiEdit` on memory paths | 讀 Claude Code hook JSON，重建候選內容後呼叫 validator；同一 file path session 內連 3 次 fail 自動 escalate surface |
| PostToolUse hook | `.claude/hooks/post-memory-index-regenerate.sh` | 合法 memory file write 成功 | 以 producer env 呼叫 `memory-hygiene-tiering.py --emit-index` 同步 `MEMORY.md`；regenerate 失敗時 surface 修復指令 |

兩條 hook 註冊在 tracked `.claude/settings.json` 的 `Write` / `Edit` / `MultiEdit` matcher；
target path 過濾由 hook 內部執行，不靠 path glob matcher。`POLARIS_MEMORY_DIR` 可覆寫
production memory dir，selftest 與 hygiene apply 都依賴此 override。
`POLARIS_MEMORY_INDEX_GRACE_UNTIL` 於既有 hand-maintained `MEMORY.md` 第一次 normalize
前提供 grace window；過期後 hook 直接 fail-stop。

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
