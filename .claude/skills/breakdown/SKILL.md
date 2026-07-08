---
name: breakdown
description: "Universal planning skill: Bug reads ROOT_CAUSE then estimates; Story/Task/Epic explores codebase then splits into sub-tasks with estimates, and packs each sub-task into a self-contained task.md work order for engineering to consume. Also handles scope challenge (advisory mode). Trigger: 拆單, 'split tasks', 拆解, 'breakdown', 'break down', 子單, 'sub-tasks', 評估這張單, 'evaluate this ticket', 估點, 'estimate', 'scope challenge', '挑戰需求', 'challenge scope', '需求質疑'."
metadata:
  author: Polaris
  version: 3.3.0
---

# Breakdown — Packer

`breakdown` 是 Packer：接收 refinement artifact、refinement Bug source mode RCA、JIRA ticket 或
DP source，把已定案的需求拆成可施工 work orders。它不擁有需求探索或技術決策；需要
改 Goal / Background / Decisions / Blind Spots / Technical Approach 時，route back
to `refinement`。

## Mandatory Contracts

- 開始前讀 `workspace-config-reader.md`、`workspace-language-policy.md`、
  `authoring-preflight.md` 與 root `language`；preview、JIRA comment、task.md / V*.md
  artifact 必須直接用 policy language 起稿，不可把 language gate 當送出前翻譯器。
- 寫 artifact 前必讀 `pipeline-handoff.md` § Artifact Schemas，再讀
  `refinement-artifact.md` / `task-md-schema.md` 等對應 artifact-specific schema。breakdown
  是唯一直接消費 `refinement.json` derive work order 的 owner；atom ownership 邊界以
  `pipeline-handoff-atom-matrix.md` 為準，SKILL 主文不複製完整 schema 表。
- 寫入 specs Markdown 時遵守 `starlight-authoring-contract.md`；task work order
  寫入 folder-native `tasks/Tn/index.md` 或 `tasks/Vn/index.md`；task schema 以
  `task-md-schema.md` 為準。
- 所有 estimate 使用 `estimation-scale.md`；JIRA sub-task / story point 操作使用
  `jira-subtask-creation.md` 與 `jira-story-points.md`。
- 寫入 task.md 前必須有 explicit user confirmation；沒有確認不可寫 JIRA、branch、
  task.md、sidecar processed flag。
- DP-backed source 若由 `auto-pass` dispatch，explicit confirmation 可由
  `AUTO_PASS_LEDGER_PATH=<absolute ledger path>` envelope token 提供，但 breakdown 必須先用
  `scripts/validate-auto-pass-ledger.sh` 驗證 schema、source match、三個 consent boolean、
  canonical `consent_excludes` enum 與 task write timestamp ordering。缺 token、relative path、
  source mismatch、invalid schema 或 task write 早於 ledger start/resume 都等同缺 confirmation，
  不得寫 task.md。
- task.md 必須能被 `engineering` 單獨消費：Allowed Files、Gate Closure Matrix、
  Behavior Contract、Test Environment、Verify Command 都要完整。
- refinement / ticket handoff 若宣告 `tool_requirements[]`，必須包成 task.md
  `## Required Tools` table。ticket-scoped 工具只能透過 task.md 提醒 engineering 檢查或安裝；
  不得把單一工單工具需求升級成 root `mise.toml` 需求。
- 若 task 修改 Polaris deterministic script behavior、release gate、bootstrap/doctor、
  dependency governance 或 selected suite，task.md 必須寫出 script test contract；
  高風險行為變更優先包進 failing selftest → implementation → passing selftest。
  text-only / trivial 文件或 help 文案變更可註明不需新增 failing selftest。
- Story / Task / Epic 拆單前讀 `infra-first-decision.md`；infra prerequisite 只能由
  refinement artifact 的 AC verification methods 推導，不得只因 visual regression config
  存在就加入 fixture task。
- Story / Task / Epic 拆單與 DP-backed task preview 前讀
  `stacked-delivery-sibling-epic-policy.md`；建立 task.md / JIRA child 前必須用
  `scripts/detect-stacked-delivery-lane.mjs` 檢查 draft task set。若結果是 `required`，
  使用者確認 sibling Epic strategy 或 explicit override 前不得寫 task.md、不得寫 JIRA、
  不得建 branch。
