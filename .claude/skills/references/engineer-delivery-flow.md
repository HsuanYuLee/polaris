# Engineer Delivery Flow

共用的「工程師交付」執行流程。**受消費者**：
- **`engineering`**（Developer 角色，ticket-driven，產品 repo）
- **`git-pr-workflow`**（Admin 角色，無 ticket，框架/docs 維護）

兩個 skill 都 include 本 reference 作為 execution backbone。唯一分歧在少數 role-specific 步驟（見 § Role Matrix）。

## Delivery Contract

### Preconditions（呼叫端必須提供）

| 項目 | Developer | Admin |
|------|-----------|-------|
| Branch | Task branch 已 checkout（`task/PROJ-NNN-*`）| 非 main 的工作 branch |
| Code | 實作完成、可 commit 的狀態 | 變更完成 |
| task.md | 路徑或完整內容（含 Repo、測試計畫、行為驗證 Layer B）| 不需要 |
| JIRA ticket key | 必填 | 不需要 |
| Base branch | 從 task.md 或 JIRA parent 推導 | 當前 branch upstream 或 `origin/main` |
| Role declaration | context 明確說 `role: developer` | context 明確說 `role: admin` |

### Postconditions（本流程保證）

- Code 經過 simplify、lint、test、coverage 檢查
- 受影響 URL 在 local dev 環境回 200 + healthy signal（Layer A）
- task.md 行為驗證項目逐項 PASS（Layer B，Developer only）
- Evidence file 寫入 `/tmp/polaris-verified-{ID}.json`
- PR 建立在正確 base branch，body 依 repo template 填充
- JIRA 狀態轉為 CODE REVIEW（Developer only）

### 不做的事

- **不做 AC 業務驗收** — 那是 `verify-AC` 的工作
- **不做 planning / breakdown** — 上游 skill 負責
- **不做 branch 建立** — 呼叫端已 checkout
- **不做 VR baseline 管理** — VR 是獨立 service skill，本流程僅條件觸發（§ Step 3.5）

---

## 設計原則

1. **單一源** — execution 紀律在此定義，skill 不重寫。skill SKILL.md 只負責路由、輸入解析、角色標註，具體怎麼做全部讀這份。
2. **框架無關** — 不寫死 Nuxt / Laravel / Rails 的命令。特定 repo 的啟動方式、healthy signal、URL 映射由 **repo handbook** 提供（§ Step 3 Discovery）。
3. **Layer A 強制 / Layer B 加料** — Layer A（「code 真的跑得起來」）是不可豁免的工程師基線；Layer B（任務特定行為）由 task.md 提供，無則跳過但 Layer A 仍跑。
4. **終態是 evidence file** — `/tmp/polaris-verified-{ID}.json` 是唯一 gate marker，`pre-pr-create` hook 讀它放行。push 不擋，只擋 `gh pr create`。

## Role Matrix

| 步驟 | Developer（engineering） | Admin（git-pr-workflow） |
|------|---------------------|------------------------|
| Input | task.md（含 Repo、測試計畫、行為驗證 Layer B）| 無 — 直接讀當前 diff |
| Step 1 Simplify | ✅ | ✅ |
| Step 2 Quality Check | ✅ | ✅ |
| Step 3 Behavioral Verify Layer A（discovery + env + URL 200 + healthy signal）| ✅ | ✅ |
| Step 3 Layer B（task.md § 行為驗證 逐項跑） | ✅ | ⏭️ 無 task.md 則跳過 |
| Step 3.5 Visual Regression（條件觸發） | ✅ 若 VR domain 命中 | ✅ 若 VR domain 命中 |
| Step 4 Pre-PR Self-Review | ✅ | ✅ |
| Step 5 Final Rebase Re-Sync | ✅（通常 skip — 主 rebase 在開發前） | ✅ |
| Step 6 Commit + Changeset | ✅ | ✅ |
| Step 7 PR Create | ✅ | ✅ |
| Step 8 JIRA Transition → CODE REVIEW | ✅ | ⏭️ 跳過（無 JIRA ticket） |
| Evidence file 鍵 | `/tmp/polaris-verified-{TICKET}.json` | `/tmp/polaris-verified-{branch-slug}.json` |

