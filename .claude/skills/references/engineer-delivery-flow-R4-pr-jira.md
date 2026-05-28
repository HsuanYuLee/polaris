## Step 7 — PR Create / Local Extension Handoff

### Local Extension role

Local Extension role 的 PR 行為由 local policy 決定。Step 7 的 precondition 仍相同：Layer A+B(+C) evidence 必須存在且匹配 task head。

- PR-bypass local endpoint：通過 gate 後不呼叫 `polaris-pr-create.sh`，而是組 workspace-local extension handoff package。
- Post-PR release endpoint（例如 `framework-release`）：先用正常 Developer PR lane 建立 / 更新 workspace PR，寫入真實 `deliverable.pr_url`，再把 PR URL 與 task head 一起交給 extension。不得用 direct push workspace `main` 取代 workspace PR。

Handoff package 必須包含：

```text
role: local-extension
extension_id: <local extension id>
task_md: <absolute path to DP task.md>
task_id: <identity.work_item_id>
repo: <repo root>
workspace_pr_url: <workspace PR URL, if local policy requires PR>
workspace_pr_number: <workspace PR number, if local policy requires PR>
task_branch: <current branch>
task_head_sha: <current HEAD>
evidence:
  ci_local: <Layer A evidence path>
  verify: <Layer B evidence path>
  vr: <Layer C evidence path, if triggered>
delivery_intent:
  endpoint: local_extension
  summary: <summary>
  changed_files: <intentional files>
release_closeout:
  helper: scripts/framework-release-closeout.sh (when declared by local policy)
```

handoff 後的 delivery side effects 由 local extension 擁有。Portable engineering 只要求 local policy 明定：

1. eligibility（哪些 task / repo 可使用 extension）
2. integration rules（如何消費已驗證的 task head；是否需要 workspace PR）
3. final verification evidence
4. failure / rollback reporting
5. task.md 標記 implemented 前要使用的 lifecycle metadata writer / closeout helper。Post-PR framework release endpoint 必須使用 `scripts/framework-release-closeout.sh`，不得手動拼接 writer、completion gate、parent closeout、cleanup 與 archive。

Local Extension role 不得寫入假的 `deliverable.pr_url`。若存在真實 workspace PR，保留真實 `deliverable` metadata，並以 `extension_deliverable` 記錄 release tail。若 local policy 提供 closeout helper，該 helper owns `extension_deliverable`、`check-release-eligible.sh`、`check-local-extension-completion.sh`、task implemented move、parent closeout、`check-release-completed.sh` 與 worktree cleanup。若沒有 closeout helper，`deliverable` 維持 absent，由 extension 透過 `scripts/write-extension-deliverable.sh` 寫入 `extension_deliverable` metadata，並在 task lifecycle closeout 前通過 `scripts/check-local-extension-completion.sh`。

### 7a. Evidence AND Gate（pre-PR / pre-release verification）

Before creating PR、local extension handoff、或 post-PR release handoff，驗證所有必要 evidence 檔案存在且 `head_sha` 匹配當前 HEAD：

| Layer | Evidence file | Required? |
|-------|--------------|-----------|
| A (CI) | `/tmp/polaris-ci-local-{branch}-{head_sha}.json` | Always（if `ci-local.sh` exists） |
| B (Verify) | `/tmp/polaris-verified-{ticket-or-task-id}-{head_sha}.json` | Developer / Local Extension with verify_command |
| C (VR) | `/tmp/polaris-vr-{ticket}-{head_sha}.json` | Only if Step 3.5 triggered |
| D (Behavior) | `/tmp/polaris-behavior-{ticket}-{head_sha}-{context_hash}.json` | Only if `verification.behavior_contract.applies=true` |

Missing 或 stale evidence → **halt**。不繼續 PR creation、local extension handoff、或 post-PR release handoff。
Behavior contract evidence 由 `scripts/run-behavior-contract.sh` 產生；`parity` / `hybrid`
先跑 `--mode baseline`，delivery 前跑 `--mode compare`。

