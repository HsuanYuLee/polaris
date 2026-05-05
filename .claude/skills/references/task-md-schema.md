# task.md Schema — Single Source of Truth

> **Status**: v1 (DP-033 Phase A + Phase B)。實作 schema (T{n}.md) + 驗收 schema (V{n}.md) 雙路徑齊備；對稱原則：驗收也是工程，所有共用基礎設施 (parser / closer / hook / D6 pr-release / D7 atomic write contract / jira_transition_log) 一份權威、T/V 共用。
>
> **Source DPs**: DP-023 (runtime contract) · DP-025 (artifact schema enforcement) · DP-028 (depends_on / Base branch binding) · DP-032 (deliverable / jira_transition_log lifecycle write-back) · DP-033 (本 reference — schema 整合 + lifecycle closure；Phase A 實作 schema、Phase B 驗收 schema) · DP-065 (task / gate contract hardening)

本 reference 是 task.md 的單一權威 schema 文件 — pipeline 的所有 producer / consumer / validator / hook 都從此派生。若本檔與個別 SKILL.md / DP plan / `pipeline-handoff.md` 描述衝突，**以本檔為準**。

---

## 1. Overview

### 兩種 task.md

Polaris pipeline 的 task.md 分兩類，都存在於同一個 Epic 的 `{specs_root}/companies/{company}/{EPIC}/tasks/` 下：

| 類型 | Filename pattern | Producer | Consumer | Schema 章節 |
|------|------------------|----------|----------|-------------|
| 實作 task.md | `T{n}[suffix].md`（`T1.md` / `T3a.md` / `T8b.md`） | `breakdown` Path A | `engineering` | § 3 Implementation Schema |
| 驗收 task.md | `V{n}[suffix].md`（`V1.md` / `V2a.md`） | `breakdown` Step D | `verify-AC` | § 4 Verification Schema |

Framework DP-backed work orders（DP-047 / DP-050）使用同一份 Implementation Schema，只是 root 從 company specs folder 換成：

```text
{specs_root}/design-plans/DP-NNN-{slug}/tasks/T{n}.md
{specs_root}/design-plans/DP-NNN-{slug}/tasks/T{n}/index.md
{specs_root}/design-plans/DP-NNN-{slug}/tasks/V{n}.md
{specs_root}/design-plans/DP-NNN-{slug}/tasks/V{n}/index.md
```

DP-backed task 使用 source-neutral identity：`source_type=dp`、`source_id=DP-NNN`、`work_item_id=DP-NNN-Tn` / `DP-NNN-Vn`、`jira_key=null`。Migration 期仍接受舊 task.md 把 pseudo-task ID 放在 `Task JIRA key` / `JIRA:`，但新 DP-backed task 應使用 canonical metadata row，並保留 `JIRA: N/A` 讓舊 reader 不因欄位缺失失效。

> **Reader fallback callout（DP-033 D8）**：所有用 task key 找 file 的 reader（`parse-task-md.sh` / `validate-task-md-deps.sh` / `verify-AC` / `engineering` / 未來 Specs Viewer）在 active `tasks/` 找不到 key 時，必須 fallback `tasks/pr-release/`，避免歷史 reference 在 task 完結後斷鏈。完整 fallback 規則 + lookup 優先順序見 § 6 Validator Mapping。`tasks/pr-release/` fallback 不等於 archive lookup；`archive/` 是 completed/abandoned container 的歷史命名空間，active resolver 預設必須排除，只有 direct archived path 或明確 `--include-archive` 類模式才可讀取。

### Filename → Schema dispatch

`pipeline-artifact-gate.sh` PreToolUse hook 用 filename pattern dispatch validator：

```
specs/*/tasks/T*.md 或 specs/*/tasks/T*/index.md → validate-task-md.sh (T mode) + validate-task-md-deps.sh
specs/*/tasks/V*.md 或 specs/*/tasks/V*/index.md → validate-task-md.sh (V mode) + validate-task-md-deps.sh（同 deps validator，自動掃 T+V）
specs/*/tasks/pr-release/*.md 或 specs/*/tasks/pr-release/*/index.md → 完全 skip（D6 pr-release 機制；validator 不掃 pr-release/，但 reader fallback 會搜）
specs/**/archive/**/tasks/*.md → 完全 skip（歷史 container，不屬 active task gate）
其他 .md             → 不適用 task.md schema
```

**Filename 為唯一 type 訊號**（DP-033 D2，2026-04-26 修正）：T*.md = 實作、V*.md = 驗收，dispatch 完全由 filename 決定。**不在 frontmatter 重複 `type` 欄位** — 任何「雙保險」`type` field 都是 illusory（rename 時 stale，ground truth 仍是 filename）。

---

## 2. Common Schema

兩種 task.md 共享下列結構規則。Implementation / Verification 額外章節分別在 § 3 / § 4。

### 2.1 Frontmatter

```yaml
---
title: "T1: Example implementation task (3 pt)"
status: IN_PROGRESS         # optional：IN_PROGRESS | IMPLEMENTED | BLOCKED
depends_on: [T1]            # optional：array of task id strings；長度 ≤ 1（DP-028 強制線性）
deliverable:                # Lifecycle-conditional（DP-032 D2）；engineering Step 7c 寫入
  pr_url: https://github.com/.../pull/2202
  pr_state: OPEN            # OPEN | MERGED | CLOSED
  head_sha: abc1234
extension_deliverable:      # Lifecycle-conditional（DP-048）；local_extension completion 寫入
  endpoint: local_extension
  extension_id: example-extension
  task_head_sha: abc1234
  workspace_commit: def5678
  template_commit: fedcba9
  version_tag: v3.73.45
  release_url: https://github.com/org/repo/releases/tag/v3.73.45
  completed_at: 2026-04-29T00:00:00Z
  evidence:
    ci_local: /tmp/polaris-ci-local-task-DP-048-T1-abc1234.json
    verify: <main checkout>/.polaris/evidence/verify/polaris-verified-DP-048-T1-abc1234.json
    vr: N/A
jira_transition_log:        # Lifecycle-conditional（DP-033 D7）；engineering / verify-AC append
  - time: 2026-04-26T10:30:00Z   # ISO 8601；建議但不強制
    # 其他欄位 freeform — 各公司 / 各 transition flow 自訂
  - time: 2026-04-26T11:15:00Z
    company_specific_field: ...
verification:               # Optional；breakdown 可宣告 runtime visual / behavior evidence 需求
  visual_regression:
    expected: none_allowed   # none_allowed | baseline_required | update_baseline
    pages: []                # [] = 使用 workspace config pages；非空 = page subset
  behavior_contract:
    applies: false
    reason: "static documentation task"
---
```

| 欄位 | 寫入時機 | Required 層級 |
|------|---------|---------------|
| `title` | breakdown 建立 task.md 時寫入，須與 H1 summary 穩定對應 | Required for docs-manager Starlight `docsSchema()` |
| `status` | breakdown 寫初值（可省略）；engineering Step 8a 標 `IMPLEMENTED`；verify-AC 全 PASS 標 `IMPLEMENTED`（Epic level）| Optional（值若存在須為 enum） |
| `depends_on` | breakdown Step 14 |  Optional；存在則須為 array、長度 ≤ 1、所有 entry 須對應同 `tasks/` 下既有 task.md（含 `pr-release/` fallback，見 § 5.2） |
| `deliverable` | engineering Step 7c (`gh pr create` 成功後) | Lifecycle-conditional — breakdown 階段不存在；engineering 寫入後須結構正確（schema + writer contract 見下） |
| `extension_deliverable` | local_extension completion helper（DP-048） | Lifecycle-conditional — local extension completion metadata；可補充真實 workspace PR deliverable 的 post-PR release tail；不得與 fake `deliverable.pr_url` 混用；Layer B evidence path 優先使用 `.polaris/evidence/verify/` durable mirror |
| `jira_transition_log` | engineering / verify-AC 每次跑 JIRA transition 後 append（成功 / 失敗皆記） | Lifecycle-conditional — 同上 |
| `verification.visual_regression` | breakdown / refinement 宣告 runtime visual evidence 需求 | Optional；存在時 `expected` 必須是 enum、`pages` 必須是 YAML list，且 `## Test Environment` Level 必須是 `runtime` |
| `verification.behavior_contract` | breakdown 宣告使用者可見行為驗證意圖 | Optional；存在時必須明確 `applies`。`applies=true` 時不得用 unknown/default，需填 mode、source_of_truth、fixture_policy、flow、assertions |

> Filename 為唯一 type 訊號（DP-033 D2 修正版）— frontmatter **不再有 `type` 欄位**。所有 schema dispatch 都依 filename pattern（T*.md / V*.md），請勿在 frontmatter 加 `type` 欄位。
>
> `title` 是 docs-manager source contract，不是 type 訊號。Starlight `docsSchema()` 直接讀 `{specs_root}`，因此 task producer 必須把 `title` 寫回 source markdown，不可仰賴 generated mirror 或 custom loader 補齊。

#### `jira_transition_log[]` schema（DP-033 D7，寬鬆）

採 list-of-maps，validator 只檢結構性、**不檢內容 / 型別 / 命名**：

- 欄位若存在必須是 list（YAML array）
- 每個 entry 必須是 map（YAML object）
- `time` 欄位（ISO 8601）**建議**有（為了排序與未來 doc viewer 顯示），但**不強制**
- 其他欄位（如 `from` / `to` / `actor` / `error` / `transition_id` / 公司自訂欄位）freeform，validator 不 enforce

Writer：engineering / verify-AC 在做 JIRA transition 時 append entry — 成功與失敗皆寫一筆，便於後續 retry / 人工排查。未來擴充：doc viewer 可對常見欄位（time / from / to / error）做特殊渲染，但 schema 層保持中性。

