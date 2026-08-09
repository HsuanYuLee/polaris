---
name: refinement
description: |
  流程的第一站，也是第一個閘：把「怎麼算成功」談成人簽得下去的斷言，凍結起來。由 driving-work-to-done 在判定要立案之後帶進來。

  driving-work-to-done 判定一件事要立案、而現場還沒有對應的單時。

  也用於：既有單的成功定義本身錯了，停 `assertion_wrong` 之後回來重簽。

  不用於：判斷「這件事要不要立案」——那在 driving-work-to-done。
metadata:
  version: 3.0.0
  requires:
    - skill: driving-work-to-done
      why: 輪次狀態由它保管（spine-loop-state.sh init/advance）；沒有它，斷言簽完沒有地方記
scope: standalone
---

# refinement — 閘一：凍結斷言

這一站只做一件事：把成功的定義變成**人簽得下去**的斷言，鎖起來。

鎖起來之後，做法怎麼變都不用回來問人；只有成功的定義本身錯了才需要回到這裡重簽。

**要不要立案的判斷不在這裡**，在 `driving-work-to-done`。走到這一站表示那個判斷已經做過
而且說出來了。

**手上正在做別的事、但長出了一個不能消失的東西時，不要走完這一整站。** 開一張種子單，
記下前因後果就好，然後回去做原本那張：

```bash
bash .claude/skills/refinement/scripts/open-seed-issue.sh \
  --issues issues --namespace <命名空間> --slug <名字> --note '<前因後果>'
```

它建目錄、寫下前因後果、記一個「還沒簽斷言」的狀態、commit，然後就結束——**不簽斷言、
不決定領域、不開 worktree**。那些是接手的人在這一站要做的事，而那時候才有人真的想過怎麼
算成功。種子單會出現在 `next --across-issues` 的答案裡（標成 `seed:`），所以它拿得給另一個
session 開工。

接手一張種子單就是從這一站的第一步開始走，走到 `init`——`init` 認得它身上那個種子狀態，
會把它升級成真的輪次並說出來，不需要先手動刪掉任何東西。

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
框架，這裡的內容完全不一樣。空殼由這一站自己帶著——它在這支 skill 的
`templates/issues/` 底下，跟 skill 一起搬走。第一次使用時：

```bash
R=.claude/skills/refinement
mkdir -p issues
cp $R/templates/issues/README.md issues/README.md
cp $R/templates/issues/gitignore.example issues/.gitignore
git -C issues init
git -C issues add . && git -C issues commit -m "issues: 開始"
```

它仍然必須是一個 git repo——理由見下方〈凍結 ＝ commit〉。`verify` 從檔案自己的路徑解析
repo，會自動跟著 `issues/` 進它自己的歷史，不需要告訴它。

凍結塊與活文件同檔——一個工作被迫產生的東西是這一份與 code，純文件類的只有這一份。這是
設計意圖，不是一個被量的門檻：那幾個檔案是流程自己寫的，數量恆定，對常數設門檻只會是儀式。
交付時被真的判定的是「舊層還撐著沒有」，見 `verify-ac`。

## 問出只有人知道的事

斷言簽的是「怎麼算成功」。但有幾件事同樣只有人回答得出來，而且它們決定**斷言本身寫得對
不對**：這一版到底要做什麼、什麼時候要、提出的人真正想解決什麼、拿什麼測。

**單裡寫的「這一層不用改」「維持現狀」「out of scope」是待證主張，不是事實。** 那是提單的
人當時的推測，而範圍抄錯的代價要到判定那一站才看得到。定範圍之前實跑一次去驗它——證實了就
寫進去並註明驗過，證偽了就把它拉回範圍內。直接抄進斷言等於把別人的假設簽成自己的定義。

**沒問的那一刻不會停下來，會自己填一個。** 那比空著糟：空著看得出來，填過的看不出來。
而判定那一站只驗實作有沒有達成那份斷言——斷言若照著一個編出來的意圖寫，整條流程會全綠地
交付錯的東西。

### 交一份草案，不交一串問題

**這一站處理的是整張工作，不是一條 AC。** 一張單裝得下一整個 Epic——同一份 `{issue}/index.md` 裡
可以有好幾組具名的凍結塊（`A`、`B`、`C`…），各自蓋封條、各自驗。所以先把整張讀完、消化
成一份計劃，不要讀一段簽一段。

