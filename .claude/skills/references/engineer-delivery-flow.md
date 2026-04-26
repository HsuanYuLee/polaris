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
| task.md | 路徑或完整內容（含 Repo、測試計畫、行為驗證 Layer B）；所有欄位讀取走 `scripts/parse-task-md.sh`（DP-032 D8） | 不需要 |
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
| Input | task.md（含 Repo、測試計畫、行為驗證 Layer B）；active `tasks/` 找不到時 fallback `tasks/complete/`（DP-033 D8）| 無 — 直接讀當前 diff |
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

## Step 2 — Local CI Mirror

執行 `bash "$(git rev-parse --show-toplevel)"/scripts/ci-local.sh`。

此 script 由 `scripts/ci-local-generate.sh` 從 repo 的 CI config（Woodpecker / GitHub Actions / GitLab CI / husky / `.pre-commit-config.yaml` / `package.json` scripts）推導產出，序列化執行 install / lint / typecheck / test / coverage 類別的 commands，並嵌入 codecov patch coverage compute。每個 repo 一份 self-contained script，框架本體不再做 CI re-discovery。

**Re-test-after-fix 鐵律**：若本 step 發現問題並修改 code，必須**重跑一次** `ci-local.sh`。上一輪修改前的結果無效。

> **Dimension model (DP-029 D6 v2 / D11；DP-032 D12-c)**：engineering 的品質要求分兩層：
> - **Dimension A — Framework Baseline（一律執行）**：TDD discipline（red-green-refactor）+ 功能驗證（`Verify Command` Step 3d）+ VR（conditional, Step 3.5）
> - **Dimension B — Repo CI-Equivalent（repo 有 `ci-local.sh` 就跑、沒有就跳）**：`ci-local.sh` 模擬 repo CI 的 patch gate / lint / typecheck / 其他 workflow jobs。repo 有配就跑，沒配就不跑 — **patch coverage 歸 repo 責任，框架不主動追加**
>
> Commit / push / `gh pr create` 前必須確認 Dimension B 全綠。Dimension A 的 TDD discipline 由 `tdd-bypass-no-assertion-weakening` canary 把關（見 `mechanism-registry.md`）。

**執行**：

```bash
bash "$(git rev-parse --show-toplevel)"/scripts/ci-local.sh
```

- exit 0 → Dimension B PASS，進 Step 3
- exit 1 → Dimension B FAIL，**回到實作階段修 root cause**，禁止放寬 assertion / `.skip()` / `as any` 繞過（canary: `tdd-bypass-no-assertion-weakening`）；修完回 Step 2 開頭重跑

**Evidence file（自動寫入）**：`ci-local.sh` 執行完必寫 `/tmp/polaris-ci-local-{branch}-{head_sha}.json`（status / branch / head_sha / timestamp / commands / summary）。`ci-local-gate.sh` PreToolUse hook 在 `git commit` / `git push` / `gh pr create` 前讀此檔案：cache hit (head_sha + status PASS) → 放行；cache miss 或非 PASS → **同步實跑** `ci-local.sh`，PASS 放行 / FAIL 擋。跳過本 step ≠ 漏網 — hook 會在第一個 git/gh 動作補位執行。

**沒有 repo CI 配置（例如框架 repo / prototype）**：`ci-local-generate.sh` 偵測不到任何可推導的 commands → 產出 NO_CHECKS_CONFIGURED 純路徑 `ci-local.sh`，直接 PASS（仍寫 evidence file status: PASS）。這是 design — 框架尊重 repo maintainer 的 CI 決策，不主動強加 coverage baseline。

**Empty-coverage 安全網（`ci-local.sh` 內建 invariant）**：若所有 patch gate 結果為 SKIP（`no_instrumented_patch_lines`）但 diff 中有匹配 gate path 的檔案，`ci-local.sh` 判定 FAIL（tests 很可能沒跑出 coverage data）。defense-in-depth — 攔截 test runner 靜默跳過 / coverage 生成失敗等未預見原因。

**Bypass**：`POLARIS_SKIP_CI_LOCAL=1` — emergency escape only，不應日常使用。**沒有** `wip:` commit-msg skip / **沒有** main-develop branch skip / **沒有** deprecation shim（D12-c 一次到位的 breaking change）。

