---
title: "Breakdown Escalation Intake Flow"
description: "breakdown scope-escalation intake：讀 engineering sidecar、重新分類 flavor、closure gate、task/refinement 落地。"
---

# Escalation Intake Flow

## Entry

觸發於使用者明說處理 escalation / breakdown intake、直接提供 sidecar path，或 active
task 的 `escalations/T{n}-{count}.md` 未 processed。

讀 `{company_specs_dir}/{EPIC}/escalations/` 中同 lineage 最高 count sidecar。讀取
frontmatter 與 gate-closure sections：

- `## Gate Closure`
- `## Current Measurement`
- `## Explained Delta`
- `## Proposed Fixes`
- `## Residual Blockers`
- `## Closure Forecast`
- `## Required Planner Decisions`
- `## Raw Evidence`

缺任一必要 gate-closure section 時停止，要求 engineering 重建 sidecar。

## Flavor Decision

`flavor` 是 hint，不是 binding。依 `escalation-flavor-guide.md` 重新判斷：

| Flavor | Breakdown action |
|---|---|
| `plan-defect` | 修現有 task.md，補 Allowed Files / estimate / Test Command / Verify Command / Test Environment |
| `scope-drift` | 拆新 task，新 task `depends_on` 原 task |
| `env-drift` | 記錄 wait / baseline approval / external drift，不放行 failing gate |

CI fail 是 blocker。小型機械性 unblock 可視為 `plan-defect`；新模組、跨頁面驗證、
可獨立 review 的改動是 `scope-drift`；base/sibling/external drift 是 `env-drift`。

主對話與最終寫入必須明寫其一：

- `accepted flavor: X`
- `re-classified to Y: reason`

若 `Closure Forecast` 顯示單一修法不足，proposal 必須一次涵蓋 residual / baseline /
env decisions；不可只補第一個 Allowed Files 就回 engineering。

## Preview Gate

沿用 Planning Flow 的 user-confirmation gate。Preview 必須包含：

- sidecar `Closure Forecast` 摘要。
- accepted / re-classified flavor。
- task.md 修改、新 task、wait、baseline approval 或 refinement route。
- 明確回答本 proposal 是否足以讓 failed gate 具備 pass 條件。

沒有 explicit confirmation 前不可寫 task.md / JIRA / inbox / processed flag。

## Closure Validation And Writes

寫入前先跑：

```bash
scripts/validate-breakdown-escalation-intake.sh \
  --sidecar "{sidecar}" \
  --route "{engineering|refinement|wait|baseline_approval|task_update}" \
  --closes-gate "{true|false}" \
  --flavor "{accepted_or_reclassified_flavor}" \
  --disposition "{accepted flavor: X | re-classified to Y: reason}" \
  --decision "{planner decision}"
```

exit != 0 時停止。

落地規則：

- `plan-defect`：由 breakdown 直接修原 task.md。
- `scope-drift`：依 `breakdown-task-packaging.md` 產新 T{n}.md。
- `env-drift`：通常只寫 JIRA / handbook wait or approval record。
- route = `refinement`：建立 refinement inbox record，schema 依
  `refinement-return-inbox.md`，位置：

  ```text
  {company_specs_dir}/{EPIC}/refinement-inbox/T{n}-{count}-{YYYYMMDDTHHMMSSZ}.md
  ```

  Body 只寫 Decision / Refinement Context / Decisions Needed / Source Audit；不得包含
  raw logs。寫完跑 `scripts/validate-refinement-inbox-record.sh`。

最後才在 sidecar frontmatter 加 `processed: true`，不改檔名。

## Handoff

- task 已修正或新 task 已建立：回 `engineering`。
- lineage `escalation_count == 2` 且仍失敗：不要再回 engineering；建立 refinement
  inbox 後提示 `refinement {EPIC}`。
