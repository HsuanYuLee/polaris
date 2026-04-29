---
name: verify-AC
description: >
  QA agent: executes Epic AC (Acceptance Criteria) verification against an AC ticket or Epic.
  Runs all AC steps, classifies each as PASS/FAIL/MANUAL_REQUIRED/UNCERTAIN, and presents
  observed vs expected as pure facts (no root-cause judgement).
  On FAIL, surfaces human disposition gate (spec issue vs implementation drift); on PASS,
  transitions the AC ticket to Done.
  Trigger: "驗 PROJ-123", "verify {TICKET}", "verify AC", "跑驗收", "AC 驗證".
  NOT for planning or implementation: implementation drift routes to bug-triage;
  spec issue routes back to refinement.
metadata:
  author: Polaris
  version: 1.1.0
---

# verify-AC — Epic 驗收 QA

pipeline 的 **QA** 環節（見 [pipeline-handoff.md](../references/pipeline-handoff.md)）。本 skill stateless + comment-driven：每次都 full re-run，結果全部寫回 JIRA comment，不依賴本地狀態。

## 前置：讀取 workspace config

讀 `references/workspace-config-reader.md`（需要 `jira.instance`、`github.org`、`base_dir`、`projects[].dev_environment`）。Fallback 用 `references/shared-defaults.md`。

## Handoff Artifact (on-demand)

上游 skill（engineering）完成 PR 後會在 `{company_base_dir}/specs/{EPIC}/artifacts/engineering-*.md` 留下 evidence artifact（格式見 `skills/references/handoff-artifact.md § engineering`）。預設**不讀** — Epic AC 驗收步驟本身就是事實基準，engineering 的 Layer B 輸出只是參考。只在以下情況打開：

- AC 驗證 observation 與 engineering 的 behavioral verify 結論矛盾（例：engineering 回報「切語系後 footer 正確」，但 AC 驗證觀察到 footer 文字沒變）
- 需要 cross-check engineering 是否已測過本 AC 對應的行為（避免兩邊重跑同一條）
- 懷疑 implementation commit 就已經 drift（例：PR 中的 commit SHA 與目前 HEAD 不符）

路徑：`{company_base_dir}/specs/{EPIC}/artifacts/engineering-{ticket_key}-*.md`
格式：`## Summary` (≤500 字 implementation + quality 摘要) + `## Raw Evidence` (test output、Layer B 輸出、commit SHAs)
先讀 Summary；需要對帳才掃 Raw Evidence。

## 角色邊界

| Do | Don't |
|----|-------|
| 執行 AC 驗證步驟 | 判斷 FAIL 原因（交給人工 disposition） |
| 呈現 observed vs expected | 直接改 code 或建 bug-fix 分支 |
| 全部 AC 每次重跑（含 PASS 過的）防 regression | 只跑上次 FAIL 的 AC |
| PASS 自動轉驗收單 Done | 壓通過（Observed ≠ Expected 就是 FAIL） |
| FAIL 時在 JIRA 呈現 disposition gate | 自己決定走 bug-triage 還是 refinement |

## 進入點消歧

| 輸入 | 處理 |
|------|------|
| AC 驗收單 key（issuetype = Task + summary 含 `[驗證]`） | 直接進入 Step 3 |
| Epic key | 掃描該 Epic 下所有 AC 驗收單，逐張進入 Step 3（依 depends_on 排序） |
| Task / Bug / Story（非驗收單） | 拒絕：「這不是驗收單。要驗收請提供 AC 驗收單或 Epic key」 |
| 未提供 key | 詢問使用者 |

## Workflow

### 1. 解析輸入 + 讀取 ticket

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <INPUT_KEY>
  fields: ["summary", "status", "issuetype", "description", "parent", "comment", "labels"]
```

判斷類型：
- Summary 含 `[驗證]` 且 issuetype = Task → 視為 AC 驗收單
- issuetype = Epic → 進入 Epic 模式（Step 1.5）
- 其他 → 拒絕

### 1.5. Epic 模式展開

若輸入為 Epic：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: parent = <EPIC_KEY> AND summary ~ "[驗證]"
  fields: ["summary", "status", "description", "comment", "labels"]
```