**Portable gate fallback**：`gate-evidence.sh` + `gate-ci-local.sh` 在 git pre-push 及 `polaris-pr-create.sh` wrapper 中也強制檢查；`gate-pr-title.sh` + `gate-changeset.sh` 在 `polaris-pr-create.sh` 與 completion gate 中強制檢查；`gate-pr-body-template.sh` 在 `polaris-pr-create.sh` 中阻擋未保留 repo template headings 的 body。Completion gate 會重新讀 deliverable 的 remote PR metadata/body，確認 PR readiness（`state=OPEN`、`isDraft=false`）、remote PR body template conformance、remote PR body language policy，以及 local visual / Playwright / behavior contract evidence 是否已發布成 PR-visible publication comment；裸 `gh pr create`、`gh pr create --draft`、PR 建立後 body drift、或 local-only 截圖/影片 evidence 都不能成為 completion endpoint。Review approval / GitHub mergeability 的 `blocked_review` 是 post-delivery review readiness，不阻擋 engineering closeout；merge conflict、stale base、failing CI、draft PR、缺 evidence / assignee 仍是 hard blocker。若需要人工上傳，先使用 `collect-evidence-upload-bundle.sh` 產生 `artifacts/{WORK_ITEM_ID}-pr-upload/`，再由使用者把檔案拖到 PR comment 並保留 publication marker。Skill-level check here is **L2 cross-LLM authoritative**（所有 LLM 都走 SKILL.md → 一定到這步）。Completion gate 是 hard gate，但 `awaiting_re_review`、`mergeable_ready`、`unsupported_mutation`、`stale_downstream` 等 readiness vocabulary 仍由 shared PR state authority 發號，不由單一 skill prose 決定。

### 7b. 讀 PR template

在撰寫 PR body draft 前先讀 `references/pr-body-builder.md` § 0 Producer Preflight 與 § 1
template detection。依 L1→L2→L3 chain 讀 repo template；L1 repo template 命中時，body
skeleton 必須從該 template 的 headings / comments intent 起稿，不可先產 generic
`Summary / Verification` body 再等 `gate-pr-body-template.sh` 或 completion gate 擋下重寫。
無 repo/company template 時才 fallback 到 Polaris 預設格式。

### 7c. 組 PR body

內文語言必須依 `references/pr-body-builder.md § 3.0`：先讀 root `workspace-config.yaml` 的 `language`，未設定才 fallback 到使用者本輪主要語言；template headings 保留 repo 原文。

| Template section | 填充來源 |
|------------------|---------|
| Description | Developer：task.md § 目標；Admin：commit messages 概要 |
| Changed | `git diff --name-only` + 人話摘要 |
| AC Coverage | Developer：task.md § AC + Layer B 驗證結果打勾；Admin：跳過 |
| Test Plan | Developer：task.md § 測試計畫；Admin：commit 摘要中的驗證摘要 |
| Related documents | 相關 JIRA / Figma / Confluence link |

### 7d. 開 PR / 推送至既有 PR

**First-cut mode**（新 PR）：

