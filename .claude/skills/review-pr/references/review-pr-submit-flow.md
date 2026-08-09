---
title: "Review PR Submit Flow"
description: "review-pr 的 language gate、GitHub review action、inline comments、suggested changes、approve status、Slack notification 與 handbook calibration。"
---

# Review Submit Contract

這份 reference 負責組裝與送出 GitHub review，以及後續 summary / Slack notification。

## Language Gate

Review body、inline comments、Slack notification 都是 user-visible external writes。送出前
依 `scripts/validate-language-policy.sh` 判斷 PR/thread primary language；無法判斷時 fallback root
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

**findings 不進 review body。** 每一條 finding 都要有 inline comment 指向具體 file + line；
把整批 findings 寫成 markdown 清單塞進 review body 當總結報告，讀的人就得自己在 diff 裡找那
幾行。body 只放一兩句總結，例如「整體架構清晰，2 項待確認（見 inline comments）」。

## Inline Comments

每個 comment 要自然描述問題、影響、規範來源或具體建議。可精準修改 diff range 時優先用
GitHub suggested change；缺測試、架構方向、或跨多處修改時用 pure comment。

Suggested change 必須確保縮排與 replacement range 正確。一個 comment 只放一個 suggestion
block。

不得重複 existing comments，也不得對 PR description 已清楚聲明的 known limitation 重複要求。

## Submit

一律呼叫 `scripts/submit-pr-review.sh`，由 wrapper 固定 writer token、canonical
`github.pull_request_review.submit` tool identity 與 GitHub review JSON shape；不得由 LLM
手拼 MCP tool 名稱或 root payload。單行 comment 用 `line`；多行 comment 用
`start_line` + `line`。wrapper 的 `--submit` lane 一次提交 review body 與 inline comments。

**三步都要走，而且是同一顆 sha。** 一則 review 是對某一份 diff 做的意見，所以它讀的、
綁的必須是同一版：

```bash
# 1. 這一次 review 依據哪一顆
REVIEWED_HEAD="$(bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N --print-head)"

# 2. diff 對那一顆取。不要用 gh 的 pr diff 子命令——它與 REST 之間有過 34 分鐘的落差，
#    而讀到舊內容會讓你對作者已經修好的東西再提一次（2026-07-27 實測）。
bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N \
  --reviewed-head "$REVIEWED_HEAD" --print-diff

# 3. 送出時原樣傳回同一顆
bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N \
  --reviewed-head "$REVIEWED_HEAD" --event EVENT --body-file BODY --comments-file COMMENTS --submit
```

沒有 `--reviewed-head` 就送出會被擋（`POLARIS_PR_REVIEW_REVIEWED_HEAD_REQUIRED`）：不宣告
的話 GitHub 會把這則 review 綁在它認為的當下 head 上，那是一顆你從來沒讀過的 commit。

送出時若 stderr 出現 `POLARIS_PR_HEAD_ADVANCED: <讀的> -> <當下>`，表示作者在你 review
期間又 push 了。**這不是錯誤，review 已經正常送出**，而且正確地綁在你讀過的那一版上。
要不要針對新的 head 再看一次由你判斷——這行訊息是寫給你讀的，不是 debug 雜訊。

提交後查 PR reviews 與 latest push time，計算：

- valid approve
- stale approve
- current request changes
- remaining approvals to threshold

## Handbook Calibration

提交後分析自己留下的 comments。符合 repo-specific、company-level、或 framework-level 可重用
pattern 時，依那家公司自己的 repo-notes skill 的 standard-first flow 寫入 handbook 或 route 到
framework memory。

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
