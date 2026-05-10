---
title: "Verify AC Reporting Flow"
description: "verify-AC 的 overall verdict、JIRA wiki report、language gate、PASS transition、Epic implemented marking 與 PENDING handling。"
---

# Verify Reporting Contract

這份 reference 負責整體結論、JIRA report、transition。

## Overall Verdict

| Step Results | Overall |
|---|---|
| all PASS | PASS |
| any FAIL | FAIL |
| MANUAL_REQUIRED or UNCERTAIN and no FAIL | PENDING |

`PENDING` 只用在 verify report / human summary。它是 aggregate reporting label，不是 shared gate
status，也不可直接寫回 `ac_verification.status`。machine-gated transition 仍應回到底層 blocking
outcome：`MANUAL_REQUIRED`、`UNCERTAIN`，或 gate layer 可直接保留的 `BLOCKED_ENV`。

## JIRA Report

Verification report 使用 JIRA REST API v2 wiki markup，不使用 MCP markdown comment。Report
包含：

- date
- overall conclusion
- step table
- observed
- expected
- environment
- tools
- timestamp
- attachments when any
- native VR evidence path when visual AC runs

送出前把 final report 寫成 temp artifact，依 `workspace-language-policy.md` 或 external write
gate 驗證。引用 AC 原文、HTTP response、error message、多語系畫面文字可以保留原文，但主敘述
使用 workspace language。

## Native VR report block

visual AC 使用 `run-visual-snapshot.sh` 時，report 的 step table 必須列出：

- runner status 與 verify-AC mapped status
- Layer C evidence JSON path：`/tmp/polaris-vr-{ticket}-{head_sha}.json` 或 durable mirror
- local verification folder：`verification/{run_id}/vr/`
- baseline / compare screenshots
- diff artifact path，例如 `verification/{run_id}/vr/diff/{page}.json`

若 JIRA attachment upload 失敗，不可遺失 evidence；report 與 final summary 必須保留 deterministic
local path，讓人工仍可檢視 screenshots / diff。

## PASS

## V*.md lifecycle write-back

若驗收來源有 V*.md work order，JIRA report / transition 前必須先寫回本輪 machine-readable
lifecycle metadata：

```bash
bash scripts/write-ac-verification.sh {v_task_md} \
  --status {PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS} \
  --last-run-at {iso8601} \
  --ac-total {n} \
  --ac-pass {n} \
  --ac-fail {n} \
  --ac-manual-required {n} \
  --ac-uncertain {n} \
  [--human-disposition {passed|rejected|deferred}] \
  [--summary "{short summary}"]
```

Helper 會原子覆寫 `ac_verification`、append `ac_verification_log[]`，並重跑
`validate-task-md.sh`。失敗表示 V*.md 與真實驗收狀態可能分裂，必須 hard stop；不得繼續
JIRA transition、Slack 通知、或口頭宣告驗收完成。

DP-backed dogfood verification 必須在寫回前後使用 main-chain compliance 檢查真實 source
container。驗收進行中允許 active V*.md；parent closeout 不允許：

```bash
bash scripts/check-main-chain-compliance.sh \
  --source-container {source_container} \
  --allow-active-verification \
  --require-release-metadata
```

只有當 verification artifact / report current，且 shared verification contract resolve 為
`PASS`，才可透過 shared JIRA transition script 將 AC ticket 轉 Done。Transition 找不到、已 Done、
credential error、API error 時，不阻塞 verification report；surface 給使用者手動處理。

也就是說：

- report layer 的 `overall=PASS` 是人類可讀結論
- machine-gated transition authority 仍來自底層 verification artifact / shared gate
- `skill says PASS` 本身不構成 stage transition authority

Epic mode 下，所有 AC tickets Done 時：

1. 回報 Epic 全部 AC 通過。
2. 執行 spec implemented marker，idempotent。

## PENDING

有 MANUAL_REQUIRED / UNCERTAIN 且無 FAIL 時，列出待人工判斷項目與 observation。

使用者確認全部 OK 後，可重新跑 verify-AC 讓該 AC 轉 PASS；若人工判斷有問題，走 FAIL
disposition。
