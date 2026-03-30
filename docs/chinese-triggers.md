# 中文指令速查表

> Polaris 所有 skill 的中文觸發詞對照。直接輸入中文即可觸發對應功能。
>
> 最後更新：2026-03-30

---

## 1. 開發流程（Development）— 輔助開發

| 功能 | 中文觸發詞 | 英文觸發詞 | 說明 |
|------|-----------|-----------|------|
| **work-on** — 智慧開發路由 | 做 PROJ-123、開始做、接這張、做這張、下一步、繼續 | work on, start dev | 偵測 ticket 狀態，自動路由到估點／拆單／建 branch／開發。支援批次模式（多張 ticket 同時輸入） |
| **fix-bug** — Bug 修正 | 幫我修正 PROJ-123、修 bug、開始修正、修正這張 | fix bug, help me fix, start fixing, fix this ticket | 端到端 bug 修正：讀單→估點→建 branch→TDD 開發→PR |
| **epic-breakdown** — 拆單與估點 | 拆單、拆解、分解任務、子單、評估這張單、評估 epic | break down epic, split tasks, decompose, create sub-tasks, evaluate this ticket | 拆解 Epic 為可執行子任務，逐一估點後批次建立 JIRA sub-task |
| **jira-branch-checkout** — 建 Branch | 開 branch PROJ-123、建 branch、切 branch、hotfix branch | create branch, checkout branch | 從 JIRA ticket 建立命名規範的 git branch（`task/PROJ-123-description`） |
| **start-dev** — 開工轉狀態 | 開始開發、開工、開始 PROJ-123、開工 PROJ-456 | start developing, start working on | 將 JIRA ticket 狀態轉為 In Development |
| **tdd** — TDD 開發循環 | 先寫測試、紅綠燈、TDD | TDD, test driven, test first, red green refactor | 強制執行 Red-Green-Refactor 循環，以測試驅動實作 |
| **git-pr-workflow** — 完整 PR 流程 | 準備發 PR（含品質檢查）、full pr flow | 發 PR, PR workflow, commit and PR, changeset, full pr flow, pull request | 完整 PR 生命週期：品質檢查→AI 迭代審查→commit→changeset→開 PR→轉 JIRA CODE REVIEW |
| **verify-completion** — 行為驗證 | 驗證、確認改好了、真的修好了嗎、驗收 | verify, check it works | 品質檢查通過後的行為驗證，測試實際執行是否正確（dev server、curl、UI render） |
| **dev-quality-check** — 品質檢查 | 品質檢查、測試檢查、跑測試、確認品質 | quality check, coverage check, run tests, check tests, validate | commit 前的品質把關：測試覆蓋率、lint、相關測試執行 |
| **wt-parallel** — 平行工作 | 平行、多個 ticket、拆分 | parallel, worktree, wt | 使用 git worktrees 管理多個平行開發工作 |

---

## 2. 程式碼審查（Code Review）— 輔助開發

| 功能 | 中文觸發詞 | 英文觸發詞 | 說明 |
|------|-----------|-----------|------|
| **review-pr** — 審查別人的 PR | 幫我 review、review 這個 PR、看一下這個 PR、檢查 PR | review PR, code review, take a look at this PR, check this PR | 以 reviewer 角色審查 PR，留 inline comments，提交 APPROVE 或 REQUEST_CHANGES |
| **fix-pr-review** — 修正自己 PR 的 review | 修 PR、修正 review、處理 review、回覆 review、CI 沒過 | fix review, address review, fix PR, CI failed, lint/test/coverage failed, pre-commit failed | 讀取 PR review comments，逐一修正，透過 sub-agent 自我審查，回覆每則 comment |
| **check-pr-approvals** — 我的 PR 狀態 | 我的 PR、PR 狀態、催 review、PR 被 approve 了嗎、幫我掃我的 PR、還有哪些 PR 沒過 | check PR approvals | 掃描自己的 open PR：rebase、自動修 CI 失敗、檢查 approve 數、選擇後發 Slack 催 review |
| **review-inbox** — 掃大家的 PR | 掃 PR、掃大家的 PR、幫我掃、review 大家的 PR、批次 review、有哪些 PR 要我看 | scan PR, review inbox, batch review | 從 Slack channel 或 need-review label 找出需要自己 review 的 PR，批次執行 review |
| **pr-convention** — 簡易開 PR | 發 PR（簡單版，無品質檢查） | open PR, gh pr create, gh pr edit, pull request | 依照 PR template 建立或編輯 PR（簡易版，不含品質檢查；完整流程請用 git-pr-workflow） |
| **review-lessons-graduation** — Review 規則整理 | 整理 review lessons、review lessons 畢業、lesson 整理、畢業 review lessons | organize review lessons, graduate lessons, consolidate lessons, promote review lessons | 將累積的 review-lessons 條目合併進主 rules，保持規則目錄精簡 |

---

## 3. 專案管理（Project Management）— 日常紀錄

