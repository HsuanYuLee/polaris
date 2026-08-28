---
name: verify-ac
description: |
  施工告一段落、要判這次到底算不算達成時的站。跑硬化 oracle 給出會擋人的機械判定，另出不擋人的判斷報告，兩者分開。流程的第二個關卡，也是最後一個。

  某張單做到一個段落，要驗收的時候。例如「驗收一下」「這樣算完了嗎」「跑一次判定」
  「可以出貨了嗎」，或剛從 engineering 交出來。

  判 PASS 之後也在這裡寫交付紀錄，供釋出尾段讀。

  不用於：還在做、只是想跑個測試看看（那是 engineering 的量測）、
  決定下一站是哪一站（走 driving-work-to-done）。
metadata:
  version: 3.0.0
scope: universal
tools:
  - name: jq
    provision: framework
    why: selftest 讀 JSON 輸出裡的欄位
    install: mise:aqua:jqlang/jq
---

# verify-ac — 第二關：執行 oracle

輸出有兩部分，權力不一樣：**機械判定會擋**（由 exit code 承載，不需要讀者同意）；
**判斷報告不擋**（帶引用的意見，由人裁）。把兩者混在一起，關卡就會開始擋一些沒人能精確
定義的東西，然後大家學會繞過它。

## 機械判定：三件事

```bash
# 1. 斷言沒被動過。這一步同時查兩件事：校驗值與內文對得上，且內文與 git 歷史一致。
#    對不上就停——這時審查根本還沒開始，因為成功的定義變了。
bash .claude/skills/verify-ac/scripts/frozen-assertion-fence.sh verify {issue}/index.md

# 2. 手上這條量測命令是登錄過的。換過而沒帶紅過證據的命令不被承認。
bash .claude/skills/verify-ac/scripts/record-measurement-change.sh verify \
  --ledger {issue}/.spine/measurement-ledger.json \
  --assertion-id A-P1 --command '<cmd>'

# 3. 跑量測。同時看 exit code 與正向證據——exit 0 而沒有正向證據不是通過。
bash .claude/skills/verify-ac/scripts/run-hardened-oracle.sh --command '<cmd>' \
  --require-tool rg --expect-evidence '<真的量到東西的痕跡>' \
  --evidence-out {issue}/.spine/evidence/<assertion-id>.json
```

任一項不成立就是非 PASS，沒有討論空間。

**一條命令被好幾條斷言共用時，用 `--assertion` 分組，一趟就產出全部證據**：

```bash
bash .claude/skills/verify-ac/scripts/run-hardened-oracle.sh --command '<cmd>' \
  --assertion A-P1 --expect-evidence '<A-P1 自己的痕跡>' --evidence-out {issue}/.spine/evidence/A-P1.json \
  --assertion A-P2 --expect-evidence '<A-P2 自己的痕跡>' --evidence-out {issue}/.spine/evidence/A-P2.json
```

命令只跑一次，每一組在同一份輸出上**各自判、各自寫**——不是把同一個判定複製 N 份，那會讓
「這條斷言真的被檢查過」變成假的。一組沒有自己的輸出路徑、或兩組指到同一個檔案，它會停。

`run-hardened-oracle.sh` 會先探工具能力再釘住、要求命令產出證明自己量到東西的輸出、
並原樣保留 stderr 與 exit code。這是因為工具會說謊：PATH 上較早的 shim、靜默跳過的測試、
被吞成 generic timeout 的錯誤，三者都能讓一個空的執行看起來像綠的。

## 現在過了幾條

上面那三件事是一條斷言一條斷言做的。要問「這張單十三條裡現在過了幾條」，跑這一支：

```bash
bash .claude/skills/verify-ac/scripts/report-assertions.sh --issue {issue}
bash .claude/skills/verify-ac/scripts/report-assertions.sh --issue {issue} --rerun
```

**它唯讀，而且不宣稱任何事。** 它不寫檔案，也不留下任何下游拿得去當證據的東西——判「這張
單能不能出貨」的仍然只有交付紀錄。有兩個地方能宣稱 PASS 的話，它們遲早會給出不同的答案。

它印三種判定，而且三種都印：**過、沒過、量不到**。量不到不是通過的溫和版本，它是第三種
——一個安靜的第三態，下一次就會被當成查過了。它做到第幾層也印（見下面那張表），因為一份
沒說自己做到第幾層的報告，讀起來永遠像做滿了。

逐條判定那段程式住在 `scripts/lib/assertion_verdicts.py`，報告與交付讀的是同一份。抄成
兩份的話，「報告說過了」與「交付說不行」會同時是對的，而沒有人有辦法說出哪一份錯。

## 舊層還撐著沒有

