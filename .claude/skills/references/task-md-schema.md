# task.md Schema — Single Source of Truth

> **Status**: v0 draft (DP-033 Phase A). 實作 schema 為主；驗收 schema 為 placeholder，待 Phase B 填寫。
>
> **Source DPs**: DP-023 (runtime contract) · DP-025 (artifact schema enforcement) · DP-028 (depends_on / Base branch binding) · DP-032 (deliverable / jira_transition_log lifecycle write-back) · DP-033 (本 reference — schema 整合 + lifecycle closure)

本 reference 是 task.md 的單一權威 schema 文件 — pipeline 的所有 producer / consumer / validator / hook 都從此派生。若本檔與個別 SKILL.md / DP plan / `pipeline-handoff.md` 描述衝突，**以本檔為準**。

---

## 1. Overview

### 兩種 task.md

Polaris pipeline 的 task.md 分兩類，都存在於同一個 Epic 的 `specs/{EPIC}/tasks/` 下：

| 類型 | Filename pattern | Producer | Consumer | Schema 章節 |
|------|------------------|----------|----------|-------------|
| 實作 task.md | `T{n}[suffix].md`（`T1.md` / `T3a.md` / `T8b.md`） | `breakdown` Path A | `engineering` | § 3 Implementation Schema |
| 驗收 task.md | `V{n}[suffix].md`（`V1.md` / `V2a.md`） | `breakdown` Step D | `verify-AC` | § 4 Verification Schema (placeholder) |

> **Reader fallback callout（DP-033 D8）**：所有用 task key 找 file 的 reader（`parse-task-md.sh` / `validate-task-md-deps.sh` / `verify-AC` / `engineering` / 未來 Specs Viewer）在 active `tasks/` 找不到 key 時，必須 fallback `tasks/complete/`，避免歷史 reference 在 task 完結後斷鏈。完整 fallback 規則 + lookup 優先順序見 § 6 Validator Mapping。

### Filename → Schema dispatch

`pipeline-artifact-gate.sh` PreToolUse hook 用 filename pattern dispatch validator：

```
specs/*/tasks/T*.md   → validate-task-md.sh + validate-task-md-deps.sh（implementation）
specs/*/tasks/V*.md   → validate-task-md.sh（verification mode，待 Phase B）
specs/*/tasks/complete/*.md → 完全 skip（D6 complete 機制；validator 不掃 complete/）
其他 .md             → 不適用 task.md schema
```

**Filename 為唯一 type 訊號**（DP-033 D2，2026-04-26 修正）：T*.md = 實作、V*.md = 驗收，dispatch 完全由 filename 決定。**不在 frontmatter 重複 `type` 欄位** — 任何「雙保險」`type` field 都是 illusory（rename 時 stale，ground truth 仍是 filename）。

---

## 2. Common Schema

兩種 task.md 共享下列結構規則。Implementation / Verification 額外章節分別在 § 3 / § 4。

### 2.1 Frontmatter

```yaml
---
status: IN_PROGRESS         # optional：IN_PROGRESS | IMPLEMENTED | BLOCKED
depends_on: [T1]            # optional：array of task id strings；長度 ≤ 1（DP-028 強制線性）
deliverable:                # Lifecycle-conditional（DP-032 D2）；engineering Step 7c 寫入
  pr_url: https://github.com/.../pull/2202
  pr_state: OPEN            # OPEN | MERGED | CLOSED
  head_sha: abc1234
jira_transition_log:        # Lifecycle-conditional（DP-033 D7）；engineering / verify-AC append
  - time: 2026-04-26T10:30:00Z   # ISO 8601；建議但不強制
    # 其他欄位 freeform — 各公司 / 各 transition flow 自訂
  - time: 2026-04-26T11:15:00Z
    company_specific_field: ...
---
```

| 欄位 | 寫入時機 | Required 層級 |
|------|---------|---------------|
| `status` | breakdown 寫初值（可省略）；engineering Step 8a 標 `IMPLEMENTED`；verify-AC 全 PASS 標 `IMPLEMENTED`（Epic level）| Optional（值若存在須為 enum） |
| `depends_on` | breakdown Step 14 |  Optional；存在則須為 array、長度 ≤ 1、所有 entry 須對應同 `tasks/` 下既有 task.md（含 `complete/` fallback，見 § 5.2） |
| `deliverable` | engineering Step 7c (`gh pr create` 成功後) | Lifecycle-conditional — breakdown 階段不存在；engineering 寫入後須結構正確（schema + writer contract 見下） |
| `jira_transition_log` | engineering / verify-AC 每次跑 JIRA transition 後 append（成功 / 失敗皆記） | Lifecycle-conditional — 同上 |

