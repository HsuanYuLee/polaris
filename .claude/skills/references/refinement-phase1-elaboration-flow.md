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

產生 preview / `refinement.md` 前先讀 `authoring-preflight.md`，並使用
`workspace-language-policy.md` 解析出的 root `language` 直接起稿；language gate 不是最後翻譯器。

輸出：

- PM questions，最多 3-5 個。
- RD risks 與 mitigation。
- affected repos / modules。
- technical approach。
- AC / edge cases / risks / pending decisions。
- suggested task structure（不估點、不建子單）。

Suggested task structure 必須先讀 `infra-first-decision.md`：用
`acceptance_criteria[].verification.method` 判斷是否需要 Mockoon fixtures、VR baseline
或 stable data seed 等 infra prerequisite。沒有 `refinement.json` 或 AC verification method
不足時要明確標示 skipped / warning，不得只因 visual regression config 存在就預覽 fixture task。

Suggested task structure 也必須先讀 `stacked-delivery-sibling-epic-policy.md`，並把 draft task
structure 交給 lens：

```bash
node scripts/detect-stacked-delivery-lane.mjs --input <task-draft.json>
```

若 task draft 只有 markdown preview，先用 text mode 取得 advisory signal：

```bash
node scripts/detect-stacked-delivery-lane.mjs --text <preview.md>
```

判定方式：

- `ok`：照原 flow 產 suggested task structure。
- `advisory`：preview 必須列出 sibling Epic 候選、feat task owner、umbrella residual ownership。
- `required`：preview 不得把 `TXa~TXn` 直接當原 Epic child task 定版；先請使用者確認拆
  sibling Epic 或留下 explicit override decision。
- `overridden`：preview 必須保留 override reason。

寫入 `{source_container}/refinement.md`，只放下游需要的 decision，不放完整討論過程。
若本輪產生 JIRA comment draft、external write body、manual validation output 或 data
investigation notes，依 `refinement-research-container.md` close out 到 source container 的
`jira-comments/`、`artifacts/external-writes/` 或 `artifacts/research/`；不得把
`.codex/external-writes/` 當作 durable storage。
啟動或重用 docs-manager：

```bash
bash scripts/polaris-toolchain.sh run docs.viewer.dev
```

多輪迭代只更新 local markdown，不寫 JIRA / artifact。

## Step 6. Finalize

使用者說「定版」、「寫回 JIRA」、「OK 了」、「可以進 breakdown」後：

1. JIRA-backed source：以 final `refinement.md` 寫 JIRA comment / label / description。
2. 依 `refinement-artifact.md` 產 `{source_container}/refinement.json`。
3. 確認 external write drafts / validation outputs 已歸檔到 source container 或刪除 temporary body file。
4. 跑 `refinement-handoff-gate.sh`。
5. 跑 language / Starlight gates。
6. 才提示 `breakdown {SOURCE}`。

這個 finalize contract 適用於所有 refinement-owned JIRA sources，不只 Epic。若 Story /
Task 被 refinement 充實後才進 breakdown，同樣必須先有 current `refinement.md` 與
`refinement.json`。Bug 不走本 flow；Bug 先由 `bug-triage` 寫 confirmed RCA handoff。
