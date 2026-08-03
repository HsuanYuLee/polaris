---
name: verify-ac
description: 施工告一段落、要判這次到底算不算達成時的站。跑硬化 oracle 給出會擋人的機械判定，另出不擋人的判斷報告，兩者分開。流程的第二個閘，也是最後一個。
when_to_use: |
  某張單做到一個段落，要驗收的時候。例如「驗收一下」「這樣算完了嗎」「跑一次判定」
  「可以出貨了嗎」，或剛從 engineering 交出來。

  判 PASS 之後也在這裡寫交付紀錄，供釋出尾段讀。

  不用於：還在做、只是想跑個測試看看（那是 engineering 的量測）、
  決定下一站是哪一站（走 driving-work-to-done）。
version: 3.0.0
---

# verify-ac — 閘二：執行 oracle

輸出有兩部分，權力不一樣：**機械判定會擋**（由 exit code 承載，不需要讀者同意）；
**判斷報告不擋**（帶引用的意見，由人裁）。把兩者混在一起，閘就會開始擋一些沒人能精確
定義的東西，然後大家學會繞過它。

## 機械判定：三件事

```bash
# 1. 斷言沒被動過。這一步同時查兩件事：封條與內文自洽，且內文與 git 歷史一致。
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

`run-hardened-oracle.sh` 會先探工具能力再釘住、要求命令產出證明自己量到東西的輸出、
並原樣保留 stderr 與 exit code。這是因為工具會說謊：PATH 上較早的 shim、靜默跳過的測試、
被吞成 generic timeout 的錯誤，三者都能讓一個空的執行看起來像綠的。

## 舊層還撐著沒有

問的是：這張單走完全程，有沒有哪一步非得靠脊椎要取代的那套東西（`task.md`、
completion-gate marker、auto-pass ledger、verify report）才走得完。

**不用自己跑，交付紀錄那一步會跑。** `record-delivery-intent.sh` 會枚舉這張單逼出了哪些
檔案、把清單餵進檢查，非 0 就不寫紀錄。想先看的話：

```bash
bash .claude/skills/verify-ac/scripts/enumerate-spine-inventory.sh --issue {issue}
bash .claude/skills/verify-ac/scripts/check-spine-legacy-layers.sh --inventory {issue}/.spine/inventory.json
```

清單用枚舉的，不是手寫的——手寫的清單由寫的人決定漏掉什麼，然後檢查就在那個漏掉的地方
變綠。它從 git diff 與 `.spine/` 現況兩處讀，兩處都不能被說服。

**「逼出幾個檔案」這個數字只印出來，不判定。** 那三個檔案是脊椎自己寫的，數量恆定，對一個
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

dogfood 觀察的樣本通常很薄，而且觀察者往往同時是被觀察者。這不使結論無效，但它使結論不是
統計證據。如實標示樣本數與觀察者身分，不要把「跑過一次」寫成「已驗證」。

## 判 PASS 之後：交出去

判定通過不等於交付。`framework-release` 要的是一份它讀得動的紀錄，不是一句「verify-ac 說 PASS」：

```bash
bash .claude/skills/verify-ac/scripts/record-delivery-intent.sh \
  --issue {issue} \
  --version-bump patch|minor|major \
  --summary '<一句話，會變成 CHANGELOG 給人看的那行>'
```

它會先重驗 fence 才寫。斷言被動過的單記錄不了交付意向——對著一份沒人簽過的成功定義
出貨，比不出貨糟。

接著它逐條檢查 fence 宣告的每個斷言 ID：要有 `{issue}/.spine/evidence/{ID}.json`、
`verdict` 是 `PASS`、`producer` 是 `run-hardened-oracle.sh`、而且 `head_sha` **等於要交付的
那個 head**。缺一條、手寫一條、或量測比交付的 head 舊，都寫不下去，而且它會逐條告訴你是哪
一條、差在哪。

三件事各有理由。**要有**，是因為在這之前沒有任何東西要求交付前得有證據，「verify-ac 說 PASS」
一路是靠散文帶著走的。**要是 oracle 產的**，是因為手寫的 PASS 是自己給自己蓋章。
**head 要對上**，是因為證據證的是一棵樹綠了；量完之後又推的 commit，證據沒看過。

`destination` 決定去哪：`workspace` 留在本地，`template` 才進 Polaris template repo。那是
閘一由人宣告的，這裡只讀不改。

紀錄寫完，這一站就結束了。之後怎麼出貨**不在這條流程裡**——釋出尾段是每個專案自己的事，
它讀這份紀錄，而這一站不需要知道它叫什麼名字。這是刻意的：一旦這裡指名某支釋出腳本，
這四支 skill 就搬不到沒有那支腳本的地方了。

**把判定結果帶回 `driving-work-to-done`**——PASS 之後要不要
推站別、非 PASS 要回哪一站、原因是實作沒到還是斷言本身錯了該停哪一種，都在那裡回答，
不在這裡。這一站產出的是判定，不是下一步。
