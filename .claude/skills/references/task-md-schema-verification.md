## 4. Verification Schema (V{n}.md)

驗收 task.md schema。對稱原則：與 § 3 Implementation Schema 對齊，所有共用基礎設施（中央 parser、move-first closer、PreToolUse hook dispatch、D6 pr-release/、D7 atomic write contract、`jira_transition_log[]`）一份權威、T/V 共用，**不平行造**。

> **Envelope boundary（DP-238 AC3）**：V*.md 是 **verify-AC execution envelope /
> lifecycle surface** —— 它承載「要驗哪些 AC、在哪個環境跑、跑出來的 lifecycle
> 狀態（`ac_verification` / `ac_verification_log[]`）」。它**不是**第二份 AC verification
> method authority：每條 AC 的 `method` / `detail`（怎麼驗、跑什麼命令）權威來源是
> `refinement.json` `acceptance_criteria[].verification`。當 V*.md `## 驗收項目` 文字與
> `refinement.json.acceptance_criteria[].verification` drift 時，verify-AC runner 一律以
> `refinement.json` 為準並 advisory log drift（見
> [`pipeline-handoff-atom-matrix.md`](pipeline-handoff-atom-matrix.md) `v_task_envelope`
> row 與 `verify-AC` SKILL.md § Deterministic Consumption）。

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
- `Task branch` — V 不開 branch（驗收不開 fix branch；AC FAIL 走 refinement Bug source mode 開新 T）

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
- Static 規則（`Runtime verify target` / `Env bootstrap command` 必須 `N/A`）
- Build 規則（`Runtime verify target` 必須 `N/A`；runner 類 Test Command 需由 breakdown readiness 要求 bootstrap）
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
| Parent closeout | T*.md 全部 IMPLEMENTED 後仍不得 close parent，直到 active V*.md 不存在且 pr-release V*.md `status: IMPLEMENTED` + `ac_verification.status: PASS` | V*.md 是 AC / dogfood 的 terminal authority；active V*.md 是 closeout blocker | `close-parent-spec-if-complete.sh` + `check-main-chain-compliance.sh` fail-closed |
| 中央 parser | `parse-task-md.sh`；`frontmatter.deliverable.head_sha` 是 immutable implementation-head authority | 同；完整 JSON payload 的 `frontmatter.ac_verification` 是 V lifecycle verdict authority | consumer 必須同時驗 parsed `task_kind` / `identity.work_item_id` / `identity.source_id`，不得只因某 block 存在就跨 T/V 或跨 source 冒充 |
| Hook | `pipeline-artifact-gate.sh` | 同（filename pattern `V*.md` branch） | 同一支 hook |
| Schema validator | `validate-task-md.sh` (T mode) | `validate-task-md.sh` (V mode) | 同一支 script，filename 分流 |
| Cross-file validator | `validate-task-md-deps.sh`（掃 T+V） | 同（含 V→T pass / T→V fail invariant） | 同一支 script |

### 4.7 `ac_verification` writer contract（atomic + verify + fail-stop，對稱 D7）

DP-039 T1 起，verify-AC 每跑完一輪 AC verification 必須透過
`scripts/write-ac-verification.sh` 寫回下列 contract（與 § 2.1 `deliverable` writer
contract **對稱** — 同一份 D7，T/V 共用）。完整舊 `{JIRA-KEY}.md` migration 仍由 DP-039
後續 task 承接，但凡是 V*.md lifecycle metadata 都不得手寫。

#### Schema (when present)

`ac_verification` (frontmatter map)：

| 欄位 | Required | 規則 |
|------|----------|------|
| `status` | required | enum：`PASS` / `FAIL` / `MANUAL_REQUIRED` / `UNCERTAIN` / `BLOCKED_ENV` / `IN_PROGRESS` |
| `last_run_at` | required | ISO 8601 timestamp（建議 UTC 或帶 timezone） |
| `ac_total` | required | int ≥ 0 |
| `ac_pass` / `ac_fail` / `ac_manual_required` / `ac_uncertain` | required | int ≥ 0；總和 == `ac_total` |
| `human_disposition` | conditional | enum：`passed` / `rejected` / `deferred`；當 `status` ≠ `PASS` 時必填（FAIL/MANUAL/UNCERTAIN/BLOCKED_ENV 需人類裁決） |
| 額外欄位 | optional | freeform（如 `disposition_reason` / `last_run_by` / 公司自訂欄位） |

`ac_verification_log[]` (frontmatter list-of-maps，寬鬆)：

- 欄位若存在必須是 list（YAML array）
- 每個 entry 必須是 map（YAML object）
- `time` 欄位（ISO 8601）**建議**有（為了排序與未來 doc viewer 顯示），但**不強制**
- 其他欄位（如 `run_by` / `result` / `fail_acs` / `disposition` / `disposition_reason` / 公司自訂欄位）freeform，validator 不 enforce

> 寬鬆原則與 `jira_transition_log[]` (§ 2.1) 完全一致 — 各公司 / 各驗收 flow / error pattern 不同，強 schema 會擋掉採用。

#### Writer contract（verify-AC，DP-039 T1 起）

1. 跑完一輪 AC verification 後 → **立刻**呼叫 `scripts/write-ac-verification.sh` 寫回 V*.md：
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
- `PENDING` 若出現在 verify report，只是 human-readable aggregate label；不可直接寫入 `ac_verification.status`
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

驗收委派 verify-AC skill 執行；FAIL 走 refinement Bug source mode AC-FAIL Path（`refinement Bug source mode-ac-fail-detection` canary）。

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
