---
name: judge
description: 施工告一段落、要判這次到底算不算達成時的站。跑硬化 oracle 給出會擋人的機械判定，另出不擋人的判斷報告，兩者分開。流程的第二個閘，也是最後一個。
when_to_use: |
  某個 source 做到一個段落，要驗收的時候。例如「驗收一下」「這樣算完了嗎」「跑一次判定」
  「可以出貨了嗎」，或剛從 work 交出來。

  判 PASS 之後也在這裡寫交付紀錄，供釋出尾段讀。

  不用於：還在做、只是想跑個測試看看（那是 work 的量測）。
version: 2.0.0
---

# judge — 閘二：執行 oracle

前置必讀：`.claude/skills/references/spine-review-guidance.md`。

輸出有兩部分，權力不一樣：**機械判定會擋**（由 exit code 承載，不需要讀者同意）；
**判斷報告不擋**（帶引用的意見，由人裁）。把兩者混在一起，閘就會開始擋一些沒人能精確
定義的東西，然後大家學會繞過它。

## 機械判定：三件事

```bash
# 1. 斷言沒被動過。這一步同時查兩件事：封條與內文自洽，且內文與 git 歷史一致。
#    對不上就停——這時審查根本還沒開始，因為成功的定義變了。
bash scripts/frozen-assertion-fence.sh verify {source}/index.md

# 2. 手上這條量測命令是登錄過的。換過而沒帶紅過證據的命令不被承認。
bash scripts/record-measurement-change.sh verify \
  --ledger {source}/.spine/measurement-ledger.json \
  --assertion-id A-P1 --command '<cmd>'

# 3. 跑量測。同時看 exit code 與正向證據——exit 0 而沒有正向證據不是通過。
bash scripts/run-hardened-oracle.sh --command '<cmd>' \
  --require-tool rg --expect-evidence '<真的量到東西的痕跡>' \
  --evidence-out {source}/.spine/evidence/<assertion-id>.json
```

任一項不成立就是非 PASS，沒有討論空間。

`run-hardened-oracle.sh` 會先探工具能力再釘住、要求命令產出證明自己量到東西的輸出、
並原樣保留 stderr 與 exit code。這是因為工具會說謊：PATH 上較早的 shim、靜默跳過的測試、
被吞成 generic timeout 的錯誤，三者都能讓一個空的執行看起來像綠的。

## 成本地板

順手量一次這個 source 逼出了多少檔案。清單用枚舉的，不是用手寫的——手寫的清單由寫的人決定
漏掉什麼，然後檢查就在那個漏掉的地方變綠：

```bash
bash scripts/enumerate-spine-inventory.sh --source {source}
bash scripts/check-spine-cost-floor.sh --inventory {source}/.spine/inventory.json
```

它從 git diff 與 `.spine/` 現況兩處讀，兩處都不能被說服。`.spine/*.json` 這類機器寫的狀態
**算在裡面**——把它排掉數字立刻就合格了，正因為如此那個決定不由量測工具做。地板指的是
「人被迫寫的檔案」還是「流程被迫產生的檔案」，是斷言層的問題，要人在閘一回答。

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

dogfood 觀察的樣本通常很薄，而且觀察者往往同時是被觀察者。這不使結論無效，但它使結論不是
統計證據。如實標示樣本數與觀察者身分，不要把「跑過一次」寫成「已驗證」。

## 判 PASS 之後：交出去

判定通過不等於交付。`framework-release` 要的是一份它讀得動的紀錄，不是一句「judge 說 PASS」：

```bash
bash scripts/record-delivery-intent.sh \
  --source {source} \
  --version-bump patch|minor|major \
  --summary '<一句話，會變成 CHANGELOG 給人看的那行>'
```

它會先重驗 fence 才寫。斷言被動過的 source 記錄不了交付意向——對著一份沒人簽過的成功定義
出貨，比不出貨糟。

接著它逐條檢查 fence 宣告的每個斷言 ID：要有 `{source}/.spine/evidence/{ID}.json`、
`verdict` 是 `PASS`、`producer` 是 `run-hardened-oracle.sh`、而且 `head_sha` **等於要交付的
那個 head**。缺一條、手寫一條、或量測比交付的 head 舊，都寫不下去，而且它會逐條告訴你是哪
一條、差在哪。

三件事各有理由。**要有**，是因為在這之前沒有任何東西要求交付前得有證據，「judge 說 PASS」
一路是靠散文帶著走的。**要是 oracle 產的**，是因為手寫的 PASS 是自己給自己蓋章。
**head 要對上**，是因為證據證的是一棵樹綠了；量完之後又推的 commit，證據沒看過。

`destination` 決定去哪：`workspace` 留在本地，`template` 才進 Polaris template repo。那是
閘一由人宣告的，這裡只讀不改。

紀錄寫完，judge 就結束了。之後由 `spine-release.sh` 讀那份紀錄跑釋出尾段——壓版本、促進
`main`、視 destination 決定要不要同步 template 與打 tag。它預設只預覽，`--execute` 才動手：

```bash
bash scripts/spine-release.sh --source {source}            # 看它打算做什麼
bash scripts/spine-release.sh --source {source} --execute
```

紀錄寫完就把站別推到終點，讓下一個人（或下一個 session）讀得到這裡已經走完：

```bash
bash scripts/spine-loop-state.sh advance \
  --state {source}/.spine/loop-state.json --to delivered
```

## 判非 PASS 之後

**自己回 `work`，不要停下來問人要不要修**：

```bash
bash scripts/spine-loop-state.sh advance \
  --state {source}/.spine/loop-state.json --to work
```

若非 PASS 的原因是斷言本身錯了，那是第四類流轉——那個要停，而且要停得讓人看得見：

```bash
bash scripts/spine-loop-state.sh stop \
  --state {source}/.spine/loop-state.json --kind assertion_wrong --note '<哪一條、為什麼>'
```

停完回 `assert` 讓人重簽。