問的是：這張單走完全程，有沒有哪一步非得靠主流程要取代的那套東西（task.md、
completion-gate marker、auto-pass ledger、verify report）才走得完。

**不用自己跑，交付紀錄那一步會跑。** `record-delivery-intent.sh` 會枚舉這張單逼出了哪些
檔案、把清單餵進檢查，非 0 就不寫紀錄。想先看的話：

```bash
bash .claude/skills/verify-ac/scripts/enumerate-spine-inventory.sh --issue {issue}
bash .claude/skills/verify-ac/scripts/check-spine-legacy-layers.sh --inventory {issue}/.spine/inventory.json
```

清單用枚舉的，不是手寫的——手寫的清單由寫的人決定漏掉什麼，然後檢查就在那個漏掉的地方
變綠。它從 git diff 與 `.spine/` 現況兩處讀，兩處都不能被說服。

**「逼出幾個檔案」這個數字只印出來，不判定。** 那三個檔案是主流程自己寫的，數量恆定，對一個
常數設門檻只會是儀式。這件事 2026-08-03 才被拆掉：門檻設在 2、實際恆為 3，於是它對每一張
真單都是紅的——而因為沒有人呼叫它，紅了幾個月沒有人知道。

## 正負兩表都要驗

只有反例的驗證，一個永遠回 FAIL 的審查端也會全綠。正例要能證明**真達標的交付確實被判
PASS**，反例要能證明**被注入問題的交付確實被擋**。兩向都跑。

## 驗證強度分三層

不可以一律降到最弱那層。「一律靜態檢視」看起來省事，實際上是把可以被證偽的東西降級成不能
被證偽的東西。

| 強度 | 適用對象 | 方法 |
|---|---|---|
| 可注入 | 會被機械執行的部分 | 刻意構造情境，觀察結果 |
| dogfood 觀察 | loop 行為 | 跑真工作記錄，樣本薄就如實標示 |
| 靜態檢視 | 只能是散文的部分 | 讀指定段落，判斷條件是否成立 |

## 判斷報告

處理只能是散文、無法被執行的部分。結論一律引用具體 `path:line`——沒有引用的斷言在報告裡
沒有份量。

報告不產生 PASS / FAIL，它產生的是「我讀了這段，依據是這幾行，我的判斷是這樣」，交給人決定。

**不得為了遷就交付的東西而放寬斷言。** 證據構不到斷言時，那是實作沒走到，不是斷言寫錯了
——斷言承載的是人簽過的意圖，而在判定這一站把它調鬆，等於自己改掉自己要對照的那把尺。
真的是斷言本身錯了，處理是停 `assertion_wrong` 回第一關重簽，那會留下一個有人看得到的
commit；就地放寬不會。

dogfood 觀察的樣本通常很薄，而且觀察者往往同時是被觀察者。這不使結論無效，但它使結論不是
統計證據。如實標示樣本數與觀察者身分，不要把「跑過一次」寫成「已驗證」。

## 讓別人看得到：報告與清單

判定的價值在於**別人能核對**，而上面那一支只印到終端——一份沒有人看得到的判定，跟沒有判定
的差別只有磁碟空間。

```bash
bash .claude/skills/verify-ac/scripts/render-evidence-report.sh --issue {issue}
bash .claude/skills/verify-ac/scripts/render-evidence-report.sh --issue {issue} --publish
```

**量完之後又落了 commit 的時候。** 證據綁在它量到的那個 head 上，而交付之前常常還會有東西
落下去——單自己的散文、`.spine/` 底下的紀錄。那時候直接跑會逐條判「量在 X，要交付 Y」，
報告尾巴還會多一行 BLOCKER。**那不是判定壞掉，是沒有人說過那段差異碰了什麼：**

```bash
bash .claude/skills/verify-ac/scripts/render-evidence-report.sh --issue {issue} \
  --head <要交付的 head> --delta-allows issues/ --delta-allows {issue}/
```

`--delta-allows` 可以給很多次，每次一條路徑前綴。**它驗證你的主張，不代你宣告**：那段差異
真的只碰了指名的路徑才放行，碰到別的就逐條判 FAIL 並指名是哪幾個檔案，兩個 commit 沒有樹
看得到就判 unmeasurable——問不到不放行。所以它擴不出「把整棵樹指名進去就全過」這種用法，
指名整棵樹的人自己會在報告上看到那段差異碰了什麼。

**沒有 `--head` 就沒有那段差異可言**，所以只給 `--delta-allows` 會被拒絕。

它產兩個檔案，因為讀的人有兩種：`report.md` 給人看，`manifest.json` 給機器讀（逐條的判定、
綁的 head、量測命令、要跟著一起送出去的檔案）。要一起送圖之類的東西，把它們放進
`{issue}/.spine/attachments/`——一個目錄的存在與否就是答案，不需要多一個設定。

