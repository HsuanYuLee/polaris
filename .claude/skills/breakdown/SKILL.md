---
name: breakdown
description: "Universal planning skill: Bug reads ROOT_CAUSE then estimates; Story/Task/Epic explores codebase then splits into sub-tasks with estimates, and packs each sub-task into a self-contained task.md work order for engineering to consume. Also handles scope challenge (advisory mode). Trigger: 拆單, 'split tasks', 拆解, 'breakdown', 'break down', 子單, 'sub-tasks', 評估這張單, 'evaluate this ticket', 估點, 'estimate', 'scope challenge', '挑戰需求', 'challenge scope', '需求質疑'."
metadata:
  author: Polaris
  version: 3.3.0
---

# Breakdown — Packer

`breakdown` 是 Packer：接收 refinement artifact、bug-triage RCA、JIRA ticket 或
DP source，把已定案的需求拆成可施工 work orders。它不擁有需求探索或技術決策；需要
改 Goal / Background / Decisions / Blind Spots / Technical Approach 時，route back
to `refinement`。

## Mandatory Contracts

- 開始前讀 `workspace-config-reader.md`、`workspace-language-policy.md`、
  `authoring-preflight.md` 與 root `language`；preview、JIRA comment、task.md / V*.md
  artifact 必須直接用 policy language 起稿，不可把 language gate 當送出前翻譯器。
- 寫 artifact 前必讀 `pipeline-handoff.md` § Artifact Schemas，再讀
  `refinement-artifact.md` / `task-md-schema.md` 等對應 artifact-specific schema。
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

## Initial-Create Task.md Writer (DP-226)

新建 `tasks/T*/index.md` 或 `tasks/V*/index.md` 時，breakdown 必須走 deterministic
producer writer，不再依賴 Claude `Write` / `Edit` / `MultiEdit` tool 的 per-call
env 或 Bash heredoc workaround：

```bash
bash scripts/write-producer-owned-artifact.sh \
  --producer-token breakdown:initial-create \
  --path /absolute/path/to/tasks/T{n}/index.md \
  --body-file /absolute/path/to/staged-task-body.md
```

語意：

- `breakdown:initial-create` token 只覆蓋 **首次建立** 的 task.md；既有 task.md 的後續
  編修（status flip、jira_transition_log 補寫等）沿用原來的 `dp-task-status-writer`
  flow，不注入此 token。
- writer 內部做 token-first lookup（即使 overlapping path globs 包含 `tasks/**/index.md`，
  token 也會解析到 initial-create entry），並以 `validate-task-md.sh` 驗證寫入內容；
  validator fail 時 rollback 任何既有內容，不留下 invalid artifact。
- staged body 由 breakdown 在 mktemp 路徑下準備好（含 frontmatter、required sections、
  Allowed Files、改動範圍、Verify Command 等），writer 不產生 body，只負責 token+glob
  enforcement 與 atomic write。
- `POLARIS_PRODUCER` env 仍只由 deterministic 觸發路徑（producer script 內部）使用，
  不得透過 Claude tool per-call env 模擬 producer。

## Shared Fail-Stops

- 每種 source 在 work-order packaging 前都必須有對應的 planning handoff：
  refinement-owned DP / Epic / Story / Task 需要 current `refinement.json`；Bug 需要
  `bug-triage` confirmed `[ROOT_CAUSE]` handoff。
- Bug ticket 沒有 `[ROOT_CAUSE]` comment：停止，請使用者先跑 `bug-triage {TICKET}`。
- DP `status: DISCUSSION` 或缺 `refinement.json`：停止並 route back to
  `refinement DP-NNN`。
- Escalation sidecar 缺 gate-closure sections：停止，要求 engineering 重建 sidecar。
- Quality Challenge / Constructability Gate 失敗：不得建 JIRA sub-task、不得產 task.md。
- `validate-task-md.sh` 或 `validate-task-md-deps.sh` 失敗：修 artifact，不得 handoff
  engineering。
- DP-backed task 若混合「tracked releaseable framework work」與「local sample/spec recut」，
  或 Allowed Files 全落在 ignored local artifact surface：停止，回 planning 重拆，不得
  handoff engineering / framework-release。
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

## L2 Deterministic Check: post-task-feedback-reflection

完成 write flow 後必須呼叫 `scripts/check-feedback-signals.sh`。

## Post-Task Reflection (required)

見 `post-task-reflection-checkpoint.md`；write 後必跑、不可跳過。
