---
name: refinement
description: 流程的第一站，也是第一個閘：把「怎麼算成功」談成人簽得下去的斷言，凍結起來。由 driving-work-to-done 在判定要立案之後帶進來。
when_to_use: |
  driving-work-to-done 判定一件事要立案、而現場還沒有對應的單時。

  也用於：既有單的成功定義本身錯了，停 `assertion_wrong` 之後回來重簽。

  不用於：判斷「這件事要不要立案」——那在 driving-work-to-done。
version: 3.0.0
---

# refinement — 閘一：凍結斷言

這一站只做一件事：把成功的定義變成**人簽得下去**的斷言，鎖起來。

鎖起來之後，做法怎麼變都不用回來問人；只有成功的定義本身錯了才需要回到這裡重簽。

**要不要立案的判斷不在這裡**，在 `driving-work-to-done`。走到這一站表示那個判斷已經做過
而且說出來了。

## 單的形狀

一張單是一個目錄：

```
issues/                              你自己的 git repo，框架 repo 忽略它
  {命名空間}/                        自己的框架工作、某家公司、某個專案——你決定怎麼分
    {單號}/
      index.md                       正文含凍結塊 fence，其餘是活文件
      .spine/loop-state.json         輪次
      .spine/measurement-ledger.json 量測命令登錄
    archive/
      {單號}/                        收斂完的搬到這裡，流程自己搬
```

命名空間叫什麼**不影響任何判定**——流程逐個走過去，不從名字推導行為。開一張新的單時，
放進它該屬於的命名空間；不確定放哪就開一個新的，命名空間本身沒有註冊表要維護。

**`issues/` 不歸框架版控。** 它記的是你在做什麼、為什麼這樣定義成功；換一個人用同一套
框架，這裡的內容完全不一樣。框架只提供空殼（`_template/issues/`）。第一次使用時：

```bash
mkdir -p issues
cp _template/issues/README.md issues/README.md
cp _template/issues/gitignore.example issues/.gitignore
git -C issues init
git -C issues add . && git -C issues commit -m "issues: 開始"
```

它仍然必須是一個 git repo——理由見下方〈凍結 ＝ commit〉。`verify` 從檔案自己的路徑解析
repo，會自動跟著 `issues/` 進它自己的歷史，不需要告訴它。

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
bash .claude/skills/refinement/scripts/frozen-assertion-fence.sh seal {issue}/index.md --by {簽的人}

# 2. commit —— 這一步才是凍結
git add {issue}/index.md && git commit -m "freeze: {issue} 斷言"

# 3. 隨時可重算比對（預設就會與 git 歷史比，不需要參數）
bash .claude/skills/refinement/scripts/frozen-assertion-fence.sh verify {issue}/index.md

# 4. 開輪次。領域的決定是這一步的一部分，不是之後補的欄位——「這件工作屬於哪個領域」
#    沒被回答就往下走，等於流程不知道它要滿足什麼條件。
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh init \
  --state {issue}/.spine/loop-state.json --pack swe-knowledge
#    不改程式碼的工作（報告、調查、文件、資料分析）要說出理由：
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh init \
  --state {issue}/.spine/loop-state.json --pack none --why '<為什麼這件工作沒有領域完成條件>'
```

**`init` 會跑該領域宣告的開工條件，不成立就不開輪次。** 條件是什麼**這裡不說**——它寫在
那個領域自己的知識裡，寫在這裡就是第二份。拒絕的訊息會說出缺的是哪一條、怎麼修，照著做
再跑一次就是了。

所以第 1 步之前先跑一次 `init` 是划算的：條件沒滿足的話，凍結的那個 commit 會落在一個
不該落的地方，而那時候它已經在那裡了。

**凍結 ＝ commit，不是 ＝ 蓋封條。** 封條只證明 fence 內文與 frontmatter 自洽——改了 fence
再重簽一次，封條一樣自洽。`--by` 只是一個字串，agent 也打得出來。真正擋住偷改的是
git 歷史：`verify` 預設把 fence 內文與該檔在 HEAD 的版本比，不同就 fail-closed，重簽不構成
授權。所以人的確認不是那個參數，是那個會出現在 diff 裡、有人看得到的 commit。

沒 commit 的斷言等於還沒凍結。單若不在 git 裡，`verify` 直接回
`POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE`——不讓「放在未追蹤的位置」買回豁免。

## 這裡不做的事

- **不寫施工計劃。** 模式宣告是一個還沒被驗證的預測；用一次廉價的嘗試去測比用一個昂貴的
  宣告去猜誠實。
- **不決定量測命令。** 那是活區，屬 `engineering`。
- **不切成很多張單。** 第一趟粗切寫進活文件當草稿即可，切錯了在 loop 裡重切，不用回來重簽。
- **不寫「怎麼算 done」。** 那一類工作共用的完成條件由領域 pack 帶進來，不進這張單的凍結區。
  抄進去等於每張單都重簽一次同樣幾行不承載新資訊的東西。
- **不決定下一步。** 走完這一站要去哪，寫在 `driving-work-to-done`，只寫在那裡。

## 領域知識

這一站簽的是**這張單獨有的**成功條件。**這一類工作共用的**那份（definition of done）由
`driving-work-to-done` 判定領域、載入對應的 pack、記在單的狀態裡。seal 完就回殼把那件事做掉，
它不是這一站的活。
