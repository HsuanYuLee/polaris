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
| `## Required Tools` | Optional | DP-194 | `validate-task-md.sh`（若存在，驗證 table 欄位與 ticket-scoped `goes_to_mise=false`） |
| `## Scope Trace Matrix` | **Breakdown readiness Hard** | DP-112 | `validate-breakdown-ready.sh`（章節存在 + goal/AC → owning files → surface/boundary → tests；owning files 必須被 Allowed Files 覆蓋） |
| `## 估點理由` | **Hard** | DP-025 | `validate-task-md.sh`（章節存在 + 非空 body） |
| `## 測試計畫（code-level）` | **Soft** | DP-025 | `validate-task-md.sh`（章節存在；內容不檢） |
| `## Test Command` | **Hard** | DP-005 / DP-025 | `validate-task-md.sh`（章節存在 + 含 fenced code block） |
| `## Test Environment` | **Hard** | DP-023 | `validate-task-md.sh`（章節存在 + Level enum + Runtime contract — 見 § 3.3） |
| `## Gate Closure Matrix` | **Breakdown readiness Hard** | DP-082 | `validate-breakdown-ready.sh`（章節存在 + scope/test/verify/ci-local + pass condition + owner/decision） |
| `## Verify Command` | **Hard**（`Level≠static` 時） | DP-023 | `validate-task-md.sh`（章節存在 + 含 fenced code block + Level=runtime 時 host alignment） |

### 3.1a Frontmatter `task_shape`（implementation default — DP-262）

Implementation task（`task_kind: T`）的 frontmatter `task_shape` 欄位語意與 common schema
（見 `task-md-schema-common.md` § 2.1）一致，這裡只補 T-task-specific 慣例：

- **Default = `implementation`**：T task 絕大多數會改 code / scripts / skills，因此缺
  `task_shape` 欄位時 reader 一律當 `implementation`。breakdown 從
  `refinement.json planned_tasks[].task_shape` 機械寫入；planned task 未宣告時 task.md
  省略此欄位，行為與本 DP 之前的既有 task.md 完全相同（零 migration shim）。
- **`audit` / `confirmation` 為 carve-out shape**：當 T task 的交付物只稽核（`audit`）或
  只確認既有狀態（`confirmation`）、不需要產出 tracked code diff 時才宣告。此時
  `validate-breakdown-ready.sh` 接受 specs-only 或 empty `## Allowed Files`，
  `check-delivery-completion.sh` 以 completion-gate marker(status=PASS)+evidence artifact
  path 完成、不要求 non-draft PR，auto-pass terminal required-PR set 也排除此 task。
- **與 `task_kind` 正交**：`task_shape` 描述「交付形狀」，`task_kind`（T/V）描述
  completion-gate dispatcher 走 implementation 還是 verification 路徑；兩者獨立，不得互相
  覆寫。`task_shape` 對 V task 不生效（V task 既有路徑不 regress）。
- **單一欄位、單一 enum 認定點**：三個 consumer（`validate-breakdown-ready` /
  `check-delivery-completion` / auto-pass terminal）讀同一個 frontmatter 欄位，enum 合法性
  集中在 `validate-task-md.sh`（非 enum 值如 `confirmaton` 直接 reject，不 silently
  default）；沒有第二套 classifier，preflight 亦複用 `validate-breakdown-ready` 本體。

### 3.2 `## Operational Context` table cells

必填 cells（每個 cell 名稱在 markdown table 第一欄；validator 要求字面比對命中）：

| Cell | 內容 | Required |
|------|------|----------|
| `Source type` | Canonical source type：`jira` / `dp` / `bug` | **Hard in canonical identity** |
| `Source ID` | Parent source/container：product Epic key（如 `EPIC-478`）、DP id（如 `DP-050`）或 Bug key（如 `BUG-123`） | **Hard in canonical identity** |
| `Task ID` | Canonical `work_item_id`：product task JIRA key 或 source pseudo ID（如 `DP-050-T1` / `DP-050-V1` / `BUG-123-T1`） | **Hard in canonical identity** |
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

Canonical Bug source task example:

