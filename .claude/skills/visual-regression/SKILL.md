---
name: visual-regression
description: >
  Visual regression guard using before/after screenshot comparison. Two modes: SIT (compare staging vs local dev)
  or Local (compare git-stashed base vs current changes). No long-lived baselines — captures fresh screenshots
  each run and deletes after comparison. Config-driven from workspace-config.yaml.
  Use when: "跑 visual regression", "檢查畫面", "頁面有沒有壞", "visual test", "screenshot test",
  "畫面測試", "截圖比對", "有沒有跑版", "畫面壞了嗎", "UI 有沒有問題", "check if pages look right",
  or when engineering detects visual_regression enabled on the current domain.
---

# Visual Regression

Before/after screenshot comparison guard。每次執行都抓 fresh before / after
screenshots，使用 Playwright diff，分析後刪除 temporary snapshots 與 test results；
不維護 long-lived baselines。

## Contract

VR 的測試單位是 domain，不是 repo。頁面由 configured URL paths 定義；不可因「頁面不在
目前 repo」而 skip。合法 skip 僅限 config 缺漏、dependency declined、clean local tree、
smart-skip 判斷無 visual impact、fixture 未建立、已知 SSR hang、環境依賴缺失。

VR 在 quality chain 中回答：「既有頁面是否仍 visually intact？」它不取代 Local CI Mirror，
也不取代 feature behavior verification。

## Reference Loading

依執行情境讀取：

| Situation | Load |
|---|---|
| Any VR run | `visual-regression-principles.md`, `visual-regression-preflight-flow.md`, `visual-regression-config.md`, `workspace-config-reader.md` |
| Screenshot execution | `visual-regression-capture-flow.md`, `dependency-consent.md` |
| Fixtures enabled | `api-contract-guard.md`, `visual-regression-fixture-flow.md`, `epic-folder-structure.md` |
| Analysis or JIRA report | `visual-regression-analysis-reporting.md`, `vr-jira-report-template.md`, `workspace-language-policy.md` |
| Engineering-triggered gate | `engineer-delivery-flow.md`, `visual-regression-analysis-reporting.md` |

JIRA report、Slack summary，或任何 external write body 送出前，必須依
`workspace-language-policy.md` 或 external write gate 驗證語言。

## Flow

1. 解析 domain 與 company config，套用 root defaults inheritance。
2. 檢查 visual regression 是否已設定；未設定則 stop，不 improvisation。
3. 執行 smart skip、dependency consent、Playwright/toolchain readiness。
4. 決定 SIT 或 Local comparison path；SIT 不可達時依 reference fallback。
5. 透過 `polaris-env.sh` 啟動 production-equivalent proxy 與 dev environment。
6. Fixtures active 時先跑 API contract guard。
7. Capture before screenshots，capture after screenshots，讓 Playwright compare。
8. 分析結果、套用 first-run quality gate、必要時上傳 artifacts 並寫 JIRA wiki report。
9. 無論 pass/fail/error 都 cleanup，保護 git stash、server state、temporary snapshots。

## Hard Rules

- Always go through production-equivalent proxy；不可直接打 app dev port 迴避 routing。
- CSR content 必須等 deterministic selector，不使用 fixed timeout 當 readiness。
- UA-based mobile SSR 必須設定 mobile user agent，不只設 viewport。
- Fixtures active 時為 strict mode：任何 diff 都不是 data variance。
- First run after fixture setup/change 必須 human screenshot review；zero-diff 不代表截圖正確。
- Playwright tests 必須 sequential，`workers: 1`。
- JIRA inline screenshot report 使用 REST API v2 wiki markup，不使用 MCP markdown comment。

## Completion

Standalone run 回報 domain、comparison path、pages count、diff summary、HTML report path、
cleanup status。Engineering-triggered run 回傳 `PASS`、`PASS_WITH_DIFFS`、或 `BLOCK`。

## Post-Task Reflection (required)

若本次修改 config、fixtures、JIRA report、或 framework references，final response 前執行
`post-task-reflection-checkpoint.md`。
