---
title: "Shared Skill References Index"
description: "Polaris shared skill references 的索引與觸發提示。"
---

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
| [bug-triage-entry-flow.md](bug-triage-entry-flow.md) | bug-triage ticket parsing、Issue Type guard、project mapping、existing ROOT_CAUSE detection、fast-path routing | bug-triage, root cause, bug diagnosis |
| [bug-triage-acfail-flow.md](bug-triage-acfail-flow.md) | bug-triage 處理 verify-AC `[VERIFICATION_FAIL]` Bug 的 feature-branch scoped investigation 與 artifact handoff | bug-triage AC-FAIL, verification fail |
| [bug-triage-root-cause-flow.md](bug-triage-root-cause-flow.md) | bug-triage fast/full path root cause analysis、Explorer boundary、impact/proposed fix schema、evidence artifact | bug-triage RCA, root cause analysis |
| [bug-triage-confirm-handoff-flow.md](bug-triage-confirm-handoff-flow.md) | bug-triage RD confirmation hard stop、JIRA ROOT_CAUSE comment、handbook observations、handoff message、error handling | bug-triage confirm, ROOT_CAUSE, breakdown handoff |
| [intake-triage-input-flow.md](intake-triage-input-flow.md) | intake-triage ticket key/JQL/Slack/Epic input parsing、JIRA fetch、standard record、Epic child convergence、theme/lens detection | intake-triage, intake input, 收單 |
| [intake-triage-scoring-flow.md](intake-triage-scoring-flow.md) | intake-triage readiness、effort、impact lens、dependencies、duplicate risk、hard blockers、verdict matrix、sorting | intake-triage, scoring, 排工 |
| [intake-triage-writeback-flow.md](intake-triage-writeback-flow.md) | intake-triage decision table、RD confirmation、JIRA intake labels/comments、PM Slack summary、workflow handoff | intake-triage writeback, Slack summary, JIRA labels |

## Estimation & Planning

| File | Description | Triggers |
|------|-------------|----------|
| [estimation-scale.md](estimation-scale.md) | Story point scale (1/2/3/5/8/13) 定義與時程換算 | breakdown, engineering estimation phase |
| [epic-template.md](epic-template.md) | Epic description 結構化模板與 readiness checklist | refinement, breakdown, PM epic quality review |
| [project-mapping.md](project-mapping.md) | JIRA ticket → local project 目錄對應（config-first） | breakdown, sasd-review, engineering |
| [breakdown-bug-flow.md](breakdown-bug-flow.md) | breakdown Bug path：讀 bug-triage ROOT_CAUSE、估點、simple bug JIRA write 與 complex bug planning handoff | breakdown bug, ROOT_CAUSE, estimate bug |
| [breakdown-escalation-intake-flow.md](breakdown-escalation-intake-flow.md) | breakdown scope-escalation intake：讀 engineering sidecar、re-classify flavor、closure validation、task/refinement 落地 | breakdown escalation, scope escalation, sidecar |
| [breakdown-dp-intake-flow.md](breakdown-dp-intake-flow.md) | breakdown DP-backed intake：消費 locked DP refinement artifact，產出 DP tasks/T*.md，不寫 JIRA | breakdown DP-NNN, ticketless DP, DP task |
| [breakdown-planning-flow.md](breakdown-planning-flow.md) | breakdown JIRA Story/Task/Epic planning：探索、拆單、Quality Challenge、Constructability Gate、JIRA write | breakdown story, split tasks, sub-tasks |
| [breakdown-task-packaging.md](breakdown-task-packaging.md) | breakdown task packaging：branch DAG、task.md/V*.md schema、validators、engineering handoff | breakdown task.md, branch chain, validate-task-md |
| [breakdown-scope-challenge-flow.md](breakdown-scope-challenge-flow.md) | breakdown advisory scope challenge：完整性檢查、scope challenge、替代方案與下一步路由 | scope challenge, 需求質疑, challenge scope |
| [refinement-artifact.md](refinement-artifact.md) | Refinement 結構化 artifact JSON schema — 供 breakdown/estimation/engineering 消費 | refinement (Tier 2+), breakdown, engineering |
| [spec-source-resolver.md](spec-source-resolver.md) | JIRA / DP-NNN / ticketless topic / artifact path 的共用 source resolution contract，含 DP locator、artifact path、section ownership | refinement, breakdown, engineering, verify-AC |
| [refinement-dp-source-mode.md](refinement-dp-source-mode.md) | refinement ticketless / DP-backed source mode 操作細節：DP creation、docs-manager preview、artifact output、LOCKED handoff | refinement DP-NNN, ticketless topic, design plan, ADR, DP artifact_path |
| [refinement-batch-readiness-flow.md](refinement-batch-readiness-flow.md) | refinement batch readiness scan：批次掃 Epic 完整度、readiness table、JIRA label/comment 與下一步路由 | refinement batch, sprint prep, readiness |
| [refinement-phase0-discovery-flow.md](refinement-phase0-discovery-flow.md) | refinement Phase 0：RD 主動發現 tech debt / code smell / performance issue，分析價值並產 JIRA ticket 草稿 | refinement phase 0, tech debt, 想重構 |
| [refinement-phase1-elaboration-flow.md](refinement-phase1-elaboration-flow.md) | refinement Phase 1：JIRA Epic 需求充實、codebase exploration、AC hardening、local preview 與定版 artifact | refinement phase 1, grooming, 補完 Epic |
| [refinement-phase2-decision-flow.md](refinement-phase2-decision-flow.md) | refinement Phase 2：技術方案討論、trade-off 比較、Decision Record 與 framework contract target-state-first | refinement phase 2, 方案討論, Decision Record |
| [sasd-review-entry-exploration-flow.md](sasd-review-entry-exploration-flow.md) | sasd-review workspace config、ticket fetch、project mapping、requirements analysis、design-first confirmation、codebase exploration | sasd-review, SA/SD, technical design |
| [sasd-review-document-template.md](sasd-review-document-template.md) | sasd-review SA/SD 文件 metadata、required/optional sections、task estimates、timeline、confidence labeling | sasd-review template, implementation plan |
| [sasd-review-publish-flow.md](sasd-review-publish-flow.md) | sasd-review scope calibration、user confirmation、JIRA/Confluence publish、language gate、completion report | sasd-review publish, Confluence SA/SD |
| [confidence-labeling.md](confidence-labeling.md) | AI 研究產出信心標示（HIGH/MEDIUM/LOW/NOT_RESEARCHED） | refinement (Tier 3), breakdown (scope-challenge), learning, sasd-review |

