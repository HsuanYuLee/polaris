# References Index

Skill 執行前掃描本 index，根據 description 和 triggers 判斷相關性，拉入相關 reference 後再開始。

## JIRA Operations

| File | Description | Triggers |
|------|-------------|----------|
| [jira-story-points.md](jira-story-points.md) | Story Points 欄位 ID 動態探測與讀寫驗證 | breakdown, jira-subtask-creation, editJiraIssue with SP |
| [jira-subtask-creation.md](jira-subtask-creation.md) | 批次建 JIRA 子單流程：查既有→建單→估點→測試計畫→驗收 | breakdown, createJiraIssue, engineering |
| [epic-verification-structure.md](epic-verification-structure.md) | 驗收架構：測試計畫/AC 驗證分離、測試 Sub-task、驗收單 lifecycle | breakdown, jira-subtask-creation, engineering |
| [epic-verification-workflow.md](epic-verification-workflow.md) | Epic 驗證完整流程：fixture lifecycle、VR gate、feature branch flow | breakdown, engineering, visual-regression, converge |
| [pipeline-handoff.md](pipeline-handoff.md) | Pipeline 角色邊界與 handoff contract：breakdown/engineering/verify-AC/bug-triage + task.md schema + AC-FAIL disposition gate | breakdown, engineering, verify-AC, bug-triage, refinement |
| [escalation-flavor-guide.md](escalation-flavor-guide.md) | Engineering scope-escalation sidecar 的 flavor 分類決策樹（plan-defect / scope-drift / env-drift）+ worked examples | engineering（寫 sidecar）, breakdown（intake path 重新分類） |
| [refinement-return-inbox.md](refinement-return-inbox.md) | breakdown route refinement 時的 inbox record 契約；refinement 只讀 inbox、不讀 engineering raw sidecar | breakdown（route refinement）, refinement（return inbox intake）, engineering（lineage cap routing） |
| [handoff-artifact.md](handoff-artifact.md) | Pipeline handoff evidence artifact 格式（Summary/Raw Evidence、20KB cap、secret scrub、on-demand read） | bug-triage, engineering, verify-AC（producer or consumer of handoff artifact） |
| [decision-audit-trail.md](decision-audit-trail.md) | JIRA Decision Record comment 格式與寫入規則 | breakdown, sasd-review |

## Estimation & Planning

| File | Description | Triggers |
|------|-------------|----------|
| [estimation-scale.md](estimation-scale.md) | Story point scale (1/2/3/5/8/13) 定義與時程換算 | breakdown, engineering estimation phase |
| [epic-template.md](epic-template.md) | Epic description 結構化模板與 readiness checklist | refinement, breakdown, PM epic quality review |
| [project-mapping.md](project-mapping.md) | JIRA ticket → local project 目錄對應（config-first） | breakdown, sasd-review, engineering |
| [refinement-artifact.md](refinement-artifact.md) | Refinement 結構化 artifact JSON schema — 供 breakdown/estimation/engineering 消費 | refinement (Tier 2+), breakdown, engineering |
| [spec-source-resolver.md](spec-source-resolver.md) | JIRA / DP-NNN / ticketless topic / artifact path 的共用 source resolution contract，含 DP locator、artifact path、section ownership | refinement, breakdown, engineering, verify-AC |
| [refinement-dp-source-mode.md](refinement-dp-source-mode.md) | refinement ticketless / DP-backed source mode 操作細節：DP creation、docs-manager preview、artifact output、LOCKED handoff | refinement DP-NNN, ticketless topic, design plan, ADR, DP artifact_path |
| [confidence-labeling.md](confidence-labeling.md) | AI 研究產出信心標示（HIGH/MEDIUM/LOW/NOT_RESEARCHED） | refinement (Tier 3), breakdown (scope-challenge), learning, sasd-review |

## Delivery Flow

| File | Description | Triggers |
|------|-------------|----------|
| [engineer-delivery-flow.md](engineer-delivery-flow.md) | 工程師交付 backbone：Simplify → Local CI Mirror (`ci-local.sh`) → Behavioral Verify → Review → Rebase → Commit → PR。由 engineering 消費，含 Developer 與 Local Extension role | engineering |
| [ci-local-env-blocker.md](ci-local-env-blocker.md) | Local CI mirror 的 `BLOCKED_ENV` status、environment blocker reason enum、classifier adapter contract、secret scrub 與 gate semantics | engineering, ci-local, completion-gate |

## PR & Git