`--base` 值**必須**來自 resolve helper，不可直接抄 task.md 字面（見 § Base Branch Resolution + DP-028 D6）：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
PR_BODY_FILE="$(mktemp -t polaris-pr-body.XXXXXX.md)"
# Write the template-derived PR body into "$PR_BODY_FILE".
bash "${CLAUDE_PROJECT_DIR}/scripts/polaris-pr-create.sh" --base "${RESOLVED_BASE}" --title "<title>" --body-file "$PR_BODY_FILE"
```

Admin 模式不得建立 Polaris-governed repo 的 source-less PR。若 framework / product repo
需要 hotfix，先補合法 source artifact（例如 DP/refinement -> breakdown task 或 Bug RCA ->
task），再進 PR creation；不得把「小修」、「emergency」或 maintainer intent 當作 bypass。

`polaris-pr-create.sh` wrapper（DP-032 Wave δ + DP-117）在 `gh pr create` 前先執行
`gate-work-source.sh`，確認 current branch 能 resolve 到合法 `task.md`；此 gate 不受
`--skip-gates` 影響且沒有 emergency bypass。通過後才依序執行 gate-base-check +
gate-evidence + gate-ci-local + gate-pr-title + gate-pr-body-template + gate-pr-language +
gate-changeset — 缺 source、`--base` 值與 resolve 結果不符、Developer title 不符、PR
body 未保留 repo template headings、PR prose 違反 workspace language、或 task changeset
缺失時 wrapper 直接 block。

不可使用裸 `gh pr create`、generic publisher、或 `gh pr create --draft` 當作 Developer
delivery 終點。即使 runtime 沒有 Claude hook，Step 8.5 仍會以 GitHub remote PR truth
重新檢查 deliverable；source-less PR、draft PR、非 open PR、或 invalid remote PR body
會阻擋 task lifecycle closeout。Codex / non-Claude runtime 不會自動套用 Claude Code
PreToolUse hook，因此 `polaris-pr-create.sh` 與 completion gate 是 portable authority；
required assignee metadata 必須以 GitHub issue assignees 為準，不能以 repo CI
`auto_assign_user` status 取代。

- Developer title：先讀 company `workspace-config.yaml` 中 matching repo 的 `projects[].delivery.pr_title.developer`；未設定才 fallback `[{TICKET}] {summary}`
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

**Revision mode**（既有 PR）：

當 engineering 以 revision mode 觸發時，PR 已存在（PR URL 是輸入之一）。此時不建新 PR，改為 push to existing PR：

1. **PR base sync 已於 R0 完成**（engineering SKILL.md § R0 步驟 4）：若 PR `baseRefName` != `RESOLVED_BASE` → R0 已跑 `gh pr edit --base "$RESOLVED_BASE"` 同步；`gate-base-check.sh`（git hook / `polaris-pr-create.sh` wrapper）同時擋 PR base 不符 resolve 結果
2. **Revision push 前要求 changeset gate**：至少執行 `polaris-changeset.sh new --task-md "<path/to/task.md>" --repo "<repo_root>"`；若暫時不能執行則至少執行 `gate-changeset.sh --repo "<repo_root>"`（revision mode 的 git pre-push 已包裝）以避免可追溯性缺口。
3. `git push` 到既有 PR 的 remote branch（branch 已 checkout）
4. 跳過 `gh pr create`（hook 不觸發）
5. 若 PR body 需更新（如新增修正摘要），先讀 `pr-body-builder.md` § 0 與 § 3d，用既有 remote body
   的 template sections 做 overlay，再 materialize body file 並跑 `gate-pr-body-template.sh --body-file`
   + `validate-language-policy.sh --blocking --mode artifact`；兩者通過後才用 `gh pr edit --body-file`
   更新；不得用 inline `--body`
6. **更新 head_sha**（revision mode）：push 成功後更新 task.md 的 `deliverable.head_sha`（同 write-deliverable.sh；`pr_state` 不變，維持 `OPEN`）

`POLARIS_PR_WORKFLOW=1` 是 legacy `pr-create-guard.sh` hook escape hatch；新流程使用 `polaris-pr-create.sh` wrapper，不應新增依賴。

### Base Branch Resolution（適用於 § 4.5 / § R0 / 本 Step 7d）

engineering 消費 task.md `Base branch` 欄位時，**一律經 resolve helper**，不可直接抄字面值：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
```

（Helper 腳本位於 repo 相對路徑 `scripts/resolve-task-base.sh`；engineering runs 以 `${CLAUDE_PROJECT_DIR}` 展開為絕對路徑呼叫。）

Helper 的行為（見 DP-028 D2 — Resolve 層）：
- 若 task.md 的 `Base branch`（即上游 task branch）**已 merged** 回 Epic feature branch → 回傳 feature branch 值
- 否則 → 回傳原 `Base branch` 字面值

task.md 若含 `Branch chain`，engineering 在 first-cut branch setup / revision R0 會先跑 cascade rebase：

```bash
"${CLAUDE_PROJECT_DIR}/scripts/cascade-rebase-chain.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --task-md "<path/to/task.md>"
```

`Branch chain` 只表達 rebase 順序（例：`develop -> feat/EPIC-478-... -> task/TASK-3711-... -> task/TASK-3900-...`）。PR base 仍只取 `resolve-task-base.sh` 的輸出，避免 `Base branch` / `PR base` 雙欄位同步問題。

**應用位置**（engineering SKILL.md 四處必呼叫 resolve helper）：

| 位置 | 目的 | 呼叫時機 |
|------|------|---------|
| § 4.5 Pre-Development Rebase | `Branch chain` cascade rebase；再以 `git rebase origin/<RESOLVED_BASE>` 的 target 切 / 對齊 task branch | first-cut 開工前 |
| § R0 Pre-Revision Rebase（步驟 1-3） | `Branch chain` cascade rebase；再以 `git rebase origin/<RESOLVED_BASE>` 的 target 對齊 PR branch | revision mode 進入後，讀施工圖前 |
| § R0 Pre-Revision Rebase（步驟 4） | `gh pr edit <PR> --base <RESOLVED_BASE>` 同步 PR base 欄位（若 PR baseRefName 不符） | 同上，rebase 成功後、讀施工圖前 |
| § Step 7d (本 flow) | `gh pr create --base <RESOLVED_BASE>` 的 `--base` 值 | 建新 PR 時（first-cut） |

