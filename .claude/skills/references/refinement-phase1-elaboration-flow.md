---
title: "Refinement Phase 1 Elaboration Flow"
description: "refinement Phase 1：JIRA Epic 需求充實、codebase exploration、AC hardening、local preview 與定版 artifact。"
---

# Phase 1 Elaboration Flow

## Step 1. Context Gathering

所有 Tier 讀 JIRA Summary / Description / AC / Comments / Linked Issues / Figma。

Tier 2+：

- 用 `project-mapping.md` 找 project。
- 讀 repo handbook。
- 查 cross-session learnings：

  ```bash
  POLARIS_WORKSPACE_ROOT={workspace_root} polaris-learnings.sh query --top 5 --min-confidence 3
  ```

Tier 3：讀外部 URL / Figma / Google Docs，所有研究附 `confidence-labeling.md`。

## Step 2. Codebase Exploration And Completeness

Tier 2+ 用 `explore-pattern.md` 探索：

- 相關現有實作。
- module / repo 影響範圍。
- hidden complexity。
- test gap。

Worktree sub-agent 要用 main checkout 絕對路徑，見 `worktree-dispatch-paths.md`。

涉及 SSR、結構化資料、API output 等 runtime 行為時，用 curl / dev server 驗證；runtime
結果與源碼分析矛盾時，以 runtime 為準。

完整性檢查項目：

- 背景與目標。
- AC。
- Scope。
- Edge cases。
- Figma / design。
- API docs。
- dependencies。
- out of scope。

## Step 3. Solution Research

Tier 3 only：

- 分析 PM 提供的範例網站。
- 搜尋 industry standard。
- 比對 codebase current state。
- 提供 2-3 個 option，附 approach、pros/cons、effort、risk、confidence。

AI 不直接替 RD / PM 做最終結論；列選項與 trade-offs。

## Step 4. AC Hardening

將模糊 AC 轉成可驗收；這個 hardened template 適用於所有 refinement-owned source，不因
JIRA Epic、Story、Task 或 ticketless / DP-backed source 而改變：

- 功能 AC。
- 非功能 AC（performance / SEO / a11y only if relevant）。
- 負面 AC。
- 每條 AC 附驗證方式：playwright / lighthouse / curl / unit_test / manual。

輸出 contract：

- `refinement.md` 必須明確保留 `功能 AC`、`非功能 AC`、`負面 AC` 與 `驗證方式`。
- `refinement.json` 的 `acceptance_criteria[]` 每條都必須能對應回上述其中一類，且保留驗證方式。

## Step 5. Gap Report And Preview

輸出：

- PM questions，最多 3-5 個。
- RD risks 與 mitigation。
- affected repos / modules。
- technical approach。
- AC / edge cases / risks / pending decisions。
- suggested task structure（不估點、不建子單）。

寫入 `{source_container}/refinement.md`，只放下游需要的 decision，不放完整討論過程。
啟動或重用 docs-manager：

```bash
bash scripts/polaris-toolchain.sh run docs.viewer.dev
```

多輪迭代只更新 local markdown，不寫 JIRA / artifact。

## Step 6. Finalize

使用者說「定版」、「寫回 JIRA」、「OK 了」、「可以進 breakdown」後：

1. JIRA-backed source：以 final `refinement.md` 寫 JIRA comment / label / description。
2. 依 `refinement-artifact.md` 產 `{source_container}/refinement.json`。
3. 跑 `refinement-handoff-gate.sh`。
4. 跑 language / Starlight gates。
5. 才提示 `breakdown {SOURCE}`。

這個 finalize contract 適用於所有 refinement-owned JIRA sources，不只 Epic。若 Story /
Task 被 refinement 充實後才進 breakdown，同樣必須先有 current `refinement.md` 與
`refinement.json`。Bug 不走本 flow；Bug 先由 `bug-triage` 寫 confirmed RCA handoff。