**歷史**：TASK-123 事件（useFetch key 改動沒補測試、本地 quality PASS 但 CI `codecov/patch/main-core` FAIL）促成 DP-029 Phase B 的 patch gate 精確模擬。早期版本掛了 framework-level `coverage-gate.sh`（D6 v1），D6 v2 (2026-04-24) 判定「repo 有配就由 Dimension B 接、沒配不追加」更乾淨，coverage-gate 下架。D12-c (v3.58.0) 進一步把 `ci-contract-run.sh` / `quality-gate.sh` / `pre-commit-quality.sh` 整批下架，改由 `ci-local-generate.sh` 為每個 repo 生成 self-contained `ci-local.sh`，框架本體只保留 `ci-local-gate.sh` PreToolUse hook 做 evidence 把關。

---

## Step 3 — Behavioral Verify（Layer A + Layer B）

> 「測試過了不等於功能動得起來」— 這一步抓 SSR crash、環境起不來、改到的頁面 500 等問題。

### 3a. Discovery（repo 怎麼跑）

從 task.md 或當前 repo 決定 target：
- Developer：經 `scripts/parse-task-md.sh <path/to/task.md> --field repo` 取得 Repo 值（不直接 grep table）
- Admin：當前 git repo root

查該 repo 的執行方式，**優先序**：

| 來源 | 讀取內容 | 命中即停 |
|------|---------|---------|
| `{repo}/.claude/rules/handbook/` 的 `dev-environment.md` + `runtime-signals.md`（或 index 裡同主題段落） | start command、healthy signal、common failure、file→URL mapping | ✅ |
| 若 handbook 無 → 探 codebase | `package.json` scripts（`dev`/`start`）、`Makefile`、`docker-compose.yml`、`README.md` Quick Start | ⚠️ 僅用於推論、需使用者確認後回填 handbook |
| 若兩者皆無 | **硬 gate** — 與使用者對話建立 handbook 段落，**不得靜默 skip** | — |

### 3b. 啟環境

**首選路徑（task.md 已落地時）**：

```bash
bash {polaris_root}/scripts/start-test-env.sh --task-md {task_md_path} [--with-fixtures]
```

`start-test-env.sh` 是 D11 L3 orchestrator，依序鏈接 L2 primitives：`ensure-dependencies → start-command → health-check → [fixtures-start]`。它會自己讀 task.md（`test_environment.dev_env_config` 抽 project name，`test_environment.fixtures` 抽 fixture path），讀 workspace-config 推 cwd，並對每一步輸出 JSON 證據；任何一步 FAIL → exit 1，下游自動跳過。**Developer 必走此路徑**（若 task.md 有 `## Test Environment` 段、且 level=runtime）。`--with-fixtures` 由 task.md 是否標 `fixture_required: true` 決定。

**Fallback（無 task.md / Admin 模式 / handbook-driven repo）**：

依 discovery 結果直接執行 start command。常見型態：
- `bash {base_dir}/scripts/polaris-env.sh <project>`（D11 之前的舊整合 entry，仍可用）
- `pnpm -C <path> dev`
- `make run` / `docker compose up -d`
- `python manage.py runserver` / `bundle exec rails s`

> Fallback 只在沒有 task.md（Admin 角色）或該 repo 還沒被 D11 涵蓋時使用。**首選 = orchestrator**；orchestrator FAIL ≠ 自動降級到 fallback。

**判定**：
- start-test-env.sh exit 0（或 fallback 啟動命令 exit 0 + health check URL 回 200）→ 繼續 3c
- 啟動失敗 → 停止。回報具體失敗原因（不要只說「起不來」），列出 orchestrator 哪一步 FAIL 或 fallback 命令的 stderr tail

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

經 `scripts/parse-task-md.sh <path/to/task.md> --field verify_command` 取得指令內容。**此指令由 breakdown（Tech Lead）鎖定，sub-agent 不可修改。**

**執行流程：**

1. 透過 `parse-task-md.sh --field verify_command` 抽出 fenced code block 內容（不要自己 grep `## Verify Command`）
2. 若為 `N/A` 或 parser 回傳空（section 缺失）→ 記錄 SKIP + 原因，繼續
3. 原封不動執行該指令（Bash tool）
4. 比對 output 與 task.md 中的「預期輸出」（此段仍由 LLM 讀 task.md 對應段落比對）
5. 將**完整的指令 + 實際 output** 寫入 evidence file 的 `layer_b`