依 AC description 中 `depends_on: AC#N` 欄位建立執行順序：
- 無 `depends_on` → 可平行
- 有 `depends_on` → 等被依賴者 PASS 後才執行

對每張驗收單依序（或並行）跑 Step 2-6。

### 2. Loop-count 警戒

掃描驗收單 + 對應 Bug ticket 的 comments，count `## 驗證結果` 出現次數。若 **≥ 3** → surface 警告：

```
⚠️ {AC_KEY} 已經驗證 {N} 次仍未通過。繼續前建議檢查：
- 是否為架構問題（非單點 bug）
- AC 描述是否有歧義
- 是否有隱藏依賴未處理
是否要繼續？（y/n）
```

### 3. 讀取驗證步驟 + 環境準備

從 AC 驗收單 description 讀取「驗證步驟」章節。若 description 缺驗證步驟 → 標記 **UNCERTAIN**，addComment 說明「無驗證步驟可執行，需補充 AC 描述」，結束本張。

**環境啟動**（local + fixture server）：

**Step 3a. 讀驗收單 task.md**

**Worktree dispatch — 主 checkout 絕對路徑**
Sub-agent 在 worktree 執行；`specs/` 與 `.claude/skills/` 是 gitignored（worktree 無此檔）。dispatch prompt 須以主 checkout 絕對路徑讀寫：
- task.md: `{company_base_dir}/specs/{EPIC}/tasks/T{n}.md`
- artifacts / verification: `{company_base_dir}/specs/{EPIC}/artifacts/`、`.../verification/`
詳見 `skills/references/worktree-dispatch-paths.md`。

查找驗收單對應的 task.md：`{company_base_dir}/specs/{EPIC_KEY}/tasks/{AC_TICKET_KEY}.md`。若存在 → 讀取 fixture 設定；若不存在 → fallback `tasks/pr-release/{AC_TICKET_KEY}.md`（DP-033 D8 reader fallback）；兩者皆無 → fallback 到 Step 3b。

**Step 3b. Fixture 自動偵測（fallback）**

若無 task.md，自動偵測 `specs/{EPIC_KEY}/tests/mockoon/` 是否有 `.json` 檔案。有 → 視為 `fixture_required: true`，使用 conventional path。無 → 視為不需 fixture，只起 dev server。

**Step 3c. 啟動環境（含 Fixture）**

跑 D11 L3 orchestrator，一支命令包住「dependencies → start-command → health-check → fixtures-start」全鏈：

```bash
bash {polaris_root}/scripts/start-test-env.sh --task-md {task_md_path} [--with-fixtures]
```

- 加 `--with-fixtures` 的條件：Step 3a 解出 `fixture_required: true`，**或** Step 3b fallback 偵測到 `specs/{EPIC_KEY}/tests/mockoon/` 有 `.json`。orchestrator 會自己讀 task.md 的 `## Test Environment` `Fixtures:` 欄抽路徑（N/A → 報錯 exit 1，由 sub-agent fall back 到 conventional path 並改用 `--fixtures-dir <path>` 重跑）
- orchestrator 自抽 project name（從 `test_environment.dev_env_config`），讀 workspace-config 推 dependencies / start_command / health_check URL；每步輸出 JSON 證據（`primitive: start-test-env`），任一步 FAIL → exit 1
- exit 0 → 繼續 Step 4（dev server + fixture server 都已 ready）
- exit ≠ 0 → 本張驗證 block，addComment「環境啟動失敗：第 {step} 步」（`step` 從 stderr / 最後一行 JSON 讀），不標 PASS/FAIL（標 UNCERTAIN）

> 不要再分別呼叫 `polaris-env.sh` + `mockoon-runner.sh`；orchestrator 已包住 D11 L2 primitives。Fallback 到舊路徑只在該 repo 還沒被 task.md schema 涵蓋時使用，需在 sub-agent return 中標註原因。

### 4. 逐步驟執行 + 分類

對每個驗證步驟：

1. 執行操作（curl / playwright / 檢視原始碼 / 檢查 JSON-LD 等）
2. 擷取 observed（含 HTTP status、response body、screenshot 路徑）
3. 對比 expected
4. 分類：