#### `verification.visual_regression` schema（DP-104）

當 task 需要 native visual regression evidence 時，在 frontmatter 宣告：

```yaml
verification:
  visual_regression:
    expected: none_allowed
    pages: ["/zh-tw"]
```

規則：

- `expected` required；enum：`none_allowed` / `baseline_required` / `update_baseline`
- `pages` required；必須是 YAML list。`[]` 表示 runner 使用 workspace config 對應 domain 的全部 pages；非空 list 表示只跑 subset。
- 宣告 `verification.visual_regression` 時，`## Test Environment` 的 `Level` 必須是 `runtime`。
- Parser 必須輸出 `verification_visual_regression_expected` 與 `verification_visual_regression_pages` field，並在 full JSON 保留 `verification.visual_regression.pages` list 型別。

#### `verification.behavior_contract` schema（DP-109）

當 task 涉及使用者可見 UI / runtime 行為時，breakdown 必須宣告驗證意圖，讓
engineering 知道要維持既有行為、對齊設計稿，或依 PM 操作 flow 驗證。

```yaml
verification:
  behavior_contract:
    applies: true
    mode: parity
    source_of_truth: existing_behavior
    fixture_policy: mockoon_required
    baseline_ref: develop
    target_url: "/zh-tw/product/12156"
    viewport: mobile
    flow: "open media lightbox, swipe next, close"
    assertions:
      - "modal visible"
      - "counter changes after swipe"
    allowed_differences: []
```

不適用使用者可見 runtime 行為時，仍要能明確宣告不適用：

```yaml
verification:
  behavior_contract:
    applies: false
    reason: "static documentation task"
```

規則：

- `applies` required；必須是 `true` 或 `false`。
- `applies=false` 時，`reason` required。
- `applies=true` 時，`mode` required；enum：`parity` / `visual_target` / `pm_flow` / `hybrid`。
- `applies=true` 時，`source_of_truth` required；enum：`existing_behavior` / `figma` / `pm_flow` / `spec`。
- `applies=true` 時，`fixture_policy` required；enum：`mockoon_required` / `live_allowed` / `static_only`。
- `applies=true` 時，`flow` required 且不可空白；`assertions` required 且必須是非空 YAML list。
- `viewport` optional；若存在，必須是 `mobile` / `desktop` / `responsive`。
- `baseline_ref`、`target_url` optional；若存在，必須是非空字串。
- `allowed_differences` optional；若存在，必須是 YAML list。`mode=hybrid` 時必須非空。
- 不允許 `mode=unknown` 或省略 mode 讓 engineering 自行猜測。

Mode 選擇：

- 替換元件、migration、refactor、移除 legacy dependency：使用 `parity`；若有少量刻意可見差異，使用 `hybrid` 並列出 `allowed_differences`。
- Figma 驅動的畫面變更：使用 `visual_target`，source_of_truth 通常是 `figma`。
- PM 提供操作 flow，但沒有要求前後畫面 parity：使用 `pm_flow`，source_of_truth 通常是 `pm_flow`。
- 若需求來源尚未決定應維持既有行為或接受畫面變更，回到 refinement；不得建立 READY task。

#### `deliverable` schema + writer contract（DP-033 D7，atomic + fail-stop）

**Schema（when present）**：

| 欄位 | Required | 規則 |
|------|----------|------|
| `pr_url` | required | 必須 match `^https://github\.com/.+/pull/\d+$` |
| `pr_state` | required | enum：`OPEN` / `MERGED` / `CLOSED` |
| `head_sha` | required | 7+ char hex |
| 額外欄位 | optional | 由 engineering writer 定義 |

**Writer contract（engineering Step 7）**：

1. `gh pr create` 成功 → **立刻**嘗試寫 `## deliverable` section（含 frontmatter `deliverable:` block 結構，依當前實作）
2. 寫入失敗（exit ≠ 0 / 被 hook 擋）→ retry **最多 3 次**（exponential backoff）
3. 重試仍失敗 → **HARD STOP**，回報：
   - PR URL（已建立）
   - task.md path
   - 失敗原因（hook output / 錯誤訊息）
   - 訊息：「task is in inconsistent state — PR created but task.md not updated. Manual recovery required.」
4. **不繼續執行下游步驟**（JIRA transition / Slack 通知 / next handoff）— 寧可 stop，不可 silent fallback
5. 寫入後 **verify**：re-read 檔案、確認 `deliverable` block 存在且 `pr_url` 正確；mismatch → 同 step 3 fail-stop

**Validator 配合**：

- Lifecycle-conditional：**不檢查存在性**（breakdown 階段不存在合法）
- **存在時必須驗 schema**（pr_url / pr_state / head_sha 結構正確）
- 不可有「validator 太嚴」擋住 engineering 自己的合法寫入（schema 寬度 ⊇ writer 輸出）

**Rationale**：silent fallback（log 到 /tmp、繼續執行）= task.md 與真實狀態不一致 → 下次 engineering 重跑時誤判為 first-cut → 重複建 PR。Inconsistent state 必須立刻被人類看到並處理。

#### `extension_deliverable` schema + writer contract（DP-048，local_extension）

用於 DP-backed framework task 走 local maintainer release endpoint 時，記錄真實 release deliverable，而不是把假 PR URL 塞進 `deliverable.pr_url`。若 local policy 要求 workspace PR，`deliverable` 記錄真實 workspace PR，`extension_deliverable` 補充 PR merge 後的 release / template sync 結果；若 local policy 明確不建 PR，`deliverable` 可不存在。

```yaml
extension_deliverable:
  endpoint: local_extension
  extension_id: example-extension
  task_head_sha: abc1234          # engineering gates 驗證過的 task HEAD
  workspace_commit: def5678       # workspace release commit
  template_commit: fedcba9        # extension-owned release commit
  version_tag: v3.73.45           # 若 local policy 無 tag，可寫 N/A
  release_url: https://github.com/org/repo/releases/tag/v3.73.45
  completed_at: 2026-04-29T00:00:00Z
  evidence:
    ci_local: /tmp/polaris-ci-local-...  # or N/A when repo has no ci-local declared
    verify: /tmp/polaris-verified-DP-NNN-Tn-...
    vr: N/A
```

Writer：`scripts/write-extension-deliverable.sh`。

Completion gate：`scripts/check-local-extension-completion.sh`，檢查：

- `extension_deliverable.endpoint == local_extension`，`extension_id` 符合呼叫端指定值
- `task_head_sha`、`workspace_commit`、`template_commit` 格式正確；`workspace_commit` 必須包含 `task_head_sha`
- Layer A `ci_local` evidence 若 repo 宣告 ci-local 則必須存在、PASS、且 `head_sha` 對應 `task_head_sha`；若 repo 無 ci-local，寫 `N/A`
- Layer B `verify` evidence 必須存在、PASS、且 `head_sha` 對應 `task_head_sha`
- `workspace_commit` 對應目前 workspace HEAD；若提供 template repo，`template_commit` 對應 template HEAD，`version_tag` 存在

`extension_deliverable` 只能由 helper 寫入。local_extension lane 若 helper 尚未成功，不得標 `status: IMPLEMENTED`。

### 2.2 標題行

```
# T{n}[suffix]: {Task summary} ({SP} pt)
# V{n}[suffix]: {Verification summary} ({SP} pt)
```

- `{n}` = 整數（從 1 開始）
- `[suffix]` = optional `a-z*`，支援 split subtasks（如 `T8a` / `T8b` / `V1a`）
- `{SP}` = story points（整數或小數；如 `3` / `2.5`）

Validator regex：`^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)`

### 2.3 Header 行（metadata quote）

緊接標題後一行：

Legacy product / historical DP metadata:

```
> Epic: {EPIC_KEY} | JIRA: {TASK_KEY} | Repo: {repo_name}
```

Canonical source-neutral metadata（DP-050 migration candidate）:

```
> Source: {SOURCE_ID} | Task: {WORK_ITEM_ID} | JIRA: {JIRA_KEY_OR_N/A} | Repo: {repo_name}
```

- `Epic:` / `Source:` **Soft required**（DP-033 D5 + DP-050）— product task 通常用 `Epic:`，source-neutral task 用 `Source:`；Bug task 是真實無 Epic 場景，硬 require 只會逼填假 Epic
- `Task:` **canonical task identity** — source-neutral `work_item_id`。Product task 可等於 JIRA key；DP-backed framework work item 使用 pseudo ID `DP-NNN-Tn` / `DP-NNN-Vn`
- `JIRA:` **migration required segment** — 真實 JIRA key；若來源不是 JIRA（例如 DP task）填 `N/A`。Legacy task 可只用 `JIRA:` 承載 task identity
- `Repo:` **必填** — 非空字串

Validator accepts either legacy or canonical shape:

```regex
legacy:    ^> .*JIRA: ([A-Z][A-Z0-9]*-[0-9]+|DP-[0-9]{3}-[TV][0-9]+[a-z]*)
canonical: ^> .*Task: ([A-Z][A-Z0-9]*-[0-9]+|DP-[0-9]{3}-[TV][0-9]+[a-z]*).*JIRA: ([A-Z][A-Z0-9]*-[0-9]+|N/A)
^> .*Repo: \S+
```

Parser canonical output:

```json
{
  "identity": {
    "source_type": "dp",
    "source_id": "DP-050",
    "work_item_id": "DP-050-T1",
    "jira_key": null
  }
}
```

Migration aliases:

| Field | Product task | DP-backed task |
|-------|--------------|----------------|
| `work_item_id` | Real task JIRA key | DP pseudo ID (`DP-NNN-Tn` / `DP-NNN-Vn`) |
| `jira_key` | Real task JIRA key | `null` / empty field output |
| `task_jira_key` | Alias of `work_item_id` | Compatibility alias of `work_item_id`; deprecated for new consumers |
| `jira` | Legacy metadata alias | Empty when metadata says `JIRA: N/A` |