- DP-backed work 沒有特殊 execution shortcut。只要 task.md 要 handoff `engineering`，
  就必須沿用與 Epic 相同的正規鏈；`framework-release` 只能作為 engineering PR 之後的
  local extension tail，不得提前取代 `engineering`。
- DP task 若只觸及 local sample / ignored specs artifacts（例如 Allowed Files 全在
  `docs-manager/src/content/docs/specs/**`），不得包成 implementation task handoff
  engineering；必須留在 refinement / breakdown artifact，或另拆真正的 tracked
  releaseable task。
- DP reset / redo / backfill 時，若 implementation task 的非 `.changeset/*.md` scope
  已被 base/current checkout 吸收，且該 task verify command 在該 checkout PASS，該 task
  不得再包成 task-bound implementation work order；必須標成 absorbed/backfilled、
  移出 refreshed task set，或 route back refinement 記錄 disposition。補一張只有
  `.changeset/*.md` 的 task PR 不是合法 delivery。
- 任何 sub-agent dispatch 前讀 `sub-agent-roles.md` 並注入 Completion Envelope；Codex
  runtime / model fallback contract 見該 reference § Runtime Adapter Contract /
  Fallback Behavior。
- 完成任何 write 後最後跑 Post-Task Reflection。

## Task Splitting Heuristic — Reviewable PR Boundary

Phase 2 / DP refinement 寫 Work Orders 前，對每張 candidate task 問三題：

1. 這張 task 有獨立的 producer 程式碼或 helper script 嗎？
2. 如果沒有，Allowed Files 是否 ≥ ~5 個且 ≥ ~100 行？
3. 切出來後，是否有獨立 review value（reviewer 看完能單獨判斷 PASS）？

三題全部 No 表示這張 task 是 **contract registration micro-task**（純 reference doc 加段
落 + SKILL.md 加 3 行 + 補 selftest fixture，沒有獨立 producer code），必須合併進它最自然
的父 task（通常是同層 schema/validator task）。

多個 owning skill 各自登錄同一 contract 時，**不需要每個 skill 切一張 task**；合併進
contract 主 task，Allowed Files 一次涵蓋多個 SKILL.md / reference doc。

例外：某 owning skill 的 producer 確實有獨立 helper script（如 `run-verify-command.sh`
等級的 writer），該 skill 可獨立切 task。

Rule of thumb：

- 3pt 以下 + 純文件登錄 → bundle
- 3pt 以上 + 含 helper script / hook / validator → 可獨立

Why：缺乏 producer code 等於沒有獨立 PR boundary。engineering 會把多張 micro-task 合併進
一顆 PR（DP-201 原 plan 切 T2/T3/T4 共 13pt 結果全併入 PR #343 commit a4763f6），導致
plan ↔ delivery 永久脫鉤，必須 reopen refinement 壓縮 task 結構。

## Bundle PR Identity (DP-230 D16)

當 framework-release 把多個 task 合進單一 aggregate-release PR 時，bundle 的
branch / worktree / PR identity 由 `--source DP-NNN` 與 `--version vX.Y.Z` 決定，
不再從任一 task summary slug 推導。breakdown 在拆 task 時要記得：

- aggregate-release branch name 一律是 `bundle-DP-NNN-vX.Y.Z`，由
  `scripts/engineering-branch-setup.sh --aggregate-release --source DP-NNN
  --version vX.Y.Z --task-md <path> [--task-md <path> ...]` 建立。
- 該 helper 會把 `bundle_branch_alias: bundle-DP-NNN-vX.Y.Z` 寫進每張 task.md
  frontmatter；breakdown 不需要手寫這個欄位，但要避免在 task.md 留下會跟
  bundle alias 衝突的 per-task release branch 設計。
- framework-release-closeout 透過 `--task-head-sha DP-NNN-T1=<sha1>,DP-NNN-T2=<sha2>`
  map syntax 對每張 task 做 per-task closeout；breakdown 拆出來的 task id 必須與
  map key 對齊（folder-native `tasks/Tn/index.md` 已自然滿足）。

## Source Routing

先讀 `spec-source-resolver.md` 判斷 source type，再只讀對應 reference：

