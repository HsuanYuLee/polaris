---
title: "Review PR Submit Flow"
description: "review-pr 的 language gate、GitHub review action、inline comments、suggested changes、approve status、Slack notification 與 handbook calibration。"
---

# Review Submit Contract

這份 reference 負責組裝與送出 GitHub review，以及後續 summary / Slack notification。

## Language Gate

Review body、inline comments、Slack notification 都是 user-visible external writes。送出前
依 `workspace-language-policy.md` 判斷 PR/thread primary language；無法判斷時 fallback root
workspace language。

將 final text 寫成 temp artifact，透過 external write gate 或 language policy validator 檢查。
Code symbols、error messages、quoted author text、suggestion blocks 可保留原文。

## Review Action

| Findings | Action |
|---|---|
| no issues | `APPROVE` |
| only nits | `APPROVE` with optional comments |
| should-fix only | `COMMENT` |
| any must-fix | `REQUEST_CHANGES` |

Review summary 要短而具體。`REQUEST_CHANGES` summary 列 must-fix bullets；
`COMMENT` summary 說明不擋 merge；`APPROVE` 不寫冗長稱讚。

## Inline Comments

每個 comment 要自然描述問題、影響、規範來源或具體建議。可精準修改 diff range 時優先用
GitHub suggested change；缺測試、架構方向、或跨多處修改時用 pure comment。

Suggested change 必須確保縮排與 replacement range 正確。一個 comment 只放一個 suggestion
block。

不得重複 existing comments，也不得對 PR description 已清楚聲明的 known limitation 重複要求。

## Submit

用 GitHub review API 一次提交 review body 與 inline comments。單行 comment 用 `line`；
多行 comment 用 `start_line` + `line`。

提交後查 PR reviews 與 latest push time，計算：

- valid approve
- stale approve
- current request changes
- remaining approvals to threshold

## Handbook Calibration

提交後分析自己留下的 comments。符合 repo-specific、company-level、或 framework-level 可重用
pattern 時，依 `repo-handbook.md` standard-first flow 寫入 handbook 或 route 到 framework
memory。

不寫入 typo、missing import、copy-paste error、單次 business logic、純 nit。

若 author 推回 reviewer comment，暫停並請使用者決定：更新 handbook 接受 author 標準，或
堅持 comment 並回覆 author。

## Slack Notification

只有輸入來源為 Slack 時，回覆原始 thread。依 `github-slack-user-mapping.md` 找 PR author 的
Slack user ID，組裝 result、finding counts、最重要 must-fix summary、approve status。

必須帶 `thread_ts`，不可發成獨立 channel message。

## Conversation Summary

最後輸出：

- PR number and title
- review result
- must-fix / should-fix / nit counts
- approve status
- handbook updates if any
- Slack notification status if any