## Delivery Flow

| File | Description | Triggers |
|------|-------------|----------|
| [engineer-delivery-flow.md](engineer-delivery-flow.md) | 工程師交付 backbone：Simplify → Local CI Mirror (`ci-local.sh`) → Behavioral Verify → Review → Rebase → Commit → PR。由 engineering 消費，含 Developer 與 Local Extension role | engineering |
| [ci-local-env-blocker.md](ci-local-env-blocker.md) | Local CI mirror 的 `BLOCKED_ENV` status、environment blocker reason enum、classifier adapter contract、secret scrub 與 gate semantics | engineering, ci-local, completion-gate |
| [engineering-entry-resolution.md](engineering-entry-resolution.md) | engineering entry resolution：resolve authoritative task.md、derive first-cut/revision/local-extension mode、duplicate guard、batch dispatch | engineering, work on, 做, revision |
| [engineering-first-cut-flow.md](engineering-first-cut-flow.md) | engineering first-cut mode：branch/worktree setup、TDD、ci-local、verify、Developer delivery closeout | engineering first-cut, 做 ticket |
| [engineering-local-extension.md](engineering-local-extension.md) | engineering local extension boundary：合法條件、handoff package、extension evidence、metadata closeout | engineering local extension, framework-release |
| [engineering-scope-escalation.md](engineering-scope-escalation.md) | engineering scope escalation：gate failure 需要 planner-owned 欄位變更時的 sidecar schema、validation、halt rules | engineering scope escalation, sidecar |
| [engineering-revision-flow.md](engineering-revision-flow.md) | engineering revision mode：pre-revision rebase、review/CI signal collection、classification、fix, verify, reply, lesson extraction | engineering revision, fix review, PR URL |
| [converge-scan-gap-flow.md](converge-scan-gap-flow.md) | converge workspace config loading、assigned work scan、Epic child expansion、GitHub PR/feature branch scan、gap classification、sorting | converge, 收斂, gap analysis |
| [converge-execution-flow.md](converge-execution-flow.md) | converge confirmation gate、downstream skill routing、parallel safety、dirty worktree handling、sub-agent completion envelope、blocked handling | converge execution, batch push |
| [converge-reporting-flow.md](converge-reporting-flow.md) | converge plan presentation、before/after rescan report、Markdown artifact requirements、Slack review follow-up、completion summary | converge report, epic progress |

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
| [review-pr-entry-fetch-flow.md](review-pr-entry-fetch-flow.md) | review-pr workspace config、Slack PR input、PR resolver、remote mode、fetch-pr-info、large PR strategy | review-pr entry, PR URL, remote review |
| [review-pr-analysis-flow.md](review-pr-analysis-flow.md) | review-pr rules/handbook loading、existing comments dedup、large PR sub-agent analysis、severity calibration | review-pr analysis, code review, severity |
| [review-pr-submit-flow.md](review-pr-submit-flow.md) | review-pr language gate、GitHub review action、inline comments、approve status、Slack notification、handbook calibration | review-pr submit, GitHub review, inline comment |
| [review-pr-rereview-learning-flow.md](review-pr-rereview-learning-flow.md) | review-pr re-review：確認修正、re-approve 判定、false positive / accepted pattern / severity learning | re-review, review learning, re-approve |
| [review-inbox-discovery-flow.md](review-inbox-discovery-flow.md) | review-inbox Label / Slack / Thread discovery、bundled scripts、review_status、scan freshness | review-inbox, 批次 review, 掃 PR |
| [review-inbox-batch-review-flow.md](review-inbox-batch-review-flow.md) | review-inbox candidates list、batch size、concurrency、per-PR review sub-agent dispatch、result fan-in | review-inbox batch review, re-approve, re-review |