| Source / signal | Path | Reference |
|---|---|---|
| Bug ticket | Bug RCA estimate / simple fix or planning handoff | `breakdown-bug-flow.md` |
| Story / Task / Epic ticket | JIRA planning, sub-task creation, task.md packaging | `breakdown-planning-flow.md` |
| `DP-NNN` or locked DP artifact | DP-backed `tasks/T{n}.md` without JIRA writes | `breakdown-dp-intake-flow.md` |
| engineering escalation sidecar | scope-escalation intake and planner decision | `breakdown-escalation-intake-flow.md` |
| `scope challenge` / `挑戰需求` | advisory challenge only, no writes unless user later confirms planning | `breakdown-scope-challenge-flow.md` |
| branch/task packaging details needed | branch DAG, task.md / V*.md validation | `breakdown-task-packaging.md` |

## Producer-Env Writer Rules (DP-226 / DP-228)

`SKILL.md` 本身只是 **documentation pointer**：寫 specs-bound artifact 的實際 writer
authority 來自 producer-env（`POLARIS_SKILL_WRITER` / `POLARIS_PRODUCER`）+ producer
registry（`scripts/lib/evidence-producers.json`），不是 SKILL.md prose 本身。

### Initial-Create Task.md Writer (DP-226 + DP-230-T10)

新建 `tasks/T*/index.md` 或 `tasks/V*/index.md` 時，breakdown 必須走 **deterministic
two-step pipeline**：先由 `derive-task-md-from-refinement-json.sh` 從
`refinement.json` 的 structured `tasks[]` entry 機械產出 staged body，再由
`write-producer-owned-artifact.sh` 用 `breakdown:initial-create` token 寫入。

```bash
# Step 1 — deterministic body derivation (no LLM judgment in pipeline).
bash scripts/derive-task-md-from-refinement-json.sh \
  --refinement-json /absolute/path/to/refinement.json \
  --task-id DP-NNN-Tn \
  > /absolute/path/to/staged-task-body.md

# Step 2 — atomic, token-guarded write.
bash scripts/write-producer-owned-artifact.sh \
  --producer-token breakdown:initial-create \
  --path /absolute/path/to/tasks/T{n}/index.md \
  --body-file /absolute/path/to/staged-task-body.md
```

語意：

- **No LLM-judgment task derivation**：staged body 必須由
  `derive-task-md-from-refinement-json.sh` 機械產生，不可由 breakdown skill session 在主
  對話中手寫 / 拼湊 frontmatter、Allowed Files、Scope Trace Matrix 或 Verify Command。
  derive script 從 refinement.json structured fields（`id`、`title`、`scope`、
  `modules`、`ac_ids`、`verification.detail`）一比一還原 task.md schema 必填欄位；initial-create
  的 `## Allowed Files` 由 matched `tasks[].modules` task intent 產生。`allowed_files` /
  `estimate_points` 仍是 forbidden per-task packaging fields，不得放回 refinement artifact。
  缺欄位即 fail-loud，沒有 LLM fallback 把 gap 填起來。需要新欄位時改 refinement artifact，
  不在 breakdown 層補。
- **`task_shape` propagation（DP-262）**：breakdown 是 task.md frontmatter `task_shape`
  的 **canonical writer**。derive script 從 `refinement.json` 的
  `planned_tasks[].task_shape`（值若存在須為 `implementation` \| `audit` \| `confirmation`）
  一比一寫入對應 task.md frontmatter；`planned_tasks[]` 缺 `task_shape` 或整個欄位不存在
  時，task.md 一律省略 `task_shape`（reader 端 default = `implementation`，見
  `task-md-schema-common.md`）。breakdown 不在主對話中自行推斷或覆寫 `task_shape`——它是
  refinement 階段宣告的 delivery shape，breakdown 只負責機械搬運。下游三個 consumer
  （`validate-breakdown-ready.sh` carve-out、`check-delivery-completion.sh` no-PR
  completion path、auto-pass terminal required-PR set）都讀同一個 frontmatter 欄位，
  enum 認定集中在 `validate-task-md.sh`，breakdown 不重寫第二套 classifier。
- `breakdown:initial-create` token 只覆蓋 **首次建立** 的 task.md；既有 task.md 的後續
  編修（status flip、jira_transition_log 補寫等）沿用原來的 `dp-task-status-writer`
  flow，不注入此 token。