> Filename 為唯一 type 訊號（DP-033 D2 修正版）— frontmatter **不再有 `type` 欄位**。所有 schema dispatch 都依 filename pattern（T*.md / V*.md），請勿在 frontmatter 加 `type` 欄位。

#### `jira_transition_log[]` schema（DP-033 D7，寬鬆）

採 list-of-maps，validator 只檢結構性、**不檢內容 / 型別 / 命名**：

- 欄位若存在必須是 list（YAML array）
- 每個 entry 必須是 map（YAML object）
- `time` 欄位（ISO 8601）**建議**有（為了排序與未來 doc viewer 顯示），但**不強制**
- 其他欄位（如 `from` / `to` / `actor` / `error` / `transition_id` / 公司自訂欄位）freeform，validator 不 enforce

Writer：engineering / verify-AC 在做 JIRA transition 時 append entry — 成功與失敗皆寫一筆，便於後續 retry / 人工排查。未來擴充：doc viewer 可對常見欄位（time / from / to / error）做特殊渲染，但 schema 層保持中性。

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

```
> Epic: {EPIC_KEY} | JIRA: {TASK_KEY} | Repo: {repo_name}
```

- `Epic:` **Soft required**（DP-033 D5 + 2026-04-26 鎖定）— Bug task 是真實無 Epic 場景（hotfix-auto-ticket 建出的 standalone Bug），硬 require 只會逼填假 Epic；warn 但放行
- `JIRA:` **必填** — 須含 JIRA key 格式 `[A-Z][A-Z0-9]+-[0-9]+`
- `Repo:` **必填** — 非空字串

Validator regex（任一項缺失即 fail）：

```regex
^> .*JIRA: [A-Z][A-Z0-9]*-[0-9]+
^> .*Repo: \S+
```

### 2.4 Status 規則 + Complete 邊界

`status` 是任務 lifecycle 的 single source of truth：

- **未填** = 進行中（默認）
- **`IN_PROGRESS`** = engineering 已啟動但尚未開 PR
- **`IMPLEMENTED`** = 任務完結 — 由 `engineering` Step 8a 或 `verify-AC` 全 PASS 寫入；同時觸發 D6 Complete move
- **`BLOCKED`** = 暫時擱置（informal，不觸發任何 hook）

Complete 觸發（DP-033 D6，**move-first 順序鎖定**）：`status` 轉為 `IMPLEMENTED` → `mark-spec-implemented.sh` 嚴格依下列順序執行：

1. `mv tasks/T1.md tasks/complete/T1.md`（先搬）
2. 在 `complete/T1.md` update frontmatter 標 `IMPLEMENTED`（後改）

永遠不會出現「在 active `tasks/` 內標完結」的 transient state。Validator 不掃 `complete/`，但下游 reader（`parse-task-md.sh` / `validate-task-md-deps.sh` / `verify-AC` 解 V-key / `engineering` / 未來 Specs Viewer）在 `tasks/` 找不到時 fallback `complete/`，保 depends_on 鏈不斷裂（完整 reader fallback 規則見 § 6）。

**Hard invariant**：完結（frontmatter `status: IMPLEMENTED`）但仍位於頂層 `tasks/` 而非 `tasks/complete/` → validator **HARD FAIL**（exit 2）。詳見 § 5.5。

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
| `## 估點理由` | **Hard** | DP-025 | `validate-task-md.sh`（章節存在 + 非空 body） |
| `## 測試計畫（code-level）` | **Soft** | DP-025 | `validate-task-md.sh`（章節存在；內容不檢） |
| `## Test Command` | **Hard** | DP-005 / DP-025 | `validate-task-md.sh`（章節存在 + 含 fenced code block） |
| `## Test Environment` | **Hard** | DP-023 | `validate-task-md.sh`（章節存在 + Level enum + Runtime contract — 見 § 3.3） |
| `## Verify Command` | **Hard**（`Level≠static` 時） | DP-023 | `validate-task-md.sh`（章節存在 + 含 fenced code block + Level=runtime 時 host alignment） |

