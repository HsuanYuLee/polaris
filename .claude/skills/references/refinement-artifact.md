# Refinement Artifact Schema

Refinement 產出的結構化 artifact，供下游 skill（breakdown, engineering）直接消費。

## 存放位置

```
{company_base_dir}/specs/{EPIC_KEY}/refinement.json
```

Spec folders 放在公司層（如 `~/work/company/specs/PROJ-123/`），不進 git。

## 同步寫入

refinement 完成時同時產出兩份：
1. **JIRA comment** — 人讀（自然語言，含 checklist 表格）
2. **Local JSON** — 機器讀（下游 skill 直接 parse）

兩份內容語義等價，格式不同。JIRA comment 是 artifact 的 human-friendly rendering。

## Schema

```jsonc
{
  // --- Metadata ---
  "epic": "PROJ-123",                    // JIRA key
  "version": "1.1",                    // artifact schema version
  "tier": 2,                           // detected complexity tier (1/2/3)
  "tier_signals": [                    // why this tier was chosen
    "3+ modules affected",
    "no new technology signals"
  ],
  "created_at": "2026-04-12T10:00:00Z",
  "refinement_round": 1,              // increments on multi-round refinement

  // --- Completeness ---
  "completeness": {
    "score": "6/8",
    "items": [
      { "name": "背景與目標", "status": "pass" },
      { "name": "AC", "status": "pass" },
      { "name": "Scope", "status": "partial", "note": "缺 out of scope" },
      { "name": "Edge cases", "status": "fail" },
      { "name": "Figma", "status": "pass" },
      { "name": "API 文件", "status": "na" },
      { "name": "依賴", "status": "pass" },
      { "name": "Baseline", "status": "na" }
    ]
    // status: "pass" | "partial" | "fail" | "na"
  },

  // --- Modules (codebase analysis) ---
  "modules": [
    {
      "path": "src/composables/useFeature.ts",
      "action": "modify",              // "create" | "modify" | "delete" | "investigate"
      "complexity": "medium",           // "low" | "medium" | "high"
      "risk": "low",                    // "low" | "medium" | "high"
      "reason": "需加入 error handling + cache，被 12 個檔案引用",
      "references": 12,                 // how many files reference this module
      "api_change": "additive"          // optional — "none" | "additive" | "breaking" (defaults to "none")
    }
  ],

  // --- Dependencies ---
  "dependencies": [
    {
      "type": "ticket",                 // "ticket" | "api" | "team" | "infra"
      "target": "BE-1234",
      "description": "API endpoint 需先上線",
      "blocking": true                  // true = must complete before this Epic
    }
  ],

  // --- Edge Cases ---
  "edge_cases": [
    {
      "scenario": "API timeout > 3s",
      "handling": "顯示 skeleton + retry",
      "severity": "medium",             // "low" | "medium" | "high"
      "source": "codebase"              // "codebase" | "pm" | "ai_suggested"
    }
  ],

  // --- AC (hardened) ---
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "使用者選擇日期後，價格區塊即時更新",
      "quantifiable": true,
      "verification": {
        "method": "playwright",          // "playwright" | "lighthouse" | "curl" | "unit_test" | "manual"
        "detail": "切換日期 → assert 價格區塊文字變更"
      },
      "negative": false                  // true = 負面 AC（什麼不應該壞）
    },
    {
      "id": "AC-NEG1",
      "text": "既有頁面的 LCP 不因此功能退化 > 10%",
      "quantifiable": true,
      "verification": {
        "method": "lighthouse",
        "detail": "before/after Lighthouse 跑分比對"
      },
      "negative": true
    }
  ],

  // --- Gap Report ---
  "gaps": {
    "pm_questions": [
      "多幣別切換是否在本次 scope 內？",
      "「價格洽詢」的 CTA 導向哪裡？"
    ],
    "rd_risks": [
      {
        "risk": "FeatureComp 元件已過度複雜，加 loading state 可能需要先重構",
        "severity": "medium",
        "mitigation": "可先用 wrapper component 隔離，不直接改 DS 元件"
      }
    ]
  },

  // --- Research (Tier 3 only, optional) ---
  "research": [
    {
      "topic": "商品頁即時價格更新的業界做法",
      "findings": "主流做法是 client-side fetch + skeleton，Shopify/Amazon 均用此模式",
      "confidence": "HIGH",              // see confidence-labeling.md
      "sources": [
        { "url": "https://shopify.dev/docs/...", "type": "official_docs" }
      ]
    }
  ],

  // --- Downstream Hints ---
  "downstream": {
    "suggested_subtask_count": 4,
    "estimated_total_points": "8-13",
    "breakdown_hints": [
      "useFeature refactor 可獨立為一張子單（不依賴 API）",
      "API integration 依賴 BE-1234，建議排後面"
    ]
  }
}
```