- writer 內部做 token-first lookup（即使 overlapping path globs 包含 `tasks/**/index.md`，
  token 也會解析到 initial-create entry），並以 `validate-task-md.sh` 驗證寫入內容；
  validator fail 時 rollback 任何既有內容，不留下 invalid artifact。
- `POLARIS_PRODUCER` env 仍只由 deterministic 觸發路徑（producer script 內部）使用，
  不得透過 Claude tool per-call env 模擬 producer。
- Pipeline 與 derive contract 由
  `scripts/selftests/derive-task-md-from-refinement-json-selftest.sh` enforce（AC28
  positive, AC-NEG9 fail-loud）。

#### Source-Type Dispatch：dp mode vs jira mode (DP-269)

`derive-task-md-from-refinement-json.sh` 依 `refinement.json` 的 `source.type` 分兩 mode；
這是同一條 initial-create lane 的 **additional contract**，不是 DP-only fast path（JIRA
Epic-backed 與 DP-backed source 對稱，呼應 `canonical-contract-governance.md` § Source
Parity，由 `scripts/validate-spec-source-parity.sh` 在 framework PR gate 保護）：

- **dp mode（`source.type=dp`）**：行為不變。task identity = canonical `DP-NNN-Tn`，
  `Repo` = `polaris-framework`（CLI `--repo` default），`Base branch` = `main`，
  `JIRA key` cell = `N/A`。
- **jira mode（`source.type=jira`）**：derive 從 `refinement.json` 注入產品事實 ——
  task identity = 真實 `tasks[].jira_key`（命中 `validate-task-md.sh`
  `is_valid_task_identity` 的 plain JIRA key 分支），`Repo` = `source.repo`，
  `Base branch` = `source.base_branch`（產品 base branch，如 `develop`），
  `JIRA key` cell = 真實 key（非 N/A）。

`source.repo` / `source.base_branch` / `tasks[].jira_key` 是 jira-only 欄位，由
`refinement` Phase 1/2 populate（base_branch 來源見 `refinement` SKILL.md §
JIRA-Epic-Backed Source Field Population；`base_branch` 從
`{company}/polaris-config/{project}/handbook/config.yaml` 讀取，無對應 entry 時 fail-stop
不硬猜）。`tasks[].jira_key=null` 的 jira task 進 derive 時 fail-closed（要求先 populate
真實 key，無 N/A fallback）；DP-backed source 帶任一 jira-only 欄位由
`validate-refinement-json.sh` fail-closed（`POLARIS_REFINEMENT_JIRA_ONLY_FIELD`，不外洩到
dp 分支）。

### Other breakdown-Owned Writes (DP-228 T10)

breakdown 寫 `refinement-inbox/`、planner-owned `task.md` 後續編修，或其他 breakdown
`owning_skill` entry 對應路徑（見 `scripts/lib/evidence-producers.json`）時，若必須以
Claude `Write` / `Edit` / `MultiEdit` 直接寫入（沒有 deterministic writer script），
**先 `export POLARIS_SKILL_WRITER=breakdown`** 再呼叫 Write tool，讓
`no-direct-evidence-write` hook 通過 owning-skill consent 檢查：

```bash
export POLARIS_SKILL_WRITER=breakdown
# 然後使用 Write tool 寫入路徑屬於 breakdown owning_skill 的檔案
```

- `POLARIS_SKILL_WRITER` 只允許設成本 skill 名（`breakdown`）；hook 會交叉比對寫入路徑是否落在
  registry 的 breakdown owning_skill entry 內，不符即 deny。
- 禁止用 Bash heredoc（`cat > foo.md <<'EOF'`、`tee specs/...`）寫入 specs-bound artifact；
  Bash heredoc 不走 hook 並繞過 producer-env 認證，違反 spec-source single-writer 原則。
- 若同一段流程同時涉及 deterministic writer + Write tool，prefer deterministic writer
  （`write-producer-owned-artifact.sh` + `--producer-token`）。

## Shared Fail-Stops

- 每種 source 在 work-order packaging 前都必須有對應的 planning handoff：
  refinement-owned DP / Epic / Story / Task 需要 current `refinement.json`；Bug 需要
  `refinement Bug source mode` confirmed `[ROOT_CAUSE]` handoff。
