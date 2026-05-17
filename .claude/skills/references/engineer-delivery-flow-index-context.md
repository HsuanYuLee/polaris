# Engineer Delivery Flow

共用的「工程師交付」執行流程。**受消費者**：
- **`engineering`**（Developer 角色，ticket-driven 或 DP-backed framework work）
- **`engineering`**（Local Extension 角色，workspace-local delivery endpoint）

舊的無 task.md Admin PR entrypoint 已 sunset；framework repo 改動也必須先有 DP-backed task.md，再由 `engineering` 進入本 delivery backbone。

## Delivery Contract

### Preconditions（呼叫端必須提供）

| 項目 | Developer | Local Extension |
|------|-----------|--------------------|
| Branch | Task branch 已 checkout（`task/PROJ-NNN-*` 或 `task/DP-NNN-Tn-*`）| Local-policy-approved task branch 已 checkout |
| Code | 實作完成、可 commit 的狀態 | 實作完成、可 local extension handoff 的狀態 |
| task.md | 路徑或完整內容（含 Repo、測試計畫、行為驗證 Layer B）；所有欄位讀取走 `scripts/parse-task-md.sh`（DP-032 D8） | task.md，同 Developer |
| JIRA ticket key | 產品 ticket 必填；DP-backed framework work 使用 DP pseudo-task ID | 依 local policy；可使用 DP pseudo-task ID |
| Base branch | 從 task.md 或 JIRA parent 推導 | 從 task.md / local policy 推導 |
| Role declaration | context 明確說 `role: developer` | context 明確說 `role: local-extension` |

### Postconditions（本流程保證）

- Code 經過 /simplify + Self-Review（Phase 3 exit gates）
- Scope 在 task.md Allowed Files 範圍內（Step 1.5 gate）
- Local CI mirror PASS — evidence: `/tmp/polaris-ci-local-{branch}-{head_sha}.json`（Layer A）
- Behavioral verify PASS — evidence: `/tmp/polaris-verified-{ticket}-{head_sha}.json`（Layer B，via `run-verify-command.sh`）
- VR PASS（if triggered）— evidence: `/tmp/polaris-vr-{ticket}-{head_sha}.json`（Layer C，via `run-visual-snapshot.sh`）
- **Layer A+B(+C) evidence AND gate**：所有必要 evidence 檔案存在且 `head_sha` 匹配當前 HEAD 才放行 PR、local extension handoff、或 post-PR release handoff
- **Completion gate before user-facing done**：回報完成前必須再檢查一次 Layer A（and Developer Layer B）是否仍對應當前 HEAD，避免在 git 動作前先口頭結案
- **Shared PR state authority**：要對外說 `awaiting_re_review`、`mergeable_ready`、或
  `needs_code_changes` 時，必須以 `resolve-pr-work-source.sh` →
  `pr-state-snapshot.sh` → `pr-action-classifier.sh` 的 fresh state 為準；schema 與
  vocabulary authority 是 `pr-state-contract.md`，不能靠 skill 自己拼 API
- **Framework-enforced final metadata**：PR body template / language、task-bound verify report、
  assignee final state 都是 completion authority，不是 repo side-effect 成功後可忽略的附帶條件
- **Remote repo CI is non-blocking when still queued / pending / running**：本流程以本地 LLM + mechanism evidence 為 completion authority；不等待遠端 CI 排隊或長時間執行完畢
- Developer：PR 建立在正確 base branch，body 依 repo template 填充
- Developer：JIRA 狀態轉為 CODE REVIEW（soft-fail）
- Developer：task.md `deliverable.pr_url` + `head_sha` 寫回
- Local Extension：交付給 workspace-local extension，由 local policy 定義是否需要 workspace PR、final verification 與 completion evidence；例如 `framework-release` 必須消費已建立 / 已 merge 的 workspace PR，而不是 direct push workspace `main`

### 不做的事

- **不做 AC 業務驗收** — 那是 `verify-AC` 的工作
- **不做 planning / breakdown** — 上游 skill 負責
- **不做 branch 建立** — 呼叫端已 checkout
- **不做 JIRA 讀取決定行為** — JIRA 是 write-only side-effect（D1）
- **不做 handbook/codebase discovery 推論** — config 缺失 → fail loud（D11）

---

## 設計原則

1. **單一源** — execution 紀律在此定義，skill 不重寫。skill SKILL.md 只負責路由、輸入解析、角色標註，具體怎麼做全部讀這份。
2. **框架無關** — 不寫死 Nuxt / Laravel / Rails 的命令。repo 的啟動方式由 **workspace-config + handbook config** 宣告（D11 composable primitives），script 消費宣告，不假設 stack。這也包含 **依賴安裝**：worktree / fresh checkout 在跑任何 test / build / dev-server 前，先透過 `scripts/env/install-project-deps.sh` 讀 task.md；`Level=static` 時 script 回傳 `noop_static` PASS，不讀 project config；其他 level 才讀 `projects[].dev_environment.install_command`，未宣告時由 script 根據 lockfile / manifest 決定（`pnpm-lock.yaml` → `pnpm install --frozen-lockfile`、`poetry.lock` → `poetry install --sync` 等），避免把「先裝套件」留給 LLM 自行猜測。
   - **Handbook machine fields boundary（DP-035）**：script-consumable project runtime / test / URL mapping / key library 欄位的 target source 是 `{company}/polaris-config/{project}/handbook/config.yaml`；`handbook/*.md` 只提供 narrative / rationale，不可被 script 當資料庫解析。過渡期 `start-test-env.sh` 使用 handbook config first；若 config 缺失才 explicit fallback 到 `workspace-config.yaml`，且 duplicate field conflict 由 validator fail loud。
