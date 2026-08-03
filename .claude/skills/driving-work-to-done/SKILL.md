---
name: driving-work-to-done
description: >
  把一件工作從「有人說了一句話」帶到「judged 過的交付」：先判斷要不要立案，再決定現在
  該在 refinement / engineering / verify-ac 哪一站、什麼時候換站，載入說明「這類工作怎麼算
  done」的知識，然後一路推進到收斂或撞上四種已宣告的停點之一。任何會改變程式碼或行為的
  請求都從這裡進，使用者不需要知道這個名字。唯讀的查詢與說明不走這裡。
when_to_use: |
  有人帶著一件要做的事出現時的第一站，不論他有沒有說出任何指令名稱。例如
  「幫我做 X」「這個壞了要修」「想重構 Y」「繼續」「接著推」。

  也用於：不知道現在在哪、不知道下一步是什麼、手上有多張單不知道先做哪一張。

  不用於：唯讀的查詢與說明（「這支腳本在幹嘛」「查一下 X」）——那些沒有「怎麼算成功」
  要簽，直接回答。
version: 1.0.0
---

# driving-work-to-done — 一件工作、一個入口、一個下一步

三支 skill 各做一站的事：`refinement` 簽下成功的定義，`engineering` 施工，`verify-ac`
判定。**它們都不決定下一步是什麼**——那寫在這裡，只寫在這裡。

一份工作有兩種成功條件，它們住在不同地方：

- **這張單獨有的**（acceptance criteria）→ 進 `refinement` 凍結的 fence。
- **這一類工作共用的**（definition of done）→ 由領域知識帶進來，見〈載入領域知識〉。

把共用的那份寫進每一張單的 fence，等於每次都重簽同樣幾行不承載新資訊的東西。

## 一、有工作進來：要不要立案

判準只有一條：**有沒有「怎麼算成功」需要人簽字。**

| 這件事 | 立案？ |
|---|---|
| 查一下、說明一段程式、跑個既有測試 | 否。沒有要簽的東西，直接做 |
| 改 typo、調一個顯然的常數 | 否。成功的定義不會有爭議 |
| 會改變行為、會有人問「這樣算好了嗎」 | **是** |
| 不確定 | **是**。立案的成本遠低於做完才發現目標不對 |

**把判斷與依據說出來**，一句話就夠，讓人能當場推翻。不立案的到此為止，直接把事做完。

**已經在進行中的單不要重問。** 同一件事往下做就是了——對已經簽過的東西再問一次是儀式，
不是把關。換成另一件會改變行為的事，才重新判斷。

## 二、現在在哪、下一步是什麼

不要問人，讀狀態：

```bash
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh where --state {issue}/.spine/loop-state.json
```

它會說出站別、有沒有停、還剩幾輪。**任何時候不確定現在在哪就跑它**——問人才是不知道
自己在哪的那個症狀。

| 現在的狀況 | 下一步 |
|---|---|
| 還沒有單 | `refinement`：判立案、寫斷言、凍結、開輪次 |
| 斷言凍結好了 | `engineering` |
| 這一輪做完了、想知道算不算達成 | `verify-ac` |
| `verify-ac` 判非 PASS，原因是實作沒到 | 回 `engineering` |
| `verify-ac` 判非 PASS，原因是**斷言本身錯了** | 停 `assertion_wrong`，回 `refinement` 重簽 |
| 交付紀錄寫成了 | 這條流程走完了。之後怎麼出貨是專案自己的事 |

**換站不需要說服任何腳本。** `advance` 是記下來，不是請求核准。還會擋人的只有兩類：
不可逆的動作，以及證據不足。

## 三、只在四個地方停

流程停下來的時候要說出是哪一種，而且要留下紀錄——**停在紀錄外等於沒停**，回來的人只
看得到一張不動的單，看不到它為什麼不動。

| 停點 | `--kind` |
|---|---|
| 斷言不對，要人重簽 | `assertion_wrong` |
| 新增依賴／重造既有組件／擴大 security surface | `surfaced_concern` |
| 連續未收斂打到上限 | `unconverged_cap`（`record` 自己會寫） |
| 需要人授權的不可逆動作 | `unauthorized_action` |

```bash
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh stop \
  --state {issue}/.spine/loop-state.json --kind surfaced_concern --note '<一句話>'
```

這四種以外的字串會被拒絕。**這四種以外的理由不是停下來的理由**——特別不包括「要不要
繼續？」「要我往下做嗎？」，那不是停點，那是把判斷推回給人。

