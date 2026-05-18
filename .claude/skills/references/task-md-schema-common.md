# task.md Schema — Single Source of Truth

> **Status**: v1 (DP-033 Phase A + Phase B)。實作 schema (T{n}.md) + 驗收 schema (V{n}.md) 雙路徑齊備；對稱原則：驗收也是工程，所有共用基礎設施 (parser / closer / hook / D6 pr-release / D7 atomic write contract / jira_transition_log) 一份權威、T/V 共用。
>
> **Source DPs**: DP-023 (runtime contract) · DP-025 (artifact schema enforcement) · DP-028 (depends_on / Base branch binding) · DP-032 (deliverable / jira_transition_log lifecycle write-back) · DP-033 (本 reference — schema 整合 + lifecycle closure；Phase A 實作 schema、Phase B 驗收 schema) · DP-065 (task / gate contract hardening) · DP-194 (Required Tools / tool requirement handoff)

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

DP-backed implementation task 與 Epic implementation task 沒有不同的施工捷徑：同樣由
`breakdown` 產出 authoritative work order，交給 `engineering` 施工；若 local policy
需要 `framework-release`，那是 PR 之後的 local extension tail。只觸及
`docs-manager/src/content/docs/specs/**` 這類 local sample/spec surface 的調整，不得被包成
DP implementation task handoff engineering。

Implementation task 若需要工單級工具，使用 `task-md-schema-task.md` § `Required Tools`
table 承接 refinement `tool_requirements[]`；這是 engineering setup handoff，不是
root `mise.toml` 變更授權。

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

此禁令只針對 root-level task dispatch `type:`。Nested domain fields 不是 dispatch 訊號，
例如 `deliverable.type`、`source.type` 或其他明確屬於子物件的 schema 欄位可保留；
inventory / migration 不得用 broad grep 刪除 nested semantic fields。

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
    flow_script: "scripts/behavior-flows/media-lightbox-carousel.sh"
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
- `fixture_policy=mockoon_required` 時，`flow_script`（或相容欄位 `script_path` /
  `playwright_script`）required；mockoon-required task 不可只描述 flow 而沒有可執行入口。
- `fixture_policy=mockoon_required` 時，`Runtime verify target` 與 `target_url` 若使用
  http/https URL，必須是 localhost / loopback / docker-service 等 fixture-backed target；
  不可指向 `dev.*` / public remote live page。
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
