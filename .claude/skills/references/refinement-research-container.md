# Refinement Research Container Contract

本 reference 定義 `refinement` 與 `learning` 共享的 research container contract。目標是讓 refinement 一開始就有穩定 source container，並把中途補充的研究資料保存成可追溯 artifact；research snapshot 是 evidence，不是 final decision。

## Container-first Rule

`refinement` 在正式 feasibility / AC hardening 前，必須先建立或定位 source container：

| Source | Container |
|--------|-----------|
| JIRA / company Epic | `{specs_root}/companies/{company}/{EPIC}/` |
| DP | `{specs_root}/design-plans/DP-NNN-{slug}/` |
| Topic | 新建 `{specs_root}/design-plans/DP-NNN-{slug}/` |
| Direct artifact path | nearest specs container |

Source resolution 以 `spec-source-resolver.md` 與 `refinement-dp-source-mode.md` 為準。`DP-NNN` 找不到或多筆 match 必須 fail loud，不可偷偷建立替代 DP。

## Research Sufficiency Gate

Gate owner 是 `refinement`。Gate 只做判斷與整理，不自動 WebSearch；若需要外部研究，輸出建議 learning query 與 blocking questions。

Gate status：

| Status | Meaning | Flow |
|--------|---------|------|
| `none` | 現有 ticket / plan / codebase context 足夠 | 直接進 refinement |
| `recommended` | 補研究會提高信心，但不是 blocker | 提示使用者可先 trigger `learning`，也可繼續 |
| `required` | 缺研究會讓方案低信心或高風險 | 預設阻塞；若使用者明確要求低信心繼續，artifact 必須記錄 defer reason |

Gate output 應包含：

- `status`
- `reasons[]`
- `suggested_learning_queries[]`
- `blocking_questions[]`
- `defer_policy`

## Snapshot Path

Research snapshot 寫在 active source container 內：

```text
{source_container}/artifacts/research/YYYY-MM-DD-{slug}.md
```

不要使用 `knowledge/`，避免和全域 `polaris-learnings` 混淆。

## Snapshot Frontmatter

最小 schema：

```yaml
---
source: learning
created: 2026-05-02
topic: research topic
confidence: HIGH
imported_from: https://example.com/source
consumed_by_refinement: false
---
```

欄位規則：

| Field | Rule |
|-------|------|
| `source` | `learning` / `manual` / `research-gate` |
| `created` | `YYYY-MM-DD` |
| `topic` | 非空 |
| `confidence` | `HIGH` / `MEDIUM` / `LOW` |
| `imported_from` | URL、PR、local path，或 `N/A` |
| `consumed_by_refinement` | `false` until refinement explicitly consumes it |

Body 建議包含：

- `## Summary`
- `## Findings`
- `## Source Notes`
- `## Relevance To Refinement`
- `## Open Questions`

## Consumption Rule

`refinement` 讀 snapshot 時，只能把它當 evidence。決策必須重新寫入：

- `plan.md` Decisions / Technical Approach / Risks
- `refinement.md`
- `refinement.json.research[]`

當 snapshot 被採用時，將 frontmatter `consumed_by_refinement` 改為 `true`，或在 `refinement.json.research[]` 中引用 snapshot path。若只讀未採用，不要標 consumed。

## `refinement.json research[]`

`research[]` 是 consumed summary，不保存完整研究內容。每個 entry 應指向 snapshot：

```jsonc
{
  "topic": "research topic",
  "findings": "decision-relevant summary",
  "confidence": "HIGH",
  "sources": [
    {
      "type": "snapshot",
      "path": "artifacts/research/2026-05-02-topic.md"
    }
  ]
}
```

Full detail 留在 `artifacts/research/*.md`。

## Required Gate Defer

若 Research Sufficiency Gate 是 `required`，但使用者要求低信心繼續，refinement artifact 必須明寫 defer reason：

```jsonc
{
  "research_gate": {
    "status": "required",
    "deferred": true,
    "defer_reason": "user accepted low-confidence continuation because ...",
    "missing_research": ["..."]
  }
}
```

沒有 snapshot 且沒有 explicit defer reason 時，不可宣稱 refinement ready。

## Learning Import Contract

`learning` 可以在使用者明確指定 target 時，把研究結果 import 到 active refinement container：

- `learning ... --for DP-NNN`
- `learning ... --container {source_container}`

沒有 target 時，`learning` 不猜 active container，維持既有 behavior。`learning` 不自動 invoke `refinement`，也不替 refinement 定版。

## Legacy Compatibility

舊 container 沒有 `artifacts/research/` 時不失敗，視為 legacy。只有新流程建立或更新的 container，才要求 gate metadata、snapshot reference 或 explicit defer reason。

舊 DP re-refinement 可以增量補 research snapshot，不需要先做批次 migration。
