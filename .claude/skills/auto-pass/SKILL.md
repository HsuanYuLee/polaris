---
name: auto-pass
description: >
  Canonical main-chain orchestrator for locked/current DP-backed sources. It
  routes a source through breakdown, engineering, and verify-AC without taking
  over their mutation authority. Trigger: "auto-pass DP-NNN", "快速通關 DP-NNN",
  "完整流程 DP-NNN" when the DP source is LOCKED and artifacts are current.
metadata:
  author: Polaris
  version: 0.1.0
---

# Auto-pass

`auto-pass` 是 locked/current DP-backed source 的主鏈 orchestrator。它的工作是解析
DP source、建立或 resume source-scoped ledger、依序 dispatch `breakdown -> engineering ->
verify-AC`，並在流程抵達 terminal state 時產出 durable report。

它不是施工 skill，也不是 release skill。`auto-pass` 不直接改 code、不直接寫 task.md、
不建立 generic GitHub PR、不判定 AC PASS/FAIL，也不執行 merge、release、deploy 或
production write。

## Source Gate

v1 只接受 DP-backed source：

- `DP-NNN`
- 指向 `docs-manager/src/content/docs/specs/design-plans/DP-NNN-*` container 內的 path

進入 execution 前必須確認：

- 只能解析到唯一 DP container。
- `index.md` frontmatter `status` 是 `LOCKED`。
- `refinement.md` 與 `refinement.json` 存在且 current。
- ledger `source.refinement_hash` 對齊 current refinement artifact。

未 LOCK、缺 artifact、artifact stale、duplicate source 或非 DP-backed source 都不得進入
execution；必須 route 回 owning skill 或 terminal `blocked_by_gate_failure`。

## Ledger Contract

每次 orchestration 必須使用主 checkout 絕對路徑底下的 ledger：

```text
{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-ledger.json
```

ledger schema、consent enum、terminal enum 與 resume 欄位以
`.claude/skills/references/auto-pass-ledger.md` 為準，並由
`scripts/validate-auto-pass-ledger.sh` 驗證。

啟動 `auto-pass` 代表使用者同意本 DP source 內的重新評估、重新拆分與 task repair。這份同意
只能透過 ledger artifact 傳給下游，不可用 conversation memory 代替。

## Dispatch Boundary

`auto-pass` 只 dispatch owning skills：

1. `breakdown` 產生或修正 DP-backed work orders。
2. `engineering` 依 authoritative task.md 施工、驗證並建立 non-draft workspace PR。
3. `verify-AC` 驗收 V work order 並產生 current verification disposition。
4. `refinement`（**amendment mode only**, DP-212）：當 `{source}/refinement-inbox/*.md` 出現
   或 verify-AC 回 `spec_issue` 時，dispatch refinement 消費 inbox、把 implementation detail
   微調寫回 `refinement.md` / `refinement.json`，counter +=1 後 loop 回 breakdown。Amendment
   不向使用者發問、不重做 Phase 0/1/2 discovery、不能改 LOCKED scope（由
   `validate-refinement-locked-scope.sh` 把關）。

inner skill 的 mandatory gates 保持原樣。任何 planner-owned gap、scope escalation、AC spec
issue、consent 外 external write、blocked conflict 或 unknown probe 都必須回到 owning skill 或
明確 pause / blocked；`auto-pass` 不得手動補欄位來通過 gate。

## Execution Loop

execution loop 以最後一次 breakdown PASS snapshot 作為本輪 required PR set：

1. Validate source 與 ledger consent。
2. Dispatch `breakdown`；PASS 後讀 `task_snapshot` marker 並更新 ledger snapshot。
3. 依 task DAG dispatch `engineering`；PR opened / ready 必須由 PR freshness 與 completion
   proof marker 判讀。
4. Dispatch `verify-AC`；verification disposition 必須 current，缺 V task / AC artifact 時回
   breakdown owning scope。
5. 所有 required PR opened / ready 且 verification disposition current 時 terminal `complete`，
   寫 final report，然後執行 terminal complete closeout chain：
   `scripts/mark-spec-implemented.sh {SOURCE_ID} --auto-archive`。

`auto-pass {KEY} resume` 必須先跑 `scripts/validate-auto-pass-resume.sh`，確認 ledger
`pause.kind=session_handoff`、resume artifact 與 source match，並沿用原 ledger 的 counters /
snapshot / drift retry。不得用新 ledger 重置 loop state。

Inner skill HALT 不等於 user decision。若 deterministic marker / validator sidecar 已 PASS，
auto-pass 必須繼續 dispatch；只有 context pressure / runtime pressure 才可寫
`pause.kind=session_handoff` 與 resume artifact。

probe result 只能來自 DP-201 proof-of-work marker、task frontmatter 或 validated ledger。若
`scripts/auto-pass-probe.sh` 無法判讀 outcome，terminal 必須是 `blocked_by_gate_failure`；
不可用 inner skill final answer 或 raw prose 補判斷。

Planning backward transition counter 採 source-level cap：`engineering -> breakdown` 與
`breakdown -> refinement-inbox` 任一 counter 達 3 時 terminal `loop_cap_reached`。
`verify-AC -> engineering` 的 implementation drift retry 另計；同一 V item 連續 3 次仍 FAIL 時
terminal `blocked_by_gate_failure`。

