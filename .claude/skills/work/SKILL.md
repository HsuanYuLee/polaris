---
name: work
description: 施工 loop：在兩個閘之間探索、實作、換量測、推進輪次。沒有第三個閘，四類流轉只有「斷言錯了」會停人。
triggers:
  - "work"
  - "施工"
  - "做"
  - "繼續做"
  - "推進"
version: 1.0.0
---

# work — 兩個閘之間

前置必讀：`.claude/skills/references/spine-implementation-guidance.md`。

這裡沒有閘。派工怎麼切、實作怎麼做、試幾次、走哪條路，都在這裡，沒有人在等你交表格。
正因為頭尾兩個閘在，中間才可以很隨便。

## 接手

讀 `{source}/index.md` 就夠了——凍結塊是成功的定義，活文件是其餘一切。不需要去翻別的
artifact。

```bash
bash scripts/frozen-assertion-fence.sh verify {source}/index.md
bash scripts/spine-loop-state.sh show --state {source}/.spine/loop-state.json
bash scripts/record-measurement-change.sh show --ledger {source}/.spine/measurement-ledger.json
```

## 量測命令

第一次寫的命令要登錄 baseline：

```bash
bash scripts/record-measurement-change.sh record \
  --ledger {source}/.spine/measurement-ledger.json \
  --assertion-id A-P1 --new-command '<cmd>' --baseline
```

**量不到目標是常態，換就是了**，但換要帶三元組：舊命令 hash、新命令 hash、以及這條新命令
**在實作之前紅過**的證據。

```bash
bash scripts/record-measurement-change.sh record \
  --ledger {source}/.spine/measurement-ledger.json \
  --assertion-id A-P1 --old-command '<舊>' --new-command '<新>' --red-evidence <path>
```

紅不了的命令什麼都沒量。一個因為工具不存在而失敗的紀錄不算紅過，它只證明環境壞了。

## 四類流轉，只有一類停人

| 發現的問題 | 往哪走 |
|---|---|
| 量測方法不對 | 原地改，帶紅過證據換命令，繼續 |
| 切分不對 | 重切，繼續 |
| 斷言不對 | **停**，回 `assert` 讓人重簽 |

施工計劃那一類不存在：這條流程不分「明確施工」與「嘗試實作」。看得懂就做，看不懂就先探。

## 輪次

一輪沒產出 code 也是一輪。「試過 A，撞到 X，結論走 B，code 全丟」是正常結果——這一輪的產出
是知識，寫進活文件就是交付。不要為了讓這一輪看起來有東西，把失敗的探索包裝成交付。

```bash
bash scripts/spine-loop-state.sh record \
  --state {source}/.spine/loop-state.json \
  --outcome converged|unconverged|zero_delta --note '<一句話>'
bash scripts/spine-loop-state.sh next --state {source}/.spine/loop-state.json
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
什麼。**凍結塊不要動**——需要動它時，回 `assert`，而且改完要 commit：凍結 ＝ commit，
`verify` 會拿 fence 內文跟 git 歷史比，改了沒 commit 就是紅的，重簽也救不了。

準備受審時轉 `judge`。
