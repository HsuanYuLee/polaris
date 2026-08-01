---
name: assert
description: 定案：把「這件事成功長什麼樣」談成一組人簽得下去的斷言，寫進 source 正文的凍結塊並蓋封條。流程的第一個閘，一個 source 只寫一次。
triggers:
  - "assert"
  - "定案"
  - "寫斷言"
  - "凍結斷言"
  - "定目標"
version: 1.0.0
---

# assert — 閘一：凍結斷言

這個入口只做一件事：把成功的定義變成**人簽得下去**的斷言，鎖起來。

鎖起來之後，做法怎麼變都不用回來問人；只有成功的定義本身錯了才需要回到這裡重簽。

## source 的形狀

一個 source 是一個目錄：

```
{source}/
  index.md                       正文含凍結塊 fence，其餘是活文件
  .spine/loop-state.json         輪次
  .spine/measurement-ledger.json 量測命令登錄
```

凍結塊與活文件同檔。這是成本地板：一個工作被迫產生的檔案不超過兩個（這份與 code），
純文件類的工作只有一份。

## 斷言長什麼樣

**陳述句，不是要求句。**「當 X 時，Y 發生」可以被注入情境驗證；「應該要有 X」不行。

**正負兩表都要有。** 只有負向表列時，「什麼都不做」可以拿滿分；只有正向表列時，副作用
沒人管。負向表列不定義成功，它圈出即使達標也不接受的做法。

**只寫意圖，不寫儀器。** 斷言承載意圖鎖死，量測是斷言的代理放開。把「用哪支腳本、閾值
多少」寫進凍結區是分層錯誤——那些東西在活區，會換。

寫進 fence 之間：

```markdown
<!-- POLARIS-FROZEN-A-BEGIN -->
#### 正向表列（達成）
- **A-P1 …**：當 … 時，… 發生。
#### 負向表列（副作用殼）
- **A-N1 …**：當 … 時，… 不發生。
<!-- POLARIS-FROZEN-A-END -->
```

## 步驟

```bash
# 1. 蓋封條（算的是 fence 內文，寫封條本身不會讓它失效）
bash scripts/frozen-assertion-fence.sh seal {source}/index.md --by {簽的人}

# 2. commit —— 這一步才是凍結
git add {source}/index.md && git commit -m "freeze: {source} 斷言"

# 3. 隨時可重算比對（預設就會與 git 歷史比，不需要參數）
bash scripts/frozen-assertion-fence.sh verify {source}/index.md

# 4. 開輪次
bash scripts/spine-loop-state.sh init --state {source}/.spine/loop-state.json
```

**凍結 ＝ commit，不是 ＝ 蓋封條。** 封條只證明 fence 內文與 frontmatter 自洽——改了 fence
再重簽一次，封條一樣自洽。`--by` 只是一個字串，agent 也打得出來。真正擋住偷改的是
git 歷史：`verify` 預設把 fence 內文與該檔在 HEAD 的版本比，不同就 fail-closed，重簽不構成
授權。所以人的確認不是那個參數，是那個會出現在 diff 裡、有人看得到的 commit。

沒 commit 的斷言等於還沒凍結。source 若不在 git 裡，`verify` 直接回
`POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE`——不讓「放在未追蹤的位置」買回豁免。

## 這裡不做的事

- **不寫施工計劃。** 模式宣告是一個還沒被驗證的預測；用一次廉價的嘗試去測比用一個昂貴的
  宣告去猜誠實。
- **不決定量測命令。** 那是活區，屬 `work`。
- **不切成很多張單。** 第一趟粗切寫進活文件當草稿即可，切錯了在 loop 裡重切，不用回來重簽。

## 交出去

seal 完成、`verify` PASS、loop state 建好，就轉 `work`。