**Role 由呼叫端傳入**，reference 不做角色偵測。呼叫端在 dispatch prompt 或 context 說明「你是 Developer / Admin」。

---

## Step 1 — Simplify Loop

在品質檢查前，先審查本次 diff 的簡潔性。

**執行方式**：invoke user-level `/simplify` skill（`~/.claude/skills/simplify/`）。若該 skill 不存在，降級為 inline 自審 — 跑一輪「讀 diff、找重複邏輯、抽共用、移除不必要複雜度」。

**迭代邏輯**：
- 每輪 `/simplify` 結束後，若 `git diff` 有新變動 → 再跑一輪（新改動可能引入新簡化機會）
- 無變動 → 進入 Step 2
- **最多 3 輪**。第 3 輪仍有修改則停止，記錄並報給使用者判斷

**不要**做：範圍超出本次 diff 的重構、重新命名無關檔案的變數、為了「美化」而動測試檔案。

---

## Step 2 — Quality Check

執行 `references/quality-check-flow.md` 的完整流程（lint / test / coverage / risk scoring）。

**Re-test-after-fix 鐵律**：若本 step 發現問題並修改 code，所有測試和 lint 必須**重跑一次**。上一輪修改前的結果無效。

本 step 通過後才能進 Step 3。未通過就繼續 = 欺騙下游。

### 2a. Coverage Gate Check（硬門檻）

Push 前必須確認 repo 的 Codecov patch gate（若有）會過。這一步抓「改動太小所以不寫測試」的誤判。

**偵測**（repo root 任一命中即視為有 gate）：
1. `codecov.yml` 或 `.codecov.yml` 含 `type: patch`
2. `.github/workflows/*.yml` 提到 `codecov/patch`

**有 gate 時，強制執行**（無 gate 直接跳到 Step 3）：

1. `git diff {base}..HEAD --name-only` 取改動檔案清單，排除 test 檔、type 檔、config、changeset、docs
2. 對每個剩下的 source file，跑 coverage（命令由 repo handbook `testing.md` 或 CLAUDE.md 提供，如 your-app：`pnpm --filter @your-org/your-app-main exec vitest run --coverage --coverage.include='<file>'`）
3. 確認改動的可執行 line 都在 coverage 報告中（不強求 100% line coverage，但 **PR diff 內的每個新/改 line 都必須至少被一個 test 碰到**）
4. 未達標 → 補測試，回 Step 2 開頭重跑
5. 達標 → 呼叫 writer 寫 evidence：

```bash
"$CLAUDE_PROJECT_DIR/scripts/write-coverage-evidence.sh" \
  --status PASS \
  --branch "$(git rev-parse --abbrev-ref HEAD)" \
  --note "patch lines covered: <summary>" \
  --file "<changed_file_1>" --file "<changed_file_2>"
```

Evidence 檔：`/tmp/polaris-coverage-{branch-slug}.json`（TTL 4h）。

**Hook 保險**：`coverage-gate.sh` 會在 `git push` 時讀這個檔。檔案不存在 / status≠PASS / >4h 過期 → exit 2 擋下 push。

**Bypass**（罕見情境）：
- `POLARIS_SKIP_COVERAGE=1 git push ...` — docs-only / config-only / 純 test 調整
- HEAD commit message 前綴 `wip:` — 草稿 push（hook 自動放行）

**為什麼是硬門檻**：TASK-123 事件 — engineering 判定「只加一行 `key` option」不需測試，本地 quality check PASS 但 CI `codecov/patch/main-core` fail。破功點是 TDD smart judgment 沒把 CI gate 納入。規則：**repo 有 patch gate → 所有 source 改動一律補測試**，不以「改動小」為由豁免。

---

## Step 3 — Behavioral Verify（Layer A + Layer B）

> 「測試過了不等於功能動得起來」— 這一步抓 SSR crash、環境起不來、改到的頁面 500 等問題。