### 2.4 Status 規則 + PR-release 邊界

`status` 是任務 lifecycle 的 single source of truth：

- **未填** = 進行中（默認）
- **`IN_PROGRESS`** = engineering 已啟動但尚未開 PR
- **`IMPLEMENTED`** = 任務已開 PR / 待 release — 由 `engineering` Step 8a 或 `verify-AC` 全 PASS 寫入；同時觸發 D6 PR-release move
- **`BLOCKED`** = 暫時擱置（informal，不觸發任何 hook）

PR-release 觸發（DP-033 D6，**move-first 順序鎖定**）：`status` 轉為 `IMPLEMENTED` → `mark-spec-implemented.sh` 嚴格依下列順序執行：

1. `mv tasks/T1.md tasks/pr-release/T1.md`（先搬）
2. 在 `pr-release/T1.md` update frontmatter 標 `IMPLEMENTED`（後改）

永遠不會出現「在 active `tasks/` 內標完結」的 transient state。Validator 不掃 `pr-release/`，但下游 reader（`parse-task-md.sh` / `validate-task-md-deps.sh` / `verify-AC` 解 V-key / `engineering` / 未來 Specs Viewer）在 `tasks/` 找不到時 fallback `pr-release/`，保 depends_on 鏈不斷裂（完整 reader fallback 規則見 § 6）。

**Hard invariant**：完結（frontmatter `status: IMPLEMENTED`）但仍位於頂層 `tasks/` 而非 `tasks/pr-release/` → validator **HARD FAIL**（exit 2）。詳見 § 5.5。

---

## 3. Implementation Schema (T{n}.md)

### 3.1 Required sections inventory

| 章節 | Required 層級 | 來源 DP | Validator |
|------|--------------|---------|-----------|
| 標題行 `# T{n}[suffix]: ...` | **Hard** | DP-025 | `validate-task-md.sh` regex |
| Header `> Epic\|JIRA\|Repo` | **Hard** (`JIRA` + `Repo`) | DP-025 | `validate-task-md.sh` regex |
| `## Operational Context` | **Hard** | DP-023 / DP-025 / DP-028 | `validate-task-md.sh`（章節存在 + 必填 cells + JIRA key + Depends on cross-field） |
| `## Verification Handoff` | Optional | DP-025 | `validate-task-md.sh`（章節存在；內容不檢） |
| `## 目標` | **Soft** | DP-025 | `validate-task-md.sh`（章節存在 + 非空） |
| `## 改動範圍` | **Hard** | DP-025 | `validate-task-md.sh`（章節存在 + 非空 body） |
| `## Allowed Files` | **Hard** | DP-033 D5 (升級自 Soft，2026-04-26 鎖定) | `validate-task-md.sh`（章節存在 + 非空 bullet list）— 直接 Hard，**不開 grace、不留 warn-only**；既有 active T 缺漏由 A7 migration script **強制 backfill** |
| `## Scope Trace Matrix` | **Breakdown readiness Hard** | DP-112 | `validate-breakdown-ready.sh`（章節存在 + goal/AC → owning files → surface/boundary → tests；owning files 必須被 Allowed Files 覆蓋） |
| `## 估點理由` | **Hard** | DP-025 | `validate-task-md.sh`（章節存在 + 非空 body） |
| `## 測試計畫（code-level）` | **Soft** | DP-025 | `validate-task-md.sh`（章節存在；內容不檢） |
| `## Test Command` | **Hard** | DP-005 / DP-025 | `validate-task-md.sh`（章節存在 + 含 fenced code block） |
| `## Test Environment` | **Hard** | DP-023 | `validate-task-md.sh`（章節存在 + Level enum + Runtime contract — 見 § 3.3） |
| `## Gate Closure Matrix` | **Breakdown readiness Hard** | DP-082 | `validate-breakdown-ready.sh`（章節存在 + scope/test/verify/ci-local + pass condition + owner/decision） |
| `## Verify Command` | **Hard**（`Level≠static` 時） | DP-023 | `validate-task-md.sh`（章節存在 + 含 fenced code block + Level=runtime 時 host alignment） |

### 3.2 `## Operational Context` table cells

必填 cells（每個 cell 名稱在 markdown table 第一欄；validator 要求字面比對命中）：

| Cell | 內容 | Required |
|------|------|----------|
| `Source type` | Canonical source type：`jira` / `dp` | **Hard in canonical identity** |
| `Source ID` | Parent source/container：product Epic key（如 `EPIC-478`）或 DP id（如 `DP-050`） | **Hard in canonical identity** |
| `Task ID` | Canonical `work_item_id`：product task JIRA key 或 DP pseudo ID（如 `DP-050-T1` / `DP-050-V1`） | **Hard in canonical identity** |
| `JIRA key` | 真實 JIRA issue key；無 JIRA 時填 `N/A` | **Hard in canonical identity** |
| `Task JIRA key` | Legacy identity cell；migration 期仍接受。新 DP-backed task 不應使用此 cell 承載 pseudo-task ID | **Hard in legacy identity** |
| `Parent Epic` | Legacy parent cell；migration 期仍接受 | **Hard in legacy identity** |
| `Test sub-tasks` | Test sub-task JIRA keys（comma-separated） | **Hard** |
| `AC 驗收單` | Verification ticket JIRA key（V*.md 對應的 ticket，或 verify-AC 消費的 AC ticket） | **Hard** |
| `Base branch` | 切 task branch / PR base 用的 base — 有 `Depends on` 時必須 `task/...`（DP-028 cross-field）；無依賴時通常 `feat/...` | **Hard** |
| `Branch chain` | 從本 work owner 可維護的最上游 anchor 到本 task branch 的完整 rebase 鏈（例：`develop -> feat/EPIC-478-... -> task/TASK-3711-... -> task/TASK-3900-...`）。若 base 是外部 dependency branch（例如別人開的 `task/<KEY>-...` / 外部 PR head），chain 必須從該外部 branch 開始，例：`task/<EXTERNAL_KEY>-... -> feat/EPIC-495-... -> task/TASK-3662-...`，不可寫成 `develop -> task/<EXTERNAL_KEY>-... -> ...`；engineering 用 `scripts/cascade-rebase-chain.sh` 消費；PR base 仍由 `Base branch` + `resolve-task-base.sh` 決定 | **Soft**（新 breakdown 必填；legacy task 缺漏時 reader fallback） |
| `Task branch` | 該 task 自己的 branch（`task/{TASK_KEY}-{slug}`） | **Hard** |
| `Depends on` | 同 Epic 內依賴的 task 描述（如 `TASK-3711 (T3a — dayjs infra)`）；無依賴 = `N/A` / `-` / 空 | **Soft**（cell 可缺；存在時參與 cross-field rule） |
| `References to load` | engineering sub-agent 須讀的 reference 列表（HTML `<br>` 換行） | **Hard** |

範例（節錄自 EPIC-478 T3b）：

```markdown
## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TASK-3900 |
| Parent Epic | EPIC-478 |
| Test sub-tasks | TASK-3826 |
| AC 驗收單 | TASK-3713 |
| Base branch | task/TASK-3711-dayjs-infra-util |
| Branch chain | develop -> feat/EPIC-478-moment-to-dayjs -> task/TASK-3711-dayjs-infra-util -> task/TASK-3900-moment-to-dayjs-products |
| Task branch | task/TASK-3900-moment-to-dayjs-products |
| Depends on | TASK-3711 (T3a — dayjs infra) |
| References to load | - `skills/references/branch-creation.md`<br>- ... |
```

Canonical DP-backed task example:

```markdown
> Source: DP-050 | Task: DP-050-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-050 |
| Task ID | DP-050-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-050-T1-canonical-task-identity |
| Task branch | task/DP-050-T1-canonical-task-identity |
| Depends on | N/A |
| References to load | - `skills/references/task-md-schema.md` |
```

### 3.3 `## Test Environment` schema (DP-023 runtime contract)

Bullet list 格式：

```markdown
- **Level**: runtime
- **Dev env config**: `workspace-config.yaml → projects[{repo}].dev_environment`
- **Fixtures**: `specs/{EPIC}/tests/mockoon/`（Mockoon CLI port 3100）
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash /Users/hsuanyu.lee/work/scripts/polaris-env.sh start exampleco --project {repo}
```

| 欄位 | Required | Level=static | Level=build | Level=runtime |
|------|----------|--------------|-------------|---------------|
| `Level` | **Hard**（enum: `static` / `build` / `runtime`） | required | required | required |
| `Dev env config` | **Soft** | optional | optional | required（指向 workspace-config 的 dev_environment block） |
| `Fixtures` | **Hard** | `N/A` | `N/A` | path（須存在於檔案系統 — DP-025 `validate-task-md-deps.sh` enforce）或 `N/A` |
| `Runtime verify target` | **Hard** | `N/A` | `N/A` | live URL（http/https，必填） |
| `Env bootstrap command` | **Hard** | `N/A` | `N/A` | shell command（必填） |

**Runtime cross-field rules**（`Level=runtime` 時）：

1. `Runtime verify target` 必須是 http/https URL（不可為 `N/A` / 空）
2. `Env bootstrap command` 必須非 `N/A`
3. `## Verify Command` fenced block 內必須出現 http/https URL
4. Verify Command URL 的 host **必須等於** Runtime verify target 的 host（DP-023 D2 Target-first）
5. docs-manager runtime task 必須把 `Runtime verify target` 和 Verify Command URL 寫到 `/docs-manager/` app path；bare origin（例如 `http://127.0.0.1:8080`）會被視為 invalid。若未來其他 app 有不同 base path，必須放在可測 contract/registry，不可只寫 prose。
6. `Fixtures` 若非 `N/A`，path 必須存在（resolve 順序：epic_dir → company_base_dir → workspace_root）