| 分類 | 條件 |
|------|------|
| **PASS** | 步驟可機器檢查 + observed == expected（含 HTTP 200 門檻）|
| **FAIL** | 步驟可機器檢查 + observed ≠ expected |
| **MANUAL_REQUIRED** | 步驟本質需主觀判斷（UX、視覺、文案）|
| **UNCERTAIN** | 能跑但 AI 不確定斷言正確性（邊界語意、非確定性輸出）|

**HTTP status 門檻**：任何 endpoint 驗證必須檢查 status code == 200（或 AC 指定值），再看 body。只看 body「看起來正確」= UNCERTAIN。

### 5. Evidence 收集

截圖、curl output、VR diff 等，先存本地留底再上傳 JIRA：

**5a. 本地留底**（見 `references/epic-folder-structure.md`）：
```bash
# Evidence 存放路徑：specs/{EPIC}/verification/{AC_KEY}/{timestamp}/
mkdir -p {company_base_dir}/specs/{EPIC}/verification/{AC_KEY}/$(date +%Y%m%d-%H%M%S)
# 複製所有 evidence 到該目錄
```

**5b. JIRA 上傳**：
```bash
bash {base_dir}/scripts/jira-upload-attachment.sh <AC_KEY> <file_path>
```

Comment 使用 VR template wiki markup（見 `references/vr-jira-report-template.md`），圖片以 `!filename.png|thumbnail!` 嵌入表格 cell。

### 6. 整體結論判定 + JIRA Comment

| 組合 | 結論 |
|------|------|
| 全部 PASS | **PASS** → Step 7（自動轉 Done）|
| 任一 FAIL | **FAIL** → Step 8（disposition gate）|
| 有 MANUAL_REQUIRED / UNCERTAIN 但無 FAIL | **PENDING** → Step 9（等使用者手動判斷）|

Comment 採 wiki markup（**不用 MCP addCommentToJiraIssue**，用 REST API v2）：

```markdown
## 驗證結果 — {YYYY-MM-DD}

**結論：PASS ✅** （或 FAIL ❌ / PENDING ⏳）

|| 步驟 || 結果 || Observed || Expected ||
| 1. {操作} | ✅ PASS | {actual, 含 HTTP status} | {expected} |
| 2. {操作} | ❌ FAIL | {actual} | {expected} |
| 3. {操作} | 🔍 MANUAL | {actual} | 需人工判斷 UX |

環境：{local + mockoon / staging / ...}
驗證工具：{curl / playwright / 檢視 HTML}
執行時間：{timestamp}
```

若 PASS 格式遵 `references/epic-verification-structure.md § 驗證結果 Comment`。

**Workspace language policy gate（advisory rollout）**

完整規則見 `references/workspace-language-policy.md`；本段只定義 verify-AC 的接入點。

JIRA comment / 驗收報告送出前，先將最終 comment body 寫入暫存 markdown，執行：

```bash
bash scripts/validate-language-policy.sh --advisory --mode artifact <verify-ac-comment.md>
```

第一版先 advisory，因為 verify-AC 會引用 AC 原文、HTTP response、錯誤訊息與多語系畫面
文字；這些片段不應被誤判為 skill 輸出語言漂移。升級成 blocking 的條件：常見 AC
引用 / response transcript 已有 allowlist 或 wrapper mode，且連續 release 無 false positive。
即使 advisory，主敘述（Observed / Expected / disposition 說明）仍必須使用 workspace
language。

### 7. PASS → 自動轉 Done

```bash
{workspace_root}/scripts/polaris-jira-transition.sh <AC_KEY> done
```

`polaris-jira-transition.sh`（D25）為跨 LLM runtime 的統一入口：built-in slug map（`done` → "Done"），workspace-config `jira.transitions.done` 可覆寫；ticket 已在 Done / 找不到 transition / 沒 creds / API error 一律 stderr 訊息 + exit 0，不阻擋驗收流程。失敗時自動退回「貼 comment 模式」（標記結論但不轉狀態），surface 給使用者手動處理。