**跨 LLM enforcement（DP-032 Wave δ）**：工程品質 gates 已從 Claude Code PreToolUse hooks 遷移至 portable 機制：
- `scripts/gates/gate-base-check.sh` — git pre-push + `polaris-pr-create.sh` wrapper 擋 `--base` 不符 resolve 結果
- `scripts/gates/gate-evidence.sh` — git pre-push / PR wrapper adapter；委派 `check-verification-passed.sh` 處理 shared `verification_passed` authority，必要時再補 Layer D behavior evidence
- `scripts/gates/gate-ci-local.sh` — git pre-commit + pre-push 擋 CI 未過
- `scripts/polaris-pr-create.sh` — 取代裸 `gh pr create`，內嵌三道 gate
跳過 resolve helper 在 Step 7d 或 R0 步驟 4 都會被 wrapper / git hook block。

---

## Step 8 — JIRA Transition（Developer only）

PR 建立後，轉 JIRA ticket 狀態為 `CODE REVIEW`：

```bash
{workspace_root}/scripts/polaris-jira-transition.sh {TICKET} code_review
```

`polaris-jira-transition.sh`（D25，DP-032 Wave α）統一所有 JIRA transition 呼叫，跨 LLM runtime 共用：built-in slug map（`code_review` → "Code Review"），workspace-config `jira.transitions.code_review` 可覆寫；ticket 已在目標狀態 / 找不到 transition / 沒 creds / API error 一律 stderr 訊息 + exit 0，不阻擋 delivery flow。

**Admin 模式跳過本 step**（無 ticket）。

### 8a. Finalize Delivery（Developer only）

PR 建立成功或 revision mode 既有 PR branch push 完成後，在任何 user-facing completion report 之前，呼叫 finalize helper。此 helper 會先跑 Completion Gate，PASS 後才將對應的 task.md frontmatter 標為 `status: IMPLEMENTED`，並清理對應的 implementation worktree；docs-manager 會直接讀取 canonical specs status：

```bash
bash "${POLARIS_ROOT}/scripts/finalize-engineering-delivery.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --ticket "<TICKET_OR_DP_TASK_ID>" \
  --workspace "<workspace_root>"
```

Helper contract：
- Finalize 前必須先產生 task-bound verify report：
  `bash "${POLARIS_ROOT}/scripts/write-task-verify-report.sh" --repo <repo> --ticket <ticket> --task-md <task.md> --head-sha <deliverable_head_sha>`；
  這份 `verify-report.md` 是 local board / reviewer 可讀佐證，缺失或 head 不符時 completion gate 會阻擋
- 先呼叫 `check-delivery-completion.sh --repo <repo> --ticket <ticket>`；失敗則 **不改 task.md lifecycle**
- completion gate PASS 後，Developer finalize helper 必須先通過 `check-release-eligible.sh`
- Developer deliverable PR 必須由 completion gate 讀 remote PR metadata/body，且通過 PR readiness：`state=OPEN`、`isDraft=false`、remote body 保留 repo template headings
- Completion Gate PASS 後呼叫 `mark-spec-implemented.sh <ticket> --status IMPLEMENTED --workspace <workspace_root>`
- 最後驗證 resolved task path 位於 `tasks/pr-release/`，且 frontmatter `status: IMPLEMENTED`
- 呼叫 `engineering-clean-worktree.sh --task-md <resolved pr-release task.md> --repo <repo>`；若沒有對應 implementation worktree，helper 合法 no-op
- cleanup / parent closeout 後，Developer finalize helper 必須再通過 `check-release-completed.sh`；terminal gate 只接受 move-first closeout、`status: IMPLEMENTED`、registered implementation worktree 已清除的 task

`mark-spec-implemented.sh` 會自動找 Task-level anchor（T{n}/V{n} key 或 `> JIRA: {TICKET}` header 比對）→ **move-first 順序**（DP-033 D6）：
  1. `mv tasks/{T}.md → tasks/pr-release/{T}.md`（先搬，永遠不會在 active `tasks/` 內寫 IMPLEMENTED）
  2. 在 `tasks/pr-release/{T}.md` 更新 frontmatter `status: IMPLEMENTED`
- `tasks/pr-release/` 若不存在自動建立
- Idempotent — 已在 pr-release/ 且已標過相同 status 不做事
- 同 key 衝突（active 與 pr-release/ 並存且內容不同）→ exit 2，須人工解決

失敗 = **HALT**，不得回報「完成 / 可交付 / 已驗完」。這避免 PR 已推、Completion Gate 已過，但 task lifecycle 忘記 move 到 `pr-release/` 或 worktree closeout 被漏掉。

**Admin 模式跳過本 step**（無 ticket / task.md）。

---