**Static / build 規則**：`Runtime verify target` / `Env bootstrap command` 預期 = `N/A`；若非 N/A → fail（避免假性宣告）。

### 3.4 `## Allowed Files`

```markdown
## Allowed Files

> breakdown 時依改動範圍列出，engineering 超出此清單的修改觸發 risk scoring +15%。

- `apps/main/plugins/dayjs.ts`
- `apps/main/products/**`
- `apps/main/products/**/*.spec.ts`
```

由 `engineer-delivery-flow.md` Step 5.5 Scope Check 消費。Hard required（DP-033 D5 升級自 Soft）— 缺失會讓 Scope Check 失靈，risk scoring 機制走空。

Allowed Files pattern 支援 repo-root relative path、glob，以及 root exact filename。`VERSION`、`README` 這類 root filename 是合法 exact pattern；不要為了通過 scope gate 改寫成 `VERSION*`。純自然語言 bullet（例如「上述檔案的 test 檔」）仍會被 scope matcher 跳過，不會變成萬用 pattern。

### 3.5 `## Scope Trace Matrix`

`## Scope Trace Matrix` 是 breakdown readiness 欄位，用來證明每個可觀測目標或 AC
都有明確 owning files、render/API 或系統邊界，以及測試。它補足 `Allowed Files`
只能描述可改檔案、但不能證明 scope 完整性的缺口。

最低格式：

```markdown
## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| dashboard 顯示 verification evidence | `docs-manager/src/pages/status.astro`, `scripts/build-status-data.mjs` | `/status` dashboard render surface | `pnpm --dir docs-manager build` |
```

規則：

- 至少一個 trace row；欄位名稱需包含 Goal/AC、Owning files、Surface/boundary、Tests。
- `Owning files` 必須是 path / glob token，且每個 token 必須被 `## Allowed Files` 覆蓋。
- UI / dashboard / API-visible work 必須列出 render/API surface；只列 data helper、
  presenter 或 generator 會被 readiness gate 擋下。
- `Surface / boundary` 不可填 `N/A` 或 unknown。若 surface 無法決定，producer 必須
  route refinement，不得交給 engineering 猜。

### 3.6 `## Gate Closure Matrix`

`## Gate Closure Matrix` 是 breakdown producer contract，不是一般 task schema 欄位。它由 `scripts/validate-breakdown-ready.sh` 在 breakdown handoff 前強制驗證，目的是避免 engineering 收到「沒有 pass 條件」的 work order。

最低格式：

```markdown
## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | changed files all match Allowed Files | breakdown |
| test | yes | Test Command passes | engineering |
| verify | yes | Verify Command passes | engineering |
| ci-local | no | N/A | no ci-local configured for this repo |
```

規則：

- 必須列出 `scope` / `test` / `verify` / `ci-local` 四個 gate。
- 每個 gate 都必須有 pass condition。
- 每個 gate 都必須有 owner / decision；baseline/env 類問題不可留白。
- `N/A` 合法，但必須有原因。
- `Allowed Files` 若含自然語言描述，readiness gate fail；自然語言只能放 `## 改動範圍`。

### 3.7 `## Test Command` / `## Verify Command`

兩者皆必須包含 fenced code block（內容由 LLM 不可改寫 — `verify-command-immutable-execute` canary）。
`## Verify Fallback Command` 是 optional section；只有 primary `## Verify Command`
因已確認 repo baseline issue 無法產生 artifact 時才可提供。Engineering 不得臨時改跑
其他 command；必須讓 `scripts/run-verify-command.sh` 先執行 primary，再於 primary
exit 非 0 時執行 fallback 並產生 `verification_mode=fallback` evidence。

DP-065 Verify Command static smoke 會在 validation 階段檢查可靜態證明的 command-shape 問題：repo-local script command 若該 script 有 `--help`，使用不存在的 `--flag` 會 fail；簡單 `rg` command 的 regex pattern 會做 parse-only smoke，regex parse error 會 fail。validator 不執行完整 Verify Command，也不嘗試解釋複雜 shell control flow。

`## Test Command` 的內容不是 schema 固定值，必須由 producer 依下列來源解析後填入：

1. `workspace-config.yaml` → `projects[].dev_environment.test_command`
2. 專案 CLAUDE.md 的測試指令
3. Fallback：`npx vitest run`

Monorepo 指令必須能從該 repo / worktree root 執行，並包含正確子目錄；例如 `pnpm --dir {app_dir} exec vitest run` 只適用於 repo root 下確實存在 `{app_dir}` 的專案，不能作為所有 task.md 的固定範例。

```markdown
## Test Command

> breakdown 產出。engineering 跑測試時**必須使用此指令**，不可自行推導。

​```bash
{project-specific test_command}
​```

## Verify Command

​```bash
curl -sf http://localhost:3100/api/activities -o /dev/null -w "%{http_code}" | python3 -c "..."
​```

預期輸出：`PASS`
```

### 3.6 Lifecycle-conditional sections

下列 sections / frontmatter 由 engineering（或 verify-AC）在特定 milestone 寫入；breakdown 階段不存在但**不應因此 fail validator**。Validator 只在「若存在」時檢查結構（schema 詳情見 § 2.1）：

| Section / Field | Writer | Trigger | 結構檢查 |
|-----------------|--------|---------|----------|
| frontmatter `deliverable.pr_url` | engineering Step 7（atomic + retry-3 + fail-stop，見 § 2.1） | `gh pr create` 成功 | URL regex `^https://github\.com/.+/pull/\d+$` |
| frontmatter `deliverable.pr_state` | engineering Step 7 / 啟動時 refresh | `gh pr view --json state` | enum: `OPEN` / `MERGED` / `CLOSED` |
| frontmatter `deliverable.head_sha` | engineering 每次 push 後 | `git push` 成功 | 7+ char hex |
| frontmatter `extension_deliverable.*` | local_extension completion helper（DP-048） | release metadata 寫回 | `endpoint=local_extension`、SHA/tag/URL/evidence schema；由 `check-local-extension-completion.sh` 做 freshness gate |
| frontmatter `jira_transition_log[]` | engineering / verify-AC 跑 JIRA transition 後 | append-only | list-of-maps；`time` 建議（不強制）；其他欄位 freeform（見 § 2.1 寬鬆 schema） |

### 3.7 Optional sections

- `## Verification Handoff` — Optional（DP-033 D5）；breakdown 慣例會寫一句「AC 驗證委派至 {AC_TICKET}」，但 validator 不檢查存在性 / 內容
- `## 測試計畫（code-level）` — Soft（章節存在即可，內容不檢）

### 3.8 完整範例（節錄結構）

```markdown
---
status: IMPLEMENTED
deliverable:
  pr_url: https://github.com/example-org/exampleco-b2c-web/pull/2202
  pr_state: OPEN
  head_sha: c7b4bf3a
jira_transition_log:
  - time: 2026-04-23T08:30:00Z
    from: TO_DO
    to: IN_DEVELOPMENT
    result: PASS
---

# T1: Mockoon fixtures 建立/擴充 (2 pt)

> Epic: EPIC-478 | JIRA: TASK-3821 | Repo: exampleco-b2c-web

## Operational Context
| 欄位 | 值 | ... |

## Verification Handoff
AC 驗證委派至 TASK-3713（由 verify-AC skill 執行）。

## 目標
{What this task accomplishes}

## 改動範圍
| 檔案 | 動作 | 說明 |

## Allowed Files
- `exampleco/mockoon/fixtures/gt478/`

## 估點理由
2 pt — ...

## 測試計畫（code-level）
- build check: ... → TASK-3823

## Test Command
​```bash
{project-specific test_command}
​```

## Test Environment
- **Level**: runtime
- **Fixtures**: `specs/EPIC-478/tests/mockoon/`
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash /path/to/polaris-env.sh start exampleco --project exampleco-b2c-web

## Verify Command
​```bash
curl -sf http://localhost:3100/api/activities ...
​```
```

具體 instance 見 `specs/companies/exampleco/EPIC-478/tasks/T1.md`、`T9.md`（或完結後的 `specs/companies/exampleco/EPIC-478/tasks/pr-release/T1.md`）。

---

## 4. Verification Schema (V{n}.md)

驗收 task.md schema。對稱原則：與 § 3 Implementation Schema 對齊，所有共用基礎設施（中央 parser、move-first closer、PreToolUse hook dispatch、D6 pr-release/、D7 atomic write contract、`jira_transition_log[]`）一份權威、T/V 共用，**不平行造**。

**Filename pattern**：`V{n}[suffix].md`（`V1.md` / `V2a.md` / `V8b.md`）— sequential 從 `V1` 起、sub-split 用 `V1a` / `V1b`（與 T{n} 同規則 — DP-033 D2 + BS#10）。**Filename 為唯一 type 訊號**，frontmatter **不**引入 `type` 欄位（DP-033 D2 修正版，2026-04-26）。

> **既有 `{JIRA-KEY}.md` 命名的驗收 task.md migration（filename 從 KB2CW-XXXX.md 改為 V{n}.md）+ verify-AC consumer 重構（讀 V*.md / 寫回 `ac_verification`）→ 移交 DP-039 `/verify-AC refactor`**（DP-033 D3 + BS#7 + BS#8）。本 § 4 只定義 target schema 與 contract，producer / consumer 切換由 DP-039 atomic 切到位。

### 4.1 Required sections inventory

