---
title: "Breakdown DP Intake Flow"
description: "breakdown DP-backed intake：消費 locked DP refinement artifact，產出 DP task work orders，不寫 JIRA。"
---

# DP Intake Flow

## Resolve DP Source

依 `spec-source-resolver.md` 定位唯一 DP folder：

```text
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/index.md
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/plan.md (legacy)
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.json
```

Hard rules：

- `DP-NNN` 必須唯一 match。
- primary DP document 必須存在；`index.md` 優先，legacy `plan.md` fallback。
- primary DP document frontmatter `status` 必須是 `LOCKED`。
- `status: DISCUSSION` 時停止，提示先跑 `refinement DP-NNN`。
- 新 DP 缺 `refinement.json` 時停止並 route back to refinement；legacy DP 只有在使用者
  明確確認後才允許 minimal intake，preview 必須標示 artifact 缺失。

## Read Without Rewriting Decisions

讀 primary DP document 的 Goal / Decisions / Blind Spots / Acceptance Criteria / Technical
Approach，以及 `refinement.json` 的 source / modules / dependencies / edge cases /
acceptance criteria / downstream breakdown hints / handoff advisories。

Ownership：

- refinement owns Goal / Background / Decisions / Blind Spots / AC / Technical Approach。
- breakdown owns Implementation Checklist finalization、Work Orders / Task Mapping、
  `tasks/T{n}.md`。

Decisions 或 Technical Approach 不足時，不補寫；route back to refinement。

## Consume Handoff Advisories

`refinement.json.handoff_advisories[]` 是 breakdown 唯一可讀的 advisory handoff surface。
breakdown 不得解析 handoff gate stderr、agent final answer、對話紀錄、或
`refinement.md` derived view 來補 task scope 或判斷 advisory disposition；那些 surface 只供
人讀 review，不是機器契約。

當 `handoff_advisories[]` 缺席或為空，視為沒有 registered advisory 需要處置。當陣列存在時，
breakdown 必須依每筆 `disposition` 處理：

- `pending`：不可 handoff engineering；先 route back to refinement / amendment，或要求上游
  把 advisory 明確吸收到 task、waive，或標記 route-back。
- `absorbed_by_task`：只有 `task_ids[]` 指向同一 `refinement.json.tasks[]` 內既有 task，且該
  task 會被本次 breakdown 打包成 task.md 時，才可視為 advisory 已由 task scope 吸收。若
  `task_ids[]` 缺失、指到不存在 task、或指到非本輪 task，停止並 route back to refinement。
- `waived`：只有在 advisory 保留非空 `reason` 時才可放行；breakdown 不得用口頭說明或 final
  answer 補 waiver reason。
- `route_back_refinement`：停止打包對應 handoff，回 refinement amendment / route-back；breakdown
  不得自行從 stderr 或散文推導替代 task scope。

如果 advisory 的 `disposition` 或必填欄位不符合
`refinement-artifact.md` 的 schema，先修 refinement artifact；不得在 breakdown 產出的
task.md 補救缺失。

## Split Work Orders

依 `breakdown-planning-flow.md` 的拆解與 constructability 原則產 preview，但輸出是
DP-backed tasks，不是 JIRA sub-tasks。新產物預設 folder-native：

```text
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/tasks/T1/index.md
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/tasks/T2/index.md
```

Task identity 使用 `DP-NNN-T1`；branch 使用 `task/DP-NNN-T1-{slug}`。

Task schema 依 `task-md-schema.md` implementation schema：

- `Task JIRA key` = pseudo-task ID。
- `Parent Epic` = source DP。
- `Test sub-tasks` = `N/A - framework work order`。
- `AC 驗收單` = `N/A - framework work order`。

DP / Epic source template 必須已收斂到 shared contract
`refinement-source-template.md`。若 source 缺 framework canonical sections、
`refinement.json acceptance_criteria[]`、或 `downstream.breakdown_hints[]`，breakdown 不得
用 markdown prose 補洞，必須 route back to refinement。

Framework-owned DP source 若會進 `framework-release`，breakdown 必須先以
`scripts/resolve-handbook.sh --project polaris-framework` 取得 canonical handbook payload，
在 codebase exploration / task packaging 前讀 `index_path`、從 `narrative_paths` 取得
`changeset-convention.md` 與 `release-topology.md`，並呼叫
`scripts/validate-handbook-load-gate.sh` 建立 session/repo marker。changeset 是 repo-native
policy，不把 exact filename 或格式步驟注入 task。task 排序與 Branch chain 要反映真實
implementation order 與預期 stack base；不要為了滿足 stack 外觀新增 fake semantic
dependency，也不要新增 generic validator 取代 `framework-release` lane 的 hard gate。