然後**交一份填好的草案出去，讓人在草案上改**：

- **每一格都先填。** 查得到的自己查（`git log` 知道誰動過這塊，`package.json` 知道怎麼跑
  測試），推得出來的先推一版。把自己查得到的東西做成問題，是把判斷推回去——而這個 repo
  的規矩是〈有標準就直接套，提一個方案〉。
- **標好每一格是誰給的。** `source` 就是「事實」與「決策」的分界，它不需要靠問答活著：
  `environment` 是我查來的、`inferred_confirmed` 是我推的等你點頭、`human` 是只有你知道
  的，我把我需要什麼寫在那一格裡等你填。
- **人改草案，改完就是定版。** 不是一問一答再拼起來。對一張十幾條 AC 的 Epic，逐題問是
  幾十輪往返，而每一輪的回答都比不上直接在草案上劃掉一行。

### 答案寫在哪

寫進 `{issue}/index.md` 的 frontmatter，跟 `destination` 同一個地方：

```yaml
plan:
  what: { answer: "…", source: inferred_confirmed }   # 推一版、人點頭
  when: { answer: "…", source: human }                # 什麼時候要
  why:  { answer: "…", source: human }                # 想解決什麼
  how:                                                # 拿什麼測
    answer: "本機起後台 + mock 掉上游 API"
    source: human
    environments: [admin-console, upstream-api-mock]
```

`source` 三種：`human`、`environment`（查出來的）、`inferred_confirmed`。
**這張單真的不需要某一項時，明講並說為什麼**——空著與不適用是兩件事：

```yaml
  when: { not_applicable: "框架自用，一單一版隨時釋出，沒有外部時程" }
```

**`how` 要多帶 `environments`。** 「要起哪些東西」寫在句子裡沒有人讀得懂；列出來之後，
「哪個環境還沒有人會起」就算得出來——而那正是〈有些答案每張單都一樣〉在講的訊號。真的
不需要起任何東西就寫 `environments: none`：**那是一個答案，不是欄位不見。**

```bash
bash .claude/skills/refinement/scripts/check-plan-answers.sh {issue}/index.md
```

**這一步在 seal 之前跑。** 凍結的那個 commit 落下去之後才發現缺，那個 commit 已經在那裡了。

### 有些答案每張單都一樣

「測試環境怎麼起」「owner 是誰」「推不出來時去哪裡問」「部署到哪裡測」——這些對同一個
repo 的每一張單答案都相同。**它們不進單，進那個 repo 的領域知識。** 塞進每一張單等於每次
重問一次同樣的東西，而重複的儀式會被學會跳過。

**什麼時候知道該生一份？計劃自己會說。** `environments` 列出來的每一個，都要有某一份領域
知識宣告它會起它：

```
<!-- {任意前綴}-ENVIRONMENT-{環境名}: {起它的命令} -->
```

`check-plan-answers.sh` 掃所有 skill 的 `SKILL.md` 找這一行。**找不到的那個環境，就是該
沉澱的那一份。** 這件事在凍結之前就說得出來，那時候計劃還改得動——比簽完斷言、開輪次時
才撞 `POLARIS_SPINE_PACK_UNRESOLVED` 早一站。

生的時候用上面同一套做法：先讀、先推、交草案、人改。**宣告的命令要真的跑得起來**——一份
沒被執行過的知識跟沒有知識一樣安靜，差別只在它看起來很完整。核心不認得鍵名也不認得環境
名，前綴由那份知識自己定。

`init` 指名的領域知識不存在時，殼也會拒絕開輪次，訊息會指回這裡。那是同一件事的第二道
網——不是第二個判準。

## 問到這條流程以外去

推不出來的困難總會出現，唯一的解法是去問一個人。**訊息送出去是不可逆的**，所以順序是
擬稿 → 人看過 → 才送：

```bash
bash .claude/skills/refinement/scripts/record-outreach.sh draft \
  --issue {issue} --id <slug> --to '<哪裡>' --body '<擬稿全文>'
bash .claude/skills/refinement/scripts/record-outreach.sh confirm \
  --issue {issue} --id <slug> --by <人> --quote '<那個人自己說的話>'
# 送出（用你手上的工具），然後：
bash .claude/skills/refinement/scripts/record-outreach.sh sent --issue {issue} --id <slug> --link <URL>
bash .claude/skills/refinement/scripts/record-outreach.sh reply --issue {issue} --id <slug> --body '<回覆>'
```

