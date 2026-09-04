---
title: "Review Comment Form"
description: "review body 與 inline comment 寫成什麼形狀：圖表優先、一個 finding 三句話、什麼時候不要畫圖。"
---

# 一則 review 寫成什麼形狀

這份只管**形式**，不管判準。該擋的還是擋，沒問題還是直接 approve——嚴重度怎麼分、送
哪一個 event，在 `review-pr-submit-flow.md`。

## 原則

**能用圖或表講的就不要寫成散文。** 一個 finding 的文字上限是三句：哪裡、為什麼是問題、
怎麼改。其餘資訊放進圖或表。

作者剛寫完那段程式碼。散文要他把你的句子重新組回成一張圖，圖直接給他那張圖。

## 用什麼形式

| 這個 finding 在講什麼 | 用什麼 |
|---|---|
| 呼叫鏈、資料流、模組相依 | `mermaid flowchart` |
| 前後端或多方互動、時序、race condition | `mermaid sequenceDiagram` |
| 狀態機、flag 組合、生命週期 | `mermaid stateDiagram-v2` |
| 現況與建議的對照、輸入與輸出的對照、edge case 矩陣 | markdown 表格 |
| 一行改法 | `suggestion` 區塊 |

GitHub 的 review body 與 inline comment 都吃 ```mermaid 圍籬，直接用。`suggestion` 有兩個
前置條件：錨的那一行必須是 diff 裡的 added line，取代範圍要對得上那幾行。有一邊對不上就
改用一般的 ```ts 圍籬，不要用 `suggestion`。

## 圖怎麼畫

- **一張圖一個問題。** 節點不超過 8 個。超過就是這張圖想講兩件事，拆開。
- **把問題標在圖上。** 出問題的節點或箭頭，文字前面加 `⚠`，讓人一眼看到位置。
- 節點名用程式碼裡真的存在的識別字：函式名、檔名、component 名。不要用抽象代稱。
- **圖不重述 diff 在做什麼。** 要畫的是作者沒看到的那條路徑。

## 不要畫圖的時候

typo、命名、少一個 null check、單行邏輯錯——這些一句話加一個 `suggestion` 區塊就結束。

**為了有圖而畫圖比散文更浪費看的人的時間。** 這一條是這套形式能用的前提，不是例外條款。

## Review body 的形狀

1. 結論一行：`APPROVE` / `COMMENT` / `REQUEST_CHANGES`，加一句原因。
2. findings 表格：`檔案:行`、嚴重度、一句話。
3. 需要圖才講得清楚的那一個核心問題，一張圖。最多兩個。
4. 沒有第 4 段。

結論那一行有兩個 event 各自要注意：`COMMENT` 要說明這則不擋 merge，`APPROVE` 不寫冗長
的稱讚。

第 2 段的表格只是索引，**每一條 finding 仍然要有自己的 inline comment 指向那一行**——
把整批 findings 寫成清單塞在 body 裡，讀的人就得自己在 diff 裡找。

## 詞

用工程師本來就在用的詞：race condition、N+1、breaking change、type narrowing、
memory leak、edge case。**不自創名詞**，也不要把常見概念重新包裝成一個新說法。

不要解釋 diff 本身在做什麼。沒有問題就直接 approve，不要為了顯得有在看而生出可有可無
的意見。
