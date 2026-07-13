---
title: "Behavior Contract"
description: "task.md verification.behavior_contract 的 engineering runner、evidence schema、gate 與 backfill policy。"
---

# Behavior Contract

`verification.behavior_contract` 是 planner 寫給 engineering 的使用者可見行為驗證意圖。
engineering 不自行猜測「要前後一致」或「照設計稿」；只依 task.md contract 執行。

## Modes

| Mode | Source of truth | Engineering gate |
|------|-----------------|------------------|
| `parity` | resolved base 的既有行為 | 先 baseline，再 compare；未宣告差異不可 drift |
| `hybrid` | 既有行為 + 明確允許差異 | 先 baseline，再 compare；只接受 `allowed_differences` |
| `visual_target` | Figma / design artifact | compare 跑 target flow assertions；baseline 只作 context |
| `pm_flow` | PM operation flow / AC steps | compare 跑 flow assertions |

`applies: false` 只需 `reason`，不要求 behavior evidence。

## `behavior_contract.applies` Decision Matrix

breakdown producer 先用下表決定 `applies`，不可留 `unknown`：

| Trigger | `applies` | Required shape |
|---------|-----------|----------------|
| 純 static framework docs、schema prose、release metadata、validator help text | `false` | 填具體 `reason`，說明不影響使用者可見 runtime 行為。 |
| UI parity、元件替換、使用者可見 refactor、移除 legacy dependency | `true` | 預設 `mode: parity`；有刻意差異時用 `hybrid` 並列 `allowed_differences`。 |
| Figma / design target 驅動畫面 | `true` | `mode: visual_target`，`source_of_truth` 指向 Figma / design artifact。 |
| PM flow / AC 操作步驟定義行為 | `true` | `mode: pm_flow`，列 `flow` 與 assertions。 |
| Migration 只改內部 script / artifact schema，無 runtime 使用者表面 | `false` | 填 migration/static reason；若 migration 會改使用者可見輸出，改用 `true`。 |

## Runner

```bash
bash scripts/run-behavior-contract.sh --task-md <task.md> --mode baseline
bash scripts/run-behavior-contract.sh --task-md <task.md> --mode compare
```

`parity` / `hybrid` 必須有 baseline；`compare` 缺 baseline 會 fail。Runner 支援
`baseline_ref`，可從 resolved base 建 temp worktree 重錄 before evidence，供已施工或已開
PR 的 task 補證據。

Task 可宣告固定 flow script：

```yaml
verification:
  behavior_contract:
    applies: true
    mode: parity
    source_of_truth: existing_behavior
    fixture_policy: mockoon_required
    baseline_ref: develop
    flow: "media-lightbox-carousel"
    flow_script: "scripts/behavior-flows/media-lightbox-carousel.sh"
    assertions:
      - "modal visible"
    allowed_differences: []
```

Flow script 以 repo root 為 cwd 執行，並透過環境變數取得輸出位置：

| Env | Meaning |
|-----|---------|
| `POLARIS_BEHAVIOR_MODE` | `baseline` 或 `compare` |
| `POLARIS_BEHAVIOR_OUTPUT_DIR` | script 必須把 screenshots/videos/state 寫到這裡 |
| `POLARIS_BEHAVIOR_TICKET` | task id / ticket |
| `POLARIS_BEHAVIOR_HEAD_SHA` | 執行目標 commit |
| `POLARIS_BEHAVIOR_TARGET_URL` | task 宣告的 target URL |
| `POLARIS_BEHAVIOR_VIEWPORT` | `mobile` / `desktop` / `responsive` |

建議 flow script 產出：

- screenshots：`*.png` / `*.jpg`
- videos：`*.webm` / `*.mp4`
- state：`behavior-state.json` 或 `state.json`

若 task 宣告 `verification.behavior_contract.assertions`，flow script 應在 state file 寫入
structured assertion coverage：

```json
{
  "assertion_results": [
    {
      "assertion": "modal visible",
      "status": "PASS",
      "source": "playwright locator assertion",
      "note": "Optional detail."
    }
  ]
}
```

`status` 只能是：

| Status | Meaning |
|--------|---------|
| `PASS` | flow script 已自動驗證該 assertion |
| `FAIL` | flow script 已驗證且失敗；整體 behavior evidence FAIL |
| `MANUAL_REQUIRED` | assertion 需要人工驗證，不得在 report / PR body 呈現為自動 PASS |
| `NOT_COVERED` | assertion 未被此 flow 覆蓋，不得在 report / PR body 呈現為自動 PASS |

Runner 會把缺少 structured result 的 task assertion 補成 `NOT_COVERED`，讓下游 report 可以
明確呈現未覆蓋項目；invalid status 會轉成 FAIL 並擋下 evidence。

產品 task 的 evidence ticket 預設使用 task.md 的 `Task JIRA key`；沒有 JIRA key 的
DP-backed task 才 fallback 到 task id。`--ticket` 是 explicit override，保留給特殊
backfill 或 migration case。

若 state file 提供 structured runtime health，runner 會把 health 納入 evidence validity：

- `comparableState.targets[].status` 為 `0` 或 `>=400` → FAIL。
- `comparableState.targets[].health.bodyHasText=false` → FAIL。
- `comparableState.targets[].health.hasNuxtRoot=false` → FAIL。

Baseline mode 也套用同一 health gate；空頁 baseline 不能作為 compare 的 source of truth。
沒有提供 health 欄位的 legacy/static flow 不會被 runner 推測失敗。

`parity` 比對優先使用 state hash；沒有 state file 時使用 stdout hash。`hybrid` 若 state
drift，但 task 有 `allowed_differences`，runner 會把 drift 標為 accepted。

