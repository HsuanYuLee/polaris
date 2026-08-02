---
title: "SASD Review Document Template"
description: "sasd-review SA/SD 文件的 metadata、required sections、optional sections、task estimates、timeline 與 confidence labeling。"
---

# SASD Document Contract

這份 reference 定義 SA/SD 文件結構。

## Metadata

文件開頭包含：

| Field | Meaning |
|---|---|
| create date | document creation date |
| author | responsible developer |
| JIRA ticket | issue link |
| PRD | product requirement link if any |
| Design | Figma / Zeplin / mockup links if any |
| API doc | API documentation link if any |
| Discussion | Slack thread or meeting notes |
| Reference | additional materials |

## Required Sections

1. Requirements：問題、目標、成功條件。
2. Dev Scope：會改的 files、modules、services；新增/刪除項目與原因。
3. System Flow：request path、sequence diagram、data flow，或清楚 prose。
4. Implementation Design：components、functions、modules、patterns、data flow。
5. Task List with Estimates：可交付 task、file scope、verification、points。
6. Timeline：total points 與 estimated days。

## Optional Sections

Large 或 ambiguous scope 加：

- Alternatives considered。
- Risk and mitigation。
- Open questions。
- Rollout / migration notes。
- Reference。

## Task List Rules

Task list 要能直接餵給 `breakdown`：

- One task equals one independently deliverable PR-sized unit。
- Points 使用 Fibonacci：1, 2, 3, 5, 8, 13。
- Target 2-5 points per task。
- 每個 task 列 specific file paths。
- 每個 task 有 objective verification method。
- 若 `breakdown` 已有 subtasks，reuse，不重拆。

## Timeline

Timeline 使用 total points / daily velocity。Velocity 不明時用 2-3 points/day range，並標示
assumption。

## Confidence

不確定的外部 API、library behavior、跨 service contract、或未能驗證的 code path，要依
`confidence-labeling.md` 標示 HIGH / MEDIUM / LOW / NOT_RESEARCHED。
