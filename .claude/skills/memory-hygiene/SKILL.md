---
name: memory-hygiene
description: Manual memory tiering — classify Hot/Warm/Cold, review candidates, and migrate MEMORY.md index + memory files. Use when the session-start advisory fires, MEMORY.md Hot grows past 15 entries, or you want a periodic cleanup. Trigger "memory-hygiene", "整理記憶", "memory 降級", "/memory-hygiene", "decay scan", "tier memory".
triggers:
  - "memory-hygiene"
  - "/memory-hygiene"
  - "整理記憶"
  - "memory 降級"
  - "memory 清理"
  - "decay scan"
  - "tier memory"
  - "memory tier"
version: 1.0.0
---

# /memory-hygiene — Manual Memory Tiering

Runs the DP-015 Part B tiering script against the active workspace memory directory. Three modes: **scan** (default, advisory), **dry-run** (full classification report), **apply** (execute migrations after user approval).

## When to Use

| Signal | Mode |
|--------|------|
| Session-start hook injected demotion candidates | scan → apply |
| `MEMORY.md` Hot section > 15 entries | dry-run → apply |
| User says "整理 memory" / "memory decay" / 手動觸發 | scan |
| Pre-version-bump checklist | dry-run |

## Mode Detection

| User says | Mode |
|-----------|------|
| "/memory-hygiene", "memory-hygiene", default | scan |
| "dry-run", "full report", "看看所有分類" | dry-run |
| "apply", "搬檔", "執行", "migrate" | apply (requires prior dry-run in this session) |

---

## Mode: scan (advisory, default)

Lightweight — equivalent to the SessionStart hook but user-triggered.

### Step 1 — Run decay-scan

```bash
/Users/hsuanyu.lee/work/scripts/memory-hygiene-tiering.py \
  decay-scan \
  --memory-dir /Users/hsuanyu.lee/.claude/projects/-Users-hsuanyu-lee-work/memory
```

### Step 2 — Report

Present the output verbatim. No edits. Ask the user:

> 要繼續跑 `dry-run` 看完整分類還是 `apply` 直接搬？或先這樣？

---

## Mode: dry-run (full classification)

Shows every memory file's tier + destination without moving anything.

### Step 1 — Run dry-run

```bash
/Users/hsuanyu.lee/work/scripts/memory-hygiene-tiering.py \
  dry-run \
  --memory-dir /Users/hsuanyu.lee/.claude/projects/-Users-hsuanyu-lee-work/memory
```

### Step 2 — Summarize

Give the user:
- Total counts per tier (Hot / Warm / Cold)
- Top 5 Hot candidates for demotion (oldest `last_triggered` + lowest `trigger_count`)
- New topic folders that would be created (if any)
- Pinned entries (reminder — user may want to un-pin stale ones)

### Step 3 — Offer apply

> 要套用這份計劃嗎？`apply` 會實際搬檔 + 更新 `MEMORY.md` + 寫 `.migration-log.md`。

If yes, proceed to Mode: apply. If no, end.

---

## Mode: apply (execute)

Runs the migration. Irreversible without `git restore` on the memory dir.

### Step 1 — Safety checks

Before running `apply`:
1. `git -C /Users/hsuanyu.lee/work status --short` — warn if `~/.claude/projects/-Users-hsuanyu-lee-work/memory/` has uncommitted changes (migration log will be easier to understand on a clean slate). Memory dir is not in the work repo but the user's mental model is still "a dir I care about" — mention it
2. Confirm the user has seen the dry-run output in this session (if not, run dry-run first)

### Step 2 — Run apply

The script supports two entry points. Prefer passing the dry-run plan via JSON stdin so the two runs see an identical file set:

```bash
/Users/hsuanyu.lee/work/scripts/memory-hygiene-tiering.py \
  dry-run \
  --memory-dir /Users/hsuanyu.lee/.claude/projects/-Users-hsuanyu-lee-work/memory \
  --json \
  | /Users/hsuanyu.lee/work/scripts/memory-hygiene-tiering.py \
    apply \
    --memory-dir /Users/hsuanyu.lee/.claude/projects/-Users-hsuanyu-lee-work/memory
```

If the script's `apply` mode is still a stub (DP-015 B10 was executed once; subsequent runs may need script extension), fall back to re-running the documented B10 migration command from the design plan (`specs/design-plans/DP-015-polaris-context-efficiency/plan.md § B10`).

### Step 3 — Post-apply report

Show the user:
- Number of files moved (hot→warm, warm→cold)
- New topic folders created
- `MEMORY.md` line count before → after
- Path to `.migration-log.md` for history

### Step 4 — Verify

Instruct the user: open a fresh session and run `/memory` — confirm `MEMORY.md` loads cleanly and the Hot count is ≤ 15.

---

## Preamble

No reference files needed beyond the script itself. The classification rules live in the script source (`scripts/memory-hygiene-tiering.py` top docstring) and `rules/feedback-and-memory.md § Memory Tiering`.

## Post-Task Reflection

If the apply run surfaced anomalies (orphan files, missing frontmatter, topic inference misses), write a framework-experience memory (`type: framework-experience`, topic `polaris-framework`) with the observation — these signals drive future script improvements.

Do NOT create a feedback memory for routine migrations — only for non-obvious script behavior the user had to correct.
