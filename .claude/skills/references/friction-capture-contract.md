---
title: "Friction Capture Contract"
description: "auto-pass / framework-release tail 共用的 friction capture canonical reference：emit stage、kind enum、writer path、deterministic trigger map 與 observability 約束。"
---

# Friction Capture Contract

`friction_log[]` 是 `/auto-pass` 主鏈與 `framework-release` tail 共用的 observability
surface，紀錄本輪流程的繞道、deterministic gap、手動補位、env bypass 等摩擦點。它是
post-task reflection、follow-up DP refinement 與 sprint planning 的 signal source，
不是事後 narrative log。

本 reference 是 canonical contract source：enum、writer path、deterministic trigger
map 都以此為準，`auto-pass`、`framework-release` 與 `auto-pass-ledger` 三個 surface
都 cross-link 回此檔。

## Ownership

- **Writer path（唯一）**：`scripts/append-auto-pass-friction.sh`。helper 保證 atomic
  write、enum validation、soft-limit warning，並在 `AUTO_PASS_LEDGER_PATH` 未設或
  ledger 不存在時 NOOP（exit 0），讓 deterministic trigger 在非 `/auto-pass` 流程
  也能安全執行。
- **Storage**：寫入 ledger `friction_log[]`，ledger 路徑為
  `{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-ledger.json`。
- **Schema authority**：`.claude/skills/references/auto-pass-ledger.md`
  § Friction Log 是 schema spec；本檔案是 emit-side contract。
- **Aggregation**：terminal report `friction_log_summary` 由
  `scripts/validate-auto-pass-report.sh` 從 ledger 重算，report 不可手寫 summary。

## Emit Stage Enum

`stage` 必須是下列其一：

| Stage | 觸發時機 |
|-------|----------|
| `source` | source resolution / refinement gate 前後 |
| `breakdown` | breakdown skill / task snapshot 過程 |
| `engineering` | engineering implementation / completion gate 過程 |
| `verify-AC` | verify-AC dispatch / probe / disposition 過程 |
| `framework-release` | framework workspace release tail（merge / sync / closeout） |
| `post-task` | terminal report 後的 reflection 與後續觀察 |

`framework-release` stage 是 framework workspace self-iteration 專屬；產品 repo 的
JIRA Epic-backed source 不會走此 stage。

## Friction Kind Enum

| Kind | 用途 |
|------|------|
| `inner_skill_halt_bypass` | inner skill HALT 但 deterministic marker 已 PASS，orchestrator 必須繼續 dispatch |
| `manual_artifact_patch` | 手動修補 artifact 欄位才能 PASS gate |
| `deterministic_gap` | 缺 deterministic gate / validator / helper，當下靠人類判斷 |
| `env_bypass` | 必須 set 環境變數才能跑通流程（例：`POLARIS_LANGUAGE_POLICY_BYPASS=1`） |
| `validator_contract_conflict` | validator 與 contract / hook 出現邏輯衝突 |
| `missing_helper_script` | 缺 helper script，需手寫指令補位 |
| `language_drift_repair` | 產出語言違反 workspace language policy，需手動回拉 |
| `other` | 上述以外的繞道；summary 必須具體說明 |

## Writer Path Contract

唯一合法 writer 是：

```bash
scripts/append-auto-pass-friction.sh "$AUTO_PASS_LEDGER_PATH" \
  --stage <stage_enum> \
  --kind  <kind_enum> \
  --summary "<workspace language 短語句，soft-limit 280 chars>" \
  [--ts <ISO8601, default=now>]
```

- helper 對 unknown `--stage` / `--kind` 回 exit 1。
- summary 為空字串時回 exit 1。
- summary 超過 280 chars 時印 stderr `WARNING: summary length ...`；**不截斷**
  （AC-NEG3 from DP-214）。
- ledger 不存在時 silent exit 0（NOOP boundary），讓 deterministic trigger 在
  非 `/auto-pass` 流程也能安全執行。
- summary 必須使用 `workspace-config.yaml` `language`（預設 zh-TW），不要先寫英文再翻譯。

不得用其他方式寫 `friction_log[]`：不可直接 `jq` 或 python edit ledger、不可在 final
report 內補 summary 數字、不可由 LLM 口頭交代「已記錄」。

## Deterministic Trigger Map (DP-220)

下列 trigger 已內建 deterministic call site，orchestrator **不需要**主動呼叫；
NOOP boundary 確保 trigger 在非 `/auto-pass` 流程不會 fail。