### 3.2 `## Operational Context` table cells

必填 cells（每個 cell 名稱在 markdown table 第一欄；validator 要求字面比對命中）：

| Cell | 內容 | Required |
|------|------|----------|
| `Task JIRA key` | 該 task 的 JIRA key（如 `TASK-123`） | **Hard** |
| `Parent Epic` | Epic key（如 `PROJ-123`） | **Hard** |
| `Test sub-tasks` | Test sub-task JIRA keys（comma-separated） | **Hard** |
| `AC 驗收單` | Verification ticket JIRA key（V*.md 對應的 ticket，或 verify-AC 消費的 AC ticket） | **Hard** |
| `Base branch` | 切 task branch 用的 base — 有 `Depends on` 時必須 `task/...`（DP-028 cross-field）；無依賴時通常 `feat/...` | **Hard** |
| `Task branch` | 該 task 自己的 branch（`task/{TASK_KEY}-{slug}`） | **Hard** |
| `Depends on` | 同 Epic 內依賴的 task 描述（如 `TASK-123 (T3a — dayjs infra)`）；無依賴 = `N/A` / `-` / 空 | **Soft**（cell 可缺；存在時參與 cross-field rule） |
| `References to load` | engineering sub-agent 須讀的 reference 列表（HTML `<br>` 換行） | **Hard** |

範例（節錄自 PROJ-123 T3b）：

```markdown
## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TASK-123 |
| Parent Epic | PROJ-123 |
| Test sub-tasks | TASK-123 |
| AC 驗收單 | TASK-123 |
| Base branch | task/TASK-123-dayjs-infra-util |
| Task branch | task/TASK-123-moment-to-dayjs-products |
| Depends on | TASK-123 (T3a — dayjs infra) |
| References to load | - `skills/references/branch-creation.md`<br>- ... |
```

### 3.3 `## Test Environment` schema (DP-023 runtime contract)

Bullet list 格式：

```markdown
- **Level**: runtime
- **Dev env config**: `workspace-config.yaml → projects[{repo}].dev_environment`
- **Fixtures**: `specs/{EPIC}/tests/mockoon/`（Mockoon CLI port 3100）
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash /Users/hsuanyu.lee/work/scripts/polaris-env.sh start your-company --project {repo}
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
5. `Fixtures` 若非 `N/A`，path 必須存在（resolve 順序：epic_dir → company_base_dir → workspace_root）

**Static / build 規則**：`Runtime verify target` / `Env bootstrap command` 預期 = `N/A`；若非 N/A → fail（避免假性宣告）。

### 3.4 `## Allowed Files`