**它唯讀，而且不判定成敗。** 讀的是已經被 oracle 判定過的東西，只是把它排版；不寫輪次
狀態、不寫交付紀錄、不碰證據，也不成為第二條可以宣稱 PASS 的路徑。

**有東西沒過照樣產得出來。** 最想看報告的那一刻，正是有東西沒過的那一刻——所以離場碼說的
是「產不產得出來」，不是「過了沒」。

### 送去哪，這裡不知道

`--publish` 掃所有 skill 找一行宣告，找到就把那兩個檔案原樣交給它，由它決定怎麼送：

```
<!-- {任意前綴}-EVIDENCE-PUBLISH-{命名空間}: {命令} -->
```

**這一層不認得任何一個目的地**，跟它不認得釋出尾段叫什麼名字是同一個理由：一旦這裡指名某
一種外部系統，這四支 skill 就搬不到沒有那個系統的地方了。

沒有人宣告那個命名空間時它**說出來並指名是哪一個**，報告留在本機，離場碼 4——那不是壞掉，
是一個要人回答的問題。不沿用別的命名空間的宣告，也不猜一個目的地。

**發佈不是關卡。** 送不出去要吵、要留下紀錄，但一條斷言的判定不會因此改變：判定由 oracle
決定，發佈是那個判定的投影。一次逾時不得把一份綠的交付變成紅的。

## 判 PASS 之後：交出去

判定通過不等於交付。釋出尾段要的是一份它讀得動的紀錄，不是一句「verify-ac 說 PASS」：

```bash
bash .claude/skills/verify-ac/scripts/record-delivery-intent.sh \
  --issue {issue} \
  --summary '<一句話，說出交付了什麼>'
```

**版本不在這裡，連欄位都沒有。** 有些專案的交付是一張單與一次部署，沒有 patch / minor /
major 可以宣告。留一個「可以不填」的格子仍然是在教一套詞彙——只下載了這一支的人不會知道
那個格子是給誰看的，而它只對某一條釋出尾段有意義。

所以版號整件事住在釋出尾段，宣告源是那條尾段本來就會讀的東西。這一站不宣告、不轉述、
不留欄位。

它會先重驗 fence 才寫。斷言被動過的單記錄不了交付意向——對著一份沒人簽過的成功定義
出貨，比不出貨糟。

接著它逐條檢查 fence 宣告的每個斷言 ID。證據的可信度分三層，**交付這條路三層全做**：

| 層 | 問的是 | 少了它，什麼東西過得了 |
|---|---|---|
| 檔案自洽 | 有沒有 `{issue}/.spine/evidence/{ID}.json`、`verdict` 是不是 `PASS`、`producer` 是不是 `run-hardened-oracle.sh`、每一條是不是量在同一棵樹的同一個 commit | 什麼證據都不用，「verify-ac 說 PASS」一路靠散文帶著走 |
| 登錄相符 | 證據記的那條命令，是不是這條斷言在量測登錄裡簽過的那一條 | 一份手寫的證據可以自己指名一條「一定會過」的命令 |
| 重跑一次 | 拿那條命令現在再跑一次，還綠不綠 | 前兩層讀的都是檔案，而一個檔案的內容是誰寫的它自己說了算 |

同一條命令通常被好幾條斷言共用，所以重跑會去重。**去重的鍵不只是命令，是決定那一趟重跑
的全部東西**：命令、在哪棵樹跑、要求出現什麼、要求不出現什麼、要哪些工具。八條斷言共用一
條命令而每一條要求不同的證據樣式，那就是八個不同的鍵、跑八次。

鍵漏掉樣式的話，第二條斷言會拿到第一條的答案，而它自己的樣式從來沒有被檢查過——**一條沒被
量到的斷言看起來就跟過了一樣**。所以這個鍵不會為了省時間而放寬。

要估時間就照這條規則數，不要照命令數。2026-08-27 有一張單 21 條斷言共用一條命令、各帶各的
樣式，照「命令」算是 1 趟、實際 21 趟——差出來的形狀是一個兩分鐘的逾時。**重跑那一步在跑
第一趟之前會把趟數印出來**，不用自己數。

**登錄檔在，就每一條斷言都要在裡面。** 「這條沒登錄過」不是豁免，那正好是一份手寫證據會長
的樣子：它指名一條沒有人簽過的命令。

### 這一層擋得住什麼、擋不住什麼

**擋得住**：手寫一份自洽的 JSON。`producer` 抄對了，命令沒登錄過；命令抄成登錄過的那一條，
重跑就是紅的。

**擋不住**，逐條說出來：