- Bug ticket 沒有 `[ROOT_CAUSE]` comment：停止，請使用者先跑 `refinement Bug source mode {TICKET}`。
- DP `status: DISCUSSION` 或缺 `refinement.json`：停止並 route back to
  `refinement DP-NNN`。
- Escalation sidecar 缺 gate-closure sections：停止，要求 engineering 重建 sidecar。
- Quality Challenge / Constructability Gate 失敗：不得建 JIRA sub-task、不得產 task.md。
- `validate-task-md.sh` 或 `validate-task-md-deps.sh` 失敗：修 artifact，不得 handoff
  engineering。
- DP-backed task 若混合「tracked releaseable framework work」與「local sample/spec recut」，
  或 Allowed Files 全落在 ignored local artifact surface：停止，回 planning 重拆，不得
  handoff engineering / framework-release。
- DP reset / redo / backfill 發現 task 已被 base/current 吸收且 verify PASS：停止派工，
  記錄 absorbed/backfilled disposition，或回 refinement 重算 surviving task set；不得用
  changeset-only work order 追認舊 lineage。
- DP-201 proof-of-work marker contract 生效後，breakdown 是 `task_snapshot`、
  `validation_fail`、`missing_v_task` 與 `route_back_refinement_inbox` canonical signal 的
  owning writer。Marker schema、producer mapping 與 freshness rule 以
  `auto-pass-proof-of-work.md` / `scripts/lib/evidence-producers.json` 為準；auto-pass 只能讀取，
  不可代寫 breakdown marker。

## Shared Handoff

- 只有在 `validate-task-md.sh`、`validate-task-md-deps.sh`、`validate-breakdown-ready.sh`
  全部通過後，才可提示 `做 {TASK_KEY}`、`做 {EPIC_KEY}` 或 `做 DP-NNN-T1`。
- Scope escalation 處理後，若 task 已修正或新 task 已建立，回到 `engineering`；若
  lineage cap 或 planner decision 指向 refinement，只建立 refinement inbox record 後提示
  `refinement {EPIC}`。

### Canonical / Standalone Handoff Contract（DP-296 AC6）

breakdown 同時是 consumer 與 producer：consumer 端預設 traverse refinement 的
**canonical** `refinement.json tasks[]` schema 來 derive work order，**不**改去解析
refinement 的 LLM freeform prose 補 scope 缺口；producer 端產出 canonical `task.md`
（`task-md-schema.md` 形狀，含 Allowed Files / Scope Trace Matrix / Verify Command）給
engineering 機械消費。LLM freeform 只在 **standalone** 情境合法——亦即該產出沒有下游
pipeline consumer 會機械消費它（例如對使用者的 task preview prose）。會被下一段 skill
機械消費的 handoff artifact 一律走 canonical schema。本契約只約束 handoff artifact 介面，
**不**約束 breakdown 內部如何拆 task 或推導估點。完整契約見
`.claude/skills/references/pipeline-handoff.md` § Canonical Schema Traversal Contract。

## Skill Workflow Boundary Gate (DP-230 D40)

`breakdown` session 開始時必須呼叫 skill-workflow-boundary baseline writer：

```bash
bash scripts/skill-workflow-boundary-gate.sh --skill breakdown --start \
  --source-container "$SOURCE_CONTAINER"
```

breakdown 完成、handoff `engineering` 前（或在 /auto-pass cross-skill transition
之前）必須跑：

```bash
bash scripts/skill-workflow-boundary-gate.sh --skill breakdown --check \
  --source-container "$SOURCE_CONTAINER"
```

breakdown 的 owning scope 僅限本 source container 的
`tasks/T*/index.md` / `tasks/T*.md` / `tasks/V*/index.md` / `tasks/V*.md` /
`tasks/**` 內 task artifact，以及 `refinement-inbox/**`。任何 owning scope 之外
的新增/修改（refinement.md / refinement.json / code / generated target）會讓
gate exit 1 並輸出 `POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:breakdown`，
breakdown 必須回去把該修改改回 refinement 階段或讓對應 owning skill 處理。

`POLARIS_LANGUAGE_POLICY_BYPASS` / `POLARIS_SKILL_BOUNDARY_BYPASS` 等 env 不能
silence 這個 gate（AC-NEG16）。

## L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`。

## Post-Task Reflection (required)

見 `post-task-reflection-checkpoint.md`；write 後必跑、不可跳過。