### 3a. Discovery（repo 怎麼跑）

從 task.md 或當前 repo 決定 target：
- Developer：讀 task.md § Operational Context 的 `Repo` 欄位
- Admin：當前 git repo root

查該 repo 的執行方式，**優先序**：

| 來源 | 讀取內容 | 命中即停 |
|------|---------|---------|
| `{repo}/.claude/rules/handbook/` 的 `dev-environment.md` + `runtime-signals.md`（或 index 裡同主題段落） | start command、healthy signal、common failure、file→URL mapping | ✅ |
| 若 handbook 無 → 探 codebase | `package.json` scripts（`dev`/`start`）、`Makefile`、`docker-compose.yml`、`README.md` Quick Start | ⚠️ 僅用於推論、需使用者確認後回填 handbook |
| 若兩者皆無 | **硬 gate** — 與使用者對話建立 handbook 段落，**不得靜默 skip** | — |

### 3b. 啟環境

依 discovery 結果執行 start command。常見型態：
- `bash {base_dir}/scripts/polaris-env.sh <project>`（已有 Docker + dev server 整合）
- `pnpm -C <path> dev`
- `make run` / `docker compose up -d`
- `python manage.py runserver` / `bundle exec rails s`

**判定**：
- 啟動命令 exit 0 + health check URL 回 200 → 繼續 3c
- 啟動失敗 → 停止。回報具體失敗原因（不要只說「起不來」）

### 3b+. Fixture Existence Advisory Check（僅 Developer）

若 task.md 有 `fixture_required: true`（指向驗收單的 fixture 需求），檢查 `specs/{EPIC_KEY}/tests/mockoon/` 是否有 `.json` 檔案：

| 結果 | 動作 |
|------|------|
| 目錄有 `.json` 檔案 | ✅ 繼續（fixture 已建） |
| 目錄為空或不存在 | ⚠️ **Advisory warning**（不 block）：「task.md 標記 fixture_required 但 mockoon 目錄為空 — 驗收階段可能缺測資。若本 task 負責建 fixture，請在實作中完成」 |

> 不 block 的原因：fixture 可能由其他子單負責建立，本 task 不一定是 fixture 的生產者。但 warning 確保開發者意識到 fixture 需求。

### 3c. 推導受影響 URL + curl 200 + healthy signal

從 `git diff {base_branch}..HEAD --name-only` 取改到的檔案清單。對照 handbook 的 **File → URL Mapping** 推導受影響的 URL。

對每個推導出的 URL：

1. `curl -sS -o /tmp/resp.html -w '%{http_code}\n' <url>`
2. HTTP code 必須 200
3. response body 比對 handbook 定義的 healthy signal（例：Nuxt 含 `__NUXT__`、API 含預期 JSON key、Go 服務 `/health` 回 `ok`）

| 結果 | 動作 |
|------|------|
| 全部 URL 200 且 healthy signal 符合 | ✅ Layer A PASS |
| 任一 URL ≠ 200 或 healthy signal 缺失 | ❌ 停止。列出具體 URL + status + 差異，回報使用者 |
| File → URL Mapping 無法推導（改動皆為 util / type / config） | 記錄「N/A」，Layer A 降級為「env-up only」通過 |

### 3d. Layer B — Verify Command（僅 Developer，hard gate）

讀 task.md 的 `## Verify Command` section。**此指令由 breakdown（Tech Lead）鎖定，sub-agent 不可修改。**

**執行流程：**

1. 從 task.md 提取 `## Verify Command` 下的 code block
2. 若為 `N/A` → 記錄 SKIP + 原因，繼續
3. 原封不動執行該指令（Bash tool）
4. 比對 output 與 task.md 中的「預期輸出」
5. 將**完整的指令 + 實際 output** 寫入 evidence file 的 `layer_b`