| Signal | Trigger site | Kind | Notes |
|--------|--------------|------|-------|
| `gate_failure` | `scripts/gate-hook-adapter.sh` | `deterministic_gap` | gate exit 2 後在 gate-failure ledger 寫入後立即呼叫 |
| `workaround_taken` | `.claude/hooks/pre-write-language-policy.sh` | `env_bypass` | `POLARIS_LANGUAGE_POLICY_BYPASS=1` explicit bypass；`POLARIS_PRODUCER` 不觸發 |
| `stage_retry` | `scripts/auto-pass-increment-counter.sh` | `inner_skill_halt_bypass` | 同 transition counter 1→2 時 emit；後續 increments 由 counter 自身管理 |
| `probe_unknown` | `scripts/auto-pass-probe.sh` | `deterministic_gap` | `emit(status="UNKNOWN", ...)` 時呼叫；missing marker / invalid JSON / ledger stale |
| `context_pressure` | orchestrator (LLM) | `other` | 寫 `pause.kind=session_handoff` 前手動呼叫，summary 帶 resume artifact path |

trigger 與 enum 對應（refinement 原文 → helper enum）：

- `gate_failure` → `deterministic_gap`
- `workaround_taken` → `env_bypass`
- `stage_retry` → `inner_skill_halt_bypass`
- `probe_unknown` → `deterministic_gap`
- `context_pressure` → `other`

新增 deterministic trigger 時，必須在 `rules/mechanism-registry.md` 對應 row 加上
`runtime` annotation，並更新本表 + 對應 selftest（一律覆蓋 `auto-pass-auto-friction-selftest.sh`
或新增 dedicated selftest）。

## Framework-Release Tail Capture

`framework-release` 是 framework workspace self-iteration tail。release 流程（PR
merge / sync-to-polaris / tag / GitHub release / closeout）若觸發下列摩擦點，必須
走同一支 `append-auto-pass-friction.sh` 寫入 `stage=framework-release`：

- **`manual_artifact_patch`**：release tail 手動修補 PR body / VERSION / CHANGELOG /
  release notes（任何在 engineering completion gate 後被 reviewer / maintainer
  追加的 metadata 修改）。
- **`deterministic_gap`**：release helper（`framework-release-closeout.sh` /
  `sync-to-polaris.sh`）缺 deterministic gate，必須靠 maintainer 操作補位。
- **`env_bypass`**：release tail 需要 set 環境變數才能跑通（例：
  `POLARIS_FRAMEWORK_RELEASE_FORCE=1`、`POLARIS_TOOL_AUTH_FAILED` 後 retry token
  fallback）。
- **`missing_helper_script`**：release tail 缺 helper，需要手寫 `gh` / `git` /
  `sync-to-polaris.sh` 指令補位。
- **`language_drift_repair`**：release summary / PR body / GitHub release body 違反
  `workspace-config.yaml language` 而需手動回拉。

release tail 仍以 `AUTO_PASS_LEDGER_PATH` 為單一 ledger 寫入點；若 release tail 在
`/auto-pass` terminal 後才執行（typical case），ledger 仍由 source container 內保留，
writer NOOP boundary 確保 silent skip 不會發生在 ledger 存在的情境。

## Observability Constraints

- **Append-only**：`friction_log[]` 只允許 append，不可修改 / 刪除既有 entry；
  helper 透過 tmp file + rename 保證 atomic。
- **No silent drop**：deterministic trigger 不可在 silent failure 後跳過 friction
  emit；trigger 內 NOOP boundary 只針對「ledger 不存在」這個合法狀態。
- **No double counting**：同一個 logical event 不可同時被 deterministic trigger
  與 orchestrator 雙寫；orchestrator 只負責 `context_pressure` 這個 LLM-judgment
  trigger。
- **Soft limit, no truncate**：summary 超過 280 chars 印 WARNING，但完整保留；
  validator 也只 surface WARNING 不變更 exit code。
- **Aggregated in terminal report**：`auto-pass` terminal report 必含
  `friction_log_summary`（total / by_stage / by_kind），由
  `validate-auto-pass-report.sh` 從 ledger 重算；report 與 ledger 不一致時 validator
  fail。

## Selftest Coverage

| Selftest | 覆蓋範圍 |
|----------|----------|
| `scripts/selftests/auto-pass-friction-log-selftest.sh` | helper enum / soft-limit / atomic write / ledger validator / report aggregator |
| `scripts/selftests/auto-pass-auto-friction-selftest.sh` | 4 個 deterministic trigger 的 emit + NOOP boundary |
| `scripts/selftests/friction-capture-contract-selftest.sh` | 本 reference 與 4 surface（auto-pass SKILL / framework-release SKILL / auto-pass-ledger / INDEX）的 wiring + framework-release "## Friction Capture during release tail" 段 + 行數 ≤ 400 |

Wiring 任一條缺失，`friction-capture-contract-selftest.sh` fail-stop +
stderr `POLARIS_FRICTION_CAPTURE_WIRING_MISSING`。

## Cross-References

- Schema spec：`.claude/skills/references/auto-pass-ledger.md` § Friction Log
- Auto-pass orchestrator 使用方式：`.claude/skills/auto-pass/SKILL.md`
  § Friction Log Capture / § Auto-Friction Triggers
- Framework-release tail 使用方式：`.claude/skills/framework-release/SKILL.md`
  § Friction Capture during release tail
- Mechanism registry（runtime annotation 與 priority audit）：
  `.claude/rules/mechanism-registry.md`