## Slack Integration

| File | Description | Triggers |
|------|-------------|----------|
| [slack-message-format.md](slack-message-format.md) | Slack mrkdwn 格式規則：URL 換行、bold/italic、長度限制 | 任何 slack_send_message, review-inbox, standup |
| [slack-pr-input.md](slack-pr-input.md) | 從 Slack thread 提取 GitHub PR URL | review-pr, engineering, review-inbox |
| [github-slack-user-mapping.md](github-slack-user-mapping.md) | GitHub username → Slack user ID 的 4 步查找鏈 | review-inbox, review-pr, engineering, check-pr-approvals |
| [review-inbox-slack-reporting.md](review-inbox-slack-reporting.md) | review-inbox Label summary、Slack/thread replies、GitHub-to-Slack mapping、language gate、conversation summary | review-inbox Slack notification, thread reply |

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
| [unit-test-detection-tdd-flow.md](unit-test-detection-tdd-flow.md) | unit-test framework detection、repo-specific command selection、TDD applicability、red/green/refactor cycle、cycle log | unit-test, TDD, 紅綠燈 |
| [unit-test-framework-patterns.md](unit-test-framework-patterns.md) | unit-test Jest/Vitest/Vue component/store/composable/mock/async 測試 pattern 與範例 | unit-test examples, mock imports |
| [unit-test-strategy-coverage.md](unit-test-strategy-coverage.md) | unit-test test target selection、coverage expectations、quality review checklist、anti-patterns、skipped-test rationale | unit-test review, coverage |
| [api-contract-guard.md](api-contract-guard.md) | Mockoon fixture vs live API schema drift 偵測：分類、流程、skill 接入點 | visual-regression, engineering |
| [verify-ac-entry-flow.md](verify-ac-entry-flow.md) | verify-AC input disambiguation、Epic expansion、depends_on ordering、loop-count warning、handoff artifact on-demand read | verify-AC, AC 驗證, Epic 驗收 |
| [verify-ac-environment-prep.md](verify-ac-environment-prep.md) | verify-AC Step 3 的 local / fixture environment preparation：task.md lookup、worktree dispatch、fixture fallback、start-test-env orchestrator | verify-AC, AC 驗證, fixture, start-test-env |
| [verify-ac-execution-flow.md](verify-ac-execution-flow.md) | verify-AC step parsing、environment prep、step execution、PASS/FAIL/MANUAL_REQUIRED/UNCERTAIN classification、evidence collection | verify-AC execution, 驗收步驟 |
| [verify-ac-reporting-flow.md](verify-ac-reporting-flow.md) | verify-AC overall verdict、JIRA wiki report、language gate、PASS transition、Epic implemented marking、PENDING handling | verify-AC report, JIRA 驗證結果 |
| [verify-ac-disposition-flow.md](verify-ac-disposition-flow.md) | verify-AC FAIL disposition：implementation drift per-AC Bug、spec issue refinement route、handoff artifact、互斥分流 | verify-AC FAIL, VERIFICATION_FAIL, disposition |
| [verify-ac-learning-lifecycle-flow.md](verify-ac-learning-lifecycle-flow.md) | verify-AC verify-ac-gap learning、post-task reflection、re-verify trigger、opportunistic state-check surfacing | verify-AC learning, re-verify |
| [visual-regression-config.md](visual-regression-config.md) | VR config schema：domain、server、fixtures、pages、viewports | visual-regression, onboard VR setup |
| [visual-regression-principles.md](visual-regression-principles.md) | visual-regression domain-level testing、production proxy、CSR readiness、mobile UA、fixture strictness、first-run gate | visual-regression, screenshot test, VR principles |
| [visual-regression-preflight-flow.md](visual-regression-preflight-flow.md) | visual-regression preflight：domain resolution、config inheritance、smart skip、dependency consent、comparison path、environment setup | visual-regression preflight, SIT mode, Local mode |
| [visual-regression-capture-flow.md](visual-regression-capture-flow.md) | visual-regression before/after capture、Local stash flow、Playwright compare、temporary artifacts | visual-regression capture, Playwright screenshot |
| [visual-regression-analysis-reporting.md](visual-regression-analysis-reporting.md) | visual-regression result analysis、strict fixture mode、diff classification、artifact upload、JIRA wiki report、cleanup、engineering return | visual-regression report, JIRA VR, diff classification |
| [visual-regression-fixture-flow.md](visual-regression-fixture-flow.md) | visual-regression Mockoon Record → Compare workflow、per-epic fixture lifecycle、edge cases、troubleshooting | visual-regression fixtures, Mockoon record, re-record fixture |
| [vr-jira-report-template.md](vr-jira-report-template.md) | VR 結果 JIRA comment 的 wiki markup 模板 | visual-regression, engineering |

