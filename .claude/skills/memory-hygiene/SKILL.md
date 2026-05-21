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
version: 1.1.0
---

# Memory Hygiene

`memory-hygiene` 是 manual memory tiering：檢查 Hot / Warm / Cold，產生 demotion
candidate，並在使用者確認後搬移 memory files 與更新 index。

## Contract

這是 memory maintenance skill，不是一般 task planning。Scan / dry-run 只讀；apply 會寫
workspace memory，因此必須先有本 session 的 dry-run 結果與使用者明確確認。

## Mode Routing

| User says | Mode | Reference |
|---|---|---|
| `/memory-hygiene`, `memory-hygiene`, default | scan | `memory-hygiene-scan-flow.md` |
| `dry-run`, `full report`, `看看所有分類` | dry-run | `memory-hygiene-scan-flow.md` |
| `apply`, `搬檔`, `執行`, `migrate` | apply | `memory-hygiene-apply-flow.md` |

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `polaris-project-dir.md`, `feedback-memory-procedures.md` |
| Scan / dry-run | `memory-hygiene-scan-flow.md` |
| Apply | `memory-hygiene-apply-flow.md` |

Classification rules live in `scripts/memory-hygiene-tiering.py` and
`rules/feedback-and-memory.md` Memory Tiering.

Plan artifact authority lives in `bash scripts/validate-memory-hygiene-plan.sh`。
`apply` 不應直接吃任意 JSON；必須先通過 plan validator。

## Hard Rules

- Apply requires prior dry-run in the same session.
- Do not hard-code user-specific memory paths; resolve active workspace memory dir.
- Do not auto-move pinned memories.
- 不刪除 Cold memories；archive 是 historical context。
- Routine migrations 不建立 feedback memory。
- If apply finds anomalies, record at most one framework-experience memory.
- Canonical apply chain is `dry-run --json | validate-memory-hygiene-plan.sh | apply`；不要手動改 plan JSON 後直接餵 apply。
- DP-213 起 apply 一定把 Hot 收斂到 ≤ 15（`MEMORY_HOT_CAPACITY` env 可覆寫）：超量者依
  確定性 ranking 自動降 Warm，pinned + graduated_to 永遠不被擠出，migration log 列出
  `overflowed-hot-capacity` 降級檔名。chain 在含 nested_frontmatter 的 plan 也能跑通；
  validator 把 nested_frontmatter 移到 warnings，apply 內部 normalize 是唯一 enforcement
  path，不需要 `POLARIS_MEMORY_HYGIENE_APPLY=1` bypass。

## Completion

Return mode, memory dir, Hot/Warm/Cold counts when available, candidate summary, apply status,
files moved, migration log path, and any anomalies.

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
