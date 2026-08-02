---
name: refinement
description: 有人帶著一件要做的事出現時的第一站。先判斷這件事要不要立案並說出依據；要立案的，把「怎麼算成功」談成人簽得下去的斷言，凍結起來。任何會改變程式碼或行為的請求都從這裡進，使用者不需要記得這個名字。
when_to_use: |
  使用者說出一件想做的事、而現場還沒有對應的 source 時。例如「幫我做 X」「我要改 Y」
  「這個需求…」「X 壞了要修」「想重構 Z」——不論有沒有指令名稱。

  也用於：既有 source 的成功定義本身錯了，要回來重簽（第四類流轉）。

  不用於：唯讀的查詢與說明（「這支腳本在幹嘛」「查一下 X」）。那些沒有「怎麼算成功」
  要簽，直接回答即可。
version: 2.0.0
---

# refinement — 閘一：立案判斷與凍結斷言

這個入口做兩件事：**先判斷要不要立案**，要立案的才把成功的定義變成**人簽得下去**的斷言，
鎖起來。

鎖起來之後，做法怎麼變都不用回來問人；只有成功的定義本身錯了才需要回到這裡重簽。

## 零、先做立案判斷，並說出來

被叫起來的第一件事不是寫斷言，是**判斷這件事該不該立案，並把判斷與依據說出口**，然後才
動作。不要靜默決定——人要能當場推翻它。

判準只有一條：**有沒有「怎麼算成功」需要人簽字。**

| 這件事 | 立案？ |
|---|---|
| 查一下、說明一段程式、跑個既有測試 | 否。沒有要簽的東西，直接做 |
| 改 typo、調一個顯然的常數 | 否。成功的定義不會有爭議 |
| 會改變行為、會有人問「這樣算好了嗎」 | **是** |
| 不確定 | **是**。立案的成本遠低於做完才發現目標不對 |

說出來的樣子：「我判斷這件事**要**立案，因為驗收標準不只一種可能」，或「我判斷**不用**
立案，這是唯讀查詢，直接做」。一句話就夠，不需要表格。

不立案的，到此為止，直接把事情做完。立案的，往下走。

## source 的形狀

一個 source 是一個目錄：

```
sources/                         你自己的 git repo，框架 repo 忽略它
  {source}/
    index.md                     正文含凍結塊 fence，其餘是活文件
    .spine/loop-state.json       輪次
    .spine/measurement-ledger.json 量測命令登錄
```

**`sources/` 不歸框架版控。** 它記的是你在做什麼、為什麼這樣定義成功；換一個人用同一套
框架，這裡的內容完全不一樣。框架只提供空殼（`_template/sources/`）。第一次使用時：

```bash
cp _template/sources/README.md sources/README.md
cp _template/sources/gitignore.example sources/.gitignore
cd sources && git init && git add . && git commit -m "sources: 開始"
```

它仍然必須是一個 git repo——理由見下方〈凍結 ＝ commit〉。`verify` 從檔案自己的路徑解析
repo，會自動跟著 `sources/` 進它自己的歷史，不需要告訴它。

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
bash .claude/skills/refinement/scripts/frozen-assertion-fence.sh seal {source}/index.md --by {簽的人}

# 2. commit —— 這一步才是凍結
git add {source}/index.md && git commit -m "freeze: {source} 斷言"

# 3. 隨時可重算比對（預設就會與 git 歷史比，不需要參數）
bash .claude/skills/refinement/scripts/frozen-assertion-fence.sh verify {source}/index.md

# 4. 開輪次
bash .claude/skills/refinement/scripts/spine-loop-state.sh init --state {source}/.spine/loop-state.json
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
- **不決定量測命令。** 那是活區，屬 `engineering`。
- **不切成很多張單。** 第一趟粗切寫進活文件當草稿即可，切錯了在 loop 裡重切，不用回來重簽。

## 交出去：人說一句「開工」，之後不再問路

seal 完成、`verify` PASS、loop state 建好，就轉 `engineering`——**不要回頭問「接下來要做什麼」**。
人在這裡簽的是成功的定義；簽完之後該走哪一站，是流程自己讀得出來的東西，不是要人再指一次
的東西。

```bash
bash .claude/skills/refinement/scripts/spine-loop-state.sh where --state {source}/.spine/loop-state.json
```

它會說出站別、有沒有停、還剩幾輪。**任何時候不確定現在在哪，就跑它，不要問人**——問人
才是不知道自己在哪的那個症狀。

流程只在四種地方停，而且停的時候要說出是哪一種：

| 停點 | `--kind` |
|---|---|
| 斷言不對，要人重簽 | `assertion_wrong` |
| `engineering` 那三件要浮出來的事 | `surfaced_concern` |
| 連續未收斂打到上限 | `unconverged_cap`（`record` 自己會寫，不用手動） |
| 需要人授權的不可逆動作 | `unauthorized_action` |

```bash
bash .claude/skills/refinement/scripts/spine-loop-state.sh stop \
  --state {source}/.spine/loop-state.json --kind surfaced_concern --note '<一句話>'
```

這四種以外的字串會被拒絕。停了就要留下紀錄再開口——**停在紀錄外等於沒停**，回來的人只看得到
一個不動的 source，看不到它為什麼不動。