| 章節 | Required 層級 | 來源 DP | Validator | T 對應 |
|------|--------------|---------|-----------|--------|
| 標題行 `# V{n}[suffix]: ...` | **Hard** | DP-033 Phase B | `validate-task-md.sh`（V mode）regex `^# V[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)` | 同 T |
| Header `> Epic\|JIRA\|Repo` | **Hard**（`JIRA` + `Repo`），Soft（`Epic`） | DP-033 Phase B | `validate-task-md.sh`（V mode；§ 2.3 規則同 T，含 Bug task 無 Epic 場景） | 同 T |
| `## Operational Context` | **Hard** | DP-033 Phase B | `validate-task-md.sh`（V mode；cells 集合 § 4.2，與 T cells 對應但部分 V-specific） | 同 T |
| `## Verification Handoff` | Optional | DP-033 Phase B | 不檢；breakdown 慣例寫一句「驗收將由 verify-AC 觸發」 | 同 T |
| `## 目標` | **Soft** | DP-033 Phase B | 章節存在 + 非空（warn-only） | 同 T |
| `## 驗收項目` | **Hard** | DP-033 Phase B | `validate-task-md.sh`（V mode；章節存在 + 非空 body — markdown row 或 bullet ≥ 1） | 對應 T 的 `## 改動範圍`（語意對稱：T 列檔案改動，V 列 AC 覆蓋；命名分開避免混淆）|
| `## 估點理由` | **Hard** | DP-033 Phase B | 章節存在 + 非空 body | 同 T |
| `## 驗收計畫（AC level）` | **Soft** | DP-033 Phase B | 章節存在；內容不檢 | 對應 T 的 `## 測試計畫（code-level）`（語意對稱：T 是 code-level 測試，V 是 AC-level 驗收計畫）|
| `## Test Environment` | **Hard** | DP-023 / DP-033 Phase B | `validate-task-md.sh`（V mode；§ 3.3 整節適用，Level enum + Runtime cross-field 全共用 T mode） | 同 T |
| `## 驗收步驟` | **Hard**（`Level≠static` 時） | DP-033 Phase B | `validate-task-md.sh`（V mode；章節存在 + 含 fenced code block + Level=runtime 時 host alignment 同 § 3.3） | 對應 T 的 `## Verify Command`（語意對稱：T 是 deterministic shell，V 是 verify-AC LLM driver entry + 逐 AC 步驟描述）|

**合理省略（不對稱、相對 T；驗收不寫 code）**：

| T 章節 | V 為何省略 |
|--------|-----------|
| `## Allowed Files` | 驗收不寫 code，無 Scope Check 概念（engineer-delivery-flow Step 5.5 不適用 V） |
| `## Test Command` | 驗收跑 AC、不跑 unit test（unit test 屬實作 T 範疇） |

> **對稱原則註**：基礎設施 reuse — `parse-task-md.sh` 中央 parser（filename 自動識別 T/V）、`mark-spec-implemented.sh` move-first closer（filename dispatch 對 T/V 共用，§ 4.6）、`pipeline-artifact-gate.sh` PreToolUse hook、D6 `tasks/pr-release/` 機制、D7 atomic + retry-3 + fail-stop write-back contract、`jira_transition_log[]` lifecycle 欄位 — 全部 T/V 共用，新增的只有 `ac_verification` / `ac_verification_log[]` 兩個 frontmatter 欄位 + `validate-task-md.sh` V mode 規則集。

### 4.2 `## Operational Context` table cells (V 版)

對應 § 3.2，但 cells 集合略不同（T-only cells 移除，V-specific cells 新增）：

| Cell | 內容 | Required | T 版差異 |
|------|------|----------|----------|
| `Task JIRA key` | 該 V 的 JIRA key（AC 驗收單，如 `TASK-3713`） | **Hard** | 同 T |
| `Parent Epic` | Epic key | **Hard** | 同 T |
| `Implementation tasks` | 該 V 驗證的實作 task 列表（如 `T1, T3a, T3b`） | **Hard** | **V 新增**；對稱 T 的 `Test sub-tasks`（T 列驗測 sub-task；V 列被驗 implementation tasks）|
| `Base branch` | 驗收跑的 branch（通常 `feat/...` 或 `develop`） | **Hard** | 同 T；V 用法是「在哪條 branch 跑驗收」，**通常不會是 `task/...`**（task branch 是個別 implementation 範疇） |
| `Depends on` | 同 Epic 內 V→T 或 V→V 依賴（如 `TASK-3902 (T3d — adapter cleanup)`），無依賴 = `N/A` / `-` / 空 | **Soft**（cell 可缺；存在時參與 cross-field rule） | 同 T；**V→T 合法、V→V 線性合法**（§ 5.3）|
| `References to load` | verify-AC sub-agent 須讀的 reference 列表（HTML `<br>` 換行） | **Hard** | 同 T；典型如 `verify-AC` skill 內 reference、Epic-specific test plan |

V 不適用的 T cells（**移除**，validator V mode 不檢）：

- `Test sub-tasks` — T 用來列驗測 sub-task；V 自己就是 driver，不需要列再下一層 sub-task
- `AC 驗收單` — T 用來指向 V；V 自己就是 AC 驗收單，不指向自己
- `Task branch` — V 不開 branch（驗收不開 fix branch；AC FAIL 走 bug-triage 開新 T）

範例（節錄自 EPIC-478 的 V1，未來 DP-039 migration 落地後）：

```markdown
## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TASK-3713 |
| Parent Epic | EPIC-478 |
| Implementation tasks | T1, T3a, T3b, T3c, T3d |
| Base branch | feat/EPIC-478-moment-to-dayjs |
| Depends on | TASK-3902 (T3d — adapter cleanup) |
| References to load | - `skills/references/verify-AC.md`<br>- `specs/EPIC-478/refinement.json` |
```

### 4.3 `## 驗收項目`（對應 T 的 `## 改動範圍`）

列舉 V*.md 涵蓋的 AC + 對應的實作 task；verify-AC 跑此清單、逐項回填 `ac_verification_log[]`：

```markdown
## 驗收項目

> breakdown 產出。verify-AC 跑下列 AC，逐項回填 frontmatter `ac_verification_log[]`。

| AC | 摘要 | 對應實作 task | 驗證類型 |
|----|------|--------------|---------|
| AC-1 | dayjs API 計算結果與 moment 一致（datetime range） | T1, T3a | runtime |
| AC-2 | products 頁面 SSR 顯示正確時區 | T3b | runtime |
| AC-3 | i18n locale 正確套用 | T3b, T3c | runtime |
| AC-4 | adapter cleanup 不留 moment import | T3d | static |
```

或 bullet list（簡單 case，validator 接受兩種）：

```markdown
## 驗收項目

- AC-1: dayjs 計算結果與 moment 一致 — covers T1, T3a (runtime)
- AC-2: products SSR 時區正確 — covers T3b (runtime)
- AC-3: ...
```

Validator (V mode): 章節存在 + 至少 1 個 markdown row（`|` 開頭）或 bullet（`- ` 開頭），與 § 3.4 `## Allowed Files` 同精神。

### 4.4 `## Test Environment` schema

V mode **完全共用** T mode 的 Test Environment 規則（§ 3.3 整節適用）：

- Level enum (`static` / `build` / `runtime`)
- Runtime cross-field rules（`Runtime verify target` http/https URL + `Env bootstrap command` 必填 + `Verify Command` URL host alignment — 對 V 來說是 `## 驗收步驟` 內 fenced block 的 URL）
- Static / build 規則（`Runtime verify target` / `Env bootstrap command` 必須 `N/A`）
- `Fixtures:` 路徑存在性（DP-025，由 `validate-task-md-deps.sh` enforce）

verify-AC 與 engineering 共用 Epic 內的 fixtures / dev environment / runtime verify target — 不重複定義。

### 4.5 `## 驗收步驟`（對應 T 的 `## Verify Command`）

對稱原則下，V*.md 也定義可執行 entry — 但 V 的 entry 是 verify-AC LLM driver，section 內容是「逐 AC 步驟描述 + 預期結果」：

```markdown
## 驗收步驟

> breakdown 產出。verify-AC 跑此 V*.md 時逐項執行，並把結果回填 frontmatter `ac_verification` + `ac_verification_log[]`。

​```bash
# Entry: verify-AC consumes this V*.md per AC step list below.
# verify-AC LLM driver 逐項跑 AC（含 Test Environment 啟動、HTTP curl、UI 檢查），
# 觀察結果與下方 Expected 比對，最後寫回 ac_verification + ac_verification_log。
echo "AC steps defined below — verify-AC executes this V*.md."
​```

### AC-1: dayjs API 計算結果與 moment 一致

**Step**:
1. 啟動 dev environment：`bash polaris-env.sh start exampleco --project exampleco-b2c-web`
2. `curl -sf http://localhost:3100/api/products?dateFrom=2026-01-01&dateTo=2026-01-31`

**Expected**:
- HTTP 200
- response.data.priceRange 與 main branch（pre-migration）數值一致

### AC-2: products 頁面 SSR 顯示正確時區

**Step**:
1. browser visit `https://localhost:3100/zh-tw/product/123`
2. 觀察日期顯示

**Expected**:
- 日期顯示為 UTC+8（台北時區）
- 不出現 `NaN` / `Invalid Date`
```

Validator (V mode):

- 章節存在
- 含至少 1 個 fenced code block（entry 訊號）
- Level=runtime 時，code block 內須含 http/https URL，URL host 須等於 `Runtime verify target` host（同 § 3.3 / § 5.1 cross-field rule，T mode 邏輯共用）

> **個別 AC 步驟結構不檢**：避免過度束縛 — `### AC-N: ...` / `**Step**` / `**Expected**` 是慣例 markdown，breakdown 產出依此模板但 validator 不 enforce 細節結構（內容由 verify-AC LLM 解讀）。

### 4.6 Lifecycle-conditional sections (V 版)

對應 § 3.6，但 V 用 `ac_verification` + `ac_verification_log[]` 取代 `deliverable`；`jira_transition_log[]` T/V 共用：