| 功能 | 中文觸發詞 | 英文觸發詞 | 說明 |
|------|-----------|-----------|------|
| **refinement** — 需求充實 | 討論需求、需求釐清、補完 Epic、這張單缺什麼、方案討論、想重構、tech debt、sprint prep | refinement, grooming, brainstorm, batch refinement | 四種模式：批次完整度掃描、RD 發起開單（Phase 0）、PM 充實需求（Phase 1）、做法討論（Phase 2） |
| **sprint-planning** — Sprint 規劃 | 排 sprint、sprint 規劃、下個 sprint、排單、capacity planning、carry over | sprint planning, planning, next sprint, organize sprint, release page, sprint backlog | 互動式 Sprint 規劃助手：拉 JIRA tickets、算 capacity、偵測 carry-over、建議優先序 |
| **standup** — 每日站會 | 站立會議、產出 standup、寫 standup、今天做了什麼 | standup, daily standup, YDY, standup report, write standup, daily report | 自動從 git commits、JIRA 狀態、Google Calendar 收集工作，產出 YDY/TDT/BOS 格式站會報告 |
| **jira-estimation** — 估點引擎 | 估點、幫我估、這張幾點（透過 work-on 觸發） | estimate（route via work-on） | 內部估點引擎，由 work-on / fix-bug / epic-breakdown 自動呼叫，不直接觸發 |
| **jira-worklog** — 記工時 | 記工時、記錄工時 | worklog, log time, time tracking, log hours | PR 開出後記錄工時至 JIRA |
| **worklog-report** — 完成報告 | 完成報告 | worklog report, done report, sprint report | 從 JIRA 查詢已完成 tickets，依 assignee 分組後發送 Slack 報告 |
| **scope-challenge** — 需求質疑 | 挑戰需求、需求質疑、需求合理性 | scope challenge, challenge requirements, question requirements, scope review | 在估點前挑戰 ticket scope 合理性，提出替代方案（僅建議，不阻擋流程） |

---

## 4. 品質保障（Quality）— 輔助開發 / 自我學習

| 功能 | 中文觸發詞 | 英文觸發詞 | 說明 |
|------|-----------|-----------|------|
| **systematic-debugging** — 系統化除錯 | 找 bug、為什麼壞了、查問題、這個怎麼回事、根因、排查 | debug, why is this failing, investigate, root cause | 結構化除錯流程：先調查根因再修，避免猜測式修正 |
| **unit-test** — 寫單元測試 | 寫測試、補測試、怎麼測、測試怎麼寫 | write test, add test, mock imports, test store | 專案感知的單元測試指南，含 mock patterns 與最佳實踐（自動偵測 Jest/Vitest） |
| **unit-test-review** — 審查測試品質 | 測試審查、review 測試、測試品質、檢查測試品質 | unit test review, review tests, check test quality, review unit test | 審查現有單元測試品質，產出評分報告與缺漏分析（僅審查，不寫新測試） |
| **learning** — 學習與研究 | 學習、研究一下、借鑑、看看這個、學習 PR、每日學習、消化 queue | learn, research this, learn from PR, daily learning, digest queue, learning queue | 三種模式：研究外部 URL/repo、從已合併 PR 萃取 review patterns、批次消化學習 queue |

---

## 5. 工具與設定（Tools & Config）— 框架管理

| 功能 | 中文觸發詞 | 英文觸發詞 | 說明 |
|------|-----------|-----------|------|
| **init** — 初始化 Workspace | 初始化、設定 workspace、填 config | init, initialize, setup workspace, setup config, configure | 互動式 Workspace 初始化精靈，建立 company 目錄與 workspace-config.yaml |
| **use-company** — 切換公司 | 切換公司、用這間、公司切換、我要做 X 公司的 | use company, switch company, set company, /use-company | 明確設定本次對話的 active company context，避免多公司自動偵測錯誤 |
| **which-company** — 路由診斷 | 哪間公司 | which company, /which-company | 診斷 JIRA ticket 或 project 路由到哪間公司，顯示完整路由解析過程 |
| **validate-isolation** — 隔離檢查 | 檢查隔離 | validate isolation, /validate-isolation | 掃描 workspace 的多公司隔離問題：L2 rules 缺 scope header、memory 缺 company 欄位等 |
| **skill-creator** — 建立 Skill | 建 skill、建立 skill | create skill, skill-creator | 建立、修改或評估 Polaris skill（確保 eval、description 優化與完整流程） |

---

## 快速對照：「我的 PR」 vs 「大家的 PR」

| 情境 | 中文說法 | 路由 skill |
|------|---------|-----------|
| 檢查自己 PR 的 approve 狀態、CI、review comments | 我的 PR、催 review、PR 狀態 | `check-pr-approvals` |
| 看有哪些別人的 PR 需要我 review | 掃 PR、大家的 PR、批次 review | `review-inbox` |
| 幫某個指定 PR 做 code review | review 這個 PR [PR URL]、幫我 review | `review-pr` |
| 修正自己 PR 上的 review comments 或 CI 失敗 | 修 PR、修正 review、CI 沒過 | `fix-pr-review` |

---

## 快速對照：開發流程路由

| 情境 | 中文說法 | 路由 skill |
|------|---------|-----------|
| 什麼都不知道，想開始做某張單 | 做 PROJ-123 | `work-on`（自動判斷下一步） |
| 修一個 JIRA Bug 單 | 修 bug PROJ-123、幫我修正 PROJ-123 | `fix-bug` |
| 拆解 Epic 為子任務 | 拆單 PROJ-123、評估 Epic | `epic-breakdown` |
| 充實需求或討論做法 | 討論需求、方案討論、refinement | `refinement` |
| 建好 code 要發 PR（含品質檢查） | 準備發 PR（full flow）| `git-pr-workflow` |
| 只是簡單開一個 PR | 發 PR | `pr-convention` |
