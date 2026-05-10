---
title: "共用 Refinement Source Template"
description: "JIRA Epic refinement 與 DP-backed refinement 共用的 canonical source container 欄位。"
---

# Refinement Source Template Contract

這份 reference 是 JIRA Epic refinement 與 DP-backed Design Plan 共用的 source
contract。Producer 可以使用不同的人類可讀 heading，但下游 `breakdown` 必須收到同一組
canonical fields。

## Canonical Section IDs

| ID | Required | Downstream purpose |
|----|----------|--------------------|
| `goal_background` | yes | 說明 source 存在原因與重要 outcome。 |
| `scope` | yes | In-scope surface、module、repo 或 workflow boundary。 |
| `out_of_scope` | yes | 防止 scope creep 的明確排除項。 |
| `acceptance_criteria` | yes | verification planning 要消費的 user-facing / negative AC。 |
| `verification_methods` | yes | 每條 AC 的驗證方法：unit、static、runtime、manual、VR 或 release gate。 |
| `technical_approach` | yes | 可行實作方向與風險。 |
| `dependencies` | yes | 跨 task、跨 team、config、release 或 data dependency。 |
| `gaps_questions` | yes | 阻擋 breakdown readiness 的 open questions / blind spots。 |
| `downstream_breakdown_hints` | yes | 建議拆單、Allowed Files boundary 與 verification handoff。 |

## Framework Rendered Columns

Every refined source must render framework-owned fields first:

- Goal
- Background
- Scope
- Out of Scope
- Acceptance Criteria
- Verification Methods
- Technical Approach
- Dependencies
- Open Questions / Blind Spots
- Downstream Breakdown Hints

Company/project template 只能 additive。它可以在 framework fields 之後加入公司專屬欄位，
但不可移除、改名或覆寫 framework-owned canonical section。

## Company Template Locations

Template resolver lookup order:

1. `{company}/polaris-config/{project}/refinement/templates/*.yaml`
2. `{company}/polaris-config/refinement/templates/*.yaml`
3. `.claude/skills/references/refinement-source-template.md`

Company config 是 local ignored runtime config。Refinement handoff 前，selected
template 必須記錄成 machine-readable manifest：

```yaml
schema_version: 1
source: framework|company|project
template_id: framework-default
path: .claude/skills/references/refinement-source-template.md
framework_sections:
  - goal_background
  - scope
  - out_of_scope
  - acceptance_criteria
  - verification_methods
  - technical_approach
  - dependencies
  - gaps_questions
  - downstream_breakdown_hints
company_sections: []
forbidden_overrides:
  - framework_sections
  - remove_framework_sections
  - override_framework_sections
selected_at: 2026-05-10T00:00:00Z
```

## Handoff Requirements

Source artifact 包含下列項目前，refinement handoff 不算完成：

- all canonical framework sections;
- any selected company/project additive sections;
- the selected template manifest;
- structured `acceptance_criteria[]`;
- structured `downstream.breakdown_hints[]`.

Markdown-only AC 或 markdown-only breakdown hints 不是有效 handoff。