**Amendment loop (DP-212)**：`breakdown_to_refinement_inbox` 在 amendment mode 自動 loop，
不是 hard-stop——每次 inbox 出現 → dispatch refinement amendment → 寫回 refinement artifact
→ counter +=1 → 繼續 dispatch breakdown。只有 counter > 3 才 terminal `loop_cap_reached`。
amendment 若命中 LOCKED scope guard（改到 Goal / Background / Decisions / Scope / AC），
`validate-refinement-locked-scope.sh` exit 2 + 標 inbox `rejected_by_scope_guard=true`，
auto-pass 必須 terminal `blocked_by_gate_failure` 並輸出 follow-up DP seed。

## Breakdown Consent Handoff

dispatch `breakdown` 時，envelope 必須包含主 checkout ledger 絕對路徑：

```text
AUTO_PASS_LEDGER_PATH=/absolute/path/to/ledger.json
```

`breakdown` 必須用 ledger validator 確認 schema、source match、三個 consent boolean、
canonical `consent_excludes` enum 與 timestamp ordering。缺 token、relative path、source
mismatch、invalid schema 或 task write 早於 ledger start/resume 都必須 fail-stop。

## Routing Policy

Full development workflow intent 依 source-state matrix route：

| Trigger | Source state | Route |
|---------|--------------|-------|
| `建 DP` / `建一個 DP` | no DP source | `refinement` |
| `完整流程 DP-NNN` / `快速通關 DP-NNN` | `DISCUSSION` / missing artifact / stale artifact | `refinement DP-NNN` |
| `完整流程 DP-NNN` / `快速通關 DP-NNN` | `LOCKED` + current DP-backed source | `auto-pass DP-NNN` |
| `DP -> PR -> 升版 DP-NNN` | `LOCKED` + current DP-backed source | `auto-pass DP-NNN`；report tail 提示 `framework-release` |
| `framework-release DP-NNN` | workspace PR opened + verification current | `framework-release` |
| `framework-release DP-NNN` | workspace PR opened + verification stale | `auto-pass DP-NNN` refresh verify-AC，不重跑 breakdown |
| `auto-pass DP-NNN resume` | ledger `pause.kind=session_handoff` + valid resume artifact | resume same ledger |

`auto-pass` 只接 locked/current DP-backed source；未 LOCK、artifact stale 或 missing source 的 case
都回 upstream owning skill，不在本 skill 內補 refinement / breakdown artifact。

## Probe Command

T3 起 `auto-pass` 使用 deterministic probe helper：

```bash
bash scripts/auto-pass-probe.sh DP-NNN

bash scripts/auto-pass-probe.sh \
  --repo /absolute/path/to/main-checkout \
  --stage source \
  --source-id DP-NNN

bash scripts/auto-pass-probe.sh \
  --repo /absolute/path/to/main-checkout \
  --stage breakdown \
  --source-id DP-NNN \
  --work-item-id DP-NNN-T1 \
  --ledger /absolute/path/to/ledger.json
```

helper 輸出 JSON，至少包含 `stage`、`status`、`terminal_status`、`next_action` 與
`evidence_path`。`status=UNKNOWN` 一律視為 blocked，不可推測 PASS。

## Friction Log Capture (DP-214)

orchestration 過程中遇到下列訊號時，必須立刻呼叫 helper 把摩擦點寫入 ledger
`friction_log[]`，作為下次 refinement / sprint planning 的 signal source。**不可**只在
口頭報告交代：

- inner skill HALT 後又繼續 dispatch（deterministic marker 已 PASS）。
- 手動補 artifact 欄位才能通過 validator。
- 缺 deterministic gate / helper script，本輪靠人類操作補位。
- 必須 set 環境變數才能跑通某個流程。
- validator 與 contract / hook 出現邏輯衝突。
- 產出語言違反 workspace language policy，需手動回拉。

寫入方式：

```bash
scripts/append-auto-pass-friction.sh "$AUTO_PASS_LEDGER_PATH" \
  --stage <source|breakdown|engineering|verify-AC|framework-release|post-task> \
  --kind  <friction_kind_enum_value> \
  --summary "<zh-TW 短語句，建議 280 chars 內>"
```

helper 保證 atomic write、enum 驗證與 soft-limit warning。enum 與 schema 以
`.claude/skills/references/auto-pass-ledger.md` § Friction Log 為準。

terminal report 透過 `validate-auto-pass-report.sh` 重新聚合 ledger 條目並驗
`friction_log_summary` 一致；報告不得手寫 summary 數字。

## Terminal Boundary

`auto-pass` 的成功終點是：

- 最後一次 breakdown PASS snapshot 內所有必要 workspace PR 已 opened / ready。
- verification disposition current。
- durable report produced。

framework workspace 的 merge、sync-to-polaris、tag、GitHub release 與 closeout 只能由
`framework-release` 負責。`auto-pass` report 只能輸出下一步 trigger，不得執行 release tail。

## Final Report

每次 terminal 都必須產生 durable report：

```text
{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-report.json
```

report schema 以 `.claude/skills/references/auto-pass-report.md` 為準，並由
`scripts/validate-auto-pass-report.sh` 驗證。`complete` report 若沒有 issue / blocker /
manual item / follow-up / sunset candidate，不需要 DP seed；其他 terminal 或含 sunset candidate
時必須有 follow-up DP seed reference。

Overlap cleanup disposition 只能使用：

- `keep`
- `narrow`
- `deprecate-note`
- `follow-up-sunset`

`follow-up-sunset` 只建立 follow-up DP seed，不得在同一 PR 刪除 skill、routing row 或行為性
deprecation。framework workspace 下一步若是 release，report 只輸出 `framework-release` tail
trigger，不執行 release。
