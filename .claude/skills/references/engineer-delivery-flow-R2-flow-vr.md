## Step 3.2 — Post-Implementation Flow Gap Audit

在 Step 2 / Step 3 都完成後、Step 3.5 / commit / PR / local-extension handoff 前，必須做一次流程 gap 檢查。這不是額外 code review，而是確認「完成」沒有依賴 LLM 自行補判斷或 tool false pass。

先執行 deterministic helper；helper exit non-zero 就停在本步修機制或回上游 artifact：

```bash
bash "${POLARIS_ROOT}/scripts/check-flow-gap-audit.sh" \
  --task-md "<path/to/task.md>" \
  --repo "$(git rev-parse --show-toplevel)"
```

檢查四類：

1. **Bypass**：本次是否使用任何 `POLARIS_SKIP_*`、`--skip-*`、manual direct push、或 local-extension PR lane exception；若有，必須有 task/workflow 明文允許與 evidence。
2. **Fallback**：本次是否靠 legacy path、repo-local ignored overlay、missing generated target、或 old wrapper 才通過；若 fallback 是 migration blocker，先修機制，不進 closeout。
3. **False pass**：任何 gate 是否把 `NO_*_CONFIGURED`、`config: (none)`、empty result、或 ignored-file-invisible 當 pass；若是 framework/config migration 變更，必須補 deterministic validator。
4. **Ignored/runtime artifacts**：若改動涉及 local ignored artifacts、worktree、generated target、company config、repo overlay、或 release closeout，驗證必須包含 `--no-ignore` 或等價掃描，不能只看 tracked diff。

對 Polaris config / instruction / release flow 變更，還必須跑：

```bash
bash scripts/validate-polaris-config-migration.sh
```

Flow gap audit 的結論要進 final / handoff；若發現 gap，先修機制或回 DP/refinement，不得只用「我判斷沒問題」結案。

DP-backed framework work 在 Step 8a closeout 前還必須跑主鏈 compliance，避免
refinement / breakdown / engineering / verify-AC 任一段靠 prose 或 local artifact 漏接：

```bash
bash "${POLARIS_ROOT}/scripts/check-main-chain-compliance.sh" \
  --source-container "<source_container>" \
  --allow-active-verification
```

### Manual Stack Replay Ledger

若為了修 stacked PR / T 系列重建分支而採用 cherry-pick、drop commit、重新排序、
force push 等 history rewrite，必須在 push 前產生 replay manifest，並用 deterministic
script 驗證格式：

```bash
bash scripts/stack-replay-manifest-check.sh --manifest <path/to/stack-replay.md>
```

Manifest 至少包含：

```markdown
# Stack Replay Manifest

## Included Commits

- `<sha>` — reason

## Excluded Commits

- `<sha>` — reason
```

這份 manifest 是「commit 取捨」的 decision ledger；scope gate 只能證明最後 diff
在 Allowed Files 內，不能證明 replay 過程沒有混入或漏掉 review fix。若沒有 replay
manifest，stack rewrite 不得進 push / closeout。若沒有任何 excluded commit，使用
`--allow-empty-excluded` 並在 manifest 寫明 `Excluded Commits` 為 `N/A`。

### PR Review Thread Disposition Gate

Revision / rebase / stack rewrite 針對既有 open PR 時，approval 不等於所有 review
thread 已處理。`reviewDecision=APPROVED` 仍可能存在 `reviewThreads.isResolved=false`
的 inline comments；即使 GitHub 已標 `isOutdated=true`，UI 仍會顯示 unresolved
conversation，reviewer 也會解讀成作者沒有收尾。進入 push / closeout 前必須跑：

```bash
bash scripts/pr-review-thread-disposition-gate.sh \
  --repo <owner/repo> \
  --pr <number> \
  --manifest <path/to/review-thread-disposition.json>
```

Manifest 必須對每個 unresolved thread 記錄，包含 outdated-but-unresolved thread：

```json
{
  "version": 1,
  "pr": "https://github.com/owner/repo/pull/123",
  "threads": [
    {
      "thread_id": "PRRT_...",
      "disposition": "fixed",
      "reason": "implemented offset-preserving parser and pushed commit"
    }
  ]
}
```

Allowed dispositions：