## 四、沒撞停點就繼續

**沒有停點就往下走，不要回頭問。** 這包含跨單：手上有多張單而當下這張走不動了，
下一張由同一個地方回答，不是由人指定。

```bash
# 這一張單還能不能往下走
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh next --state {issue}/.spine/loop-state.json

# 手上這一整棵樹，接下來做哪一張
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh next --across-issues issues
```

單張回 `continue` 就繼續，回 `stop:<kind>` 才停。跨單回 `next:{命名空間}/{單號}`，並且把停住
的逐張列出來、把已收斂與已交付的算成數字——**不列成清單但要有數字**，一個安靜的第三態下一次
就會被當成看過了。

排序只看狀態：最靠近交付的先做（在製品不該堆高），同一站取最近動過的那張（那是「你剛剛在做
哪一張」寫在磁碟上的唯一痕跡）。命名空間叫什麼、單號多大都不參與。

反覆出現的失敗長這樣，看到就是退化了：

- 把連續的意圖收斂成單步，做完一步就停下來報告；
- 停在階段邊界等人說「好」；
- 用一句「要不要繼續？」把判斷推回給人。

## 五、載入領域知識：這類工作怎麼算 done

`refinement` 判完要立案之後，判斷這件工作屬於哪個領域，載入對應的知識，**並把載了什麼
記在單的狀態裡**。

| 這件工作 | 載入 |
|---|---|
| 會改到程式碼、要進版控 | `swe-knowledge` |
| 不會改程式碼（報告、調查、文件、資料分析） | 沒有適用的領域 |

領域的決定**就在開輪次那一步**，不是之後補的欄位：

```bash
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh init \
  --state {issue}/.spine/loop-state.json --pack swe-knowledge
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh init \
  --state {issue}/.spine/loop-state.json --pack none --why '<為什麼這件工作沒有領域完成條件>'
```

`init` 還會跑那個領域宣告的**開工條件**——條件寫在 pack 自己的知識裡，核心只負責找到它、
跑它、不成立就拒絕開輪次。所以核心不認得任何一個領域的條件，換一個領域不用動核心。

中途要改判領域（做著做著發現它其實會動到程式碼）用這一支，它是覆蓋不是追加：

```bash
bash .claude/skills/driving-work-to-done/scripts/record-knowledge-pack.sh record \
  --state {issue}/.spine/loop-state.json --pack swe-knowledge
```

**「沒有適用的領域」是一個被記下來的選擇，不是欄位空著。** 兩者在檔案裡長得不一樣，
在報告裡也要長得不一樣。

**指名的 pack 載不到就停，不要照常往下走。** 散文說「去載 X」而 X 不在，是完全安靜的：
routing 照樣把工作分派出去，只是分派到一份從未被讀取的程序。這個 repo 有過六支 skill
整段存在期間零載入而沒有人發現。`record-knowledge-pack.sh` 會拒絕一個解析不到 SKILL.md
的 pack 名字——它擋的就是這件事。

## 六、這一組東西要能整包搬走

`driving-work-to-done` ＋ `refinement` ＋ `engineering` ＋ `verify-ac` ＋ 領域 pack，複製到
另一個 repo 就能用。所以：

- **每一句指令都指向 skill 目錄裡的東西**，不指向 repo 根目錄的腳本、`.claude/rules/`、
  或任何 hook。那些在 claude.ai 與 Cowork 不存在。
- **不假設命名空間叫什麼**。`issues/{命名空間}/{單}/` 的中間那一段是誰決定的都不影響判定。
- **不假設領域**。核心的散文裡不出現只有軟體工程才成立的詞——它們屬於 `swe-knowledge`，
  不屬於這裡。那份詞表就在下面這一行，機器讀得到；量測從它讀，不另外抄一份：

  <!-- SWE-ONLY-VOCABULARY: branch|pull request|PR|merge|CI|deploy|codecov|lint -->

  唯一的例外是凍結用的 `git commit`——凍結的簽名就是那個 commit，跟領域無關。這個例外被
  指名寫在這裡，不是靜默放行：一個沒被說出來的豁免，跟沒有豁免在出事的時候長得一樣。

## 這裡不做的事

- **不判定達成**。那是 `verify-ac`，它有 oracle。
- **不決定量測命令**。那是 `engineering` 的活區。
- **不出貨**。交付紀錄寫成就是這條流程的終點，釋出尾段屬專案私有。