## Repo Knowledge

| File | Description | Triggers |
|------|-------------|----------|
| [repo-handbook.md](repo-handbook.md) | Per-repo coding 準則：repo 類型辨識、handbook 結構生成、standard-first 校準、stale detection | onboard (optional), engineering (Phase 0.5), review-pr (Step 3), engineering (Step 5 + 7b) |

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
| [dependency-consent.md](dependency-consent.md) | Optional dependency 的使用者同意管理（playwright、mockoon-cli） | onboard, visual-regression, e2e |
| [onboard-interaction-patterns.md](onboard-interaction-patterns.md) | onboard smartSelect、AI repo detection、audit trail 與 sub-agent Completion Envelope 規則 | onboard, setup workspace, company onboarding |
| [onboard-core-workflow.md](onboard-core-workflow.md) | onboard 核心公司設定流程：precheck、language、company basics、GitHub、JIRA、Confluence、Slack、Kibana、projects、scrum、infra、write | onboard, rerun setup, setup company |
| [onboard-runtime-setup-flow.md](onboard-runtime-setup-flow.md) | onboard dev environment runtime contract：start command、ready signal、health check、requires、validation | onboard Step 9a, dev environment, runtime contract |
| [onboard-visual-regression-setup.md](onboard-visual-regression-setup.md) | onboard visual regression setup：domain mapping、key pages、SIT URL、locale、Playwright tooling generation | onboard Step 9b, visual regression setup |
| [onboard-post-setup-flow.md](onboard-post-setup-flow.md) | onboard post-setup：repo clone、genericize mapping、MCP health、daily learning、toolchain、Codex bootstrap、handbook generation | onboard post setup, codex bootstrap, handbook |
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
| [memory-tiering-contract.md](memory-tiering-contract.md) | Hot/Warm/Cold memory lifecycle：tier 定義、write discipline、decay migration、與 polaris-learnings.sh 邊界 | memory tiering, memory hygiene, MEMORY.md, post-task-reflection |
| [session-timeline.md](session-timeline.md) | JSONL 事件日誌 schema 與 polaris-timeline.sh 介面 | standup, checkpoint, skill invocation logging |
| [post-task-reflection-checkpoint.md](post-task-reflection-checkpoint.md) | 所有 write skill 的最終步驟 checklist：feedback、learning、mechanism audit | 每個 write skill 的最後一步 |
| [checkpoint-save-flow.md](checkpoint-save-flow.md) | checkpoint save mode 的狀態收集、checkpoint note、timeline checkpoint/session_summary 寫入、使用者確認格式 | checkpoint save, 存檔 |
| [checkpoint-carry-forward-flow.md](checkpoint-carry-forward-flow.md) | checkpoint save mode 的 cross-session carry-forward validator、exit code handling、pending item disposition、retry 規則 | checkpoint carry-forward, pending items |
| [checkpoint-resume-list-flow.md](checkpoint-resume-list-flow.md) | checkpoint resume/list mode 的 timeline query、checkpoint selection、branch verification、context restore、output table 格式 | checkpoint resume, list checkpoints |
| [my-triage-resume-flow.md](my-triage-resume-flow.md) | my-triage zero-input routing、branch-ticket context、Hot memory、recent checkpoints、WIP branch scan、resume candidate 排序 | my-triage resume, 下一步, 繼續 |
| [my-triage-dashboard-flow.md](my-triage-dashboard-flow.md) | my-triage assigned work JIRA scan、status verification、GitHub progress enrichment、grouping/sorting、dashboard output | my-triage dashboard, 我的工作 |
| [my-triage-state-flow.md](my-triage-state-flow.md) | my-triage `.daily-triage.json` schema、寫入時機、standup TDT handoff、progress enum、stale state handling | my-triage state, standup TDT |
| [memory-hygiene-scan-flow.md](memory-hygiene-scan-flow.md) | memory-hygiene scan/dry-run mode、memory dir resolution、decay-scan command、full classification report、apply confirmation gate | memory-hygiene scan, decay scan |
| [memory-hygiene-apply-flow.md](memory-hygiene-apply-flow.md) | memory-hygiene apply mode 的 safety checks、dry-run plan reuse、migration command、post-apply report、fresh-session verification、anomaly memory rule | memory-hygiene apply, memory 降級 |
| [standup-data-collection-flow.md](standup-data-collection-flow.md) | standup config/defaults、auto-triage guard、日期計算、git/JIRA/Calendar YDY data collection | standup, daily, EOD |
| [standup-planning-flow.md](standup-planning-flow.md) | standup YDY merge/dedup、plan vs actual、TDT candidates、PR status、Polaris backlog、BOS collection | standup TDT, BOS, plan vs actual |
| [standup-format-publish-flow.md](standup-format-publish-flow.md) | standup YDY/TDT/BOS/口頭同步格式、local markdown backup、language gate、Confluence append | standup publish, Confluence standup |
| [standup-template.md](standup-template.md) | standup entry 固定 section、巢狀格式、口頭同步 bullet、Confluence markdown conventions | standup template, YDY, TDT, BOS |
| [daily-learning-scan-spec.md](daily-learning-scan-spec.md) | 每日技術文章掃描器的 RemoteTrigger 規格模板 | learning setup, schedule daily scan |
| [learning-external-flow.md](learning-external-flow.md) | learning External mode 流程：target detection、security pre-scan、baseline snapshot、research depth、synthesis、Route A/B/C 落地 | learning external, learn URL, deep dive, research |
| [learning-queue-flow.md](learning-queue-flow.md) | learning Queue mode 流程：Slack daily queue 讀取、condensed summary、detailed recommendation、archive 去重 | learning queue, daily learning, 讀文章 |
| [learning-pr-batch-flow.md](learning-pr-batch-flow.md) | learning PR / Batch mode 流程：merged PR review lesson extraction、Layer 1 dedup、batch scan、handbook write | learning PR, batch learn, 掃 review, review lessons |
| [learning-setup-flow.md](learning-setup-flow.md) | learning Setup mode 的每日學習 scanner 設定流程：workspace config 偵測、RemoteTrigger 建立、Slack connector 授權提示、test run | learning setup, daily learning scanner, RemoteTrigger |
| [learning-queue.md](learning-queue.md) | 待閱讀技術文章清單（data file） | learning, daily-learning-scan |
| [learning-archive.md](learning-archive.md) | 已處理 URL 去重 archive（data file） | daily-learning-scan, learning setup |