| File | Description | Triggers |
|------|-------------|----------|
| [pr-body-builder.md](pr-body-builder.md) | PR template 偵測、body 組裝、AC Coverage、母單 PR、Bug RCA 偵測 | engineering（透過 engineer-delivery-flow Step 7） |
| [commit-convention-default.md](commit-convention-default.md) | Commit message L3 兜底規範（L1 tooling / L2 handbook / L3 default fallback chain；type enum；`{TICKET}` 推導；multi-commit；revision 規格） | engineering（透過 engineer-delivery-flow Step 6a） |
| [changeset-convention-default.md](changeset-convention-default.md) | Changeset L3 兜底規範（filename slug、frontmatter `{package}: patch` default、description = task title、`ticket_prefix_handling=strip` default、idempotent skip） | engineering, breakdown（task.md `deliverables.changeset` 宣告生產端） |
| [branch-creation.md](branch-creation.md) | JIRA ticket / DP task → branch 建立流程（含 dependency branch 偵測） | engineering |
| [cascade-rebase.md](cascade-rebase.md) | Feature branch PR stack 的 cascade rebase 邏輯 | engineering, check-pr-approvals |
| [feature-branch-pr-gate.md](feature-branch-pr-gate.md) | Task PR 全 merge 後自動建 feature→develop PR 的偵測邏輯 | converge, check-pr-approvals, engineering |
| [pr-input-resolver.md](pr-input-resolver.md) | PR URL/number/branch → owner+repo+number 解析 | review-pr, engineering, check-pr-approvals |
| [stale-approval-detection.md](stale-approval-detection.md) | PR approval 失效偵測：approved before last push = 無效 | check-pr-approvals, review-inbox, converge |

## Slack Integration

| File | Description | Triggers |
|------|-------------|----------|
| [slack-message-format.md](slack-message-format.md) | Slack mrkdwn 格式規則：URL 換行、bold/italic、長度限制 | 任何 slack_send_message, review-inbox, standup |
| [slack-pr-input.md](slack-pr-input.md) | 從 Slack thread 提取 GitHub PR URL | review-pr, engineering, review-inbox |
| [github-slack-user-mapping.md](github-slack-user-mapping.md) | GitHub username → Slack user ID 的 4 步查找鏈 | review-inbox, review-pr, engineering, check-pr-approvals |

## Sub-agent & Exploration

| File | Description | Triggers |
|------|-------------|----------|
| [model-tier-policy.md](model-tier-policy.md) | 跨 LLM model selection policy：semantic classes、Codex / Claude runtime mapping、approved small-model candidates、risk gates、effort 分離 | sub-agent dispatch, model tier, small_fast, realtime_fast, model override |
| [sub-agent-roles.md](sub-agent-roles.md) | Sub-agent dispatch 標準：completion envelope、model tier、QA/Architect/Critic | 任何 skill 啟動 sub-agent |
| [sub-agent-reference.md](sub-agent-reference.md) | Sub-agent 輔助參考：model tier 表、T1/T2/T3 決策分類、self-regulation scoring、pipeline restore points、fan-in validation、write isolation model、safety hooks | 任何 skill 啟動 sub-agent, engineering batch mode, parallel sub-agent dispatch |
| [explore-pattern.md](explore-pattern.md) | Adaptive codebase 探索模式：handbook-first → 小範圍直讀 / 大範圍平行 sub-agent → handbook 回寫 | refinement (Tier 2+), sasd-review, breakdown, systematic-debugging, engineering, bug-triage |
| [worktree-dispatch-paths.md](worktree-dispatch-paths.md) | Worktree 子代理必須使用主 checkout 絕對路徑存取 gitignored 框架 artifacts（`specs/`、`.claude/skills/`），含 copy-paste dispatch block | engineering, breakdown, verify-AC, refinement, bug-triage, sasd-review（任何 dispatch 子代理進 worktree 且需讀寫 specs/ 的 skill） |

## Testing & VR

| File | Description | Triggers |
|------|-------------|----------|
| [tdd-smart-judgment.md](tdd-smart-judgment.md) | 逐檔判斷是否適用 TDD（testable vs config/style/type-def） | unit-test, engineering, bug-triage |
| [api-contract-guard.md](api-contract-guard.md) | Mockoon fixture vs live API schema drift 偵測：分類、流程、skill 接入點 | visual-regression, engineering |
| [verify-ac-environment-prep.md](verify-ac-environment-prep.md) | verify-AC Step 3 的 local / fixture environment preparation：task.md lookup、worktree dispatch、fixture fallback、start-test-env orchestrator | verify-AC, AC 驗證, fixture, start-test-env |
| [visual-regression-config.md](visual-regression-config.md) | VR config schema：domain、server、fixtures、pages、viewports | visual-regression, /init VR setup |
| [vr-jira-report-template.md](vr-jira-report-template.md) | VR 結果 JIRA comment 的 wiki markup 模板 | visual-regression, engineering |

## Repo Knowledge

| File | Description | Triggers |
|------|-------------|----------|
| [repo-handbook.md](repo-handbook.md) | Per-repo coding 準則：repo 類型辨識、handbook 結構生成、standard-first 校準、stale detection | init (optional), engineering (Phase 0.5), review-pr (Step 3), engineering (Step 5 + 7b) |

## Epic Folder Structure

