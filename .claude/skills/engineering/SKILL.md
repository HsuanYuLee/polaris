---
name: engineering
description: |
  已經有凍結的斷言、要開始或繼續施工時的站。兩個閘之間的 loop：探索、實作、換量測、推進輪次。這裡沒有閘。

  某張單的斷言已經凍結，接下來要動手做的時候，或剛從 refinement 交出來。

  也用於：跨 session 接手一張做到一半的單——讀凍結塊與活文件就能接上。

  不用於：還沒有斷言的工作、要判這次算不算達成（走 verify-ac）、
  決定下一站是哪一站（走 driving-work-to-done）。
metadata:
  version: 3.0.0
  requires:
    - skill: driving-work-to-done
      why: 輪次與停點由它保管；換站與停哪一種也只有它回答
scope: universal
---

# engineering — 兩個閘之間

這裡沒有閘。派工怎麼切、實作怎麼做、試幾次、走哪條路，都在這裡，沒有人在等你交表格。
正因為頭尾兩個閘在，中間才可以很隨便。

## 接手

讀 `{issue}/index.md` 就夠了——凍結塊是成功的定義，活文件是其餘一切。不需要去翻別的
artifact。

```bash
bash .claude/skills/engineering/scripts/frozen-assertion-fence.sh verify {issue}/index.md
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh show --state {issue}/.spine/loop-state.json
bash .claude/skills/engineering/scripts/record-measurement-change.sh show --ledger {issue}/.spine/measurement-ledger.json
```

## 量測命令

第一次寫的命令要登錄 baseline：

```bash
bash .claude/skills/engineering/scripts/record-measurement-change.sh record \
  --ledger {issue}/.spine/measurement-ledger.json \
  --assertion-id A-P1 --new-command '<cmd>' --baseline
```

**量不到目標是常態，換就是了**，但換要帶三元組：舊命令 hash、新命令 hash、以及這條新命令
**在實作之前紅過**的證據。

```bash
bash .claude/skills/engineering/scripts/record-measurement-change.sh record \
  --ledger {issue}/.spine/measurement-ledger.json \
  --assertion-id A-P1 --old-command '<舊>' --new-command '<新>' --red-evidence <path>
```

紅不了的命令什麼都沒量。一個因為工具不存在而失敗的紀錄不算紅過，它只證明環境壞了。

**量不到要說出來，不能回綠。** 負向的量測天生會把「我沒看到」讀成「它沒發生」——掃到 0 個
檔案、找不到那棵樹、正則對上 0 次，這些在輸出上跟「掃過了，沒問題」長得一模一樣。所以每條
量測前面要有一個 preflight：目標在不在、樣本數夠不夠。**preflight 不過就用另一個 exit code
停下來**（慣例是 2＝量不到、1＝量到了而且是紅的、0＝綠），不要讓它走進判定。

**自己剛寫的檢查第一次就綠是可疑訊號**，通常代表規則太窄。落地之前先餵它一份已知壞掉的
輸入，確認它真的會紅。

## 在這裡發現問題，先自己解

| 發現的問題 | 怎麼辦 |
|---|---|
| 量測方法不對 | 原地改，帶紅過證據換命令，繼續 |
| 切分不對 | 重切，繼續 |
| 斷言不對 | 不是這一站能解的——回 `driving-work-to-done` 讀該停哪一種 |

施工計劃那一類不存在：這條流程不分「明確施工」與「嘗試實作」。看得懂就做，看不懂就先探。

## 輪次

一輪沒產出 code 也是一輪。「試過 A，撞到 X，結論走 B，code 全丟」是正常結果——這一輪的產出
是知識，寫進活文件就是交付。不要為了讓這一輪看起來有東西，把失敗的探索包裝成交付。

```bash
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh record \
  --state {issue}/.spine/loop-state.json \
  --outcome converged|unconverged|zero_delta --note '<一句話>'
```

連續沒收斂到上限時流程升人類，不繼續自轉。上限是活區可調的參數，不是驗收條件。

## 三件要浮出來的事

方法自由，但有三件事 oracle 照不到，即使做了會變綠也要寫進活文件並講清楚為什麼，等人回話：

- **新增依賴**：把一個新套件拉進來。
- **重造既有組件**：手寫一個 repo 裡已經有的東西。
- **擴大 security surface**：多開一個對外介面、多讀一份憑證、多信任一個輸入。

共同點是後果落在綠燈之外——測試會過，代價在別的地方。

## 交出去

活文件寫到讓下一個人（可能是明天的你）能接手：現在在哪、試過什麼、為什麼走這條、下一步是
什麼。**凍結塊不要動**——需要動它時，回 `refinement`，而且改完要 commit：凍結 ＝ commit，
`verify` 會拿 fence 內文跟 git 歷史比，改了沒 commit 就是紅的，重簽也救不了。

這一輪做完，回 `driving-work-to-done` 讀下一步——換站與停點都由那裡回答，這一站不自己決定
往哪走。

### 送審之前，把自己寫下的話跟自己寫下的行為對一遍

**你寫下的每一句描述性的話都是產出的一部分，不是旁白。** 它對讀的人承諾了某件事，而承諾
與行為是分開演化的：先寫下承諾，做的過程中改了做法，然後沒有回頭改那句話。兩者從此各說
各話，而看起來完全正常——沒有東西會紅。

oracle 照不到這一類，因為量測量的是行為，不是描述行為的那句話。所以它只能自己讀一遍。
成本很低：**送審前把這一輪寫過的描述掃過去，一句一句問「這句現在還是真的嗎」。**

在描述裡承認一個邊界情況，就要追它到底——「這裡可能是空的」寫得出來，就要回答「那誰會
收到這個空的」。修掉眼前那個症狀不等於處理掉那個事實。

2026-08-07 的標本：外部審查開了五條意見，四條成立，而**沒有一條是知識缺口**，全部是同一
個形狀——我寫下的一句話跟我寫下的行為對不上。其中最嚴重的那條，我在同一個檔案裡就寫著
「這裡可能是空的」，只在其中一條路上處理掉，沒有跟著那個值往外追一步。

### 送審之前，先讓證據跟得上 head

`verify-ac` 的交付紀錄會逐條檢查：fence 宣告的每個斷言 ID 都要有 `verdict: PASS` 的證據，
而且**證據綁的 head 要等於要交付的那個 head**。證據證的是一棵樹綠了，不是一條分支綠了；
量完之後又推了三個 commit，那些證據就跟要出去的東西無關了。

所以順序是：**code 全部 commit 完 → 才跑量測 → 才送審**。反過來做，verify-ac 會把你打回來
重量一次。