| 結果 | 動作 |
|------|------|
| 指令 output 符合預期 | ✅ Layer B PASS |
| 指令 output 不符合預期或 exit code ≠ 0 | ❌ **停止整個流程**，不進 Step 4。回報實際 output vs 預期 |
| `parse-task-md.sh --field verify_command` 回傳空（legacy task.md 無此 section） | ⚠️ 降級為舊行為：讀 `## 行為驗證` section 逐項實測（見下方 Legacy 段落） |

**為何是 hard gate**：breakdown 時 Tech Lead 已掌握改動的預期 runtime 行為，寫成可執行指令。sub-agent 只管跑指令 — 跑不過就是沒做對，不需要自行判斷「夠不夠好」。這消除了「sub-agent 聲稱 pass 但沒真跑」的結構性弱點。

**Legacy 行為驗證（task.md 無 Verify Command 時的 fallback）：**

`parse-task-md.sh` 目前未把 `## 行為驗證` 暴露成獨立 field（僅 `verify_command` 是中央化欄位）；本 fallback 路徑仍由 LLM 直接讀 task.md 對應段落。若未來 parser 擴出 `behavioral_verification` field，這段改用 `--field behavioral_verification`。逐項實測：

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

### Base Branch Resolution（適用於 § 4.5 / § R0 / 本 Step 5）

engineering 消費 task.md `Base branch` 欄位時，**一律經 resolve helper**，不可直接抄字面值：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
```

（Helper 腳本位於 repo 相對路徑 `scripts/resolve-task-base.sh`；engineering runs 以 `${CLAUDE_PROJECT_DIR}` 展開為絕對路徑呼叫。）

Helper 的行為（見 DP-028 D2 — Resolve 層）：
- 若 task.md 的 `Base branch`（即上游 task branch）**已 merged** 回 Epic feature branch → 回傳 feature branch 值
- 否則 → 回傳原 `Base branch` 字面值

這處理 depends_on 鏈在 review 期間 merge 造成的 base 漂移 — task branch 已不存在於 remote，但 rebase / PR 仍要落在有效的 base。

**應用位置**（engineering SKILL.md 四處必呼叫 resolve helper）：

| 位置 | 目的 | 呼叫時機 |
|------|------|---------|
| § 4.5 Pre-Development Rebase | `git rebase origin/<RESOLVED_BASE>` 的 target | first-cut 開工前 |
| § R0 Pre-Revision Rebase（步驟 1-3） | `git rebase origin/<RESOLVED_BASE>` 的 target | revision mode 進入後，讀施工圖前 |
| § R0 Pre-Revision Rebase（步驟 4） | `gh pr edit <PR> --base <RESOLVED_BASE>` 同步 PR base 欄位（若 PR baseRefName 不符） | 同上，rebase 成功後、讀施工圖前 |
| § Step 7c (本 flow) | `gh pr create --base <RESOLVED_BASE>` 的 `--base` 值 | 建新 PR 時（first-cut） |

**Revision mode 特別重要**：PR 已 open 期間，(a) 上游 task branch 可能被 merged 掉——R0 若直接讀 task.md `Base branch` 字面值，會 rebase 到一個已不存在的 remote branch；經 resolve helper 後自動回退到 feature branch。(b) PR baseRefName 本身可能就是錯的（pre-DP-028 建立或漂移）——R0 把它當事實會複製錯誤，用 resolve helper + `gh pr edit --base` 同步才是正確做法。

**Hook 保險**：`.claude/hooks/pr-base-gate.sh`（DP-028 D4）同時擋 `gh pr create --base <X>` 與 `gh pr edit --base <X>` 不符 resolve 結果 — 跳過 resolve helper 在 Step 7c 或 R0 步驟 4 都會被 block。與其在 hook 擋，不如在 § 4.5 / § R0 / § Step 7c 呼叫時就算對值。

### 偵測是否需要

```bash
git fetch origin
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
git log --oneline HEAD..origin/${RESOLVED_BASE} | head -1
```

- 無新 commit → **跳過**（開發前的 rebase 仍是最新的）
- 有新 commit → 執行 rebase（依 `references/cascade-rebase.md` 邏輯，含 cascade if needed；target 一律用 `${RESOLVED_BASE}`）

### Conflict 處理

嘗試自動解。解不了 → 停下告知使用者，**不繼續開 PR**。

### Rebase 後 changeset 衛生

`.changeset/` 可能因 base merge 帶入 inherited changeset。Rebase 完成後重跑 Step 6 的 Changeset 清理（刪除非本 PR ticket key 的 changeset）。

---

## Step 5.5 — Scope Check（Advisory + Risk Signal）

比對 `git diff --name-only` 與 task.md `## Allowed Files` 清單：

