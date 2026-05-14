---
title: "Sibling Epic policy for stacked delivery"
description: "refinement / breakdown 階段偵測長線性 stack，並要求拆 sibling Epic 的共用規則。"
---

# Stacked Delivery Sibling Epic Policy

## Purpose

當 planning preview 已經形成 `TXa -> TXb -> TXc` 或等價長線性 delivery lane，且第一張 task 會自然成為 aggregation / feat branch 時，Polaris 必須在 task.md / JIRA child 寫入前處理 sibling Epic 策略。

這條規則避免 engineering 後期才用 synthetic feat branch、local force-push 或非 GitHub PR merge 的方式補救 stack。

## Lens Command

在 refinement suggested task structure preview 前，以及 breakdown write 前，使用 deterministic lens 檢查 task draft：

```bash
node scripts/detect-stacked-delivery-lane.mjs --input <task-draft.json>
```

若只有 markdown preview，可先用 text mode 取得 advisory signal：

```bash
node scripts/detect-stacked-delivery-lane.mjs --text <preview.md>
```

CLI JSON 輸出包含：

- `status`: `ok` / `advisory` / `required` / `overridden`
- `lanes[]`: family、tasks、feat_task、aggregation_signal、independently_shippable、recommendation
- `summary`: 可直接放入 preview 的簡短說明

CLI 在 `status=required` 時 exit 1。這是刻意設計，讓 breakdown write 前可以 fail-stop。

## Decision Policy

拆 sibling Epic 的判斷：

1. 同一 delivery lane 出現三張以上 task，例如 `T3e~T3k` 或 `T8a~T8f`。
2. 第一張 task 是後續 PR 的自然 base / aggregation branch。
3. 該 lane 可獨立 review、merge、release 或 revert。
4. 與 umbrella Epic 內其他 lane 沒有檔案層級或 AC 層級強耦合，只需要 umbrella tracking。

若符合 1 + 2，refinement / breakdown 至少必須提示拆 sibling Epic。

若同時符合 3 + 4，breakdown 必須 fail-stop；使用者確認 sibling Epic 策略或提供 explicit override 前，不得建立 task.md、不得建立 JIRA child、不得推 branch。

## Required Output

命中 `required` 時，preview / artifact 必須包含：

- proposed sibling Epic summary
- umbrella Epic residual ownership
- moved child task mapping
- feat branch owner，例如 `T3e is the feat branch for T3 dayjs migration`
- downstream stack merge rule：`TXb~TXn` 透過 GitHub PR merge 合入 `TXa`
- override decision record，如果使用者選擇不拆

## Non-matches

不要強制拆 sibling Epic：

- 只有一到兩張 task。
- dependency 只是短 prerequisite，不形成獨立 release / revert lane。
- PM / RD 明確要求留在同一 Epic，且使用者接受 review / merge / revert 風險；此時必須留下 override reason。

## JIRA Write Boundary

本 policy 不授權 agent 自動建立 JIRA Epic。JIRA sibling Epic 建立、issue link、child re-parent 都是外部寫入，仍需遵守 external write gate、workspace language policy，以及使用者確認。