| Field | Writer | Trigger | 結構檢查 |
|-------|--------|---------|----------|
| frontmatter `ac_verification` | verify-AC（每輪覆寫，§ 4.7 contract） | 每跑完一輪 AC verification | map；status enum / last_run_at ISO8601 / 計數 int / human_disposition enum (conditional) |
| frontmatter `ac_verification_log[]` | verify-AC（每輪 append，§ 4.7 contract） | 每跑完一輪 AC verification | list-of-maps；`time` ISO 8601 建議；其他欄位 freeform（同 `jira_transition_log[]` 寬鬆原則） |
| frontmatter `jira_transition_log[]` | engineering / verify-AC（共用，append-only） | 跑 JIRA transition 後 | 同 § 2.1 寬鬆 schema |

**T / V 對稱關係表**：

| 維度 | Implementation (T) | Verification (V) | 共通結構 |
|------|---------------------|-------------------|----------|
| 主交付 | PR | AC 驗收結果 | — |
| 摘要單筆（最新狀態，覆寫） | `deliverable` (pr_url / pr_state / head_sha) | `ac_verification` (status / last_run_at / 計數 / human_disposition) | frontmatter map，每次寫覆寫 |
| 歷次列表（append-only） | `jira_transition_log[]` | `ac_verification_log[]` + `jira_transition_log[]` | frontmatter list-of-maps，寬鬆 schema |
| Writer contract | atomic + verify + retry-3 + fail-stop (§ 2.1 D7) | 同 contract（§ 4.7） | 一份 D7，T/V 共用 |
| 完結觸發 | engineering Step 8a → IMPLEMENTED → mark-spec-implemented.sh → `pr-release/T*.md` | verify-AC 全 PASS + human_disposition=passed → IMPLEMENTED → mark-spec-implemented.sh → `pr-release/V*.md` | 同一支 closer script（filename dispatch 自動識別 T/V，已實裝） |
| 中央 parser | `parse-task-md.sh` | 同 | filename dispatch（已實裝） |
| Hook | `pipeline-artifact-gate.sh` | 同（filename pattern `V*.md` branch） | 同一支 hook |
| Schema validator | `validate-task-md.sh` (T mode) | `validate-task-md.sh` (V mode) | 同一支 script，filename 分流 |
| Cross-file validator | `validate-task-md-deps.sh`（掃 T+V） | 同（含 V→T pass / T→V fail invariant） | 同一支 script |

### 4.7 `ac_verification` writer contract（atomic + verify + fail-stop，對稱 D7）

verify-AC Phase B 啟動後（DP-039 consumer 重構落地），每跑完一輪 AC verification 必須遵下列 contract（與 § 2.1 `deliverable` writer contract **對稱** — 同一份 D7，T/V 共用）：

#### Schema (when present)

`ac_verification` (frontmatter map)：

| 欄位 | Required | 規則 |
|------|----------|------|
| `status` | required | enum：`PASS` / `FAIL` / `MANUAL_REQUIRED` / `UNCERTAIN` / `IN_PROGRESS` |
| `last_run_at` | required | ISO 8601 timestamp（建議 UTC 或帶 timezone） |
| `ac_total` | required | int ≥ 0 |
| `ac_pass` / `ac_fail` / `ac_manual_required` / `ac_uncertain` | required | int ≥ 0；總和 == `ac_total` |
| `human_disposition` | conditional | enum：`passed` / `rejected` / `deferred`；當 `status` ≠ `PASS` 時必填（FAIL/MANUAL/UNCERTAIN 需人類裁決） |
| 額外欄位 | optional | freeform（如 `disposition_reason` / `last_run_by` / 公司自訂欄位） |

`ac_verification_log[]` (frontmatter list-of-maps，寬鬆)：

- 欄位若存在必須是 list（YAML array）
- 每個 entry 必須是 map（YAML object）
- `time` 欄位（ISO 8601）**建議**有（為了排序與未來 doc viewer 顯示），但**不強制**
- 其他欄位（如 `run_by` / `result` / `fail_acs` / `disposition` / `disposition_reason` / 公司自訂欄位）freeform，validator 不 enforce

> 寬鬆原則與 `jira_transition_log[]` (§ 2.1) 完全一致 — 各公司 / 各驗收 flow / error pattern 不同，強 schema 會擋掉採用。

#### Writer contract（verify-AC，DP-039 啟動後）

1. 跑完一輪 AC verification 後 → **立刻**嘗試寫回 V*.md：
   - **覆寫** `ac_verification` block（最新一輪狀態）
   - **Append** `ac_verification_log[]` 一筆 entry（包含本輪詳情，由 verify-AC 自選欄位）
2. 寫入失敗（exit ≠ 0 / 被 hook 擋）→ retry **最多 3 次**（exponential backoff）
3. 重試仍失敗 → **HARD STOP**，回報：
   - V*.md path
   - 失敗原因（hook output / 錯誤訊息）
   - 訊息：「V*.md is in inconsistent state — verification ran but task.md not updated. Manual recovery required.」
4. **不繼續執行下游步驟**（JIRA transition / `mark-spec-implemented.sh` / Slack 通知 / next handoff）— 寧可 stop，不可 silent fallback
5. 寫入後 **verify**：re-read 檔案、確認 `ac_verification.last_run_at` == 本輪時間戳；mismatch → 同 step 3 fail-stop
6. 全 PASS 且 `human_disposition: passed` → 觸發 `mark-spec-implemented.sh {V_KEY} --status IMPLEMENTED` → move-first 到 `tasks/pr-release/V{n}.md`（move-first 順序與 T 完全一致，§ 2.4）

#### Validator 配合

- Lifecycle-conditional：**不檢查存在性**（breakdown 階段不存在合法）
- **存在時必須驗 schema**（status enum / last_run_at ISO8601 / 計數 int / human_disposition conditional）
- 不可有「validator 太嚴」擋住 verify-AC 自己的合法寫入（schema 寬度 ⊇ writer 輸出）

#### Rationale

與 `deliverable` 對稱 — silent fallback（log 到 `/tmp` 或繼續執行）= V*.md 與真實狀態不一致 → 下次 verify-AC 重跑時誤判為首次（重複執行）或誤判為已通過（漏跑） → AC 結果與 task.md 紀錄分裂。Inconsistent state 必須立刻被人類看到並處理。

對稱意義：driver（engineering vs verify-AC）不同，但「寫回失敗 = HARD STOP」的工程紀律一致，工程師對兩種任務的 lifecycle 期待相同。

### 4.8 完整範例（節錄結構）

```markdown
---
status: IMPLEMENTED
depends_on: [T3d]
ac_verification:
  status: PASS
  last_run_at: 2026-04-27T14:00:00Z
  ac_total: 4
  ac_pass: 4
  ac_fail: 0
  ac_manual_required: 0
  ac_uncertain: 0
  human_disposition: passed
ac_verification_log:
  - time: 2026-04-26T10:30:00Z
    run_by: verify-AC
    result: FAIL (1/4)
    fail_acs: [AC-2]
    disposition: rejected
    disposition_reason: spec issue — AC-2 expected wrong timezone
  - time: 2026-04-27T14:00:00Z
    run_by: verify-AC
    result: PASS (4/4)
    disposition: passed
jira_transition_log:
  - time: 2026-04-26T10:30:00Z
    from: TO_DO
    to: VERIFICATION_IN_PROGRESS
  - time: 2026-04-27T14:05:00Z
    from: VERIFICATION_IN_PROGRESS
    to: DONE
---

# V1: dayjs 遷移驗收 (3 pt)

> Epic: EPIC-478 | JIRA: TASK-3713 | Repo: exampleco-b2c-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TASK-3713 |
| Parent Epic | EPIC-478 |
| Implementation tasks | T1, T3a, T3b, T3c, T3d |
| Base branch | feat/EPIC-478-moment-to-dayjs |
| Depends on | TASK-3902 (T3d — adapter cleanup) |
| References to load | - `skills/references/verify-AC.md` |

## Verification Handoff

驗收委派 verify-AC skill 執行；FAIL 走 bug-triage AC-FAIL Path（`bug-triage-ac-fail-detection` canary）。

## 目標

驗證 EPIC-478 dayjs 遷移完整無 regression（API 計算 + UI SSR + i18n + cleanup）。

## 驗收項目

| AC | 摘要 | 對應實作 task | 驗證類型 |
|----|------|--------------|---------|
| AC-1 | dayjs API 計算結果與 moment 一致 | T1, T3a | runtime |
| AC-2 | products 頁面 SSR 顯示正確時區 | T3b | runtime |
| AC-3 | i18n locale 正確套用 | T3b, T3c | runtime |
| AC-4 | adapter cleanup 不留 moment import | T3d | static |

## 估點理由

3 pt — 4 個 AC，含 runtime + static 混合；首輪 FAIL 後手動 disposition AC-2 為 spec issue（非實作 bug），重跑 PASS。

## 驗收計畫（AC level）

- AC-1/AC-2/AC-3 走 mockoon fixtures (runtime)
- AC-4 走 `grep -r 'moment'` 檢查 (static)

## Test Environment

- **Level**: runtime
- **Fixtures**: `specs/EPIC-478/tests/mockoon/`
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash /Users/hsuanyu.lee/work/scripts/polaris-env.sh start exampleco --project exampleco-b2c-web

## 驗收步驟

​```bash
# Entry: verify-AC consumes this V*.md per AC step list below.
echo "verify-AC dispatches AC-1 .. AC-4."
​```

### AC-1: dayjs API 計算結果與 moment 一致
**Step**: ...
**Expected**: ...

### AC-2: ...
```

具體 instance 將由 DP-039 producer cutover 後產出（既有以 `{JIRA-KEY}.md` 命名的驗收 task.md migration 同步移交）。

---

## 5. Cross-section Invariants

