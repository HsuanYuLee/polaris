---
title: "Visual Regression Analysis Reporting"
description: "visual-regression 結果分析、strict fixture mode、diff classification、artifact upload、JIRA wiki report、cleanup 與 engineering return contract。"
---

# Result And Reporting Contract

這份 reference 負責 Playwright compare 後的判讀、reporting、cleanup。

## First-run Gate

第一次 fixture setup 或 fixture change 後，必須先讓使用者 review screenshots。未確認內容正確
前，不可發布 JIRA report，也不可把 zero-diff 當作 pass evidence。

## Strict Fixtures

Fixtures active 時，所有 API data deterministic。任何 diff 都是 fail signal，不可歸類成
data variance，也不可用提高 threshold 方式接受。

Diff 只能進一步判斷為：

- intentional visual change
- regression
- major diff requiring manual confirmation
- unknown because page ownership data is missing

## Diff Classification

Fixtures inactive 或需要 secondary analysis 時，對每個 diff page 判斷 changed files 是否與
該 page 相關：

| Condition | Classification |
|---|---|
| page `source_project` files changed | intentional |
| global style/layout files changed | intentional for affected pages |
| no related code changed | regression |
| diff ratio > 50% | major diff，不做 intentional/regression 判斷 |
| missing `source_project` | unknown |

Report 使用 zh-TW，包含 comparison path、fixture state、pass pages、diff pages、major
diffs、HTML report path。

## Artifact Upload

若 VR 是 ticket verification flow 的一部分，cleanup 前收集 after screenshots 與 diff images
到 temp directory，再用 shared JIRA attachment script 上傳。

JIRA 同名 attachment 有 binding trap：wiki markup comment 在建立時綁定 attachment ID。
重傳同名檔不會更新舊 comment。Safe flow 是 delete old attachment 後再 upload and repost，
或使用 versioned filenames。

Standalone run 不上傳 artifacts，只提供 local HTML report path。

## JIRA Wiki Report

不論 pass 或 fail，ticket verification flow 必須寫 rich JIRA report。使用
`vr-jira-report-template.md`，並透過 REST API v2 wiki markup 發 comment；不要使用 MCP
markdown comment。

Report rules：

- 每頁一個 `h3.` section。
- PASS pages 附 after desktop / mobile screenshots。
- FAIL pages 附 diff image，以及必要時 before / after。
- SKIP pages 說明原因與解除條件。
- 圖片使用 `!filename.png|thumbnail!`。
- 發送前先通過 `workspace-language-policy.md` 或 external write gate。

Upload 失敗時 fallback text-only summary，並附 HTML report 檢視方式。

## Cleanup

Cleanup always runs，即使 test fail 或中途 error：

1. 若 Local path stash 尚未 pop，優先 restore git state。
2. Stop environment through recorded `polaris-env.sh stop <company>` path。
3. 停掉本次啟動的 fixture server。
4. 刪除 `snapshots/`。
5. 刪除 `test-results/`。
6. 保留 `playwright-report/`。

Git state 與 server state 是最高優先級；若 cleanup 失敗，回報 manual recovery info。

## Engineering Return

Engineering-triggered VR 不走互動式長報告，回傳：

| Result | Meaning |
|---|---|
| `PASS` | all screenshots match |
| `PASS_WITH_DIFFS` | 只有 intentional diffs |
| `BLOCK` | regression、major diff、unresolved fixture/first-run gate |

`PASS_WITH_DIFFS` 可以繼續 PR workflow，但必須在 summary 註明 expected visual changes。
`BLOCK` 必須停止 delivery flow，等使用者處置。