1. 經 `scripts/parse-task-md.sh <path/to/task.md> --field allowed_files` 取得 Allowed Files 陣列（一行一條）
2. 執行 `git diff {base}..HEAD --name-only` 取得實際改動檔案
3. 比對：

| 情況 | 處置 |
|------|------|
| 所有檔案都在 Allowed Files 內 | ✅ 繼續 |
| 有超出 scope 的檔案 | ⚠️ Advisory — 列出超出的檔案，commit message 必須附理由（「Scope addition: {file} — {reason}」）|

**不 block commit**，但 self-regulation scoring 對計畫外檔案加 +15%（原 +10%）。

若 `parse-task-md.sh --field allowed_files` 回傳空（legacy format 無此 section）→ 跳過本步驟。

---

## Step 6 — Commit + Changeset

### 6a. Commit

依 `references/commit-convention-default.md` 的 fallback chain 解析 commit message 規範：

1. **L1 — Repo tooling**：`{repo}/.commitlintrc.*` / `commitlint.config.*` / `package.json#commitlint` / husky `commit-msg` hook（最權威；機器規則 + commit-msg hook 同源 SoT）
2. **L2 — Repo handbook**：`{repo}/.claude/rules/handbook/**/*.md` 的 commit convention 段（補 L1 未宣告的敘述要求）
3. **L3 — Polaris default**：`references/commit-convention-default.md`（本 framework 兜底；headline 格式、type enum、subject 規則、squash 策略、revision 規格皆由此檔提供）

**規則衝突處理**：L1 命中即停（type enum / scope / subject limit 走 L1）；L2 / L3 只在 L1 未宣告的維度補充。

**做法**：手動寫 commit message + `git commit`（不假設 `git ai-commit` 等 user-level 工具可用，DP-032 D22 已從 framework 拔除）。commit-msg hook fail → 讀 stderr → 對照 L1 config 修 msg → 重試。

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