| File | Description | Triggers |
|------|-------------|----------|
| [epic-folder-structure.md](epic-folder-structure.md) | Epic artifact 統一 folder schema：`docs-manager/src/content/docs/specs/companies/{company}/{EPIC}/` 下 refinement、tasks、tests（lighthouse/mockoon/vr）、verification | breakdown, refinement, engineering, verify-AC, visual-regression, mockoon-runner |

## Config & Infrastructure

| File | Description | Triggers |
|------|-------------|----------|
| [workspace-config-reader.md](workspace-config-reader.md) | 兩層 config 解析流程（root + company）與完整欄位索引 | 所有需要讀 config 的 skill |
| [shared-defaults.md](shared-defaults.md) | 跨 skill 共用預設值（Slack channels、JIRA、GitHub、infra） | 所有讀 workspace-config 的 skill |
| [external-write-gate.md](external-write-gate.md) | 外部寫入前的共用 preflight helper：JIRA / Slack / Confluence / GitHub body file 的 language gate 與 optional Starlight gate | 所有會寫外部 surface 的 skill |
| [dependency-consent.md](dependency-consent.md) | Optional dependency 的使用者同意管理（playwright、mockoon-cli） | /init, visual-regression, e2e |
| [polaris-project-dir.md](polaris-project-dir.md) | ~/.polaris/projects/$SLUG/ 目錄結構與 slug 解析 | polaris-learnings.sh, polaris-timeline.sh |
| [workspace-overlay.md](workspace-overlay.md) | Framework worktree 與 main-checkout overlay 邊界：ignored specs、`.codex/`、local maintainer skills、generated output 的 read-only resolver contract | engineering, framework-release, framework-docs-health, docs-manager |

## Confluence & Docs

| File | Description | Triggers |
|------|-------------|----------|
| [confluence-page-update.md](confluence-page-update.md) | Confluence 頁面搜尋、讀取、追加內容的共用流程 | standup, sprint-planning, sasd-review |
| [sasd-confluence.md](sasd-confluence.md) | SA/SD Confluence 存放位置（space/folder/年份子頁面） | sasd-review |

## Session & Learning

| File | Description | Triggers |
|------|-------------|----------|
| [review-lesson-extraction.md](review-lesson-extraction.md) | PR review 萃取共用邏輯：sub-agent prompt、dedup、寫入 handbook | learning (PR/Batch mode), engineering Step 12.5 |
| [cross-session-learnings.md](cross-session-learnings.md) | JSONL 知識庫 schema 與跨 session 技術洞察持久化規則。含 `plan-gap` / `review-lesson` 標籤規格與 promotion pipeline | post-task-reflection, session-start, engineering (revision mode R3a/R6), learning (--promote) |
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
| [framework-iteration-procedures.md](framework-iteration-procedures.md) | 框架自迭代 procedures：Post-Version-Bump Chain、Backlog Hygiene scan、Validated Pattern Promotion、Framework Experience frontmatter | version-bump, organize-memory, docs-sync, standup (monthly) |
| [feedback-memory-procedures.md](feedback-memory-procedures.md) | Feedback/memory 操作流程：direct rule write、hygiene checks、carry-forward、dedup、backlog format、frontmatter spec、injection scan | post-task-reflection, organize-memory, feedback write, rule promotion |
| [mechanism-rationalizations.md](mechanism-rationalizations.md) | Mechanism Registry 的 Common Rationalizations 查表集 + Deterministic Quality Hooks 技術細節（evidence file spec、bypass flags） | post-task mechanism audit (when drift suspected), hook configuration, verification-evidence debugging |
| [deterministic-hooks-registry.md](deterministic-hooks-registry.md) | Deterministic Quality Hooks 完整表（ID、Rule、Enforcement、Script）— 從 mechanism-registry.md 拆出以降低 rules 載入成本 | hook configuration, hook debugging, validate-mechanisms |
| [library-change-protocol.md](library-change-protocol.md) | 依賴變更完整協議：三層調查、替換/升級評估、Decision Tier、config 系統性排除、workaround 文件標準 | engineering (library evaluation), review-pr (reviewer suggests upgrade), bug-triage (dependency issue) |
| [knowledge-compilation-protocol.md](knowledge-compilation-protocol.md) | Framework 知識編譯協議：Atom vs Derived 邊界、backwrite、parallel naming lock | learning (External mode framework target), docs-sync, framework docs/rules updates |
| [starlight-authoring-contract.md](starlight-authoring-contract.md) | Specs Markdown 的 Starlight authoring contract：frontmatter、description、duplicate H1、producer boundary、validator explicit path、legacy migration | refinement, breakdown, engineering, verify-AC, docs-manager, specs markdown producer |
| [skill-progressive-disclosure.md](skill-progressive-disclosure.md) | Skill slimming 的 progressive disclosure placement policy：SKILL.md / reference / script / DP-memory 邊界、粒度與驗證期待 | skill slimming, framework iteration, refinement, breakdown, engineering, verify-AC, learning |
