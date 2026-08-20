# 文件流轉

這份規則講一件事：**在這個 repo 裡，一份文件該住在哪。**

它不進 skill 目錄，因為它不需要被帶走。skill 到了 claude.ai 或 Cowork，那裡沒有這個
workspace 的目錄結構。

**「一張單怎麼從一格搬到另一格」不在這裡了。** 那是判準——位置是狀態的投影、兩層推導、
問不到就說出來——判準跟著它唯一的消費者走，寫在 `driving-work-to-done`〈一張單住在哪〉。
留在這裡的只有這個 repo 自己的實例，以及沒有任何一支 skill 認領的那幾件。

## 這個 repo 的單樹

單樹根是 `issues/`。**命名空間叫什麼不影響任何判定**——沒有註冊表、沒有白名單，流程從
`{單}/.spine/loop-state.json` 讀狀態，不從路徑推導身分。所以這裡也不列現在有哪幾個：
一份抄在散文裡的清單會漂，而下面那支腳本本來就會把它們印出來。

**命名空間有哪幾個、格子有哪幾個、各裝幾張，問那支腳本**：

```bash
bash .claude/skills/driving-work-to-done/scripts/place-issues-by-state.sh --issues issues --check
```

`issues/` 是使用者自己的 git repo，框架 repo 忽略它（見 `.gitignore` 的
`versioned-elsewhere` 類）。空殼由 `refinement` 自己帶著（`templates/issues/`）——
開 `issues/` 是那一站的活，殼跟著那一站走。

## 開 branch：實作要，單不要

**開工前要成立什麼條件，寫在 `swe-knowledge`，不在這裡。** 那是軟體工程這一類工作共用的
東西，而且 `spine-loop-state.sh init` 會去讀它、不成立就拒絕開輪次。

這裡連複述一次都不複述：複述就是第二份，而兩份會漂。2026-08-03 這條規矩只有散文的時候，
它在寫下的一小時內失效四次，寫下它的那個 commit 本身就落在 `main` 上。

這裡只留兩件只有這個 repo 才成立的事。

**命名用單的目錄名加 `feat/` 前綴**，例如 `feat/DP-466-a-human-who-does-not-type-commands`。
**這一條刻意沒有閘在守**：`gate-spine-delivery.sh` 的檔頭寫著理由——一張單的身分寫在
`delivery.json` 裡，不寫在 ref 上，所以命名是給看 PR 清單的人用的慣例，屬於 repo 知識而不
屬於閘。忘記命名不會壞掉任何東西，只會讓清單難讀。

**`issues/` 不開 branch。** 一張單只有一個狀態——最新的那個——直接推就好。理由跟 J-P1 是
同一句話：一張單只有一個家。單分岔出兩個版本，「現在到底走到哪」就有兩個答案，而這整套
流程的前提是那個問題只有一個答案（`{單}/.spine/loop-state.json`）。單的歷史留在 commit 裡，
不留在並行的分支裡。

所以兩個 repo 的節奏不一樣，這是刻意的：框架 repo 一張單一條 branch，`issues` repo 一直
往前推。`init` 的閘只管框架 repo 那一邊——它跑在你開單的那個工作區上，而 `issues` 從來
不是那個工作區。

## 舊層的東西在哪

DP-462 之前的交付層留下兩堆，分開放：

- **知識**（spec 正文、設計、決策）→ 已經搬進 `issues/`，跟著單走，現在跟其他做完的單
  一起躺在終局那幾格裡。
- **證據**（截圖、報告、build 產物）→ 留在 `docs-manager/src/content/docs/specs/`，那是
  它自己的 repo。知識搬、證據留在原地：搬證據要重寫一整批相對路徑，而證據的價值在於它
  當時就長在那裡。

要找一張舊單的來龍去脈，去 `issues/`；要找它當時貼的圖，去 specs repo。

## 新文件往哪放

問一句：**這件事能不能只靠一支 skill 完成？**

- 能 → 進那支 skill 自己的目錄（腳本、reference、範例都一樣）。skill 目錄會被帶到
  claude.ai 與 Cowork，放在外面的東西在那裡不存在。
- 不能，而且只有在這個 repo 裡才成立 → 進 `.claude/rules/`，像這一份。
- 是某一張單的過程紀錄 → 進那張單的 `{單}/index.md` 活文件，不要另開檔案。一個工作被迫產生的
  檔案不超過兩個（那份 index.md 與 code）。

**不要為了「比較好找」而複製一份。** 兩份會漂，而漂掉的那一刻通常沒有人在看。

<!-- POLARIS-SCOPE: framework — 這一份講的是這個 repo 自己的單樹長什麼樣；換一個環境它沒有對象。跟著 template repo 走，不進 skill 目錄——理由寫在本文開頭 -->
