# 文件流轉

這份規則講一件事：**一份文件該住在哪、由誰搬。**

它不進 skill 目錄，因為它不需要被帶走。skill 到了 claude.ai 或 Cowork，那裡沒有這個
workspace 的目錄結構——需要知道「DP 單放哪、舊層知識在哪」的，只有在這個 repo 裡開發框架
本身的那個 LLM。

## 一張單住在哪

```
issues/{命名空間}/{單號}/          活躍
issues/{命名空間}/archive/{單號}/  收斂完
```

`issues/` 是使用者自己的 git repo，框架 repo 忽略它（見 `.gitignore` 的
`versioned-elsewhere` 類）。框架只提供空殼 `_template/issues/`。

**命名空間叫什麼不影響任何判定。** 沒有註冊表、沒有白名單、沒有「framework 就要怎樣」的
分支。流程逐個走過去，從 `.spine/loop-state.json` 讀狀態，不從路徑推導身分。用位置判斷身分
是這套框架一路禁止的形狀。

## 誰搬

**流程搬，人不搬。** `spine-loop-state.sh record` 寫完輪次就叫
`archive-delivered-issues.sh`，把 `status == "converged"` 的搬進同命名空間的 `archive/`，
把還沒收斂卻躺在 archive 的搬回來。

位置是狀態的投影，**不是第二個權威**。唯一的權威是 `.spine/loop-state.json` 的 `status`。
所以：

- 手動 `git mv` 一張單 → 下一次 `record` 會把它搬回它該在的地方，這是對的。
- 想讓一張單消失在待辦清單裡 → 讓它收斂，不要搬它。
- `--check` 是用來讓「位置與狀態對不上」被看見，不是用來讓人選一邊。

沒有 `.spine/loop-state.json` 的目錄（舊層搬進來的知識、還沒開輪次的種子）**不參與位置
判定**，但它們的數量每次都會被印出來。一個不被判定的第三態如果安靜，下一次就會有人以為
那幾百個目錄都被檢查過了。

## 開 branch：實作要，單不要

**改程式碼之前，先開一條 branch。** 名字用單的目錄名加 `feat/` 前綴，例如
`feat/DP-466-a-human-who-does-not-type-commands`。時機是 `refinement` 判定要立案之後——
凍結那個 commit 就該落在 branch 上，一個還沒開工的成功定義直接躺在 `main` 上等於它已經是
既成事實。

`main` 只接收判定過的東西：`verify-ac` 判 PASS、交付紀錄寫成，由 `framework-release` 併進去。

**`issues/` 不開 branch。** 一張單只有一個狀態——最新的那個——直接推就好。理由跟 J-P1 是
同一句話：一張單只有一個家。單分岔出兩個版本，「現在到底走到哪」就有兩個答案，而這整套
流程的前提是那個問題只有一個答案（`.spine/loop-state.json`）。單的歷史留在 commit 裡，
不留在並行的分支裡。

所以兩個 repo 的節奏不一樣，這是刻意的：框架 repo 一張單一條 branch，`issues` repo 一直
往前推。

**這條沒有機械閘在守。** 現在只有這段散文，忘記時不會有任何東西擋下來——2026-08-03 就是
這樣讓三張單的 commit 全部混在 `main` 上。要讓它站得住，`spine-loop-state.sh init` 那一刻
該拒絕站在預設分支上的工作區。在那之前，這是一條靠人記得的規則，而靠人記得的規則的失效率
就是那次的樣子。

## 舊層的東西在哪

DP-462 之前的交付層留下兩堆，分開放：

- **知識**（spec 正文、設計、決策）→ 已經搬進 `issues/` 的 archive，跟著單走。
- **證據**（截圖、報告、build 產物）→ 留在 `docs-manager/src/content/docs/specs/`，那是
  它自己的 repo。知識搬、證據留在原地：搬證據要重寫一整批相對路徑，而證據的價值在於它
  當時就長在那裡。

要找一張舊單的來龍去脈，去 `issues/`；要找它當時貼的圖，去 specs repo。

## 新文件往哪放

問一句：**這件事能不能只靠一支 skill 完成？**

- 能 → 進那支 skill 自己的目錄（腳本、reference、範例都一樣）。skill 目錄會被帶到
  claude.ai 與 Cowork，放在外面的東西在那裡不存在。
- 不能，而且只有在這個 repo 裡才成立 → 進 `.claude/rules/`，像這一份。
- 是某一張單的過程紀錄 → 進那張單的 `index.md` 活文件，不要另開檔案。一個工作被迫產生的
  檔案不超過兩個（那份 index.md 與 code）。

**不要為了「比較好找」而複製一份。** 兩份會漂，而漂掉的那一刻通常沒有人在看。
