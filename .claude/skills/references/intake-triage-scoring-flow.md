---
title: "Intake Triage Scoring Flow"
description: "intake-triage 的 readiness、effort、impact lens、dependencies、duplicate risk、hard blockers、verdict matrix 與排序規則。"
---

# Intake Scoring Contract

這份 reference 負責 ticket scoring、verdict、排序。

## Readiness

Readiness 0-3，對照 `epic-template.md` readiness essentials：

| Item | Signal |
|---|---|
| background / goal | why this is needed |
| AC | at least one clear acceptance condition |
| scope | affected page, component, API, or flow |

3 = 可直接開工；2 = 有小缺口；1 = 缺關鍵資訊；0 = 無法開工。

## Effort Signal

不做 codebase probe，只從 ticket 內容判斷：

| Signal | Effort |
|---|---|
| single page/component, clear change | S |
| two or three pages/components, conditional logic | M |
| cross-page/module, new composable or API integration | L |
| architecture, cross-project, infra dependency | XL |
| insufficient info | ? |

## Impact Lens

Impact 是 Low / Med / High。Lens 來源優先順序：

1. workspace config `intake_triage.lenses`
2. built-in defaults

Built-in themes：

- SEO：structured data、meta tags、canonical、高流量頁面為 High。
- CWV：影響不及格 LCP / CLS / INP 頁面為 High。
- a11y：影響 WCAG 2.1 AA 主要流程為 High。
- generic：依 ticket 描述的 business value 判斷。

混合 theme 批次時，每張 ticket 各自套用 lens，並在輸出標 `[SEO]` / `[CWV]` /
`[a11y]` / `[generic]`。

## Dependencies

從 JIRA issue links 與同批文本比對 dependencies：

- `independent`
- `blocker`
- `blocked`
- `conflict-risk`

同元件、同頁面、同 composable 的 tickets 可能有 merge conflict 或順序風險。

## Duplicate Risk

比對同批 summary 與 description：

- `Likely`：幾乎同一改動對象，建議合併。
- `Possible`：部分重疊但可獨立。
- `None`：無重疊。

## Hard Blockers

只在 ticket 明確描述會有害時標 `blocked-hard`：

- data incompatible
- overly specialized UI harming common flow
- change likely causes known external misinterpretation

資訊不足時不標 hard blocker，交由 refinement 或 engineering 後續發現。

## Verdict Matrix

| Condition | Verdict |
|---|---|
| readiness 3, S/M, High | Do First |
| readiness 3, S/M, Med/Low | Do Soon |
| readiness 2-3, L, High | Do Soon, needs estimate |
| readiness 2-3, L/XL, Med/Low | Do Later |
| readiness 0-1 | Skip |
| duplicate Likely | Skip |
| effort ? | Do Later |
| blocked-hard | Hard Blocker |

Do First 最多三張。超過時依 Impact、Effort、created time 降最低者到 Do Soon。

同 verdict 內排序：Impact desc、Effort asc、created asc。若 A blocks B 且 A verdict 低於 B，
提升 A 到與 B 同級。