DP-backed work 若要驗證 framework 自身開發鏈，必須另外產出 V*.md dogfood verification
work order。T*.md 實作 task 不可把「驗收 DP 自身」塞進 engineering 完成宣告；V*.md PASS
前 parent closeout/archive 必須被 deterministic gate 擋住。

DP-backed split hard rules：

- `engineering` 只接 releaseable tracked work。Allowed Files 至少要有一個 tracked
  non-spec path，不能全部落在 `docs-manager/src/content/docs/specs/**` 這類 local sample /
  ignored artifact surface。
- local sample consumption、sample recut proof、或 docs-manager canonical spec
  調整，若目的只是驗證新 contract 被下游 consume，必須留在 DP / refinement / breakdown
  artifact，或作為 release 後 follow-up；不可偽裝成 engineering implementation task。
- 不得把 tracked framework release work 和 sample/local artifact recut 包進同一張 DP task。
  需要兩者時，先切出 releaseable task；sample follow-up 在 release 後另行處理。

## Confirmation And Writes

Preview 必須包含 summary / points / allowed files / depends_on chain / source DP path /
artifact gap / route-back issue。使用者確認前不可寫 task.md、不可更新 DP plan。

### Auto-pass Ledger Consent

當 DP intake 是由 `auto-pass` dispatch 時，breakdown 可以用 ledger artifact 作為本 source
內重新評估、重新拆分與 task repair 的 confirmation。dispatch envelope 必須包含：

```text
AUTO_PASS_LEDGER_PATH=/absolute/path/to/ledger.json
```

breakdown 寫入任何 task.md 前必須執行 ledger validator；`--task-write-at` 使用實際即將寫入的
timestamp，必須晚於 ledger `started_at` 或最近一次 `resumed_at`：

```bash
bash scripts/validate-auto-pass-ledger.sh "$AUTO_PASS_LEDGER_PATH" \
  --source-container "{dp_folder_absolute_path}" \
  --source-id "DP-NNN" \
  --task-write-at "{task_write_iso8601}"
```

fail-stop 條件：

- `AUTO_PASS_LEDGER_PATH` 缺失或不是絕對路徑。
- ledger schema invalid。
- ledger `source.id` / `source.container` 與本 DP source 不一致。
- `consent_policy.auto_reestimate`、`auto_resplit`、`auto_task_repair` 任一不是 `true`。
- `consent_excludes` 不是 canonical enum 全集。
- task write timestamp 早於 ledger `started_at` / `resumed_at`。

以上任一失敗都視為缺 confirmation；breakdown 不得寫 task.md、不得更新 DP plan，也不得把
conversation memory 當成 consent。

確認後：

```bash
scripts/validate-task-md.sh {dp_folder}/tasks/T{n}/index.md
scripts/validate-task-md-deps.sh {dp_folder}/tasks/
scripts/validate-breakdown-ready.sh {dp_folder}/tasks/T{n}/index.md
```

全部 pass 後，更新 primary DP document Implementation Checklist / Work Orders linkage。
Validator fail 時修 artifact，不 handoff engineering。

Handoff engineering 前執行 main-chain compliance：

```bash
bash scripts/check-main-chain-compliance.sh \
  --source-container {dp_folder} \
  --allow-active-verification
```

若 `validate-breakdown-ready.sh` 因「DP task 只觸及 local spec/sample artifacts」失敗，
這不是 engineering 要接的 implementation lane；必須回到 breakdown 重新分流。

## DP-201 Proof Markers

breakdown 擁有下列 proof-of-work 輸出：

- `task_snapshot`：從 locked DP / refinement artifact 打包出的 task set durable summary。
- `validation_fail`：已有具體 work item 後，packaging validation 失敗時寫入 `.polaris/evidence/validation-fail/{work_item_id}.json`。
- `missing_v_task`：DP-backed source 需要驗收但無法產出 V task 時的 durable marker。
- `route_back_refinement_inbox`：以 `refinement-inbox/` folder presence 作為 canonical signal；除非未來 validator 證明 folder presence 不足，否則不要新增 duplicate route-back marker。

所有 JSON marker 必須遵守 `auto-pass-proof-of-work.md` 與
`scripts/lib/evidence-producers.json`。`auto-pass` 只能讀取，不是 writer。

Handoff 提示：

```text
做 DP-NNN-T1
```