## 下游 Skill 如何使用

| Skill | 讀取欄位 | 用途 |
|-------|---------|------|
| **breakdown** | `modules`, `dependencies`, `downstream.breakdown_hints`, `modules[].complexity/risk`, `edge_cases`, `acceptance_criteria` | 每個 module action = 一張子單；blocking dependency = 排序依據；complexity + risk + edge case 數量 → 點數加權 |
| **breakdown** (Step 3a — AC drift) | `acceptance_criteria[].id` | 比對既有子單 description 的 AC 引用，偵測 refinement 重整後的編號漂移 |
| **engineering** | `acceptance_criteria[].verification`, `modules[].path` | 知道要改哪些檔案、怎麼驗證 |
| **breakdown** (scope-challenge) | `gaps.rd_risks`, `research[].confidence` | 低信心研究 + 高風險 = challenge 候選 |
| **breakdown** (Step 5.5 — infra-first) | `acceptance_criteria[].verification.method`, `modules[].api_change` | 決定是否插入 infra 前置子單 + ordering 規則。見 `skills/references/infra-first-decision.md` |
| **refinement** (Step 5 — § 子單結構 preview) | 同上 | Preview breakdown 將產出的 infra 子單數量，確保規格階段跟施工階段訊息一致 |

### `modules[].api_change` 欄位（v1.1 新增，optional）

Refinement Step 2（Codebase Exploration）分析模組時填入，幫助下游判斷 API 變動性質：

- **`"none"`**（預設）— 不涉及 API 變動或 API 為內部 helper
- **`"additive"`** — 新增 endpoint/field 或選擇性參數，舊 client 不受影響
- **`"breaking"`** — 刪除/改名 endpoint、改變回傳 shape、必填參數變動

缺 `api_change` 欄位時，下游（breakdown / engineering）應視為 `"none"`。v1.0 artifact 不會含此欄位 — 向後相容。

### AC ID 格式約定

`acceptance_criteria[].id` 是 downstream 消費者的**唯一穩定錨點**。規範：

- 正面 AC：`AC1`, `AC2`, `AC3` …（連號，從 1 開始）
- 負面 AC：`AC-NEG1`, `AC-NEG2` …（獨立序列）
- 子 AC（若需要）：`AC2.1`, `AC2.2` …（點號分隔）

**子單 description 引用 AC 時統一用 `ACn` 或 `AC#n`（兩者等價，Step 3a 比對時正規化處理）**。避免 `要求 1`, `驗收項目 A` 等非結構化指稱 — 它們無法被 drift 偵測器辨識。

Refinement v2+ 重整 AC 結構（合併、拆分、重編）時，既有子單若已存在，必須同步處理，否則 breakdown Step 3a 會觸發 drift 警告。見 `skills/breakdown/SKILL.md` § 3a AC 引用漂移偵測與調和。

## 版本演進

當 artifact schema 需要新增欄位時：
- 新增欄位用 optional（下游 skill 用 `?.` 存取）
- `version` 欄位標記 schema 版本
- 不刪除既有欄位（向後相容）
