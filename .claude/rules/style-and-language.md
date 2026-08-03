# 風格與語言

這份只講兩件事：**用什麼語言寫**，以及**寫成什麼樣子**。文件該住在哪、由誰搬，在
`document-flow.md`。

判準是可攜性：只有 skill 目錄會被帶到 claude.ai / Cowork，rules 與 hooks 不會。**所以
這一份必須到哪裡都成立**——任何需要 hook、validator、worktree 或這個 repo 特定目錄才
成立的東西都不屬於這裡，它要嘛搬進某支 skill 自己的目錄，要嘛屬於 `document-flow.md`
那種明講「只在這個 repo 裡成立」的規則。

## 語言

`workspace-config.yaml` 的 `language` 決定所有面向人的文字：對話回覆、報告、artifact、
PR body、JIRA comment、Slack 訊息。讀不到那個檔就用英文。

- **直接用那個語言寫**，不要先寫英文再翻譯。
- **識別字保持原樣**：函式名、檔案路徑、ticket key、命令字串、錯誤碼。
- 這條包含**最終回覆**。hook 攔得到寫檔，攔不到你講的話——所以要自己記得。

## 風格

**先講結論。** 第一句是答案，理由放後面。

**附證據，不要只下斷言。** 想說服對方接受任何結論（「這樣沒問題」「已經修好」「不是這個
原因」）就得附具體證據：檔案內容、命令輸出、來源連結。拿不出來就明講拿不出來。

**被反駁時當成待證主張**，不要反射性同意。要嘛用證據反駁，要嘛用證據承認。

**Runtime 的事要 runtime 驗。** 源碼分析是假設不是證據；SSR 輸出、API 回應、渲染結果一律
實跑一次。**push 之前先在本機跑完能跑的**——type check、lint、單元測試、受影響頁面的冒煙。
把 CI 當第一道防線等於把 reviewer 當驗證工具。

**有標準就直接套，提一個方案。** 不要把 2-3 個等價選項列給人選——那是把判斷推回去。附
reasoning 與 tradeoff，對方仍然可以不同意。只有真正互斥、風險輪廓不同的方向才需要問。

**原則同意就是開始執行。** 拿到「OK / 同意 / 就這樣做」之後直接做完，不要再列一輪「需要
你確認的事」。例外只有三種：不可逆動作（force push、rm -rf、production deploy、推 tag）、
自己起意的對外寫入、以及只有對方才知道的商業決策。

**連結要能點。** ticket 用完整 URL。Slack 訊息裡 URL 後面接中文要空一行或用 `<...>` 包起來，
不然 parser 會把中文吃進 URL。

## 程式碼

**新增或修改的 function 要有 doc-comment**（TSDoc / JSDoc / Google-style docstring /
shell function header），說明它做什麼、參數與回傳值是什麼。既有沒動的不強制回填。

**帶業務意義的 literal 抽成有名字的常數**，名字說不完的在宣告處補一行。純視覺數值
（padding、gap）與 `aria-label` 這類不強制。

**Inline comment 只在「為什麼」不自明時寫，一短行。** 逐行解說「做什麼」是雜訊。

**語言選擇**：串工具、檔案操作、簡單 control flow → bash。結構化資料、複雜 regex、需要
在記憶體裡建資料結構 → python。只有裝了 node_modules 才能跑 → mjs。純檔案掃描不要拉
Node，純 bash 能解的不要拉 Python——啟動成本會在 aggregate 跑的時候累積。

## 命令

**不要用 `cd`。** 用工具自己的路徑參數：`git -C`、`pnpm -C`、`gh --repo`、`bash /abs/path`。
`cd X && Y` 是複合命令，權限樣式難維護。

**不要用 `&&` 串不相干的命令**，分開下。Pipe 算一個命令，正常用。

**閘門與對外寫入之間要有 fail-stop 邊界**：`set -euo pipefail`，或者把檢查與寫入拆成兩次
呼叫，寫入只在檢查回 0 之後跑。

## 工具不存在時

**停下來並說出修法，不要偷偷安裝。** 禁止 `brew install`、`npm -g`、`pip install`、
`curl | sh`，以及任何往 `PATH` 上丟二進位檔的動作。屬於這個 workspace 的工具，修法是
`mise install`；屬於產品專案的，指向該團隊的 setup 文件。`git` 與 coreutils 假設存在。

## 這個 repo 的知識在哪

不要在這裡抄 repo 的知識。需要某個 repo 的規範時，去問管那件事的 skill——它自己的目錄裡
帶著它需要的東西。
