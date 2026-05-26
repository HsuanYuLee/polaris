# Refinement Artifact Schema

Refinement 產出的結構化 artifact，供下游 skill（breakdown, engineering）直接消費。

此 artifact 支援 JIRA-backed 與 ticketless / DP-backed source。Source resolution 規則以
[`spec-source-resolver.md`](spec-source-resolver.md) 為準。

寫入前先讀 `pipeline-handoff.md` § Artifact Schemas 作為 validator gateway；本檔是
`refinement.json` 的完整 producer schema authority。

## 存放位置

JIRA-backed ticket：

```
{company_specs_dir}/{EPIC_KEY}/refinement.json
```

Spec folders 放在 docs-manager 的 company namespace（如 `~/work/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-521/`），不進 git。

Ticketless / DP-backed work：

```
{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.json
```

DP folder 放在 `docs-manager/src/content/docs/specs/design-plans/`，不綁公司；`plan.md` 是 durable decision
record，`refinement.json` 是 machine-readable artifact。

## 同步寫入

refinement 完成時同時產出兩份：
1. **JIRA comment** — 人讀（自然語言，含 checklist 表格）
2. **Local JSON** — 機器讀（下游 skill 直接 parse）

兩份內容語義等價，格式不同。JIRA comment 是 artifact 的 human-friendly rendering。

## Schema