| 結果 | 動作 |
|------|------|
| 指令 output 符合預期 | ✅ Layer B PASS |
| 指令 output 不符合預期或 exit code ≠ 0 | ❌ **停止整個流程**，不進 Step 4。回報實際 output vs 預期 |
| task.md 無 `## Verify Command` section（legacy task.md） | ⚠️ 降級為舊行為：讀 `## 行為驗證` section 逐項實測（見下方 Legacy 段落） |

**為何是 hard gate**：breakdown 時 Tech Lead 已掌握改動的預期 runtime 行為，寫成可執行指令。sub-agent 只管跑指令 — 跑不過就是沒做對，不需要自行判斷「夠不夠好」。這消除了「sub-agent 聲稱 pass 但沒真跑」的結構性弱點。

**Legacy 行為驗證（task.md 無 Verify Command 時的 fallback）：**

讀 task.md 的 `## 行為驗證` section（若有）。逐項實測：

| 類型 | 驗證方式 |
|------|---------|
| Wiring 檢查（"composable X 被 page Y import"）| `grep` 對應 import 敘述、或啟頁面 curl HTML 含預期元素 |
| SSR 輸出檢查（"HTML 含 JSON-LD BreadcrumbList"）| curl + grep |
| 效能目標（"TTFB < Ns"）| 走 `references/behavioral-verification.md § Perf A/B Worktree` |
| AC-linked 行為（"切語系後 footer 正確"）| **此類若屬 Epic-level AC 應寫在 AC 驗收單，非本 task** |

每項逐條記錄 PASS / FAIL / SKIP（附原因）。FAIL 停止整個流程，不進 Step 4。

### 3e. 寫 evidence file

不論 Layer A / B 結果（PASS 才會到這裡），寫入 evidence file：

```json
{
  "ticket": "PROJ-123",                           // Admin 模式：branch slug
  "role": "developer",                           // or "admin"
  "timestamp": "2026-04-14T09:30:00Z",
  "branch": "task/PROJ-123-breadcrumblist",
  "layer_a": {
    "env_up": "PASS",
    "changed_urls": [
      {"url": "/zh-tw/product/133300", "status": 200, "signal": "PASS"}
    ],
    "discovery_source": "handbook"               // or "codebase_probe" / "user_prompt"
  },
  "layer_b": {
    "source": "verify_command",
    "command": "curl -sS http://dev.yourapp.com/zh-tw/product/24632 | python3 -c \"import sys; html=sys.stdin.read(); head=html.split('</head>')[0]; assert 'application/ld+json' in head, 'NOT FOUND'; print('PASS')\"",
    "expected": "PASS",
    "actual_output": "PASS",
    "status": "PASS"
  },
  "summary": {"total": 3, "pass": 3, "fail": 0, "skip": 0}
}
```

無此檔案 → `pre-pr-create-hook` 擋下 `gh pr create`，整個流程必定要寫。

---

## Step 3.5 — Visual Regression（條件觸發）

> 此步驟在 Behavioral Verify 之後、Self-Review 之前執行。VR 是獨立 service skill（`visual-regression`），本流程僅負責判定是否觸發。

### 觸發條件

1. 讀 workspace-config.yaml → `visual_regression.domains[]`
2. 從 `git diff {base}..HEAD --name-only` 的改動檔案，比對 domain 的 `pages[].path` 或 file→URL mapping
3. **觸發**：改動檔案對應到任一 VR domain 的頁面 → invoke `visual-regression` skill（Local mode）
4. **不觸發**：改動未命中 VR domain（純 util / type / config / 非 VR 覆蓋頁面）→ 跳過，記錄 `vr: "N/A — no VR-covered pages affected"`

### 執行

觸發時，以 Local mode 執行 VR（比對 git stash base vs 當前變更）：
- VR PASS（zero-diff 或 expected diff）→ 繼續 Step 4
- VR FAIL（unexpected diff）→ **停止**。列出 failing pages，回報使用者決定是否修正或 accept

### Evidence 整合

VR 結果附加到 evidence file：

```json
{
  "vr": {
    "triggered": true,
    "mode": "local",
    "domain": "dev.example.com",
    "pages_checked": 4,
    "result": "PASS",
    "detail": "zero-diff across 4 pages, 2 viewports"
  }
}
```