跨欄位 / 跨檔案規則。validator 的 cross-field 檢查邏輯都源自本節。

### 5.1 Test Environment Level → Verify Command（DP-023）

| Level | Verify Command 要求 |
|-------|---------------------|
| `static` | fenced code block 必填；可為純 grep / file existence check；`Runtime verify target` 預期 `N/A` |
| `build` | fenced code block 必填；可包含 `pnpm build` + 後續 artifact 檢查 |
| `runtime` | fenced code block 必填；**必須**包含 http/https URL；URL host **必須等於** `Runtime verify target` host |

違反 → `validate-task-md.sh` exit 1 → `pipeline-artifact-gate.sh` PreToolUse hook 擋 Edit/Write（exit 2）。**T/V 共用**（V mode 完整 reuse § 3.3 cross-field rules）。

### 5.2 depends_on 規則（DP-025 + DP-028）

| 規則 | Validator | 違反行為 |
|------|-----------|----------|
| frontmatter `depends_on` 須為 array of task id strings | `validate-task-md-deps.sh` | exit 1 |
| 每個 entry 必對應同 `tasks/` dir 既有 task.md（`tasks/{ID}.md` 或 `tasks/{ID}/index.md`；找不到時 fallback `tasks/pr-release/{ID}.md` / `tasks/pr-release/{ID}/index.md` — DP-033 D6 + D8）；**T/V 跨類型 reference 合法**（V→T / V→V，§ 5.3） | `validate-task-md-deps.sh`（filename pattern `[TV]*.md` / `[TV]*/index.md`） | exit 1，列出 broken ref |
| graph 須為 DAG（無 cycle） | `validate-task-md-deps.sh`（DFS coloring，跨 T/V 同圖） | exit 1，印出 cycle chain |
| 陣列長度 ≤ 1（強制線性 chain — DP-028 D5；T/V 共用） | `validate-task-md-deps.sh`（is-linear-dag） | exit 1，建議線性化或拆 Epic |
| **T→V 禁止**（DP-033 D4，§ 5.3）— T*.md 的 `depends_on` 不可指向 V*.md | `validate-task-md-deps.sh`（cross-type direction check） | exit 1，列出違規 + 建議拆 Epic |
| `Depends on`（Operational Context cell）非空 ⇒ `Base branch` cell 必須 `task/...`（DP-028 cross-field，T mode 適用；V mode 不檢此 cross-field — V 通常從 `feat/...` 或 `develop` 跑驗收） | `validate-task-md.sh`（T mode only） | exit 1 |

### 5.3 V → T / T → V 方向性（DP-033 D4，Phase B 已實作）

跨類型 `depends_on` 方向性規則（由 `validate-task-md-deps.sh` filename pattern 從 `T*.md` 擴展為 `[TV]*.md` 後 enforce）：

| 方向 | 範例 | 規則 | Validator 行為 |
|------|------|------|---------------|
| V→T | `V1.md` `depends_on: [T2]` | **合法** — 驗收前提是相關實作完成 | pass |
| V→V | `V2.md` `depends_on: [V1]` | **合法** — 驗收 chain（前置驗收先過再跑下一輪） | pass（仍受 DP-028 線性 chain 限制：≤ 1 dep） |
| T→V | `T5.md` `depends_on: [V1]` | **禁止** — 實作不應卡在驗收（避免循環依賴 + Epic 內 phase 化） | exit 1，列出違規 task |
| T→T | `T2.md` `depends_on: [T1]` | 合法（既有規則 § 5.2） | pass |

**分段驗收場景**（T1+T2 → V1 → T3+T4 → V2）：

由 `breakdown` SKILL.md Step 6 / Step 7.5 Quality Challenge 偵測（兩組互不依賴 AC + 兩組互不依賴實作 task 群），主動提示「建議拆 Epic」（兩個交付 = 兩個 Epic 是 PM 視角的自然分法） — validator 不 enforce（advisory，留 PM 判斷）。原因：

- schema 規則最簡單（validator 邏輯乾淨）
- 兩個交付 = 兩個 Epic 是 PM 視角的自然分法（JIRA 上看兩個 Epic 比帶 phase label 的單一 Epic 直覺）
- 過去 EPIC-478 / EPIC-521 / EPIC-542 都是「實作完一次驗收」模式，無真實分段需求

**未來擴張空間**：若分段驗收需求強烈，再開新 DP 升級到 Path B（允許 T→V 加警示）或 Path C（雙欄位 `depends_on` + `requires_ac`）。Phase B 不預先支援。

### 5.4 Fixture 路徑存在性（DP-025）

`## Test Environment` 的 `Fixtures:` 若非 `N/A`，path 必須在以下任一位置存在：

1. `{epic_dir}/{path}`（相對於 Epic folder）
2. `{company_base_dir}/{path}`（相對於 company base）
3. `{workspace_root}/{path}`（相對於 workspace root）

由 `validate-task-md-deps.sh` enforce。違反 → exit 1，列出 checked candidates。

### 5.5 完結 task 物理位置（DP-033 D6 + D7，Hard invariant）

兩條 invariant 由 validator hard-enforce，違反 → exit 2（PreToolUse hook 擋 Edit/Write，或 `--scan` 模式列為 FAIL）：

#### Invariant: 完結 task 物理位置

- task frontmatter `status: IMPLEMENTED` ⇒ **必須** 位於 `tasks/pr-release/{filename}`，不得停留於頂層 `tasks/`
- 違反場景：`tasks/T5.md` 內 frontmatter `status: IMPLEMENTED` → validator **HARD FAIL**（exit 2）
- **Mitigation 機制**：`mark-spec-implemented.sh` **鎖定 move-first 順序**（`mv tasks/T.md tasks/pr-release/T.md` → 再 update frontmatter）。永不出現 transient「在頂層 tasks/ 內標完結」狀態 → validator 可放心 fail-loud
- 不留 grace、不開 warn-only：手寫 `status: IMPLEMENTED` 而未跑 `mark-spec-implemented.sh` 的人類路徑 → 由 hook 擋下 → 提示走 helper script

#### Invariant: 同 key 唯一性

- 同一 task key（`T{n}` / `V{n}`）不可同時存在 legacy 與 folder-native source，也不可同時存在 `tasks/` 與 `tasks/pr-release/`
- 違反場景：`tasks/T1.md` 與 `tasks/T1/index.md` 並存，或 `tasks/T1.md` 與 `tasks/pr-release/T1/index.md` 並存 → validator **HARD FAIL**（同 key ambiguity / D6 move-first 失敗的 silent corruption signal）；`V1` 同樣 HARD FAIL
- 由 `validate-task-md-deps.sh`（cross-file 階段，filename pattern `[TV]*.md`）enforce — T/V 共用同一條 invariant

#### 邊界

- Validator 永遠 skip `tasks/pr-release/` 下的所有檔案（不論 schema） — 完結檔保留歷史樣貌，不重跑
- engineering Step 8a 透過 `mark-spec-implemented.sh` 自動觸發 pr-release move
- Reader fallback 規則（用 task key 找 file 時）見 § 6 Validator Mapping

---

## 6. Validator Mapping

**T mode rules（filename `T*.md`，§ 3 Implementation Schema）**：

| Rule | Layer | Script | Exit code | Bypass env var |
|------|-------|--------|-----------|----------------|
| 標題 / Header / 章節存在性 / Operational Context cells / Test Command 含 code block | Implementation single-file | `scripts/validate-task-md.sh <path>` | 1 (violations) / 2 (usage) | — |
| Test Environment Level enum + Runtime contract（`Runtime verify target` / `Env bootstrap` / Verify Command host alignment） | Implementation single-file (DP-023) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `## 改動範圍` / `## 估點理由` / `## 目標` 非空 + Operational Context 含 JIRA key | Implementation single-file (DP-025) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `Depends on` (cell) 非空 ⇒ `Base branch` `task/...` | Implementation single-file (DP-028 cross-field, T mode only) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `## Allowed Files` 章節存在 + 非空 | Implementation single-file (DP-033 D5 升 Hard，無 grace) | `scripts/validate-task-md.sh`（Phase A A2 升級） | 1 / 2 | — |
| frontmatter `verification.behavior_contract` 欄位形狀（存在時） | Implementation single-file (DP-109 behavior intent) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| Lifecycle-conditional 結構（`deliverable` / `extension_deliverable` / `jira_transition_log`） | Implementation single-file (DP-032 D2/D3 + DP-033 D5/D7 + DP-048) | `scripts/validate-task-md.sh`（只在欄位存在時檢查；`deliverable` / `extension_deliverable` 必驗 schema、`jira_transition_log` 寬鬆 list-of-maps） | 1 / 2 | — |

**V mode rules（filename `V*.md`，§ 4 Verification Schema）**：

| Rule | Layer | Script | Exit code | Bypass env var |
|------|-------|--------|-----------|----------------|
| 標題 / Header / 章節存在性 / Operational Context cells (V 版，§ 4.2) / 驗收步驟含 code block | Verification single-file (DP-033 Phase B) | `scripts/validate-task-md.sh <path>`（V mode） | 1 / 2 | — |
| Test Environment Level enum + Runtime contract（**完全共用 T mode**，§ 4.4 / § 3.3） | Verification single-file (DP-023 reuse) | `scripts/validate-task-md.sh <path>`（V mode） | 1 / 2 | — |
| `## 驗收項目` / `## 估點理由` / `## 目標` 非空 + Operational Context 含 JIRA key | Verification single-file (DP-033 Phase B) | `scripts/validate-task-md.sh <path>`（V mode） | 1 / 2 | — |
| Lifecycle-conditional 結構（`ac_verification` / `ac_verification_log` / `jira_transition_log`） | Verification single-file (DP-033 Phase B § 4.7 對稱 D7) | `scripts/validate-task-md.sh`（V mode；`ac_verification` 必驗 schema、`ac_verification_log` / `jira_transition_log` 寬鬆 list-of-maps） | 1 / 2 | — |