Epic 模式下，所有 AC 驗收單都 Done 時：

1. Notify：「Epic {EPIC_KEY} 全部 AC 通過，可以 merge feature branch。」
2. 執行 `scripts/mark-spec-implemented.sh {EPIC_KEY}`，將 `{company}/specs/{EPIC_KEY}/refinement.md` frontmatter `status` 標為 `IMPLEMENTED`，讓 docs-viewer sidebar 顯示灰+✅。idempotent（已標過就 no-op）。

### 8. FAIL → Human Disposition Gate

在驗收單貼 comment，附 disposition checkbox（由使用者編輯勾選）：

```markdown
## Disposition（請人工勾選，二選一）

- [ ] **實作偏差** — code 沒達到 AC 行為 → 建 per-AC Bug → bug-triage
- [ ] **規格問題** — AC 描述錯誤/不完整 → 回 refinement
```

**呈現給使用者**：skill 執行完後 prompt：

```
🚦 {AC_KEY} FAIL — 請選擇 disposition：
  1. 實作偏差（建 Bug → bug-triage）
  2. 規格問題（Epic 加 label → refinement）
  3. 稍後再處理（不路由，保留 FAIL 狀態）
```

**單一 disposition per cycle**（實作 / 規格互斥）。

#### 8a. 實作偏差 → per-AC Bug

對每條 FAIL 的 AC 建一張 Bug（N 條 FAIL = N 張 Bug）：

```
mcp__claude_ai_Atlassian__createJiraIssue
  cloudId: {config: jira.instance}
  projectKey: {從 Epic 的 project 推}
  issueTypeName: "Bug"
  summary: "[{EPIC_KEY}][驗證失敗] AC#{N} — {AC 描述摘要}"
  parentKey: <EPIC_KEY>
```

Bug description 填 `pipeline-handoff.md § Bug ticket 必要資訊` 區塊（[VERIFICATION_FAIL]、實作追溯、失敗項目、復現條件、驗證 metadata）。

**不填 assignee**（bug-triage 對 assignee blind，由運維層決定）。

**Handoff artifact 寫入**（DP-024 D3 擴散；見 `skills/references/handoff-artifact.md § verify-AC`）：

對每張新建的 Bug，寫一份 evidence artifact 給下一 skill（bug-triage AC-FAIL Path）on-demand 讀：

- **路徑**：`{company_base_dir}/specs/{EPIC}/artifacts/verify-ac-verify-fail-{BUG_KEY}-{timestamp}.md`（timestamp 格式 `YYYY-MM-DDTHHMMSSZ` UTC）
- **格式**：frontmatter（`skill: verify-ac`、`ticket: {BUG_KEY}`、`scope: verify-fail`、`timestamp`、`truncated: false`、`scrubbed: false`）+ `## Summary`（≤ 500 字：AC# + 期望行為 + 實際觀察 + HTTP status + env snapshot）+ `## Raw Evidence`（失敗步驟 transcript、curl output / playwright trace、evidence attachment 路徑、AC ticket description 引用、被驗證的 commit SHA / dev server URL / fixture path）
- **寫入後必跑 scrub + cap**：`python3 scripts/snapshot-scrub.py --file {artifact_path}`（scrub secrets、20KB 截斷、更新 frontmatter flag）
- **寫入後必跑 language advisory**：`bash scripts/validate-language-policy.sh --advisory --mode artifact {artifact_path}`；若主敘述違反 workspace language，修正後再交給 bug-triage
- artifact 路徑加進 Bug description 的 `[VERIFICATION_FAIL]` metadata 區塊，bug-triage Step 2-AF 會在需要時讀

回到 AC 驗收單貼 comment：「FAIL — 追蹤於 {BUG_KEY_1}, {BUG_KEY_2}, ...」。

**Routing**：skill 結束後告知使用者：「建了 {N} 張 Bug：{BUG_KEYS}。跑 `bug-triage {BUG_KEY}` 開始診斷。」

#### 8b. 規格問題 → refinement

在 Epic 上：

1. `editJiraIssue` 加 label `verification-spec-issue`
2. `addCommentToJiraIssue`（透過 REST API v2 wiki markup）：