未觸發時：`"vr": { "triggered": false, "reason": "no VR-covered pages affected" }`

---

## Step 4 — Pre-PR Self-Review Loop

啟動獨立 Reviewer sub-agent 對本地 diff 做 code review（格式、型別、邊界、測試覆蓋、convention）。

**Reviewer 規格**：見 `references/sub-agent-roles.md § Critic (Pre-PR Review)`。回傳 JSON `{ passed, blocking[], non_blocking[], summary }`。

**迭代**：
- `passed: true` → 進 Step 5
- `passed: false` → 逐項修 blocking → 回 Step 1（修改後要重新 simplify / quality check / behavioral verify）
- **最多 3 輪**，超過詢問使用者手動處理或強制繼續

---

## Step 5 — Final Rebase Re-Sync

> **主 rebase 已在開發前完成**（engineering SKILL.md § 4.5 / R0）。本步驟只做 final re-sync：若 base branch 在開發期間又前進了，補做一次 rebase。

### 偵測是否需要

```bash
git fetch origin
git log --oneline HEAD..origin/{base} | head -1
```

- 無新 commit → **跳過**（開發前的 rebase 仍是最新的）
- 有新 commit → 執行 rebase（依 `references/cascade-rebase.md` 邏輯，含 cascade if needed）

### Conflict 處理

嘗試自動解。解不了 → 停下告知使用者，**不繼續開 PR**。

### Rebase 後 changeset 衛生

`.changeset/` 可能因 base merge 帶入 inherited changeset。Rebase 完成後重跑 Step 6 的 Changeset 清理（刪除非本 PR ticket key 的 changeset）。

---

## Step 5.5 — Scope Check（Advisory + Risk Signal）

比對 `git diff --name-only` 與 task.md `## Allowed Files` 清單：

1. 讀 task.md `## Allowed Files` section
2. 執行 `git diff {base}..HEAD --name-only` 取得實際改動檔案
3. 比對：

| 情況 | 處置 |
|------|------|
| 所有檔案都在 Allowed Files 內 | ✅ 繼續 |
| 有超出 scope 的檔案 | ⚠️ Advisory — 列出超出的檔案，commit message 必須附理由（「Scope addition: {file} — {reason}」）|

**不 block commit**，但 self-regulation scoring 對計畫外檔案加 +15%（原 +10%）。

若 task.md 無 `## Allowed Files` section（legacy format）→ 跳過本步驟。

---

## Step 6 — Commit + Changeset

### 6a. Commit

使用專案慣例（`git ai-commit --ci` 若可用，否則手動寫 commit message + `git commit`）。commit message 參照 repo 的 `.claude/rules/` commit convention。

### 6b. Changeset（若 repo 使用 changesets）

偵測 repo 是否有 `.changeset/` 目錄。若無則跳過。

**建立**：用 Write tool 建 `.changeset/{kebab-case}.md`，格式從 repo 的 `changeset-guideline.md` 讀取（通常 `patch` + ticket key + conventional prefix）。

**清理（Inherited Changeset Check）**：
1. `git diff origin/{base} --name-only -- .changeset/` 列出所有 changeset 檔
2. 每個 changeset 讀內容、比對 ticket key
3. 不匹配 → `git rm` 刪除（inherited from dependency branch）

### 6c. JIRA Safety Net（Admin fallback）

Admin 模式無 ticket key。若 repo 的 changeset guideline 要求 ticket key：
- Admin branch 名含 `wip/` 或 `polaris/` → 允許省略
- 其他情況 → 提示使用者補 key，或走 `references/pr-input-resolver.md` 的 fallback 流程

---

## Step 7 — PR Create

### 7a. 讀 PR template

依 `references/pr-body-builder.md` 的 template detection 邏輯讀取 repo 的 `.github/pull_request_template.md`。無則 fallback 到預設格式。

### 7b. 組 PR body

