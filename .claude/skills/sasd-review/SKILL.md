---
name: sasd-review
description: >
  Generates a SA/SD (System Analysis / System Design) document for a JIRA ticket —
  a structured implementation plan produced before coding begins. Use this skill
  whenever the user mentions SASD, SA/SD, 寫 SA, 出 SA/SD, SA 文件, SD 文件,
  架構文件, implementation plan, 系統分析, 系統設計, 技術設計, 異動範圍,
  dev scope, design doc, technical design, or asks to analyze what changes are needed
  for a ticket, plan the implementation approach, or produce a technical design
  document — even if they don't explicitly say "SA/SD".
metadata:
  author: Polaris
  version: 1.1.0
---

# SA/SD Review — Design-First Gate

在寫 code 前，為 JIRA ticket 產出 System Analysis / System Design 文件，先對齊需求、
異動範圍、技術方案、task estimates 與風險。

## Contract

`sasd-review` 是 design-first gate。它產出 implementation plan，不施工、不建 branch、
不開 PR。若 ticket 已經有清楚方案，也仍需確認方向，不可直接假設。

Small change 可產 brief plan；medium scope 產 standard SA/SD；large or cross-service scope
需包含 alternatives 與 risk mitigation。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `sasd-review-entry-exploration-flow.md`, `workspace-config-reader.md`, `project-mapping.md`, `shared-defaults.md` |
| Codebase exploration | `explore-pattern.md`, `repo-handbook.md`, `worktree-dispatch-paths.md`, `planning-worktree-isolation.md` as needed |
| Document writing | `sasd-review-document-template.md`, `estimation-scale.md`, `confidence-labeling.md` |
| External publish | `sasd-review-publish-flow.md`, `sasd-confluence.md`, `confluence-page-update.md`, `workspace-language-policy.md`, `external-write-gate.md` |

Explore sub-agent dispatch 必須注入 `sub-agent-roles.md` 的 Completion Envelope。Planning
decision 留在主 session；sub-agent 只提供 codebase impact evidence。

## Flow

1. 讀 workspace config，解析 JIRA ticket key。
2. Fetch JIRA ticket，讀 summary、description、AC、PRD/design/API/discussion links。
3. 依 `project-mapping.md` 找 target project；找不到就問使用者。
4. 讀 requirements，列 ambiguities；不清楚的先問，不猜。
5. 依 `explore-pattern.md` 探索 codebase，取得 affected files、current architecture、risks。
6. 中大型 scope 提出 2-3 個 approach 與 trade-offs，請使用者確認 recommendation。
7. 依 template 產出 SA/SD：requirements、dev scope、system flow、implementation design、
   task list with estimates、timeline。
8. 呈現給使用者調整；確認後才可寫 JIRA comment 或 Confluence page。
9. External write 前跑 language gate。

## Design Rules

- Task estimates 必須使用 Fibonacci scale。
- Task list 要能直接成為 breakdown input；每個 task 有 file scope 與 verification method。
- Dev scope 使用具體 file/module/service，不寫泛稱。
- 不確定的研究結論標 confidence。
- Runtime feasibility probe 需要跑環境時，使用 dedicated worktree，不污染 main checkout。

## Completion

輸出 SA/SD draft、unresolved questions、chosen approach、estimated points/days、publish status、
以及建議下一步：更新 JIRA/Confluence、或進 `breakdown`。

## Post-Task Reflection (required)

Execute `post-task-reflection-checkpoint.md` before reporting completion.
