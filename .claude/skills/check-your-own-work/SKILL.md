---
name: check-your-own-work
description: |
  Before handing your own change over — opening a PR, asking for review, saying
  "done" — check it against six questions that come from what reviewers actually
  caught: claims that do not match the diff, the repo's own rules not applied,
  half-done pattern changes, runtime behaviour asserted from reading source,
  last round's comments still unaddressed, and assertions that cannot fail.

  Use when you are about to hand your own work over, or when someone asks you to
  self-check, double-check, or go over your change before submitting.

  交出自己的改動之前——開 PR、找人 review、說「做完了」——先對一次自己寫的東西。
  六問來自 review 真的抓到的東西，不是想像出來的清單。

  不用於：看別人的 PR（那是 code review，主語是別人的改動）。
  不用於：判定某個交付達不達標——這支不判紅、不擋人，它產出一份要被處置的清單。
metadata:
  version: 1.0.0
scope: standalone
---

# check-your-own-work — 交出去之前，先對一次自己寫的東西

**這不是一道閘。** 它不回 PASS／FAIL，也不阻止任何後續動作。它產出一份 finding 清單，
而那份清單的價值完全來自**它在同一輪裡被處置掉**——一份沒有人動的報告，跟沒有報告一樣。

六問不是想出來的。它們是從 829 則真人 review 意見逆推出來的六類反覆缺陷，而其中四類
**完全不需要任何領域知識就避得掉**：它們是「我沒有把自己剛寫的東西跟自己剛寫的宣稱對一次」，
不是「我不知道這個框架怎麼寫」。

## 先把材料撈出來

```bash
bash .claude/skills/check-your-own-work/scripts/collect-self-check-inputs.sh
bash .claude/skills/check-your-own-work/scripts/collect-self-check-inputs.sh --repo <path> --base <ref> --pr <number>
```

三個參數都可以不給：repo 預設是當下的目錄，base 自己去問 `origin/HEAD`（問不到就依序試
`main`／`master`／`develop`），PR 自己去問 `gh`。**它唯讀，不對外寫入任何東西。**

它逐問印出那一問需要的輸入，**拿不到的那幾問指名說出為什麼拿不到**，最後印
`ANSWERABLE: n/6`。這一行是整支腳本存在的理由：一份只答了兩問的自檢，讀起來跟答滿六問的
一模一樣，所以它要說出自己少了哪幾問。

**答不出不是通過。** 沒有 `gh`、沒有 PR、沒有上一輪意見、這個 repo 一份規範都沒有、diff
是空的——這五種都是常態，不是錯誤，但它們各自代表「這一問沒有答案」，不代表「這一問沒事」。

## 六問

### 一、我寫下的每一句宣稱，在 diff 裡都找得到對應的改動嗎

宣稱不只是 PR 描述。commit message、changeset、註解、docstring、型別宣告、變數名——**每一句
描述性的話都是產出的一部分，不是旁白**。它對讀的人承諾了某件事，而承諾與行為是分開演化的：
先寫下承諾，做的過程中改了做法，然後沒有回頭改那句話。

沒有東西會紅。編譯器不看，測試不看，只有下一個依它行事的人會踩到。

標本：四個 PR 各自宣稱有一組 harness 檔案，那些檔案不在 diff 裡；同時各帶一個宣告某個套件
要發版的 changeset，而那個套件一行都沒動。

### 二、我碰到的這些檔案類型，這個 repo 自己的規範說了什麼

**從 repo 現場讀，不從記憶讀。** 腳本會把它找到的規範檔逐份列出來——去讀它們。

兩件事讓「憑記憶」特別危險：

- **規範會翻面。** 同一份檔案上個月說 A，這個月改成 B，而記得舊版本的人不會發現自己記錯了。
- **被違反的正好是已經寫下來的那些。** 量到的第 2 類缺陷裡，reviewer 引用的就是這個 repo
  自己的規範檔——引用它的是 reviewer，不是作者。

一份規範都找不到時，那不是「沒有規矩」，是「規矩沒有寫下來」——去讀鄰近的既有程式碼。

### 三、這個修法是不是一個 pattern

把這次的修法講成一句話，然後 **grep 整棵樹找同型的地方**，說出還有幾處、以及為什麼那幾處
不改。腳本印的「同目錄還有幾個同副檔名」是一個下界，不是答案。

「我只改了我看到的那一處」不是理由。標本：一個顯示問題的成因被作者寫進其中一個檔案的註解裡，
另外三處一模一樣的地方沒動。

### 四、我講的哪些 runtime 行為是實測的，哪些只是從源碼推的

**源碼分析是假設，不是證據。** 把這一輪講過的每一句 runtime 行為列出來，逐句標記。推的那
幾句要嘛去跑一次，要嘛在交出去的時候明講它是推的。

這一類特別會躲：build 期注入、CDN 資產、外掛的載入順序——純 grep 抓不到的載入路徑，讀源碼
會得到一個很有說服力的錯誤結論。**被挑戰的時候，把「被挑戰」當成「我很可能漏看某條執行
路徑」的高機率訊號**，先去跑一次再回應。

### 五、上一輪 review 的每一則，在現在的 HEAD 上是什麼狀態

逐則問：修掉了、還在、還是我判斷不修？**「我記得我修過了」不算**，去看現在的檔案內容。

而且處置要**回到那則意見上**。不是「有沒有處理」——是提出的人拿不拿得到那個處置。他看的是
他留言的地方，回在別處他收不到，而「還沒被回覆」跟「我還沒動手」長得一模一樣。

標本：同一個日期處理的 bug 被三位 reviewer 在三輪裡各指一次；作者說修好了之後它還在。

### 六、我新增的每一條斷言，注入一刀會不會紅

**整檔會紅證明不了每一條都在守。** 恆真的那一條躲在同一個區塊裡永遠看不到——要指名跑那
一條，而且每一條「回來的路」各注入一次，再配一個正向控制。

這次的 diff 沒有動到任何測試檔的話，**那本身就是一條 finding**：一個改了行為卻沒有任何新
斷言的交付，等著被問「那你怎麼知道它是對的」。

## 處置：這一步不做，前面六問等於沒做

每一條 finding 只有兩種結局：

- **修掉**，然後那一條就不存在了。
- **不修**，寫下一句為什麼——「這一處是刻意的，因為⋯」「這一處超出這次的範圍，另外開單」。

**兩者都沒有的 finding 存在時，這次自檢還沒跑完。** 一條被列出來然後沒有人碰的 finding，
比沒有列出來更糟：它讓這份清單看起來被處理過了。

清單要交給別人看的時候（貼進 PR、貼進討論串、寫成一份自檢結果），照
`references/report-format.md` 的段落骨架寫，第 3 段走「檢查結果」那一格。留在自己手上
邊看邊改的那一輪不必套——那個當下沒有第二個讀者。

## 它不做的事

- **不判紅、不擋人。** 沒有「不通過就不能往下」的形狀。真正該擋人的是不可逆、會出去到這個
  repo 之外、而且看 diff 的人看不出來的後果——那種東西要一道閘，不是一份清單。
- **不對外寫入。** 不送出程式碼審查、不留審查意見、不寫入任何議題追蹤或通訊系統。這支從頭
  到尾唯讀。
- **不抄任何一個 repo 的規範進自己的目錄。** 規範每次執行時從那個 repo 讀。抄下來的那一刻
  它就開始漂，而漂掉那天沒有人在看。
- **不看別人的 PR。** 主語是自己剛寫的東西。
