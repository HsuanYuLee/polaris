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

`parity` 比對優先使用 state hash；沒有 state file 時使用 stdout hash。`hybrid` 若 state
drift，但 task 有 `allowed_differences`，runner 會把 drift 標為 accepted。

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