```jsonc
{
  // --- Metadata ---
  "epic": "EPIC-530",                    // JIRA key
  "source": {
    "type": "jira",                    // "jira" | "dp" | "topic"
    "id": "EPIC-530",                    // JIRA key or DP-NNN
    "container": "{company_specs_dir}/EPIC-530",
    "plan_path": null,                 // DP-backed only: docs-manager/src/content/docs/specs/design-plans/DP-NNN-*/plan.md
    "jira_key": "EPIC-530"               // null for ticketless work
  },
  "version": "1.0",                    // artifact schema version
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
      "references": 12                  // how many files reference this module
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

  // --- Tool Requirements (optional, DP-194) ---
  "tool_requirements": [
    {
      "name": "mockoon-cli",
      "owner": "ticket",                // "framework" | "delivery" | "project" | "ticket" | "user"
      "install_authority": "workspace_dependency_consent",
      // "root_mise" | "system" | "project_package_manager" |
      // "workspace_dependency_consent" | "manual_user_action"
      "check_command": "mockoon-cli --version",
      "install_command": null,          // optional；需要時寫明確 command / consent path
      "runtime_profile": "ticket",      // "core" | "runtime" | "delivery" | "ticket"
      "goes_to_mise": false,            // ticket-scoped tools must stay false
      "handoff_hint": "engineering setup must check or install before Verify Command"
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
      "category": "functional",         // "functional" | "non_functional" | "negative"
      "quantifiable": true,
      "verification": {
        "method": "playwright",          // "playwright" | "lighthouse" | "curl" | "unit_test" | "manual"
        "detail": "切換日期 → assert 價格區塊文字變更"
      },
      "negative": false                  // legacy compatibility alias；new producer 仍應寫 category
    },
    {
      "id": "AC-NEG1",
      "text": "既有頁面的 LCP 不因此功能退化 > 10%",
      "category": "negative",
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

  // --- Research (optional consumed summary) ---
  "research": [
    {
      "topic": "商品頁即時價格更新的業界做法",
      "findings": "主流做法是 client-side fetch + skeleton，Shopify/Amazon 均用此模式",
      "confidence": "HIGH",              // see confidence-labeling.md
      "sources": [
        { "url": "https://shopify.dev/docs/...", "type": "official_docs" },
        { "path": "artifacts/research/2026-05-02-price-update.md", "type": "snapshot" }
      ]
    }
  ],

  // --- Research Gate (optional for new producer) ---
  "research_gate": {
    "status": "none",                    // "none" | "recommended" | "required"
    "deferred": false,
    "defer_reason": null,
    "missing_research": []
  },

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

### Ticketless / DP-backed metadata example

```jsonc
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-045",
    "container": "/Users/name/work/docs-manager/src/content/docs/specs/design-plans/DP-045-refinement-design-plan-unification",
    "plan_path": "/Users/name/work/docs-manager/src/content/docs/specs/design-plans/DP-045-refinement-design-plan-unification/plan.md",
    "jira_key": null
  },
  "version": "1.0",
  "tier": 2,
  "created_at": "2026-04-28T10:00:00Z",
  "refinement_round": 1
}
```

為了相容既有 JIRA artifacts，舊資料可以保留 top-level `epic`。新 producer 應寫入
`source`；只有 JIRA Epic 存在時，才把 `epic` 當作 convenience alias 保留。

AC hardening contract：

- 所有 refinement-owned source 共用同一套 hardened AC：功能 AC、非功能 AC、負面 AC。
- `acceptance_criteria[]` 每條必須保留 `verification`。
- 新 producer 應寫 `category`，讓 JSON artifact 不丟失 markdown 中的分類。
- `negative` 欄位只作 legacy compatibility；consumer 應優先讀 `category`。

## 下游 Skill 如何使用

| Skill | 讀取欄位 | 用途 |
|-------|---------|------|
| **breakdown** | `modules`, `dependencies`, `downstream.breakdown_hints`, `modules[].complexity/risk`, `edge_cases`, `acceptance_criteria` | 每個 module action = 一張子單；blocking dependency = 排序依據；complexity + risk + edge case 數量 → 點數加權 |
| **engineering** | `acceptance_criteria[].verification`, `modules[].path` | 知道要改哪些檔案、怎麼驗證 |
| **breakdown** (scope-challenge) | `gaps.rd_risks`, `research[].confidence`, `research_gate` | 低信心研究 + 高風險 = challenge 候選 |

### `tool_requirements` handoff（DP-194）

`tool_requirements[]` 用來保留工單級或專案級工具需求，避免單一工單需要的 CLI / package
被誤升級為 root `mise.toml` framework runtime dependency。新 producer 應優先寫
top-level `tool_requirements[]`；legacy-compatible producer 也可以用
`dependencies[]` 的 `type: "tool"` entry 承載相同欄位。

每個 entry 至少包含：

| Field | Required | 說明 |
|-------|----------|------|
| `name` | yes | tool / package / binary 名稱 |
| `owner` | yes | `framework` / `delivery` / `project` / `ticket` / `user` |
| `install_authority` | yes | `root_mise` / `system` / `project_package_manager` / `workspace_dependency_consent` / `manual_user_action` |
| `check_command` | yes | engineering setup 可執行的檢查命令 |
| `install_command` | optional | 需要安裝時的明確命令；若走 consent / manual path 可為 `null` |
| `runtime_profile` | yes | `core` / `runtime` / `delivery` / `ticket` |
| `goes_to_mise` | yes | boolean；`owner=ticket` 或 `runtime_profile=ticket` 時必須是 `false` |
| `handoff_hint` | yes | 給 breakdown / engineering 的 install 或 `BLOCKED_ENV` guidance |

## Research Snapshot Relationship

`research[]` 是 refinement 已消化的 summary，不是完整研究紀錄。Full research detail 應保存在 source container：

```text
{source_container}/artifacts/research/YYYY-MM-DD-{slug}.md
```

Snapshot schema 與 Research Sufficiency Gate 見 `refinement-research-container.md`。

Producer rule：

- `research[].sources[]` 可引用 external URL、PR、local path，或 `type: "snapshot"` 的 `artifacts/research/*.md` path。
- Gate status 為 `required` 時，若沒有 usable snapshot，必須在 `research_gate.defer_reason` 記錄 explicit low-confidence defer reason。
- Legacy artifacts 可以沒有 `research_gate`；新 producer 應寫入。

## Strong-Bound Machine Contract

新 artifact 必須具備：

- `schema_version`：必填。
- `tasks[]`：每筆必填 `id` / `kind` / `title` / `scope` / `allowed_files` /
  `modules` / `ac_ids` / `dependencies` / `estimate_points` / `verification`。
- `tasks[].dependencies` 只代表 task.md 可消費的 work-item dependency：同 source
  短式 `T1` / `V1`，或完整 work-item id（例如 `DP-231-T1`）。裸 source
  predecessor（例如 `DP-229`、`DP-230`、`EXAMPLE-4190`）必須留在 top-level
  `dependencies[]` 或文字 references；不得混入 task DAG。validator 會以
  `POLARIS_REFINEMENT_TASK_DEPENDENCY_INVALID` fail-loud，避免 breakdown derive 產出
  `Depends on=DP-229` + `Base branch=main` 的非法 task.md。
- `adversarial_pass[]`：每筆必填 `ac_id` / `attack` / `enforce`。
- Bug-specific fields（`reproduction` / `root_cause` / `source_pr` / `severity` /
  `impact_scope` / `regression`）只允許 `source.type=bug`，其他 source type 不得出現。

`refinement.md` 是 derived view；先收斂 strict `refinement.json`，再用
`scripts/render-refinement-md.sh` 產生 Markdown。`draft_json` 只可用於 authoring state，
不可 LOCK、不可 handoff、不可 render canonical `refinement.md`。

`source.type = dp` 時，`breakdown` 產出 DP-backed tasks：

```
{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/tasks/T{n}.md
```

`source.type = jira` 時，`breakdown` 維持既有 JIRA sub-task + company specs path。

## 版本演進

當 artifact schema 需要新增欄位時：
- 新增欄位用 optional（下游 skill 用 `?.` 存取）
- `version` 欄位標記 schema 版本
- 不刪除既有欄位（向後相容）
- `source` 欄位為新 producer 必填；legacy artifact 若缺少 `source`，consumer 可從 `epic` 推導 `source.type = jira`
