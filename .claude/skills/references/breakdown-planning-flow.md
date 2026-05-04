---
title: "Breakdown Planning Flow"
description: "breakdown JIRA Story / Task / Epic planning：需求分析、探索、拆單、quality challenge、constructability、JIRA write。"
---

# Planning Flow

## Ticket And Project Intake

取得 ticket key 的順序：使用者提供、branch 名稱推導、詢問使用者。用 Atlassian
getJiraIssue 讀 ticket，判斷 Issue Type。Bug 轉 `breakdown-bug-flow.md`。

Project mapping：從 Summary `[...]` tag、Labels、Components 對照 `project-mapping.md`。
仍無法匹配時詢問使用者。

開發進度偵測：

- 既有子單：JQL `parent = <TICKET_KEY>`。
- feature branch：`git branch -a | grep <TICKET_KEY>`。
- commit log：若有 branch，檢視已完成工作。

已有子單或 commits 時，先提示使用者是補充、追蹤已完成工作，或重新拆。

## Explore

提取 Summary、Description、AC、附件連結。資訊不足時列缺口並詢問。

若 `{company_specs_dir}/{EPIC_KEY}/refinement.json` 存在且 modules 非空，直接讀
artifact 的 modules / AC / technical approach，跳過 Explore。Artifact 缺欄位時只補缺少
部分；不存在時才依 `explore-pattern.md` 探索 codebase。

Worktree sub-agent 需使用 main checkout 絕對路徑，詳見 `worktree-dispatch-paths.md`。
dispatch 必須注入 Completion Envelope，完整 detail 寫入
`specs/{EPIC}/artifacts/explore-{timestamp}.md`。

## Split Strategy

| Size | Total points | Strategy |
|---|---|---|
| small | <= 5 pt | one task |
| medium | 6-13 pt | 2-4 tasks |
| large | 13+ pt | 4+ tasks, each 2-5 pt |

拆解原則：

- 依功能模組、頁面、可獨立驗收的使用者價值拆，不依技術層硬拆。
- 單一功能無法獨立測試時合併。
- 每張 task 建議 2-5 pt；超過 5 pt 要考慮再拆。
- API / cross-repo change 排第一；BFF 可獨立；大量 tracking 可獨立；Spike 可獨立。
- 有 visual regression config 時，加入 1pt stable fixture recording task，排在 API 後、
  frontend 前。
- 偵測到互不依賴的分段驗收結構時，advisory 建議拆 Epic；不由 validator enforce。

## Quality Challenge

拆單與估點後自動審查，最多 3 輪。逐張檢查：

- points <= 5。
- AC 明確。
- Happy Flow 有使用者視角。
- 可獨立開發與驗收。
- 無循環依賴。
- 無未驗證 hidden assumption。
- 沒有明顯 80/20 簡化方案被忽略。

有 FAIL 時先自動調整再審；3 輪後仍 FAIL，連同未解問題呈現使用者，不進 write。

## Constructability Gate

Step 8 preview 前，每張 task 必須有：

- machine-matchable Allowed Files。
- Gate Closure Matrix，至少 scope / test / verify / ci-local。
- 每個 gate 的 pass condition。
- owner / planner decision。
- readiness blocker handling。
- Test Environment 與 Verify Command。

Repo-wide baseline/env drift 沒 owner 時，新增 prerequisite / wait / baseline decision
或 route refinement；不得把必失敗 task 標 READY。

## User Confirmation Preview

Preview 使用 workspace policy language，包含：

- task summary / points / dependencies / allowed files。
- readiness / gate closure 摘要。
- JIRA sub-task list。
- branch chain high-level summary。
- any blockers / route-back decisions。

使用者確認前不可寫 JIRA、branch、task.md。

## JIRA Writes

確認後：

1. 用 `jira-story-points.md` 查 Story Points 欄位 ID。
2. 用 `jira-subtask-creation.md` 批次建立 sub-tasks。
3. 更新母單 estimate 並回查驗證。
4. 寫完成回報與 AC traceability matrix。
5. 必要時整合母單 description，但實作細節放子單 description，不污染母單。

接著進 `breakdown-task-packaging.md` 建 branch / task.md / V*.md。