| Disposition | Meaning |
|---|---|
| `fixed` | 本 PR 已用 code/test 修正 |
| `reply_only` | 需要在 GitHub 回覆說明，無 code change |
| `not_actionable` | 非 action item，或已由後續 diff 失效 / GitHub 已標 outdated，但仍需回覆與 resolve |
| `deferred_with_reason` | 明確延後，reason 需指出 owner / follow-up |

有 unresolved thread 卻沒有 disposition manifest，或 manifest 少任何 thread，
就不得 force push 或回報完成。Flat PR comments / `reviewDecision` / approval 數量都不能取代此 gate。

### Evidence schema

`/tmp/polaris-verified-{ticket}-{head_sha}.json`：

```json
{
  "ticket": "EPIC-521",
  "head_sha": "abc1234",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "command": "curl -sS ...",
  "stdout_hash": "sha256:...",
  "urls_detected": [{"url": "...", "http_status": 200}],
  "at": "2026-04-26T09:30:00Z"
}
```

---

## Step 3.5 — Visual Regression（`run-visual-snapshot.sh`，conditional，D18）

### 觸發條件

**Triggered by**：`task.md Test Environment Level=runtime` AND `task.md verification.visual_regression` is non-empty（from DP-033 schema）。

**NOT triggered by**：config glob ∩ git diff filename matching（old mechanism removed）。

無 task.md / task.md 無 VR 段落 → **跳過**。

### 執行

`scripts/run-visual-snapshot.sh`（D18）：
- `--mode baseline`：screenshot before state
- `--mode compare`：screenshot after + image diff + PASS/FAIL judgment per task.md `expected` field
- 若 task 使用 fixture-backed VR，先用 `--mode record` 建立 fixture，review 後 baseline / compare 才能通過 Layer C gate。

### PASS/FAIL table

從 task.md `verification.visual_regression.expected` 讀取：

| expected | diff result | verdict |
|----------|------------|---------|
| `none_allowed` | any diff | FAIL |
| `none_allowed` | 0 diff | PASS |
| `baseline_required` | first run, no before | PASS, establish baseline |
| `update_baseline` | diff exists | PASS, new baseline + diff images in PR |
| `update_baseline` | 0 diff | FAIL (tentative strict) |

### Evidence

`/tmp/polaris-vr-{ticket}-{head_sha}.json`（Layer C, conditional — only required when trigger fires）。

PR / completion gate 會要求 matching `head_sha` 且 `status=PASS`、`mode=compare`、`writer=run-visual-snapshot.sh`。缺少、stale、`BLOCK`、`BLOCKED_ENV`、`MANUAL_REQUIRED` 都不可視為可交付。

若本步或 Step 3 Behavioral Verify 產生需要 PR 可見化的截圖、影片、VR artifact、或
Playwright behavior evidence，進 Step 7 前必須依
`references/evidence-upload-bundle.md` 產生人工上傳包：

```bash
bash "${POLARIS_ROOT}/scripts/collect-evidence-upload-bundle.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --ticket "<TICKET_OR_DP_TASK_ID>" \
  --head-sha "$(git rev-parse HEAD)" \
  --source-container "<spec_container>" \
  --target pr
```

此 bundle 只方便使用者拖檔到 PR；不取代 Layer A/B/C evidence，也不滿足 completion gate。

### visual-regression skill sunset（D18）

獨立的 `visual-regression` skill 正在 sunset。VR execution 吸收進本 delivery flow step。**Do NOT invoke the `visual-regression` skill** — 待 `run-visual-snapshot.sh` 落地後使用。

---

## Step 4 — _(已搬至 Step 1.3 — Phase 3 exit gate)_

> **DP-032 D21（v3.63.0+）**：原 Pre-PR Self-Review Loop 概念前移為 Phase 3 的 exit gate，發生在 /simplify 之後、Step 1.5 Scope Gate 之前。
>
> - 新位置：本檔 § Step 1.3
> - Reviewer baseline：handbook-first（見 § Step 1.3）
> - 迭代：blocking → 回 **Phase 3**（不只 /simplify），hard cap 3 輪，**NO bypass**
> - Step 4 編號保留作為 placeholder，不重編後續 Step 5/6/7/8 以免下游 reference 斷裂

---