- **一個能在同一棵樹上執行任意命令的施工端。** 它可以把量測命令本身換成一條永遠會過的
  命令，然後三層全綠。擋這件事的不是這裡，是登錄那一層要求換命令必須帶「實作之前紅過」的
  證據，而登錄與那份證據都在 git 歷史裡——偽造得留下一個有人看得到的 commit。
- **一條從第一天就量不到目標的命令。** 它一直是綠的，紅控從來沒發生過。擋它的是 engineering
  登錄 baseline 時的紀律，不是這裡。
- **散文那一半。** 判斷報告不歸這三層管，它本來就不擋人。

所以這三層不是證明。它做的是把偽造的成本從「寫一個 JSON 檔」提高到「改一條登錄過的命令，
而那個改動會出現在 diff 裡」。**不要把它說成擋得住所有偽造**——一個宣稱自己滴水不漏的檢查，
會讓下一個人不再看 diff，而那正是它真正靠著的東西。

**證據量在哪棵樹，用 `--cwd` 指名，不要靠命令自己 `cd` 進去。** 這兩件事看起來一樣，
結果不一樣：`run-hardened-oracle.sh` 的 `head_sha` 與量測所在都從**它讓命令跑起來的那個
目錄**取，而那個目錄由 `--cwd` 決定。命令字串裡自己 `cd` 進產品 repo 的話，那個目錄仍然是
你站的地方——量測本身跑對了，記下來的 head 卻取自另一棵樹。

**那份紀錄看起來完全正常**，而它綁的 commit 跟這張單的產出無關：那棵樹上任何人壓一次版，
同一批證據就分屬兩個 head，交付紀錄因此寫不成，要整批重量。所以：

```bash
bash .claude/skills/verify-ac/scripts/run-hardened-oracle.sh --command '<cmd>' \
  --cwd <這張單的改動真的落下去的那棵樹> ...
```

**`--cwd` 一換，命令裡的相對路徑就跟著換基準。** 量測腳本常常住在單裡，而單住在
`issues/`——用一條相對框架 repo 根的路徑去叫它，`--cwd` 指到產品的樹之後那條路徑就不存在了
（實測 `exit 127`）。**改成絕對路徑不是出路**：登錄那一步會擋下抄了這台機器路徑的命令
（`POLARIS_MEASUREMENT_COMMAND_CARRIES_A_PATH`）。

那道拒絕自己就寫著出路——**單的目錄問 `spine-loop-state.sh find`**。它從當下位置往上找
`issues/`，所以在產品的工作樹裡也答得出來：

```bash
--cwd <那棵樹> \
--command 'bash "$(... spine-loop-state.sh find <單名> | tail -1)/verify/verify.sh" A-P1'
```

三種都不適用時才用 `--exempt-path` 與 `--exempt-why` 具名寫進登錄。

寫交付紀錄那一步會把證據記的樹跟這張單宣告的落腳處比一次，對不上就停
（`POLARIS_DELIVERY_INTENT_TREE_NOT_LANDING`）。**一張單宣告了不只一棵樹是允許的**，
落在其中任何一棵都算數。兩邊有任何一邊答不出來時它說出是哪一邊沒問到，不當成相符。

**交付的 head 從證據來，不從你站的地方來。** 一張單住在 `issues/`、程式碼落在某個產品
repo 是常態，兩棵樹的 head 不一樣；問當下的位置只有在兩者剛好重合時才對，而它答錯的時候
長得跟答對一模一樣。量完之後那棵樹又有新 commit 落下去的話它會擋——那一條是回頭問證據
自己記下的那棵樹現在在哪，不是問你在哪。真的要指定就用 `--head`。

`destination` 決定去哪：`workspace` 留在本地，`template` 才進 Polaris template repo。那是
第一關由人宣告的，這裡只讀不改。

紀錄寫完，這一站就結束了。之後怎麼出貨**不在這條流程裡**——釋出尾段是每個專案自己的事，
它讀這份紀錄，而這一站不需要知道它叫什麼名字。這是刻意的：一旦這裡指名某支釋出腳本，
這四支 skill 就搬不到沒有那支腳本的地方了。

**把判定結果帶回 `driving-work-to-done`**——PASS 之後要不要
推站別、非 PASS 要回哪一站、原因是實作沒到還是斷言本身錯了該停哪一種，都在那裡回答，
不在這裡。這一站產出的是判定，不是下一步。

<!-- PROSE-EXTERNAL-PATHS: report.md — 跑起來才長出來的東西，落在那張單的 .spine/report/ 底下（單住在別的 repo） -->
<!-- PROSE-EXTERNAL-PATHS: manifest.json — 同上，跟 report.md 同一次產出 -->
<!-- PROSE-EXTERNAL-PATHS: docs-manager/ — 動手對象：那是 specs 站台自己的 repo，這支 skill 往它寫東西、讀它的結構，不是我們抄一份放著的知識 -->