**Shared rules（T/V 共用，filename pattern 擴展為 `[TV]*.md`）**：

| Rule | Layer | Script | Exit code | Bypass env var |
|------|-------|--------|-----------|----------------|
| frontmatter `depends_on[]` 引用存在性 + DAG 無 cycle + 線性 chain (≤1 dep) | Cross-file (DP-025 / DP-028) | `scripts/validate-task-md-deps.sh <tasks_dir>` | 1 / 2 | — |
| **V→T pass / T→V fail 方向性**（DP-033 D4，§ 5.3） | Cross-file (DP-033 Phase B B4) | `scripts/validate-task-md-deps.sh` | 1 / 2 | — |
| `## Test Environment` Fixtures path 存在性（T/V 共用） | Cross-file (DP-025) | `scripts/validate-task-md-deps.sh <tasks_dir>` | 1 / 2 | — |
| 完結 task 物理位置（`status: IMPLEMENTED` ⇒ 位於 `tasks/pr-release/`，T/V 共用） | Single-file (DP-033 D6 § 5.5) | `scripts/validate-task-md.sh`（檢查 frontmatter status × 檔案路徑） | 2 (hard fail) | — |
| 同 key 唯一性（active 與 pr-release 不並存，T/V 共用） | Cross-file (DP-033 D6 § 5.5) | `scripts/validate-task-md-deps.sh`（filename pattern `[TV]*.md`） | 2 (hard fail) | — |
| PR-release scope skip（`tasks/pr-release/` 下檔案完全跳過 schema 驗證） | Both validators | 上述 scripts 內建 `case */pr-release/*: continue` | n/a | — |
| Filename `T*.md` / `V*.md` → schema dispatch | PreToolUse Hook | `.claude/hooks/pipeline-artifact-gate.sh` → `scripts/pipeline-artifact-gate.sh` | 2 (block Edit/Write) | `POLARIS_SKIP_ARTIFACT_GATE=1`（emergency only） |
| 全部上述規則自動 dispatch | PreToolUse Hook（physical block） | 同上 | 2 | 同上 |

### Scan mode

兩個 validator 都支援 `--scan <workspace_root>` 模式，遞迴掃所有 `specs/*/tasks/T*.md`、`specs/*/tasks/V*.md` 與 folder-native `tasks/[TV]*/index.md` 並列 PASS / FAIL，永遠 exit 0（report mode），用於 migration 盤點。

### Bypass 慣例

- `POLARIS_SKIP_ARTIFACT_GATE=1` 是唯一支援的 bypass，僅供 migration / 結構性 schema 變更暫時違規時使用
- 不開新 bypass（DP-025 D3 + DP-032 NO-bypass 立場）— validator script 本身壞掉 → 修 script，不繞 script

### Reader Fallback 規則（DP-033 D8）

所有用 task key 找 file 的 reader 在 `tasks/` 頂層找不到時，**必須 fallback** `tasks/pr-release/`。否則 depends_on chain 會在完結 task 後斷裂（最常見：T5 還在做但 depends_on 已完工的 T1）。

| Reader | 用途 | Fallback 行為 |
|--------|------|---------------|
| `parse-task-md.sh` / `resolve-task-md.sh` | 給 task key 找 task.md path | 先 `tasks/{key}.md` / `tasks/{key}/index.md` → 找不到 fallback `tasks/pr-release/{key}.md` / `tasks/pr-release/{key}/index.md` |
| `validate-task-md-deps.sh` | 解 depends_on chain（最關鍵 — chain 跨完結 task 是常態） | 同上；保 T5 depends_on 已完結 T1 不假錯 |
| `verify-AC` | 讀 V-key task.md 取 fixture / verify 設定 | 同上 |
| `engineering` | 從 branch / ticket key 推 task.md path（first-cut + revision R0 / 修 PR base） | 同上 |
| 未來 Specs Viewer / docs UI | 渲染 task.md（完結 task 仍可見，可加 visual marker） | 同上 |

**統一 lookup 優先順序**：

```
1. tasks/{key}.md              # active
2. tasks/{key}/index.md          # folder-native active fallback
3. tasks/pr-release/{key}.md     # pr-release fallback
4. tasks/pr-release/{key}/index.md
3. fail (broken ref / not found)
```

**Hard fail invariant（D8 + § 5.5）**：同一 key 在 legacy / folder-native source **同時存在**，或在 active `tasks/` 與 `tasks/pr-release/` **同時存在** → validator hard fail（exit 2）。此狀態為 ambiguity 或 D6 move-first 失敗的 silent corruption signal，不應發生；validator 早期偵測比下游 reader 拿到錯版本好。

### Producer / Consumer 對應

| Producer | 寫入時機 | Hook trigger |
|----------|---------|--------------|
| `breakdown` Step 14 (Path A) | 產 T*.md | Edit/Write → hook 跑 T mode validator + deps validator |
| `breakdown` Step D | 產 V*.md（Phase B 規格已落地；producer cutover 從 `{JIRA-KEY}.md` → `V{n}.md` 移交 DP-039 atomic 切） | Edit/Write → hook 跑 V mode validator + deps validator |
| `engineering` Step 7c | 寫入 frontmatter `deliverable` | hook 跑 T mode validator（含 lifecycle 結構檢查） |
| `engineering` `jira-transition.sh` | append `jira_transition_log[]`（T*.md） | 同上 |
| `engineering` Step 8a | T*.md `status: IMPLEMENTED` + pr-release move | hook 跑 T mode validator → `mark-spec-implemented.sh` move-first（先 mv 到 `pr-release/` 再 update frontmatter）|
| `verify-AC`（DP-039 重構後） | 每跑完一輪 AC verification 寫回 V*.md `ac_verification`（覆寫摘要） + `ac_verification_log[]`（append）+ `jira_transition_log[]`（append） | hook 跑 V mode validator（lifecycle 結構檢查） |
| `verify-AC` 全 PASS + human_disposition=passed（DP-039 重構後） | V*.md `status: IMPLEMENTED` + pr-release move | hook 跑 V mode validator → `mark-spec-implemented.sh`（**同一支 closer，filename dispatch 對 T/V 共用**） |

| Consumer | 讀取方式 |
|----------|---------|
| `engineering`（first-cut + revision R0） | `scripts/parse-task-md.sh` 中央 parser；不直接 grep |
| `verify-AC`（DP-039 重構後） | 同 `scripts/parse-task-md.sh`（filename dispatch 自動識別 V*.md，**T/V 共用同一支 parser**） |
| `pr-base-gate.sh` | `scripts/resolve-task-md-by-branch.sh` + `scripts/resolve-task-base.sh`（DP-028 三層消費） |
| `mark-spec-implemented.sh` | 直接編輯 frontmatter `status`；filename dispatch 對 T/V 共用 move-first 流程 |

---

## Appendix A — v0 → v1 TODO 收斂紀錄（2026-04-26）

v0 草稿留有 6 個 `<!-- TODO discuss -->`，已在 2026-04-26 review 全部鎖定（見 `specs/design-plans/DP-033-task-md-lifecycle-closure/plan.md` § Discussion Log 2026-04-26 entry）：

| # | 主題 | 章節 | 鎖定結果 |
|---|------|------|----------|
| 1 | Reader fallback 規則 | § 1 Overview + § 6 | 加 callout（active → pr-release fallback）；folder 從 `archive/` 改名 `pr-release/`（語意精準、與 memory archive 詞義脫鉤） |
| 2 | `jira_transition_log[]` schema | § 2.1 + § 3.6 | 寬鬆 list-of-maps；`time`（ISO 8601）建議不強制；其他欄位 freeform；validator 不檢內容 |
| 3 | `deliverable` 寫入 atomic 機制 | § 2.1 + § 3.6 | atomic + verify, fail-stop（retry 3 次 backoff → HARD STOP，不繼續下游）；validator 必驗 schema |
| 4 | Header 行 `Epic:` 是否升 Hard | § 2.3 | 維持 **Soft** — Bug task 是真實無 Epic 場景（hotfix-auto-ticket） |
| 5 | `## Allowed Files` 升 Hard 的 grace 策略 | § 3.1 | **直接 Hard、不開 grace、不留 warn-only**；既有 active T 缺漏由 A7 migration script 強制 backfill |
| 6 | `status: IMPLEMENTED` 但未 pr-release 移動 | § 5.5 | validator **HARD FAIL**（exit 2）；`mark-spec-implemented.sh` 鎖定 move-first 順序，永不出現 transient 不一致狀態 |

伴隨修正：

- **D2 修正**：移除 frontmatter `type` 欄位 — filename pattern 為唯一 type 訊號。BS#11（filename ↔ type 一致性）整條作廢
- **新增 D7**：Lifecycle write-back contracts（jira_transition_log 寬鬆 + deliverable atomic）
- **新增 D8**：Reader fallback 規則（跨 active / pr-release 邊界）

---

## See Also

- `pipeline-handoff.md § Artifact Schemas` — 整個 pipeline artifact 的 high-level overview（task.md 是其中一類）；本檔為 task.md 的詳細 spec
- `epic-folder-structure.md` — `specs/{EPIC}/tasks/` 在 Epic folder 中的位置
- `engineer-delivery-flow.md` — engineering 消費 task.md 的完整步驟（含 deliverable 寫回時機）
- `branch-creation.md` + DP-028 三層消費模型 — `Base branch` / `Task branch` / `Depends on` cells 的 deterministic 解析路徑
- DP plans — 章節級語境：DP-023（runtime contract）/ DP-025（schema enforcement）/ DP-028（depends_on binding）/ DP-032（lifecycle write-back）/ DP-033（本 reference 的母 plan）