| Template section | 填充來源 |
|------------------|---------|
| Description | Developer：task.md § 目標；Admin：commit messages 概要 |
| Changed | `git diff --name-only` + 人話摘要 |
| AC Coverage | Developer：task.md § AC + Layer B 驗證結果打勾；Admin：跳過 |
| Test Plan | Developer：task.md § 測試計畫；Admin：commit 摘要中的驗證摘要 |
| Related documents | 相關 JIRA / Figma / Confluence link |

### 7c. 開 PR / 推送至既有 PR

**First-cut mode**（新 PR）：

```bash
POLARIS_PR_WORKFLOW=1 gh pr create --base <detected-base> --title "<title>" --body "<body>"
```

- Developer title：`[{TICKET}] <summary>`
- Admin title：`<type>(<scope>): <summary>`（conventional commit 格式）

**Revision mode**（既有 PR）：

當 engineering 以 revision mode 觸發時，PR 已存在（PR URL 是輸入之一）。此時不建新 PR，改為 push to existing PR：

1. `git push` 到既有 PR 的 remote branch（branch 已 checkout）
2. 跳過 `gh pr create`（hook 不觸發）
3. 若 PR body 需更新（如新增修正摘要），用 `gh pr edit` 更新

`POLARIS_PR_WORKFLOW=1` 讓 `pr-create-guard.sh` hook 放行（evidence file + quality flow 已確認）。僅 first-cut mode 需要。

### 7d. Update PR description（可選）

`git update-pr-desc --ci` 若可用，讓 AI 自 diff 產描述填回 PR body。

---

## Step 8 — JIRA Transition（Developer only）

PR 建立後，轉 JIRA ticket 狀態為 `CODE REVIEW`（`transitionJiraIssue`，transition id 見 `references/jira-*.md`）。

轉換失敗（ticket 已不在 IN DEVELOPMENT）則忽略，不中斷流程。

**Admin 模式跳過本 step**（無 ticket）。

### 8a. Mark task spec as IMPLEMENTED（Developer only）

PR 建立成功後，將對應的 task.md 或 plan.md frontmatter 標為 `status: IMPLEMENTED`，讓 docs-viewer sidebar 顯示綠底完成樣式：

```bash
{workspace_root}/scripts/mark-spec-implemented.sh {TICKET}
```

Helper 會自動：
- 先找 Epic-level anchor（`specs/{TICKET}/refinement.md` / `plan.md`）
- 找不到時 fallback 到 Task-level anchor（`specs/*/tasks/T*.md` 比對 `> JIRA: {TICKET}` header）
- Idempotent — 已標過相同 status 不做事

失敗（找不到 anchor 等）不中斷流程，但需在對話中告知使用者。

**Admin 模式跳過本 step**（無 ticket / task.md）。

---

## Halting Conditions

流程在任何步驟失敗皆停止，不靜默繼續：

| 步驟 | 失敗處置 |
|------|---------|
| Step 1 Simplify 3 輪未穩定 | 詢問使用者手動介入 |
| Step 2 Quality Check | 修 → re-run；修不了停止回報 |
| Step 3a Discovery 兩層皆無 | **硬 gate** — 對話建立 handbook，不可 skip |
| Step 3b 環境起不來 | 停止。回報原因 |
| Step 3c URL 非 200 / healthy signal 缺 | 停止。列差異 |
| Step 3d Layer B FAIL | 停止。不進 Step 3.5 |
| Step 3.5 VR FAIL（unexpected diff） | 停止。列 failing pages，使用者決定 |
| Step 4 Review 3 輪仍有 blocking | 詢問使用者手動處理 |
| Step 5 Final re-sync conflict 解不了 | 停止。不開 PR |
| Step 7 PR create hook 擋（evidence missing） | 停止。回頭檢查 3e |

---

## Evidence File

### Schema