```markdown
> Source: BUG-123 | Task: BUG-123-T1 | JIRA: N/A | Repo: exampleco-b2c-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | bug |
| Source ID | BUG-123 |
| Task ID | BUG-123-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - per-task self-contained |
| AC 驗收單 | N/A - per-task self-contained |
| Base branch | main |
| Branch chain | main -> task/BUG-123-T1-root-cause-fix |
| Task branch | task/BUG-123-T1-root-cause-fix |
| Depends on | N/A |
| References to load | - `companies/exampleco/BUG-123/refinement.json` |
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
| `Env bootstrap command` | **Hard** | `N/A` | `N/A` or shell command | shell command（必填） |

**Runtime cross-field rules**（`Level=runtime` 時）：

1. `Runtime verify target` 必須是 http/https URL（不可為 `N/A` / 空）
2. `Env bootstrap command` 必須非 `N/A`
3. `## Verify Command` fenced block 內必須出現 http/https URL
4. Verify Command URL 的 host **必須等於** Runtime verify target 的 host（DP-023 D2 Target-first）
5. docs-manager runtime task 必須把 `Runtime verify target` 和 Verify Command URL 寫到 `/docs-manager/` app path；bare origin（例如 `http://127.0.0.1:8080`）會被視為 invalid。若未來其他 app 有不同 base path，必須放在可測 contract/registry，不可只寫 prose。
6. `Fixtures` 若非 `N/A`，path 必須存在（resolve 順序：epic_dir → company_base_dir → workspace_root）

**Static 規則**：`Runtime verify target` / `Env bootstrap command` 預期 = `N/A`；若非 N/A → fail（避免假性宣告）。

**Build 規則**：`Runtime verify target` 預期 = `N/A`；`Env bootstrap command` 可為 `N/A` 或
install/build setup command。若 `Test Command` 執行 test/build runner，breakdown readiness
gate 會要求非 `N/A` bootstrap，避免把 repo dependency setup 留給 engineering 猜測。

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

### 3.4a `## Required Tools`（optional，DP-194）

當 task 需要 framework root toolchain 之外的 CLI / package / local binary 才能執行
Test Command 或 Verify Command 時，breakdown 可寫 `## Required Tools`。這是
planning-to-engineering handoff，不是 root `mise.toml` 變更授權。

格式為 markdown table：

```markdown
## Required Tools

| name | owner | install_authority | check_command | install_command | runtime_profile | goes_to_mise | handoff_hint |
|------|-------|-------------------|---------------|-----------------|-----------------|--------------|--------------|
| mockoon-cli | ticket | workspace_dependency_consent | mockoon-cli --version | N/A | ticket | false | Run dependency consent/install before Verify Command. |
```

欄位 contract：

| Field | Required | Allowed values / rule |
|-------|----------|-----------------------|
| `name` | yes | tool / package / binary 名稱 |
| `owner` | yes | `framework` / `delivery` / `project` / `ticket` / `user` |
| `install_authority` | yes | `root_mise` / `system` / `project_package_manager` / `workspace_dependency_consent` / `manual_user_action` |
| `check_command` | yes | engineering setup 可執行的檢查命令 |
| `install_command` | optional | 明確 install command；沒有時可填 `N/A` |
| `runtime_profile` | yes | `core` / `runtime` / `delivery` / `ticket` |
| `goes_to_mise` | yes | `true` / `false`；`owner=ticket` 或 `runtime_profile=ticket` 時必須為 `false` |
| `handoff_hint` | yes | 缺工具時的 install / `BLOCKED_ENV` guidance |

Validator 只在 section 存在時驗證表格。沒有工單級工具需求時，section 可省略。

### 3.5 `## Scope Trace Matrix`

`## Scope Trace Matrix` 是 breakdown readiness 欄位，用來證明每個可觀測目標或 AC
都有明確 owning files、render/API 或系統邊界，以及測試。它補足 `Allowed Files`
只能描述可改檔案、但不能證明 scope 完整性的缺口。

最低格式：

```markdown
## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| release closeout records verification evidence | `scripts/framework-release-closeout.sh`, `scripts/check-release-completed.sh` | framework release completion gate | `bash scripts/framework-release-closeout-selftest.sh` |
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

Deterministic script task 必須在 `## Test Command`、`## Verify Command` 或 Scope Trace Matrix 寫出 script test contract。高風險 script behavior / dependency / selected suite / bootstrap / doctor / release preflight / lifecycle gate 變更，要標明哪個 failing selftest 先失敗、implementation 後通過。text-only、comment-only、typo、help output 等 trivial change 可以註明不新增 failing selftest 的理由。

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

若 project 的 Nuxt/Vitest runner 已知會受 caller shell debug env 影響，`Test Command`
必須在 command 入口清掉 inherited debug env（例如 `env -u DEBUG ...`），不要把
app-level runtime/config workaround 包進產品 task。

Producer 不得把 clean base 已知會失敗的 repo-wide / app-wide command 寫成 READY
task 的唯一 hard `Test Command`。若解析到的 workspace/project default test command 在
resolved base 已因 unrelated baseline issue 失敗，breakdown 必須改用 task-owned targeted
test command，或把 baseline/env decision 明確記錄為 blocker / fallback；不可把 clean-base
紅燈交給 engineering 到 delivery 階段才發現。

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