3. **task.md authoritative（D1）** — task.md 是 engineering 內部的唯一 state container。Verification URLs, allowed files, verify command, deliverable 全在 task.md。Engineering 對 JIRA 是 write-only（side-effect display）。
4. **Positive-evidence + fail-loud（D11/D12）** — script exit 0 必須代表「實際做了且通過」；config 缺失 → fail loud，不 fallback 推論。
5. **Evidence 只由 script 產出（D15/D16）** — LLM 不直接寫 evidence file（hook 物理擋 Write/Edit on `/tmp/polaris-verified-*` / `/tmp/polaris-ci-local-*`）；evidence `writer` 欄位 + whitelist gate 提供 cross-LLM 保護。
6. **終態是 evidence AND gate** — Layer A（`ci-local.sh`）+ Layer B（`run-verify-command.sh`）+ Layer C（`run-visual-snapshot.sh`, conditional）三檔 evidence 全部 `head_sha` 匹配當前 HEAD 才放行 PR、local extension handoff、或 post-PR release handoff。
7. **產品 repo CI 設定唯讀** — Engineering 讀取 repo CI declarations 來建立 local mirror，但不得在產品 ticket / revision PR 中修改 Woodpecker、GitHub Actions、GitLab CI、Codecov、husky、pre-commit、或 package script 等 CI 設定來修綠燈。若 gate failure 的 root cause 是 CI config 或 local/remote parity，應 fail-stop 並回報 framework / repo-owner decision，而不是把 CI policy change 混入產品交付。

## Two-Segment Architecture（D21）

```
┌─ LLM 實作段（可迭代，fail-cheap）───────┐  ┌─ 機械自驗段（線性，fail-stop）──────────────────┐
│ Phase 3: TDD → /simplify → Self-Review │  │ Step 1.5 Scope → 2 Rebase+Quality+CI          │
│          (exit: 三者全綠)              │  │   → 3 Verify → 3.5 VR → 5 Base Detect         │
│                                        │  │   → 6 Commit → 7 PR/Extension → 8 JIRA/Ext    │
└────────────────────────────────────────┘  └──────────────────────────────────────────────┘
```

**Step 完整序列**：Step 1 Simplify → Step 1.3 Self-Review → Step 1.5 Scope Gate → Step 2 前置 Rebase → Step 2 Local CI Mirror → Step 3 Verify → Step 3.2 Flow Gap Audit → Step 3.5 VR → Step 5 Base Freshness → Step 6 Commit+Changeset → Step 7 PR / Local Extension Handoff → Step 8 JIRA / Extension Verification → Step 8a Finalize Delivery（Completion Gate + IMPLEMENTED + Worktree Cleanup）

## Role Matrix

| 步驟 | Developer（engineering） | Local Extension（engineering + workspace-local policy） |
|------|---------------------|-----------------------------------------------|
| Input | task.md（含 Repo、測試計畫、行為驗證）；active `tasks/` 找不到時 fallback `tasks/pr-release/`（DP-033 D8）| task.md（同 Developer schema；eligibility 由 local policy 定義） |
| Step 1 Simplify | ✅ | ✅ |
| **Step 1.3 Self-Review（Phase 3 exit gate，D21）** | ✅ | ✅ |
| **Step 1.5 Scope Gate（`check-scope.sh`，D20）** | ✅ | ✅ |
| **Step 2 前置 Rebase（`engineering-rebase.sh`，D6/D19）** | ✅ | ✅ |
| Step 2 Local CI Mirror（`ci-local.sh`，D12） | ✅ | ✅ |
| Step 3 Behavioral Verify（`run-verify-command.sh`，D15） | ✅ | ✅ |
| Step 3.2 Flow Gap Audit（bypass / fallback / false-pass / ignored artifacts） | ✅ | ✅ |
| Step 3.5 Visual Regression（`run-visual-snapshot.sh`，conditional，D18） | ✅ 若 task.md VR 觸發 | ✅ 若 task.md VR 觸發 |
| ~~Step 4~~（已搬至 Step 1.3 — Phase 3 exit gate，編號留空避免下游 reference 斷裂） | — | — |
| Step 5 Base Freshness Detection（`check-base-fresh.sh`，D19） | ✅ | ✅ |
| Step 6 Commit + Changeset | ✅ | 依 local policy；portable flow 至少產生 handoff package |
| Step 7 PR Create（含 7a Evidence AND Gate） | ✅ | 依 local policy：PR-bypass endpoint 改走 handoff；post-PR release endpoint 仍須建立 / 更新 workspace PR |
| Step 8 JIRA Transition → CODE REVIEW | ✅ | ⏭️ 跳過（無 JIRA ticket） |
| Step 8a Mark IMPLEMENTED | ✅ | ✅ 但只在 extension final verification 成功後 |
| **Step 8.5 Completion Gate（`check-delivery-completion.sh` / `check-local-extension-completion.sh`）** | ✅ | ✅ `extension_deliverable` metadata + Layer A/B freshness gate |
| Evidence file 鍵 | `/tmp/polaris-verified-{TICKET}-{head_sha}.json` 或 `/tmp/polaris-verified-{TASK_ID}-{head_sha}.json` | `/tmp/polaris-verified-{TASK_ID}-{head_sha}.json` |

**Role 由呼叫端傳入**，reference 不做角色偵測。呼叫端在 dispatch prompt 或 context 說明「你是 Developer / Local Extension」。Local Extension 的具體 endpoint、repo、release/push 權限、final verification 全部由 workspace-local policy 定義，不進 portable reference。

---

