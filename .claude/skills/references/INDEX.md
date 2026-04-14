# References Index

Skill 執行前掃描本 index，根據 description 和 triggers 判斷相關性，拉入相關 reference 後再開始。

## JIRA Operations

| File | Description | Triggers |
|------|-------------|----------|
| [jira-story-points.md](jira-story-points.md) | Story Points 欄位 ID 動態探測與讀寫驗證 | breakdown, jira-subtask-creation, editJiraIssue with SP |
| [jira-subtask-creation.md](jira-subtask-creation.md) | 批次建 JIRA 子單流程：查既有→建單→估點→測試計畫→驗收 | breakdown, createJiraIssue, engineering |
| [epic-verification-structure.md](epic-verification-structure.md) | 驗收架構：測試計畫/AC 驗證分離、測試 Sub-task、驗收單 lifecycle | breakdown, jira-subtask-creation, engineering |
| [epic-verification-workflow.md](epic-verification-workflow.md) | Epic 驗證完整流程：fixture lifecycle、VR gate、feature branch flow | breakdown, git-pr-workflow, visual-regression, converge, epic-status |
| [pipeline-handoff.md](pipeline-handoff.md) | Pipeline 角色邊界與 handoff contract：breakdown/engineering/verify-AC/bug-triage + task.md schema + AC-FAIL disposition gate | breakdown, engineering, verify-AC, bug-triage, refinement |
| [decision-audit-trail.md](decision-audit-trail.md) | JIRA Decision Record comment 格式與寫入規則 | breakdown, sasd-review |

## Estimation & Planning

| File | Description | Triggers |
|------|-------------|----------|
| [estimation-scale.md](estimation-scale.md) | Story point scale (1/2/3/5/8/13) 定義與時程換算 | breakdown, engineering estimation phase |
| [epic-template.md](epic-template.md) | Epic description 結構化模板與 readiness checklist | refinement, breakdown, PM epic quality review |
| [project-mapping.md](project-mapping.md) | JIRA ticket → local project 目錄對應（config-first） | breakdown, sasd-review, engineering |
| [refinement-artifact.md](refinement-artifact.md) | Refinement 結構化 artifact JSON schema — 供 breakdown/estimation/engineering 消費 | refinement (Tier 2+), breakdown, engineering |
| [confidence-labeling.md](confidence-labeling.md) | AI 研究產出信心標示（HIGH/MEDIUM/LOW/NOT_RESEARCHED） | refinement (Tier 3), breakdown (scope-challenge), learning, sasd-review |

## Delivery Flow

| File | Description | Triggers |
|------|-------------|----------|
| [engineer-delivery-flow.md](engineer-delivery-flow.md) | 工程師交付 backbone：Simplify → Quality → Behavioral Verify → Review → Rebase → Commit → PR。Developer（engineering）與 Admin（git-pr-workflow）共用 | engineering, git-pr-workflow |
| [quality-check-flow.md](quality-check-flow.md) | lint / test / coverage / risk scoring 自檢流程。engineer-delivery-flow Step 2 消費 | engineering, git-pr-workflow（透過 engineer-delivery-flow） |

## PR & Git

| File | Description | Triggers |
|------|-------------|----------|
| [pr-body-builder.md](pr-body-builder.md) | PR template 偵測、body 組裝、AC Coverage、母單 PR、Bug RCA 偵測 | engineering, git-pr-workflow（透過 engineer-delivery-flow Step 7） |
| [branch-creation.md](branch-creation.md) | JIRA ticket → branch 建立流程（含 dependency branch 偵測） | engineering, git-pr-workflow |
| [cascade-rebase.md](cascade-rebase.md) | Feature branch PR stack 的 cascade rebase 邏輯 | git-pr-workflow, fix-pr-review, check-pr-approvals |
| [feature-branch-pr-gate.md](feature-branch-pr-gate.md) | Task PR 全 merge 後自動建 feature→develop PR 的偵測邏輯 | epic-status, git-pr-workflow, check-pr-approvals, engineering |
| [pr-input-resolver.md](pr-input-resolver.md) | PR URL/number/branch → owner+repo+number 解析 | review-pr, fix-pr-review, check-pr-approvals |
| [stale-approval-detection.md](stale-approval-detection.md) | PR approval 失效偵測：approved before last push = 無效 | check-pr-approvals, review-inbox, epic-status |

## Slack Integration

| File | Description | Triggers |
|------|-------------|----------|
| [slack-message-format.md](slack-message-format.md) | Slack mrkdwn 格式規則：URL 換行、bold/italic、長度限制 | 任何 slack_send_message, review-inbox, standup |
| [slack-pr-input.md](slack-pr-input.md) | 從 Slack thread 提取 GitHub PR URL | review-pr, fix-pr-review, review-inbox |
| [github-slack-user-mapping.md](github-slack-user-mapping.md) | GitHub username → Slack user ID 的 4 步查找鏈 | review-inbox, review-pr, fix-pr-review, check-pr-approvals |