**送出動作本身腳本攔不到**——那是別的工具做的。它攔得住的是紀錄：沒有人的原話就記不下
送出，而一個留不下紀錄的動作，事後看起來就是沒發生。回覆寫回來之後它是活文件的一部分，
下一個人不用再問一次同樣的問題。

## 斷言長什麼樣

**陳述句，不是要求句。**「當 X 時，Y 發生」可以被注入情境驗證；「應該要有 X」不行。

**正負兩表都要有。** 只有負向表列時，「什麼都不做」可以拿滿分；只有正向表列時，副作用
沒人管。負向表列不定義成功，它圈出即使達標也不接受的做法。

**只寫意圖，不寫儀器。** 斷言承載意圖鎖死，量測是斷言的代理放開。把「用哪支腳本、閾值
多少」寫進凍結區是分層錯誤——那些東西在活區，會換。

**指名一個會吃輸入的東西時，要說出那組輸入。**「當 X 時，Y 發生」裡的 X 常常不是一個值，
是一整組——而漏掉的那幾種不會被量到，因為量測只做斷言叫它做的事。所以斷言裡要出現「哪幾
種」，不是留給施工的人自己挑一個最順的。

這不是在寫儀器：「排序欄位被清空時送出什麼」是意圖，「用哪支測試框架填空字串」才是儀器。
判準是**列不出三種通常就是還沒想過**——一個吃使用者輸入的東西至少有「空的、超出範圍的、
型別不對的」，一個吃回應的東西至少有「缺欄位的、空集合的、錯誤碼的」。

2026-08-07 的標本：一條斷言寫「送出的排序與內容跟畫面一致」，而「一致」只在一個合法值上
被量過。清空輸入欄位那一種從來沒進過斷言，於是十六條斷言全綠、交付紀錄寫成、流程判定
通過，而送出去的是一個空字串。**沒有任何一站做錯自己的事**——那正是這條要擋的形狀。

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
# 1. 只有人知道的那幾項都有答案了（見〈問出只有人知道的事〉）。缺項就不要往下蓋封條——
#    凍結的那個 commit 落下去之後才發現缺，那個 commit 已經在那裡了。
bash .claude/skills/refinement/scripts/check-plan-answers.sh {issue}/index.md

# 2. 蓋封條（算的是 fence 內文，寫封條本身不會讓它失效）
bash .claude/skills/refinement/scripts/frozen-assertion-fence.sh seal {issue}/index.md --by {簽的人}

# 3. commit —— 這一步才是凍結
git add {issue}/index.md && git commit -m "freeze: {issue} 斷言"

# 4. 隨時可重算比對（預設就會與 git 歷史比，不需要參數）
bash .claude/skills/refinement/scripts/frozen-assertion-fence.sh verify {issue}/index.md

# 5. 開輪次。領域的決定是這一步的一部分，不是之後補的欄位——「這件工作屬於哪個領域」
#    沒被回答就往下走，等於流程不知道它要滿足什麼條件。
#    --where 是「這張單的改動會落在哪些地方」，一個地方給一次；它不是「我現在站在哪」。
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh init \
  --state {issue}/.spine/loop-state.json --pack swe-knowledge \
  --where <工作區路徑> [--where <另一個>]...
#    不改程式碼的工作（報告、調查、文件、資料分析）要說出理由：
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh init \
  --state {issue}/.spine/loop-state.json --pack none --why '<為什麼這件工作沒有領域完成條件>'
```

**落腳處要在這一站問出來。** 一張單住在 `issues/` 而程式碼落在某個產品 repo 是常態，而
「落在哪」只有提單與施工的人知道——它跟計劃那四格一樣，是別人回答不了的東西。細節（怎麼
記、怎麼比、下游怎麼讀）寫在 `driving-work-to-done`〈載入領域知識〉，這裡不抄第二份。

**`init` 會跑該領域宣告的開工條件，不成立就不開輪次。** 條件是什麼**這裡不說**——它寫在
那個領域自己的知識裡，寫在這裡就是第二份。拒絕的訊息會說出缺的是哪一條、怎麼修，照著做
再跑一次就是了。

所以第 2 步之前先跑一次 `init` 是划算的：條件沒滿足的話，凍結的那個 commit 會落在一個
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