```markdown
## [VERIFICATION_SPEC_ISSUE] AC#{N}

- 來源：verify-AC on {AC_TICKET_KEY}
- Observed：{actual}
- Expected (per AC)：{AC spec}
- 規格問題：{AC 描述哪裡不清楚 / 矛盾 / 不完整}
- 建議方向：{給 refinement 參考}
```

回到 AC 驗收單貼 comment：「規格待 refinement 釐清 → 見 Epic {EPIC_KEY} comment」。

**不建新 ticket**。

### 9. PENDING → 等人工

有 MANUAL_REQUIRED / UNCERTAIN 但無 FAIL 時，skill 結束時列出待人工項目：

```
⏳ {AC_KEY} 有 {N} 項需人工判斷：
  - Step 3: {MANUAL_REQUIRED 描述}
  - Step 5: {UNCERTAIN 描述，附 observation}

使用者確認後：
  - 全部 OK → 執行 `verify-AC {AC_KEY}` 重跑（會標 PASS）
  - 有問題 → 手動標記 FAIL，觸發 disposition
```

### 10. 能力擴充素材累積

對每個 MANUAL_REQUIRED / UNCERTAIN，寫一筆 learning：

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  bash {base_dir}/scripts/polaris-learnings.sh add \
  --key "verify-ac-gap-<AC_KEY>-<step_slug>" \
  --type pitfall \
  --tag verify-ac-gap \
  --content "<步驟描述 + 為何無法自動斷言>" \
  --confidence 5 \
  --source "verify-AC <AC_KEY>" \
  --metadata '{"ac_ticket":"<AC_KEY>","step":"<step_id>"}'
```

同類案例累積 3 次 → 抽成自動驗證 pattern（未來加到本 SKILL.md / reference）。

### 11. L2 Deterministic Check: post-task-feedback-reflection

整輪驗證結束（PASS / FAIL / PENDING 三路皆適用）後，跑 advisory check：session 內若出現自糾正信號（command 失敗後自修 / rerun）但無新 feedback memory 檔案 → 提示反思。

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-feedback-signals.sh" \
  --skill verify-AC
```

根據 exit code（advisory — script 恆 exit 0）：
- **exit 0 + 無 stdout** — 無反思訊號，直接結案
- **exit 0 + 有 stdout** — 依 `rules/feedback-and-memory.md` 判斷是否寫 feedback memory 或更新 handbook

此 canary 原列 `rules/mechanism-registry.md § Feedback & Memory`（behavioral），DP-030 Phase 2C 下放為 deterministic。L1 fallback 由 Stop hook（`.claude/hooks/feedback-reflection-stop.sh`）補位。遵循 `skills/references/l2-script-conventions.md` advisory 約定。

## Re-verify

本 skill stateless，每次執行都 full re-run。觸發方式：

- **Explicit**：使用者說「驗 {EPIC}」或「verify {AC_KEY}」
- **Opportunistic**：其他 skill（converge / next / my-triage / standup）偵測到「feature branch 所有 task PR 已 merge + AC 驗收單仍 Open + 無進行中 bug-triage」→ surface 建議

## Do / Don't

- Do: 每次 full re-run，含之前 PASS 過的 AC（防 regression）
- Do: HTTP status code == 200 是最低門檻，status 不對 = FAIL
- Do: Evidence 上傳為 JIRA attachment，comment 用 wiki markup 嵌入
- Do: FAIL 時呈現 disposition gate，等人工勾選
- Do: PASS 自動透過 `polaris-jira-transition.sh` 轉到 Done（D25）
- Do: Epic 模式下，依 AC `depends_on` 排序
- Don't: 判斷 FAIL 原因（AI 只呈現事實）
- Don't: 單張 AC 同時走兩條 disposition（互斥）
- Don't: 只跑上次 FAIL 的 AC（必須 full re-run）
- Don't: 用 MCP `addCommentToJiraIssue` 貼驗證結果（會丟格式，用 REST API v2）
- Don't: 跳過無驗證步驟的 AC（標 UNCERTAIN，addComment 要求補 AC）

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