## Sub-agent & Exploration

| File | Description | Triggers |
|------|-------------|----------|
| [sub-agent-roles.md](sub-agent-roles.md) | Sub-agent dispatch 標準：completion envelope、model tier、QA/Architect/Critic | 任何 skill 啟動 sub-agent |
| [explore-pattern.md](explore-pattern.md) | Adaptive codebase 探索模式：handbook-first → 小範圍直讀 / 大範圍平行 sub-agent → handbook 回寫 | refinement (Tier 2+), sasd-review, breakdown, systematic-debugging, engineering, bug-triage |

## Testing & VR

| File | Description | Triggers |
|------|-------------|----------|
| [tdd-smart-judgment.md](tdd-smart-judgment.md) | 逐檔判斷是否適用 TDD（testable vs config/style/type-def） | unit-test, engineering, bug-triage |
| [api-contract-guard.md](api-contract-guard.md) | Mockoon fixture vs live API schema drift 偵測：分類、流程、skill 接入點 | visual-regression, engineering |
| [visual-regression-config.md](visual-regression-config.md) | VR config schema：domain、server、fixtures、pages、viewports | visual-regression, /init VR setup |
| [vr-jira-report-template.md](vr-jira-report-template.md) | VR 結果 JIRA comment 的 wiki markup 模板 | visual-regression, engineering |

## Repo Knowledge

| File | Description | Triggers |
|------|-------------|----------|
| [repo-handbook.md](repo-handbook.md) | Per-repo coding 準則：repo 類型辨識、handbook 結構生成、standard-first 校準、stale detection | init (optional), engineering (Phase 0.5), review-pr (Step 3), fix-pr-review (Step 5 + 7b), git-pr-workflow (post-PR) |

## Config & Infrastructure

| File | Description | Triggers |
|------|-------------|----------|
| [workspace-config-reader.md](workspace-config-reader.md) | 兩層 config 解析流程（root + company）與完整欄位索引 | 所有需要讀 config 的 skill |
| [shared-defaults.md](shared-defaults.md) | 跨 skill 共用預設值（Slack channels、JIRA、GitHub、infra） | 所有讀 workspace-config 的 skill |
| [dependency-consent.md](dependency-consent.md) | Optional dependency 的使用者同意管理（playwright、mockoon-cli） | /init, visual-regression, e2e |
| [polaris-project-dir.md](polaris-project-dir.md) | ~/.polaris/projects/$SLUG/ 目錄結構與 slug 解析 | polaris-learnings.sh, polaris-timeline.sh |

## Confluence & Docs

| File | Description | Triggers |
|------|-------------|----------|
| [confluence-page-update.md](confluence-page-update.md) | Confluence 頁面搜尋、讀取、追加內容的共用流程 | standup, sprint-planning, sasd-review |
| [sasd-confluence.md](sasd-confluence.md) | SA/SD Confluence 存放位置（space/folder/年份子頁面） | sasd-review |

## Session & Learning

| File | Description | Triggers |
|------|-------------|----------|
| [review-lesson-extraction.md](review-lesson-extraction.md) | PR review 萃取共用邏輯：sub-agent prompt、dedup、寫入格式、graduation | learning (PR/Batch mode), review-pr Step 6.5 |
| [cross-session-learnings.md](cross-session-learnings.md) | JSONL 知識庫 schema 與跨 session 技術洞察持久化規則 | post-task-reflection, session-start |
| [session-timeline.md](session-timeline.md) | JSONL 事件日誌 schema 與 polaris-timeline.sh 介面 | standup, checkpoint, skill invocation logging |
| [post-task-reflection-checkpoint.md](post-task-reflection-checkpoint.md) | 所有 write skill 的最終步驟 checklist：feedback、learning、mechanism audit | 每個 write skill 的最後一步 |
| [daily-learning-scan-spec.md](daily-learning-scan-spec.md) | 每日技術文章掃描器的 RemoteTrigger 規格模板 | learning setup, schedule daily scan |
| [learning-queue.md](learning-queue.md) | 待閱讀技術文章清單（data file） | learning, daily-learning-scan |
| [learning-archive.md](learning-archive.md) | 已處理 URL 去重 archive（data file） | daily-learning-scan, learning setup |

## Framework Meta

| File | Description | Triggers |
|------|-------------|----------|
| [challenger-audit.md](challenger-audit.md) | 多角色 UX 審查系統，pre-release 時使用 | challenger, version-release |
| [docs-editorial-guideline.md](docs-editorial-guideline.md) | README/docs 文風規範：結論先行、show don't tell、structured vs editorial 分層 | docs-sync, version-bump README update |