```markdown
## Allowed Files

> breakdown 時依改動範圍列出，engineering 超出此清單的修改觸發 risk scoring +15%。

- `apps/main/plugins/dayjs.ts`
- `apps/main/products/**`
- 上述檔案的 test 檔
```

由 `engineer-delivery-flow.md` Step 5.5 Scope Check 消費。Hard required（DP-033 D5 升級自 Soft）— 缺失會讓 Scope Check 失靈，risk scoring 機制走空。

### 3.5 `## Test Command` / `## Verify Command`

兩者皆必須包含 fenced code block（內容由 LLM 不可改寫 — `verify-command-immutable-execute` canary）：

```markdown
## Test Command

> breakdown 產出。engineering 跑測試時**必須使用此指令**，不可自行推導。

​```bash
pnpm -C apps/main vitest run
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
| frontmatter `jira_transition_log[]` | engineering / verify-AC 跑 JIRA transition 後 | append-only | list-of-maps；`time` 建議（不強制）；其他欄位 freeform（見 § 2.1 寬鬆 schema） |

### 3.7 Optional sections

- `## Verification Handoff` — Optional（DP-033 D5）；breakdown 慣例會寫一句「AC 驗證委派至 {AC_TICKET}」，但 validator 不檢查存在性 / 內容
- `## 測試計畫（code-level）` — Soft（章節存在即可，內容不檢）

### 3.8 完整範例（節錄結構）

```markdown
---
status: IMPLEMENTED
deliverable:
  pr_url: https://github.com/your-org/your-app/pull/2202
  pr_state: OPEN
  head_sha: c7b4bf3a
jira_transition_log:
  - time: 2026-04-23T08:30:00Z
    from: TO_DO
    to: IN_DEVELOPMENT
    result: PASS
---

# T1: Mockoon fixtures 建立/擴充 (2 pt)

> Epic: PROJ-123 | JIRA: TASK-123 | Repo: your-app

## Operational Context
| 欄位 | 值 | ... |

## Verification Handoff
AC 驗證委派至 TASK-123（由 verify-AC skill 執行）。

## 目標
{What this task accomplishes}

## 改動範圍
| 檔案 | 動作 | 說明 |

## Allowed Files
- `your-company/mockoon/fixtures/gt478/`

## 估點理由
2 pt — ...

## 測試計畫（code-level）
- build check: ... → TASK-123

## Test Command
​```bash
pnpm -C apps/main vitest run
​```

## Test Environment
- **Level**: runtime
- **Fixtures**: `specs/PROJ-123/tests/mockoon/`
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash /path/to/polaris-env.sh start your-company --project your-app

## Verify Command
​```bash
curl -sf http://localhost:3100/api/activities ...
​```
```

具體 instance 見 `your-company/specs/PROJ-123/tasks/T1.md`、`T9.md`（或完結後的 `your-company/specs/PROJ-123/tasks/complete/T1.md`）。

---

## 4. Verification Schema (V{n}.md)

> **Phase B 待寫**。
>
> DP-033 Phase B 完成後在此填入：
>
> - Filename pattern：`V{n}[suffix].md`（V1.md / V2a.md，sequential 從 V1 起，sub-split `V1a/V1b`，與 T{n} 同規則 — DP-033 D2 + BS#10）。**Filename 為唯一 type 訊號，不引入 frontmatter `type` 欄位**（D2 修正版，2026-04-26）
> - Required sections：包含 breakdown 寫入的 fields（`test_urls` / `depends_on` 含 V→T binding）+ verify-AC 寫回的 `ac_verification` lifecycle section
> - Cross-section invariant：V→T `depends_on` 合法、T→V `depends_on` 禁止（DP-033 D4）
> - verify-AC 寫回 `ac_verification` 的 contract（atomic / 重跑覆寫語意，比照 DP-033 D7 `deliverable` 的 atomic + verify + fail-stop 模式）
>
> 既有以 `{JIRA-KEY}.md` 命名的驗收 task.md migration 移交 **DP-039 `/verify-AC refactor` seed**（DP-033 D3 + BS#7）；本檔不 cover migration script。

---

## 5. Cross-section Invariants

跨欄位 / 跨檔案規則。validator 的 cross-field 檢查邏輯都源自本節。

### 5.1 Test Environment Level → Verify Command（DP-023）

| Level | Verify Command 要求 |
|-------|---------------------|
| `static` | fenced code block 必填；可為純 grep / file existence check；`Runtime verify target` 預期 `N/A` |
| `build` | fenced code block 必填；可包含 `pnpm build` + 後續 artifact 檢查 |
| `runtime` | fenced code block 必填；**必須**包含 http/https URL；URL host **必須等於** `Runtime verify target` host |

違反 → `validate-task-md.sh` exit 1 → `pipeline-artifact-gate.sh` PreToolUse hook 擋 Edit/Write（exit 2）。

### 5.2 depends_on 規則（DP-025 + DP-028）

| 規則 | Validator | 違反行為 |
|------|-----------|----------|
| frontmatter `depends_on` 須為 array of task id strings | `validate-task-md-deps.sh` | exit 1 |
| 每個 entry 必對應同 `tasks/` dir 既有 task.md（`tasks/{ID}.md`；找不到時 fallback `tasks/complete/{ID}.md` — DP-033 D6 + D8） | `validate-task-md-deps.sh` | exit 1，列出 broken ref |
| graph 須為 DAG（無 cycle） | `validate-task-md-deps.sh`（DFS coloring） | exit 1，印出 cycle chain |
| 陣列長度 ≤ 1（強制線性 chain — DP-028 D5） | `validate-task-md-deps.sh`（is-linear-dag） | exit 1，建議線性化或拆 Epic |
| `Depends on`（Operational Context cell）非空 ⇒ `Base branch` cell 必須 `task/...`（DP-028 cross-field） | `validate-task-md.sh` | exit 1 |

### 5.3 V → T / T → V 方向性（DP-033 D4，Phase B 實作）

- **V→T 合法**：驗收前提是相關實作完成（如 V1 `depends_on: [T2]`）
- **T→V 禁止**：實作不應卡在驗收 — 避免循環依賴 + Epic 內 phase 化
- **分段驗收場景**（T1+T2 → V1 → T3+T4 → V2）：breakdown 偵測到此需求時主動提示「建議拆 Epic」（兩個交付 = 兩個 Epic）

Phase B 在 `validate-task-md-deps.sh` 加跨類型方向性檢查（BS#9）。

### 5.4 Fixture 路徑存在性（DP-025）

`## Test Environment` 的 `Fixtures:` 若非 `N/A`，path 必須在以下任一位置存在：

1. `{epic_dir}/{path}`（相對於 Epic folder）
2. `{company_base_dir}/{path}`（相對於 company base）
3. `{workspace_root}/{path}`（相對於 workspace root）

由 `validate-task-md-deps.sh` enforce。違反 → exit 1，列出 checked candidates。

### 5.5 完結 task 物理位置（DP-033 D6 + D7，Hard invariant）

兩條 invariant 由 validator hard-enforce，違反 → exit 2（PreToolUse hook 擋 Edit/Write，或 `--scan` 模式列為 FAIL）：

#### Invariant: 完結 task 物理位置

- task frontmatter `status: IMPLEMENTED` ⇒ **必須** 位於 `tasks/complete/{filename}`，不得停留於頂層 `tasks/`
- 違反場景：`tasks/T5.md` 內 frontmatter `status: IMPLEMENTED` → validator **HARD FAIL**（exit 2）
- **Mitigation 機制**：`mark-spec-implemented.sh` **鎖定 move-first 順序**（`mv tasks/T.md tasks/complete/T.md` → 再 update frontmatter）。永不出現 transient「在頂層 tasks/ 內標完結」狀態 → validator 可放心 fail-loud
- 不留 grace、不開 warn-only：手寫 `status: IMPLEMENTED` 而未跑 `mark-spec-implemented.sh` 的人類路徑 → 由 hook 擋下 → 提示走 helper script

#### Invariant: 同 key 唯一性

- 同一 task key（`T{n}` / `V{n}`）不可同時存在 `tasks/` 與 `tasks/complete/`
- 違反場景：`tasks/T1.md` 與 `tasks/complete/T1.md` 並存 → validator **HARD FAIL**（D6 move-first 失敗的 silent corruption signal）
- 由 `validate-task-md-deps.sh`（cross-file 階段）enforce

#### 邊界

- Validator 永遠 skip `tasks/complete/` 下的所有檔案（不論 schema） — 完結檔保留歷史樣貌，不重跑
- engineering Step 8a 透過 `mark-spec-implemented.sh` 自動觸發 complete move
- Reader fallback 規則（用 task key 找 file 時）見 § 6 Validator Mapping

---

## 6. Validator Mapping

| Rule | Layer | Script | Exit code | Bypass env var |
|------|-------|--------|-----------|----------------|
| 標題 / Header / 章節存在性 / Operational Context cells / Test Command 含 code block | Implementation single-file | `scripts/validate-task-md.sh <path>` | 1 (violations) / 2 (usage) | — |
| Test Environment Level enum + Runtime contract（`Runtime verify target` / `Env bootstrap` / Verify Command host alignment） | Implementation single-file (DP-023) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `## 改動範圍` / `## 估點理由` / `## 目標` 非空 + Operational Context 含 JIRA key | Implementation single-file (DP-025) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `Depends on` (cell) 非空 ⇒ `Base branch` `task/...` | Implementation single-file (DP-028 cross-field) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| frontmatter `depends_on[]` 引用存在性 + DAG 無 cycle + 線性 chain (≤1 dep) | Cross-file (DP-025 / DP-028) | `scripts/validate-task-md-deps.sh <tasks_dir>` | 1 / 2 | — |
| `## Test Environment` Fixtures path 存在性 | Cross-file (DP-025) | `scripts/validate-task-md-deps.sh <tasks_dir>` | 1 / 2 | — |
| 全部上述規則自動 dispatch | PreToolUse Hook（physical block） | `.claude/hooks/pipeline-artifact-gate.sh` → `scripts/pipeline-artifact-gate.sh` | 2 (block Edit/Write) | `POLARIS_SKIP_ARTIFACT_GATE=1`（emergency only） |
| Filename `T*.md` / `V*.md` → schema dispatch | PreToolUse Hook | 同上（Phase B 加入 V*.md branch） | 2 | 同上 |
| V→T / T→V 方向性 | Cross-file (DP-033 D4) | `scripts/validate-task-md-deps.sh`（Phase B B4） | 1 / 2 | — |
| `## Allowed Files` 章節存在 + 非空 | Implementation single-file (DP-033 D5 升 Hard，無 grace) | `scripts/validate-task-md.sh`（Phase A A2 升級） | 1 / 2 | — |
| Lifecycle-conditional 結構（`deliverable` / `jira_transition_log`） | Implementation single-file (DP-032 D2/D3 + DP-033 D5/D7) | `scripts/validate-task-md.sh`（Phase A A2 加入；只在欄位存在時檢查；`deliverable` 必驗 schema、`jira_transition_log` 寬鬆 list-of-maps） | 1 / 2 | — |
| 完結 task 物理位置（`status: IMPLEMENTED` ⇒ 位於 `tasks/complete/`） | Single-file (DP-033 D6 § 5.5) | `scripts/validate-task-md.sh`（檢查 frontmatter status × 檔案路徑） | 2 (hard fail) | — |
| 同 key 唯一性（active 與 complete 不並存） | Cross-file (DP-033 D6 § 5.5) | `scripts/validate-task-md-deps.sh`（cross-folder 掃描） | 2 (hard fail) | — |
| Complete scope skip（`tasks/complete/` 下檔案完全跳過 schema 驗證） | Both validators | 上述 scripts 內建 `case */complete/*: continue` | n/a | — |

### Scan mode

兩個 validator 都支援 `--scan <workspace_root>` 模式，遞迴掃所有 `specs/*/tasks/T*.md` / `tasks/` 並列 PASS / FAIL，永遠 exit 0（report mode），用於 migration 盤點。

### Bypass 慣例

- `POLARIS_SKIP_ARTIFACT_GATE=1` 是唯一支援的 bypass，僅供 migration / 結構性 schema 變更暫時違規時使用
- 不開新 bypass（DP-025 D3 + DP-032 NO-bypass 立場）— validator script 本身壞掉 → 修 script，不繞 script

### Reader Fallback 規則（DP-033 D8）

所有用 task key 找 file 的 reader 在 `tasks/` 頂層找不到時，**必須 fallback** `tasks/complete/`。否則 depends_on chain 會在完結 task 後斷裂（最常見：T5 還在做但 depends_on 已完工的 T1）。

| Reader | 用途 | Fallback 行為 |
|--------|------|---------------|
| `parse-task-md.sh` | 給 task key 找 task.md path | 先 `tasks/{key}.md` → 找不到 fallback `tasks/complete/{key}.md` |
| `validate-task-md-deps.sh` | 解 depends_on chain（最關鍵 — chain 跨完結 task 是常態） | 同上；保 T5 depends_on 已完結 T1 不假錯 |
| `verify-AC` | 讀 V-key task.md 取 fixture / verify 設定 | 同上 |
| `engineering` | 從 branch / ticket key 推 task.md path（first-cut + revision R0 / 修 PR base） | 同上 |
| 未來 Specs Viewer / docs UI | 渲染 task.md（完結 task 仍可見，可加 visual marker） | 同上 |

**統一 lookup 優先順序**：

```
1. tasks/{key}.md              # active
2. tasks/complete/{key}.md     # completed fallback
3. fail (broken ref / not found)
```

**Hard fail invariant（D8 + § 5.5）**：同一 key 在 active `tasks/` 與 `tasks/complete/` **同時存在** → validator hard fail（exit 2）。此狀態為 D6 move-first 失敗的 silent corruption signal，不應發生；validator 早期偵測比下游 reader 拿到錯版本好。

### Producer / Consumer 對應

| Producer | 寫入時機 | Hook trigger |
|----------|---------|--------------|
| `breakdown` Step 14 (Path A) | 產 T*.md | Edit/Write → hook 跑 implementation validator |
| `breakdown` Step D | 產 V*.md（Phase B） | Edit/Write → hook 跑 verification validator |
| `engineering` Step 7c | 寫入 `deliverable.pr_url` | hook 跑 implementation validator（含 lifecycle 結構檢查） |
| `engineering` `jira-transition.sh` | append `jira_transition_log[]` | 同上 |
| `engineering` Step 8a / `verify-AC` 全 PASS | `status: IMPLEMENTED` + complete move | hook 跑 implementation validator → `mark-spec-implemented.sh` move-first（先 mv 到 `complete/` 再 update frontmatter） |
| `verify-AC` Step 3a（Phase B） | 寫入 V*.md `ac_verification` | hook 跑 verification validator |

| Consumer | 讀取方式 |
|----------|---------|
| `engineering`（first-cut + revision R0） | `scripts/parse-task-md.sh` 中央 parser；不直接 grep |
| `verify-AC` | 解析 V*.md（Phase B contract 待定 — § 4） |
| `pr-base-gate.sh` | `scripts/resolve-task-md-by-branch.sh` + `scripts/resolve-task-base.sh`（DP-028 三層消費） |
| `mark-spec-implemented.sh` | 直接編輯 frontmatter `status` |

---

## Appendix A — v0 → v1 TODO 收斂紀錄（2026-04-26）

v0 草稿留有 6 個 `<!-- TODO discuss -->`，已在 2026-04-26 review 全部鎖定（見 `specs/design-plans/DP-033-task-md-lifecycle-closure/plan.md` § Discussion Log 2026-04-26 entry）：

| # | 主題 | 章節 | 鎖定結果 |
|---|------|------|----------|
| 1 | Reader fallback 規則 | § 1 Overview + § 6 | 加 callout（active → complete fallback）；folder 從 `archive/` 改名 `complete/`（語意精準、與 memory archive 詞義脫鉤） |
| 2 | `jira_transition_log[]` schema | § 2.1 + § 3.6 | 寬鬆 list-of-maps；`time`（ISO 8601）建議不強制；其他欄位 freeform；validator 不檢內容 |
| 3 | `deliverable` 寫入 atomic 機制 | § 2.1 + § 3.6 | atomic + verify, fail-stop（retry 3 次 backoff → HARD STOP，不繼續下游）；validator 必驗 schema |
| 4 | Header 行 `Epic:` 是否升 Hard | § 2.3 | 維持 **Soft** — Bug task 是真實無 Epic 場景（hotfix-auto-ticket） |
| 5 | `## Allowed Files` 升 Hard 的 grace 策略 | § 3.1 | **直接 Hard、不開 grace、不留 warn-only**；既有 active T 缺漏由 A7 migration script 強制 backfill |
| 6 | `status: IMPLEMENTED` 但未 complete 移動 | § 5.5 | validator **HARD FAIL**（exit 2）；`mark-spec-implemented.sh` 鎖定 move-first 順序，永不出現 transient 不一致狀態 |

伴隨修正：

- **D2 修正**：移除 frontmatter `type` 欄位 — filename pattern 為唯一 type 訊號。BS#11（filename ↔ type 一致性）整條作廢
- **新增 D7**：Lifecycle write-back contracts（jira_transition_log 寬鬆 + deliverable atomic）
- **新增 D8**：Reader fallback 規則（跨 active / complete 邊界）

---

## See Also

- `pipeline-handoff.md § Artifact Schemas` — 整個 pipeline artifact 的 high-level overview（task.md 是其中一類）；本檔為 task.md 的詳細 spec
- `epic-folder-structure.md` — `specs/{EPIC}/tasks/` 在 Epic folder 中的位置
- `engineer-delivery-flow.md` — engineering 消費 task.md 的完整步驟（含 deliverable 寫回時機）
- `branch-creation.md` + DP-028 三層消費模型 — `Base branch` / `Task branch` / `Depends on` cells 的 deterministic 解析路徑
- DP plans — 章節級語境：DP-023（runtime contract）/ DP-025（schema enforcement）/ DP-028（depends_on binding）/ DP-032（lifecycle write-back）/ DP-033（本 reference 的母 plan）
