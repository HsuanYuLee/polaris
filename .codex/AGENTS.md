<!-- 由 .claude/instructions/compile.sh 產生，不要直接改這個檔。 -->
<!-- 來源：.claude/instructions/manifest.yaml 的目標 codex -->
<!-- 重新產生：bash .claude/instructions/compile.sh --target codex -->
<!-- 檢查有沒有過期：bash .claude/instructions/compile.sh --check -->

# Polaris

## 這個 workspace 是什麼

一組 skill。每支 skill 自己的目錄裡帶著它需要的東西——腳本、參考文件、範例。

**東西有兩種帶走的方式，而它們帶走的範圍不一樣。** 這個分別決定每一樣東西住在哪：

| 通道 | 帶走什麼 | 走這條的 |
|---|---|---|
| template repo | `.claude/rules/`、`.claude/hooks/`、`.claude/skills/`、`_template/`、根目錄檔案 | 框架自己整包搬家 |
| claude.ai／Cowork 單支上傳 | 只有那一個 skill 目錄 | 要能像第三方 lib 一樣單獨用的 skill |

**每一支 skill 在自己的 frontmatter 用 `scope:` 說出它走哪一條**，核心不從名字或位置推導：

- `scope: framework`——**這一格幾乎是空的，而且應該保持空的。** 只有那些照描述做成通用
  就不成立的東西才屬於這裡：釋出尾段讀這個 repo 的 `.changeset/`、推這個 repo 的 tag、
  同步到這個人的 template repo，換一個環境它就沒有意義。
- `scope: standalone`（沒宣告時的預設）——**其餘全部。** 判準是一個問題：**照這支
  skill 自己的描述，把它做成通用、不依賴環境，是不是更好用？** 幾乎每一次答案都是「是」。

  想像的使用者不是你：一個不會寫程式、沒有維護能力、連工作環境都初始化不了的人，
  由工程師把 skill 匯進他的 Claude Desktop。**在那裡不成立的東西，就是不該留在 skill
  裡的東西**——「主 checkout 在哪」「這個 workspace 的設定在哪」在那裡沒有答案，所以
  一支 standalone skill 要嘛不問這些問題，要嘛問不到的時候說出來並照樣工作。
- `scope: company-only`／`scope: maintainer-only`——不出去。

以前這裡寫的是「沒有共用的腳本目錄，因為只有 skill 目錄會被帶走」。**那句話是假的**：
template repo 追蹤 `.claude/rules/` 與 `.claude/hooks/`，skill 目錄從來不是唯一會被帶走
的東西。它把通道二的限制套到了通道一的內容上，代價是 2026-08-09 量到的 70 份副本
（188 支腳本、118 個名字）——其中五類回答「這個 workspace 的某個東西在哪」的腳本，在
通道二那些環境裡根本沒有答案，複製過去只是雜訊。

## 事情怎麼進來

**任何會改變程式碼或行為的請求，第一站是 `driving-work-to-done`。** 使用者不需要知道這個
名字，也不會說出來——「幫我做 X」「這個壞了要修」「想重構 Y」都算。

**只讀的問題不走這條。**「這支腳本在幹嘛」「查一下 X」沒有「怎麼算成功」需要人簽，
直接回答。

那支 skill 是唯一回答「下一步是什麼」的地方：要不要立案、現在在哪一站、什麼時候換站、
什麼時候停、這一類工作怎麼算 done。立案之後的三站——`refinement` 簽下成功的定義 →
`engineering` 施工 → `verify-ac` 判定——各自只做自己那一站的事，不決定往哪走。頭尾兩個閘
在，中間才可以很隨便。

**這段散文不重述那支 skill 的判準。** 判準抄成兩份就會漂，而漂掉的那一刻沒有人在看。

## Skill 優先

使用者的話對上某支 skill 的 trigger 時，**先 invoke 那支 skill**，不要先讀檔、先查 API、
先派 sub-agent。skill 自己會處理它的資料抓取與歧義。

「我已經知道怎麼做」不是跳過的理由——skill 裡帶著你不會記得的步驟。一句話真的對上兩支
skill 時先問人，但要在任何 tool call 之前問，不是讀完再問。

## 判斷順序

衝突時從尾巴開始放棄，第一項絕不放棄：

1. **功能完整**——交付物要真的解決問題，不得裁掉必要功能去換其他屬性。
2. **易讀**——接手的人要能直接看懂。
3. **效能與簡潔**——前兩項相同時，短的、快的、抽象少的贏。

出現候選方案時直接依這個順序決定一個，附理由與取捨；不要把等價選項列出來讓人選。

## 提新東西之前

要開新的單、發明新機制、加新結構之前，先回答「現在有什麼在管這件事」並把它用盡。
證明既有的不夠、而且拿得出證據，才談新增。

自己剛寫出來的判斷是草稿，不是根據。任何驅動決策的句子（「X 需要 Y」「因為 Z 所以卡住」）
說出口時要嘛有證據，要嘛當成待驗的假設，不要拿來當下一步的地基。

## 常駐規則

`.claude/rules/` 底下兩份，只有這兩份：

- `style-and-language.md`——用什麼語言寫、寫成什麼樣子。
- `document-flow.md`——一份文件該住在哪、由誰搬。

放在這裡的判準是「需不需要被帶走」：skill 目錄會到 claude.ai 與 Cowork，rules 不會。所以
只有在這個 repo 裡才成立的知識才進 rules，其餘都該長在某支 skill 自己的目錄裡。

## Codex

Codex 讀 `AGENTS.md`。這個 workspace 自己維護一份，`.agents/skills` 是指向
`.claude/skills` 的 symlink，所以 skill 兩邊看到的是同一份。產品 repo 根目錄的
`AGENTS.md` 屬於那個 repo，不由這裡安裝或修改。

**Codex 沒有 hook。** 任何靠 hook 擋下來的東西在 Codex 這邊都不存在，包含語言檢查。
送出回覆前自己確認 `workspace-config.yaml` 的 `language`。