```json
{
  "ticket": "string",              // Developer 必填；Admin 可用 branch slug
  "role": "developer | admin",
  "timestamp": "ISO-8601",
  "branch": "string",
  "layer_a": {
    "env_up": "PASS | FAIL | SKIP",
    "changed_urls": [{"url": "...", "status": 0, "signal": "PASS|FAIL"}],
    "discovery_source": "handbook | codebase_probe | user_prompt"
  },
  "layer_b": [{"item": "string", "status": "PASS|FAIL|SKIP", "evidence": "string"}],
  "summary": {"total": 0, "pass": 0, "fail": 0, "skip": 0}
}
```

### 寫入時機

Step 3e 寫入。若 Layer B 結果在 3d 後續步驟（Step 4 review 修 bug）有變動，需**重寫整個 evidence file**（TTL 新鮮度 < 4h，hook 會查 timestamp）。

### 寫入工具

`scripts/polaris-write-evidence.sh --ticket <ID> --layer-a <json> --layer-b <json>`（或手動 Write tool 建檔）。

### Hook Enforcement

`pre-pr-create-hook.sh` 在 `gh pr create` 執行前檢查：
- 檔案存在、`ticket` / `branch` 匹配
- `timestamp` 在 4h 內
- `layer_a.env_up` = `PASS`（或所有 `changed_urls` 為 N/A）
- `summary.fail` = 0

任一不符 → exit 2，hook 擋下 PR create，列出不符原因。

### Bypass

`POLARIS_SKIP_EVIDENCE=1` 可豁免（用於沒改 runtime code 的 commit，例如純 docs）。hook 收到此 env var 放行但記錄 log。

---

## Role-Specific Notes

### Developer 呼叫端責任（engineering SKILL.md）

呼叫前：
- 已通過 Plan Existence Gate（task.md 存在）
- 已 checkout 正確 branch（或現在建立）
- 已執行 `polaris-sync.sh` 部署 AI 設定

呼叫時 context：
- Role: `developer`
- task.md 完整內容（或路徑）
- JIRA ticket key
- Base branch

### Admin 呼叫端責任（git-pr-workflow SKILL.md）

呼叫前：
- 確認當前 repo 是 Polaris framework / docs / 通用 repo（skill-routing 會擋產品 repo）
- 當前 branch 非 main

呼叫時 context：
- Role: `admin`
- 當前 branch
- PR type（framework / docs / other）

---

## Iteration & Halting Metrics

Risk signal（若多次觸發，呼叫端應停下回報使用者而非繼續）：

- Step 1-4 任一 step 重跑 ≥ 3 次
- evidence file 重寫 ≥ 2 次
- 同一檔案連續被修 ≥ 4 次
- 總 tool call 數超過 40 但仍未進 Step 7

符合 ≥ 2 項 → 停止，回報當前狀態給使用者判斷（對應 `sub-agent-delegation.md § Self-Regulation Scoring`）。

---

## 和其他 reference 的關係

- [quality-check-flow.md](quality-check-flow.md) — Step 2 內容
- [behavioral-verification.md](behavioral-verification.md) — Step 3 的效能 A/B Worktree、goal-backward wiring 等延伸工具（Layer B 高階驗證使用）
- [pipeline-handoff.md](pipeline-handoff.md) — 角色邊界與 task.md schema（Developer 上游）
- [repo-handbook.md](repo-handbook.md) — handbook 結構（Step 3a Discovery 讀取來源）
- [cascade-rebase.md](cascade-rebase.md) — Pre-work rebase（engineering § 4.5 / R0）+ Step 5 final re-sync
- [sub-agent-roles.md](sub-agent-roles.md) — Step 4 Reviewer sub-agent 規格
- [pr-body-builder.md](pr-body-builder.md) — Step 7 PR template detection + body 組裝
- [pr-input-resolver.md](pr-input-resolver.md) — PR URL/number/branch 解析
- [visual-regression-config.md](visual-regression-config.md) — Step 3.5 VR domain 設定 schema

## 來源

本 reference 從原 `git-pr-workflow` Step 2-9、原 `verify-completion` 行為驗證段、原 `dev-quality-check` Step 6 smoke test 整併而來。2026-04-14 engineering（原 work-on）重構 v2 抽出作為共用 backbone（見 memory `project_workon_redesign_v2.md`）。