## No Executable Flow → NOT_COVERED Route-back

`applies: true` 卻沒有可執行的 flow（缺 `flow_script`、或 `fixture_policy: static_only`
沒有 runnable script）時，runner **不得**靜默當作 covered。這種情況沒有任何 runtime 證據，
runner 會 emit evidence-level `status=NOT_COVERED` 的 behavior marker（與 `PASS` / `FAIL`
同一 producer、同一 evidence path、同一 schema，只是狀態值不同），`comparison.kind=not_covered`
（`reason=no_executable_flow`），並以 **exit 2** route-back（fail-closed contract 條件，
刻意與 generic exit 1 crash-like failure 區隔）。

`NOT_COVERED` 不是 assertion-level 補值那條路徑（runner 對缺 structured result 的 assertion
仍會補 assertion-level `NOT_COVERED`），而是整份 evidence 的終局狀態：gate 要求 `status=PASS`，
因此 `NOT_COVERED` 不會通過 completion gate，auto-pass 必須停在 owning producer
（breakdown / refinement）補上可執行的 flow_script 或重新評估 `applies`，**不得**在本地
自行修補（見 `auto-pass-execution-flow.md` § No Executable Flow Route-back）。

## Verification Trustworthiness Gate（DP-417 T8）

當 task 宣告 before/after 畫面 / 行為 fidelity（`applies: true` 且 `mode` 為 `parity` /
`hybrid` / `vr`）時，compare 的 PASS 必須由**真實 render** 與**真實比對**支撐。這條 gate 由
`scripts/lib/verification-fidelity-trust.sh` 統一實作，`run-behavior-contract.sh`
（`parity` / `hybrid`）與 `run-visual-snapshot.sh`（`vr`）共用同一份判定，不各自另寫一套。

**Layer 1 — 真實 render trust**（`run-behavior-contract.sh` compare）：下列冒充一律
fail-closed（marker `status=FAIL`、`comparison.kind=fidelity_trust`、exit 2 +
`POLARIS_VERIFICATION_FIDELITY_UNTRUSTED`），不得產出 PASS marker：

- state file 直接宣告字面 `hash`（flow 自報比對結果，沒有真的 render）→ `hardcoded_state_hash`。
- 沒有 behavior state file 也沒有任何真實 render 的截圖 / 影片（只有 placeholder 佔位檔、
  或 unit + grep 代替 render）→ `no_rendered_artifact`。

真實的 behavior state file **或**帶有正確 magic bytes 的截圖 / 影片（PNG / JPEG / WEBM / MP4）
即視為真實 render，比對方法（byte-SHA / state-hash / 感知）不限。

**Layer 2 — 測試主體隔離**（`replaces_existing` fidelity task，兩個 runner 皆適用）：宣告
「替換既有實作且維持 fidelity」的 task 若在 compare 到達 PASS 時，被替換的舊 source 仍存在於
測試環境，該 PASS 是被舊 source 汙染的（confounded）。runner 在 render 前 fail-closed
（exit 2 + `POLARIS_VERIFICATION_CONFOUNDED`；VR marker `status=BLOCK`），要求「先清乾淨再
驗證」。

宣告方式（`verification.behavior_contract` 或 `verification.visual_regression` 皆可）：

```yaml
verification:
  behavior_contract:
    applies: true
    mode: parity
    replaces_existing: true
    replaced_paths:
      - "src/legacy/OldWidget.js"
```

- `replaces_existing: true` 但 `replaced_paths` 為空 → 無法驗證隔離，一律 fail-closed。
- `replaced_paths` 內任一路徑在測試環境仍存在 → confounded，fail-closed。
- `replaces_existing` 未宣告或非 `true` → 本層 no-op，不影響既有 task。

`applies: false` 與非 fidelity mode（`visual_target` / `pm_flow`）不受本 gate 影響。

## Evidence

Runner 會寫 head/context 綁定 JSON：

```text
/tmp/polaris-behavior-{ticket}-{head_sha}-{context_hash}.json
<repo>/.polaris/evidence/behavior/{ticket}/polaris-behavior-{ticket}-{head_sha}-{context_hash}.json
<repo>/.polaris/evidence/behavior/{ticket}/{baseline|compare}-{context_hash}-{short_sha}/...
```

Gate 要求 `compare` evidence：

- `writer=run-behavior-contract.sh`
- `ticket` 與 current task 一致
- `head_sha` 與 current HEAD 一致
- `mode=compare`
- `status=PASS`
- 若 task 有 `assertions`，每條 assertion 都必須在 `assertion_results[]` 有 structured
  result，且 status 必須是 `PASS`、`FAIL`、`MANUAL_REQUIRED` 或 `NOT_COVERED`
- 至少一個 screenshot 或 video reference
- `parity` / `hybrid` 必須有 `baseline_evidence`

若 local evidence 含 video / screenshot，completion gate 仍要求 PR-visible publication
marker。需要人工上傳時使用：

```bash
bash scripts/collect-evidence-upload-bundle.sh \
  --repo <repo> \
  --ticket <ticket> \
  --head-sha <head_sha> \
  --source-container <spec-container> \
  --target pr
```

## Backfill Policy

所有未 archive work orders 最終都必須有 `verification.behavior_contract` 或進 planner
decision queue。不得填 `unknown`。

- 明確 static/docs/framework/release/metadata task：可補 `applies: false` 與 reason。
- replacement / migration / refactor / remove legacy dependency：預設 `parity`，有刻意可見差異才用 `hybrid`。
- Figma/design target：`visual_target`。
- PM flow / AC 操作步驟：`pm_flow`。
- 判斷不足：寫 decision queue，回 `breakdown` / `refinement`。