## Framework Meta

| File | Description | Triggers |
|------|-------------|----------|
| [challenger-audit.md](challenger-audit.md) | 多角色 UX 審查系統，pre-release 時使用 | challenger, version-release |
| [docs-sync-scope-detection.md](docs-sync-scope-detection.md) | docs-sync deterministic lint、git diff scoping、change classification、coverage score 與不需同步情境 | docs-sync, sync docs, docs out of date |
| [docs-sync-update-flow.md](docs-sync-update-flow.md) | docs-sync English source docs 更新順序、zh-TW translation sync、pillar mapping 與 editorial constraints | docs-sync update, README sync, workflow guide sync |
| [docs-sync-verification-flow.md](docs-sync-verification-flow.md) | docs-sync bilingual language validation、docs lint、internal links、Starlight check 與 completion report | docs-sync verify, bilingual docs |
| [framework-iteration-procedures.md](framework-iteration-procedures.md) | 框架自迭代 procedures：Post-Version-Bump Chain、Backlog Hygiene scan、Validated Pattern Promotion、Framework Experience frontmatter | version-bump, organize-memory, docs-sync, standup (monthly) |
| [feedback-memory-procedures.md](feedback-memory-procedures.md) | Feedback/memory 操作流程：direct rule write、hygiene checks、carry-forward、dedup、backlog format、frontmatter spec、injection scan | post-task-reflection, organize-memory, feedback write, rule promotion |
| [mechanism-rationalizations.md](mechanism-rationalizations.md) | Mechanism Registry 的 Common Rationalizations 查表集 + Deterministic Quality Hooks 技術細節（evidence file spec、bypass flags） | post-task mechanism audit (when drift suspected), hook configuration, verification-evidence debugging |
| [deterministic-hooks-registry.md](deterministic-hooks-registry.md) | Deterministic Quality Hooks 完整表（ID、Rule、Enforcement、Script）— 從 mechanism-registry.md 拆出以降低 rules 載入成本 | hook configuration, hook debugging, validate-mechanisms |
| [mechanism-deterministic-contracts.md](mechanism-deterministic-contracts.md) | Mechanism Registry 拆出的 deterministic contract groups：artifact schemas、handoff gates、delivery wrappers、release closeout 等只在 gate 被忽略/誤讀時 audit | mechanism registry, post-task audit, validate-mechanisms, deterministic contract |
| [library-change-protocol.md](library-change-protocol.md) | 依賴變更完整協議：三層調查、替換/升級評估、Decision Tier、config 系統性排除、workaround 文件標準 | engineering (library evaluation), review-pr (reviewer suggests upgrade), bug-triage (dependency issue) |
| [knowledge-compilation-protocol.md](knowledge-compilation-protocol.md) | Framework 知識編譯協議：Atom vs Derived 邊界、backwrite、parallel naming lock | learning (External mode framework target), docs-sync, framework docs/rules updates |
| [starlight-authoring-contract.md](starlight-authoring-contract.md) | Specs Markdown 的 Starlight authoring contract：frontmatter、description、duplicate H1、producer boundary、validator explicit path、legacy migration | refinement, breakdown, engineering, verify-AC, docs-manager, specs markdown producer |
| [skill-progressive-disclosure.md](skill-progressive-disclosure.md) | Skill slimming 的 progressive disclosure placement policy：SKILL.md / skill-private reference/script / shared reference/script / DP-memory 邊界、粒度與驗證期待 | skill slimming, skill resource ownership, resource rehome, framework iteration, refinement, breakdown, engineering, verify-AC, learning |
| [validate-isolation-flow.md](validate-isolation-flow.md) | validate isolation mode 的 multi-company scope headers、cross-company conflicts、memory company tags、MEMORY.md index、user data leak scan、report rows | validate isolation, 檢查隔離 |
| [validate-mechanisms-flow.md](validate-mechanisms-flow.md) | validate mechanisms mode 的 static canary smoke tests、routing/skill contract drift、hook/settings checks、model tier drift、L2 embedding integrity、exit handling | validate mechanisms, 檢查機制 |
| [validate-reporting-flow.md](validate-reporting-flow.md) | validate combined report format、PASS/WARN/FAIL summary、proposed fixes、skipped checks、user confirmation boundary | validate report, health check |