`--base` 值**必須**來自 resolve helper，不可直接抄 task.md 字面（見 § Base Branch Resolution + DP-028 D6）：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
POLARIS_PR_WORKFLOW=1 gh pr create --base "${RESOLVED_BASE}" --title "<title>" --body "<body>"
```

Admin 模式（無 task.md）直接用當前 branch upstream 或 `origin/main`，跳過 resolve helper。

`pr-base-gate.sh` hook（DP-028 D4）會擋 `--base` 值與 resolve 結果不符的呼叫 — 跳過 helper 會在這一步被 block。

- Developer title：`[{TICKET}] <summary>`
- Admin title：`<type>(<scope>): <summary>`（conventional commit 格式）

**PR 建立成功後（Developer first-cut mode）— deliverable 回寫（DP-033 A8）**：

`gh pr create` 成功取得 `PR_URL` 後，**立刻**呼叫 write-deliverable 寫回 task.md。此步驟是 hard gate — 失敗 = HALT，不繼續執行 Step 8：

```bash
HEAD_SHA=$(git rev-parse HEAD)
"${CLAUDE_PROJECT_DIR}/scripts/write-deliverable.sh" "<path/to/task.md>" "$PR_URL" "OPEN" "$HEAD_SHA"
```

- 腳本內部：寫入 `.tmp` → `mv`（atomic）→ re-read verify（`deliverable.pr_url` 必須 match）
- 失敗時（含 3 次 retry 後仍失敗）→ 腳本 exit 1，輸出：
  ```
  task is in inconsistent state — PR created but task.md not updated. Manual recovery required.
  ```
- **不得繼續執行 Step 8**（JIRA transition / Slack 通知 / next handoff）直到此步驟 exit 0
- 不得用 `/tmp` fallback 或 silent continue — inconsistent state 必須立刻被人類看到
- Admin 模式（無 task.md）跳過本段

**Revision mode**（既有 PR）：

當 engineering 以 revision mode 觸發時，PR 已存在（PR URL 是輸入之一）。此時不建新 PR，改為 push to existing PR：

1. **PR base sync 已於 R0 完成**（engineering SKILL.md § R0 步驟 4）：若 PR `baseRefName` != `RESOLVED_BASE` → R0 已跑 `gh pr edit --base "$RESOLVED_BASE"` 同步；`pr-base-gate.sh` hook 同時擋 `gh pr create --base` 與 `gh pr edit --base` 不符 resolve 結果
2. `git push` 到既有 PR 的 remote branch（branch 已 checkout）
3. 跳過 `gh pr create`（hook 不觸發）
4. 若 PR body 需更新（如新增修正摘要），用 `gh pr edit --body` 更新（不帶 `--base` 不會觸發 gate）
5. **更新 head_sha**（revision mode）：push 成功後更新 task.md 的 `deliverable.head_sha`（同 write-deliverable.sh；`pr_state` 不變，維持 `OPEN`）

`POLARIS_PR_WORKFLOW=1` 讓 `pr-create-guard.sh` hook 放行（evidence file + quality flow 已確認）。僅 first-cut mode 需要。

### 7d. Update PR description（可選）

`git update-pr-desc --ci` 若可用，讓 AI 自 diff 產描述填回 PR body。

---

## Step 8 — JIRA Transition（Developer only）

PR 建立後，轉 JIRA ticket 狀態為 `CODE REVIEW`：

```bash
{workspace_root}/scripts/polaris-jira-transition.sh {TICKET} code_review
```

`polaris-jira-transition.sh`（D25，DP-032 Wave α）統一所有 JIRA transition 呼叫，跨 LLM runtime 共用：built-in slug map（`code_review` → "Code Review"），workspace-config `jira.transitions.code_review` 可覆寫；ticket 已在目標狀態 / 找不到 transition / 沒 creds / API error 一律 stderr 訊息 + exit 0，不阻擋 delivery flow。

**Admin 模式跳過本 step**（無 ticket）。

### 8a. Mark task spec as IMPLEMENTED（Developer only）

PR 建立成功後，將對應的 task.md 或 plan.md frontmatter 標為 `status: IMPLEMENTED`，讓 docs-viewer sidebar 顯示綠底完成樣式：

```bash
{workspace_root}/scripts/mark-spec-implemented.sh {TICKET}
```

Helper 會自動：
- 先找 Epic-level anchor（`specs/{TICKET}/refinement.md` / `plan.md`）→ in-place frontmatter update
- 找不到時 fallback 到 Task-level anchor（T{n}/V{n} key 或 `> JIRA: {TICKET}` header 比對）→ **move-first 順序**（DP-033 D6）：
  1. `mv tasks/{T}.md → tasks/complete/{T}.md`（先搬，永遠不會在 active `tasks/` 內寫 IMPLEMENTED）
  2. 在 `tasks/complete/{T}.md` 更新 frontmatter `status: IMPLEMENTED`
- `tasks/complete/` 若不存在自動建立
- Idempotent — 已在 complete/ 且已標過相同 status 不做事
- 同 key 衝突（active 與 complete/ 並存且內容不同）→ exit 2，須人工解決

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
  "runtime_contract": {
    "level": "static | build | runtime",
    "runtime_verify_target": "string | N/A",
    "runtime_verify_target_host": "string",
    "verify_command": "string",
    "verify_command_url": "string",
    "verify_command_url_host": "string"
  },
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

`scripts/polaris-write-evidence.sh --ticket <ID> --task-md <path/to/task.md> --result "PASS: ..."`（可重複 `--result`；或手動 Write tool 建檔）。

### Hook Enforcement

`pre-pr-create-hook.sh` 在 `gh pr create` 執行前檢查：
- 檔案存在、`ticket` / `branch` 匹配
- `timestamp` 在 4h 內
- `runtime_contract` 存在，且 `level` 為 `static|build|runtime`
- 若 `level=runtime`：`runtime_verify_target` 必須是 live URL，`verify_command_url` 必須存在，且兩者 host 一致
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
