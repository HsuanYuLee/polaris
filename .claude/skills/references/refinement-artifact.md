# Refinement Artifact Schema

Refinement 產出的結構化 artifact。**Consumer boundary（DP-238 AC2）**：`breakdown` 是唯一
直接消費 `refinement.json`（acceptance_criteria / modules / dependencies / downstream）並
derive work order 的 owner。`engineering` 不直接讀 `refinement.json` 補 scope authority；它
只消費 `breakdown` 產出的 authoritative task.md。atom ownership 以
[`pipeline-handoff-atom-matrix.md`](pipeline-handoff-atom-matrix.md) `refinement_artifact`
row 為準。

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
    "jira_key": "EPIC-530",              // null for ticketless work
    // --- jira-only fields (DP-269) — required when source.type=jira, forbidden when source.type=dp ---
    "repo": "exampleco-web",             // product repo slug (= polaris-config/{project}/ dir name); derive jira mode -> task.md Repo
    "base_branch": "develop"             // product base branch (from polaris-config/{project}/handbook/config.yaml); derive jira mode -> task.md Base branch
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
    },
    {
      "id": "AC3",
      "text": "T13 SCSS 層只移除 form-* 與 bootstrap import，排除 ExampleCo 自有 selector",
      "category": "functional",
      "quantifiable": true,
      "verification": {
        "method": "unit_test",
        "detail": "grep 確認 form-input / form-select selector 已移除",
        // DP-359 D3：SCSS-removal verify_command 的 curated-token single source
        // of truth（additive optional，validated-when-present）。見下方
        // § `acceptance_criteria[].verification.curated_tokens`。
        "curated_tokens": ["form-input", "form-select"]
      },
      "negative": false
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

### `tasks[].task_shape` / `tasks[].tracked_deliverable_hint`（canonical home，DP-296）

`task_shape` 與 `tracked_deliverable_hint` 是 `tasks[]` entry 的 **first-class** 欄位，
是這兩個語義的 canonical home。LOCK gate 的 breakdown-ready preflight
（`scripts/validate-refinement-lock-preflight.sh`）直接讀 `tasks[]`，在 **LOCK 當下**
就驗證每筆 planned task 的 delivery shape 是否可通過 `validate-breakdown-ready.sh`，
而不必等 breakdown 真的打包出 task.md 才發現違規。

| Field | Required | 說明 |
|-------|----------|------|
| `task_shape` | optional | `implementation`（缺欄位 default）/ `audit` / `confirmation`；enum 由 `validate-task-md.sh` 認定，breakdown 從本欄位寫入 task.md frontmatter `task_shape`（canonical writer） |
| `tracked_deliverable_hint` | optional | `tracked`（缺欄位 default）/ `specs_only`；宣告該 task 的交付物是 tracked code change（`tracked`）還是 specs/evidence-only artifact（`specs_only`），preflight 用來決定合成 placeholder 的 Allowed Files 形狀 |

Contract（DP-262 AC5 / AC-NEG3 / AC7，DP-296 canonicalize）：

- `task_shape: implementation`（或缺欄位）卻宣告 `tracked_deliverable_hint: specs_only`
  的 task，會在 LOCK preflight 被 `validate-breakdown-ready.sh` 判為非
  breakdown-ready，preflight exit 2 fail-stop（carve-out 不外溢到 implementation）。
- `task_shape ∈ {audit, confirmation}` 的 task 宣告 `specs_only` deliverable
  合法（confirmation-only delivery shape）。
- preflight 複用 `validate-breakdown-ready.sh` 本體，不自行重寫 specs-prefix /
  `task_shape` 判斷（單一 classifier）。
- 缺這兩個欄位的 task 在 preflight 是 no-op PASS（implementation / tracked default）。

> **Legacy top-level `planned_tasks[]` 已移除（DP-296）**：DP-262 曾用 top-level
> `planned_tasks[]` 攜帶 `task_shape` / `tracked_deliverable_hint`。DP-296 把這兩個語義
> 收斂為 `tasks[]` first-class 欄位，移除 `planned_tasks[]` schema 與雙 writer path。
> 既有含 `planned_tasks[]` 的 active `refinement.json` 由
> `scripts/migrate-refinement-planned-tasks-to-canonical.sh` 一次性確定性遷移
> （依 task_id 折入 `tasks[]` 後刪除 `planned_tasks[]`）；新 producer 一律寫
> `tasks[]`，不得重新產生 `planned_tasks[]`。

### `tasks[].verification` per-task body fields（all source，DP-302）

`tasks[].verification` 除了 verification `method` / `detail` 之外，可攜帶一組 **per-task
body 欄位**，作為 `derive-task-md-from-refinement-json.sh` 產出 task.md body 的
**field-driven** 輸入。這些欄位對**所有** `source.type` 適用（不是 jira-only）：derive 一律讀
欄位，不看 type，body 因此「結構一模一樣、只有值不同」（DP-302 Goal / D3）。

| Field | Required | 說明 |
|-------|----------|------|
| `behavior_contract` | optional | object；required boolean `applies`。`applies=false` 時必須附非空 `reason`（對齊 task.md frontmatter `verification.behavior_contract` 契約：framework infra task=false 須說明、runtime/UI/product task=true）。`applies=true` 時 derive **fail-loud** 強制一組子欄位（見下方 § behavior_contract `applies=true` 子欄位契約）。derive 寫入 task.md frontmatter `verification.behavior_contract` |
| `test_environment` | optional | object；required `level` ∈ `static` / `component` / `integration` / `runtime`。derive 寫入 task.md `## Test Environment` 的 Level |
| `verify_command` | optional | 非空字串；derive 寫入 task.md `## Verify Command`（無無條件 framework 尾段；framework-only 步驟只在此欄位明確要求時才出現，D5） |
| `references` | optional | 字串陣列（每筆非空）；derive 寫入 task.md `References to load`。實際 container 路徑（`companies/` vs `design-plans/`）由 resolved container 生成，不由本欄位寫死（D4） |

Contract（DP-302 AC3 / AC-NEG1）：

- 這四個欄位是 **validated-when-present**：缺欄位的 task 在 `validate-refinement-json.sh`
  是 no-op PASS（既有 active refinement.json 早於本欄位仍可通過；back-compat）。
- 但只要欄位 **present**，其 shape 就被 fail-loud enforce（缺 `applies`、`applies=false`
  缺 `reason`、`test_environment.level` 出 enum、`verify_command` 空字串、`references`
  非陣列皆 exit 1 並指名欄位）。這讓 derive 不能 silently 套 framework default
  （AC-NEG1）。
- back-compat 鬆綁不外洩：本欄位是 additive optional，不改動既有 `method` / `detail`
  required 契約。

#### behavior_contract `applies=true` 子欄位契約

當 `behavior_contract.applies=true` 時，`derive-task-md-from-refinement-json.sh`
（`bc_applies` block）對下列子欄位 **fail-loud**（缺任一即 exit 1 並指名欄位，
no framework default），與 `validate-task-md.sh` 對 runtime/product task 的要求一致。
這份清單與 derive enforcement 同步，由 doc↔enforcement parity selftest
（`scripts/selftests/refinement-artifact-behavior-contract-doc-parity-selftest.sh`）
機械斷言 doc 不得比 enforcement 寬鬆。

**無條件必填子欄位**（`applies=true` 時全部都要）：

| 子欄位 | 說明 |
|--------|------|
| `mode` | 比對模式，例如 `parity`（before/after 完全一致）/ `hybrid`（允許列舉差異）。 |
| `source_of_truth` | 行為基準來源（baseline 由哪個 commit / 環境 / fixture 定義）。 |
| `fixture_policy` | fixture 取用政策，例如 `mockoon_required`（必須掛 Mockoon fixture）/ `none`。 |
| `flow` | 驗證流程描述（要走哪些步驟才觀察到該行為）。 |
| `assertions` | 非空字串陣列，每筆是一條可觀察的行為斷言（空陣列 fail-loud）。 |

**條件必填子欄位**（依上面值再展開）：

| 觸發條件 | 額外必填 | 說明 |
|----------|----------|------|
| `fixture_policy: mockoon_required` | `flow_script` | 必填非空 flow script 路徑（validator 接受 `flow_script` / `script_path` / `playwright_script` 任一）。 |
| `mode: hybrid` | `allowed_differences` | 必填非空字串陣列，逐條列出允許的 before/after 差異。 |

**可選 passthrough 子欄位**（宣告時才寫入 task.md，缺則略過）：`baseline_ref`、
`target_url`、`viewport`。其中 mobile UI parity task 用 `viewport: mobile` 宣告（desktop
省略或填 `viewport: desktop`）。

範例（mobile UI parity task，`mode: parity` + `fixture_policy: mockoon_required`）：

```yaml
verification:
  behavior_contract:
    applies: true
    mode: parity
    source_of_truth: "feat/DP-335 HEAD before refactor"
    fixture_policy: mockoon_required
    flow_script: scripts/flows/product-detail-mobile.sh
    flow: "載入商品頁 mobile viewport，截圖比對 before/after"
    viewport: mobile
    assertions:
      - "mobile 商品頁 above-the-fold 元素位置與 baseline 一致"
      - "CLS 無新增位移"
```

範例（framework infra task，無 runtime / UI 行為）：

```yaml
verification:
  behavior_contract:
    applies: false
    reason: "framework reference doc 對齊 + deterministic selftest；無 runtime / UI 行為變更"
```

### `acceptance_criteria[].verification.curated_tokens`（SCSS-removal scan token single source of truth，DP-359）

`curated_tokens` 是 **AC entry verification block** 的 optional 欄位，是
SCSS-removal 類 verify_command 掃描 token 的 **single source of truth**。當某張
AC 描述「移除某些 CSS class selector 殘留」這類驗收（典型 Bootstrap-removal
重構），AC 在 `verification.curated_tokens` 列出**允許掃描的 class selector
token 清單**；綁到該 AC 的 task（`tasks[].ac_ids` → 此 AC）的 SCSS-removal
verify_command 掃描 token 必須是 curated-token 的子集。

| Field path | Required | Shape |
|------------|----------|-------|
| `acceptance_criteria[].verification.curated_tokens` | optional | 非空字串陣列；每筆是一個 class selector token（可帶或不帶前導 `.`，gate 以去點、小寫後比對） |

Contract（DP-359 D3 / D4 / AC-NF1）：

- **additive optional、validated-when-present**：缺欄位的 AC 在
  `validate-refinement-json.sh` 是 no-op PASS（既有 active refinement.json 早於本
  欄位仍可通過；back-compat 對齊 DP-302 AC-NEG2 pattern）。present 時 shape 被
  enforce：非陣列、或含空字串元素 fail-loud。
- **single source of truth（AC-NF1）**：curated-token **只**定義於此 AC 欄位；
  verify_command 的 SCSS-removal gate 讀同一來源（task 的 `ac_ids` → 對應
  `acceptance_criteria[*].verification.curated_tokens` 的 union），不存在第二條
  token 定義 path。「排除 ExampleCo 自有 selector」是 data——結構化清單本就不含
  ExampleCo-own token，subset 檢查 mechanical，不靠散文判斷。
- **deterministic gate（D4）**：`validate-refinement-json.sh` 偵測 task 的
  `verification.verify_command` 含 SCSS-removal clause——一個掃 `assets/style/css`
  / `*.scss` / `*.css` 的 negative-assertion `! rg ... '\.<token>' ...`——時，抽出
  其掃描的 anchored class token，與該 task `ac_ids` 對應 AC 的 curated-token union
  比對：掃描 token 非子集（含裸 `\.modal` / `\.btn` 這類未列在 curated-token 的
  family pattern），或使用未錨定的過寬 family pattern（如 `\.modal*`）時，
  **fail-closed exit 2 + `POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE`**。掃描
  token ⊆ curated set → PASS。不含 SCSS-removal clause 的一般 verify_command（如
  `bash scripts/selftests/*.sh`）是 no-op PASS（AC-NEG1）。

範例（T13 SCSS 層只移 `form-*`，curated-token 排除 ExampleCo 自有 selector）：

```jsonc
{
  "acceptance_criteria": [
    {
      "id": "AC3",
      "text": "T13 SCSS 層只移除 form-* 與 bootstrap import，排除 ExampleCo 自有 selector",
      "verification": {
        "method": "unit_test",
        "detail": "grep 確認 form-* selector 已移除",
        "curated_tokens": ["form-input", "form-select"]   // single source of truth
      }
    }
  ],
  "tasks": [
    {
      "id": "DP-NNN-T13",
      "ac_ids": ["AC3"],
      "verification": {
        // ⊆ curated_tokens → PASS
        "verify_command": "! rg '\\.form-input|\\.form-select' assets/style/css"
        // 若改成裸 `! rg '\\.modal' assets/style/css`（modal 不在 curated）→
        // exit 2 + POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE
      }
    }
  ]
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
- `verification.curated_tokens`（DP-359）為 optional、validated-when-present：當
  AC 描述 SCSS class selector 移除驗收時，列出允許掃描的 curated-token 清單，作為
  SCSS-removal verify_command 的 single source of truth（見
  § `acceptance_criteria[].verification.curated_tokens`）。

## 下游 Skill 如何使用

> **Consumer boundary（DP-238 AC2）**：`breakdown` 是唯一直接消費 `refinement.json`
> 並 derive work order 的 owner。`engineering` 不在本表 —— 它只消費 `breakdown` 產出的
> authoritative task.md（Allowed Files / Scope Trace Matrix / Verify Command），不直接讀
> `refinement.json` 的 `acceptance_criteria` / `modules` 補 scope。`verify-AC` 讀
> `acceptance_criteria[].verification` 作 verification method/detail authority（見
> [`pipeline-handoff-atom-matrix.md`](pipeline-handoff-atom-matrix.md) `refinement_artifact`
> / `v_task_envelope` row）。

| Skill | 讀取欄位 | 用途 |
|-------|---------|------|
| **breakdown** | `modules`, `dependencies`, `downstream.breakdown_hints`, `modules[].complexity/risk`, `edge_cases`, `acceptance_criteria`, `tasks[].task_shape`, `verification_strategy.mode` | 每個 module action = 一張子單；blocking dependency = 排序依據；complexity + risk + edge case 數量 → 點數加權；`tasks[].task_shape` 寫入 task.md frontmatter。`verification_strategy.mode` 是是否 require source-level V 的唯一 structured input；breakdown 消費此欄位，不以 `source.type` 自行決定。task.md（含 Allowed Files / Verify Command）由 breakdown derive，是 engineering 的唯一施工輸入 |
| **verify-AC** | `acceptance_criteria[].verification.method/detail` | verification method/detail authority（V*.md 是 execution envelope，不覆寫此來源） |
| **breakdown** (scope-challenge) | `gaps.rd_risks`, `research[].confidence`, `research_gate` | 低信心研究 + 高風險 = challenge 候選 |
| **refinement** (LOCK preflight, DP-262/DP-296) | `tasks[].task_shape`, `tasks[].tracked_deliverable_hint` | `validate-refinement-lock-preflight.sh` 合成 placeholder 跑 `validate-breakdown-ready.sh`，LOCK 時 fail-stop 不 ready 的 task |

### `handoff_advisories[]` durable handoff signal（DP-379）

`handoff_advisories[]` 是 refinement 對下游公開的 machine-readable advisory record。它用來
保存 author-time gate 或 release-surface advisory 的處置狀態，讓 breakdown / handoff gate
讀 canonical artifact，而不是讀對話、stderr transcript 或 agent final answer。

每筆 advisory 至少包含：

| Field | Required | 說明 |
|-------|----------|------|
| `id` | yes | 穩定 advisory id；同一 artifact 內不可重複 |
| `producer` | yes | 產生 advisory 的 deterministic producer / gate 名稱 |
| `severity` | yes | advisory 嚴重度；由 producer 定義語意 |
| `recommended_action` | yes | 對下游的建議處置 |
| `disposition` | yes | `pending` / `absorbed_by_task` / `waived` / `route_back_refinement` |
| `task_ids` | conditional | advisory 綁定的 task id。若 `disposition=absorbed_by_task`，必須是非空 array，且每筆指向同一 artifact 的既有 `tasks[].id`（短式或完整 work-item id 皆可） |
| `reason` | conditional | 若 `disposition=waived`，必須提供非空 waiver reason |

下游語意：

- `pending`：不可 handoff；需要 refinement amendment / route-back，或由上游改成明確
  `absorbed_by_task`、`waived`、`route_back_refinement` disposition 後再交給 breakdown。
- `absorbed_by_task`：breakdown 只有在 `task_ids[]` 指向同一 artifact 的既有 `tasks[]`，
  且該 task 會被 derive 成本次 task.md 時，才可把 advisory 視為已由列出的 task scope
  吸收。缺 `task_ids[]`、指向不存在 task、或指向非本輪 task 時，不得靠散文補 scope。
- `waived`：必須保留 reason；不得只靠口頭說明、對話紀錄或 final answer 放行。
- `route_back_refinement`：要求回 refinement amendment / route-back，而不是由 breakdown
  從 stderr 猜 task scope。

Consumer contract：

- breakdown 只能讀 `refinement.json.handoff_advisories[]` 作 advisory authority；不得讀
  handoff gate stderr transcript、agent final answer、對話紀錄或 derived `refinement.md`
  來補 disposition / task scope。
- `render-refinement-md.sh` 產出的 Handoff Advisories section 是 human review view，不是第二份
  source of truth。

`render-refinement-md.sh` 會在 `refinement.md` derived view 顯示 Handoff Advisories section，
供人讀 review；derived view 不是第二份權威。

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
- `verification_strategy`：optional structured source-level AC verification strategy。
  新 producer 在 LOCK 前必填；legacy artifact 可缺欄位以維持讀取相容。當存在時，
  `mode` enum = `per_task_self_verify` / `source_level_v_required` /
  `external_ac_ticket`，且 `reason` / `authority` 必填非空。此欄位是 source-neutral：
  `breakdown` / LOCK gates 只讀 `verification_strategy.mode` 決定是否 require V task，
  不以 `source.type` 分路。`source_level_v_required` 必須在 `tasks[]` 中有 V task；
  `external_ac_ticket` 必須帶外部 AC ticket identity。
- `tasks[]`：每筆必填 `id` / `kind` / `title` / `scope` / `allowed_files` /
  `modules` / `ac_ids` / `dependencies` / `estimate_points` / `verification`。
  `task_shape`（`implementation` default / `audit` / `confirmation`）與
  `tracked_deliverable_hint`（`tracked` default / `specs_only`）為 optional first-class
  欄位（DP-296 canonical home，見 § `tasks[].task_shape` / `tasks[].tracked_deliverable_hint`）。
  `tasks[].verification` 的 per-task body 欄位（`behavior_contract` / `test_environment` /
  `verify_command` / `references`）為 optional、validated-when-present，對所有 source 適用
  （DP-302，見 § `tasks[].verification` per-task body fields）。
- `tasks[].id` 接受兩種形式（DP-260）：短式 `T1` / `V1`（可選 `a`-suffix，如 `T1a`），
  或完整 work-item id（例如 `DP-231-T1`、`EPIC-4190-V2`）。完整形式的 source prefix
  必須等於 `source.id`；外族 prefix（例如 `OTHERDP-999-T1`）由
  `validate-refinement-json.sh` 以 `POLARIS_REFINEMENT_TASK_ID_INVALID` fail-stop。
  `derive-task-md-from-refinement-json.sh` 同樣支援兩種形式：CLI `--task-id` 一律
  傳 canonical 完整 id（`DP-NNN-Tn`），derive 先比完整 id，未命中時若 CLI source
  prefix == `source.id` 再 fall back 比對短式 id；輸出 task.md frontmatter 一律
  emit canonical 完整 id。
- `tasks[].dependencies` 只代表 task.md 可消費的 work-item dependency：同 source
  短式 `T1` / `V1`，或完整 work-item id（例如 `DP-231-T1`）。裸 source
  predecessor（例如 `DP-229`、`DP-230`、`EXAMPLE-4190`）必須留在 top-level
  `dependencies[]` 或文字 references；不得混入 task DAG。validator 會以
  `POLARIS_REFINEMENT_TASK_DEPENDENCY_INVALID` fail-loud，避免 breakdown derive 產出
  `Depends on=DP-229` + `Base branch=main` 的非法 task.md。
- `adversarial_pass[]`：每筆必填 `ac_id` / `attack` / `enforce`。
- Bug-specific fields 只允許 `source.type=bug`，其他 source type 不得出現：
  - `reproduction_steps[]`：必填，non-empty string array。
  - `root_cause`：必填，non-empty string。
  - `source_pr`：必填，non-empty string；尚未定位時必須寫明 `N/A - <reason>`。
  - `severity`：必填，non-empty string。
  - `impact_scope`：必填，non-empty string。
  - `regression`：必填，boolean 或 non-empty string。
- Legacy `reproduction` 不再是 canonical field；new producer 必須寫
  `reproduction_steps[]`，validator 仍會阻擋 non-bug source 出現 legacy
  bug-only field。
- **jira-only schema 欄位（DP-269）**：下列欄位只允許 `source.type=jira`，是 derive
  jira mode 注入 task.md `Repo` / `Base branch` / 真實 JIRA identity 的來源；
  `source.type=dp` 出現任一欄位時 `validate-refinement-json.sh` 以
  `POLARIS_REFINEMENT_JIRA_ONLY_FIELD` fail-closed（比照 DP-228 jira-only consent
  欄位禁令，避免鬆綁外洩到 dp 分支）：
  - `source.repo`：產品 repo slug（= `polaris-config/{project}/` 目錄名）。
    `source.type=jira` 時 **required**（derive jira mode → task.md `Repo`）。
  - `source.base_branch`：產品 base branch（如 `develop`，來源
    `polaris-config/{project}/handbook/config.yaml`）。`source.type=jira` 時
    **required**（derive jira mode → task.md `Base branch`）。
  - `tasks[].jira_key`：每筆 task 的真實子單 key（JIRA key string）或 `null`
    （尚未建子單）。`source.type=jira` 時為 string | null；`derive` 在 jira mode 對
    `null` fail-closed（要求先 populate，無 N/A fallback）。`source.type=dp` 時此欄位
    必須完全缺席。
  - `tasks[].repo`：optional per-task repo override。cross-repo Epic 的 task 可各自宣告
    product repo；缺欄位時 derive fallback `source.repo`。`source.type=dp` 時此欄位必須
    完全缺席。
  - `tasks[].base_branch`：optional per-task base branch override。值必須來自該 task repo 的
    `{company}/polaris-config/{repo}/handbook/config.yaml` `base_branch`；缺欄位時 derive
    fallback `source.base_branch`。`source.type=dp` 時此欄位必須完全缺席。

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
