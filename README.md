# Polaris

一組給 coding agent 用的 skill，加上讓它們被找到、被正確迭代的執行環境。

這份文件對兩個讀者說話：**未來的自己**，以及**接手這個 repo 的 LLM**。它只回答三個問題
——這個 repo 是什麼、一件工作怎麼進來、一支 skill 怎麼被帶走。其餘的都不在這裡：每一支
skill 的行為住在它自己的 `SKILL.md`，那是唯一的權威。**這份文件不重述任何一支 skill 在做
什麼**，因為重述就是第二份，而兩份會漂。

## 這個 repo 是什麼

一個假設：**只要給 LLM 足夠的知識與固定的流程，需要推測的東西越少，它就越能做對。**
所以知識與流程都裝在 skill 裡，由 LLM 依意圖取用；skill 因此長得像第三方 lib——可獨立
安裝、可互相依賴、可按需載入。這個 repo 是它們的執行環境。

`.claude/skills/` 底下一個目錄就是一支 skill，它需要的東西都收在自己身上：腳本、參考
文件、範例。目錄外只有兩份常駐規則（`.claude/rules/`），因為它們是「只有在這個 repo 裡
才成立」的知識。

## 事情怎麼進來

**任何會改變程式碼或行為的請求，第一站是 `driving-work-to-done`。** 使用者不需要知道這個
名字，也不會說出來——「幫我做 X」「這個壞了要修」「想重構 Y」都算。只讀的問題不走這條，
直接回答。

那支 skill 是唯一回答「下一步是什麼」的地方。它把工作推過三站，頭尾兩個閘在，中間才可以
很隨便：

```
driving-work-to-done  ← 唯一決定「現在在哪、下一步是什麼」的地方
        │
        ├─ refinement   閘一：把「怎麼算成功」寫成人簽得下去的斷言，凍結
        ├─ engineering  兩個閘之間：探索、實作、換量測。這裡沒有閘
        └─ verify-ac    閘二：跑硬化 oracle，判定，寫交付紀錄
                            │
                     framework-release  判定過了才走這一段：併 main、壓版、同步、打 tag
```

`swe-knowledge` 不是一站，是一份知識：「會改到程式碼的工作怎麼算 done」。
`driving-work-to-done` 判定領域之後把它載進來。

**凍結 ＝ 那個 commit，不是那個封條。** 斷言寫在單的 `index.md` 裡一對註解標記之間，
`verify-ac` 會拿它跟 git 歷史比；重簽不構成授權，真正擋住偷改的是那個有人看得到的 diff。

## 有哪些 skill

這裡有 15 支 skill。**這張表只給名字與一句話**——要知道某一支怎麼運作，去讀它自己的
`SKILL.md`。

| skill | 一句話 |
|---|---|
| `driving-work-to-done` | 一件工作的唯一入口，也是唯一回答「下一步」的地方 |
| `refinement` | 閘一：把成功的定義凍結成斷言 |
| `engineering` | 兩個閘之間的施工區 |
| `verify-ac` | 閘二：機械判定 ＋ 不擋人的判斷報告 |
| `swe-knowledge` | 軟體工程這一類工作共用的「怎麼算 done」 |
| `framework-release` | 判定過之後的釋出尾段 |
| `review-pr` | 以 reviewer 身分審別人的單一 PR |
| `review-inbox` | 掃出一整批等你看的 PR |
| `request-pr-review` | 自己名下的 PR 現在卡在誰身上 |
| `pr-pickup` | Slack 那一半：從訊息裡撈出 PR，修完回覆原串 |
| `standup` | 每日站會報告與下班摘要 |
| `checkpoint` | 長 session 的存檔與接續 |
| `learning` | 從外部資源與已合併的 PR 萃取樣式 |
| `memory-hygiene` | 記憶分層與搬遷 |
| `visual-regression` | 前後截圖比對的視覺回歸守衛 |

另外有一組 skill 住在一個公司命名空間目錄底下（`.claude/skills/{命名空間}/{名字}/`）。
它們寫的是某一家公司的 repo、環境與流程，只對那個環境成立，所以不列在這裡。命名空間
目錄本身不是一支 skill，判準是形狀（底下有沒有 skill）不是名字。

## 一支 skill 怎麼被帶走

**東西有兩種帶走的方式，範圍不一樣，而這個分別決定每一樣東西住在哪。**

| 通道 | 帶走什麼 | 走這條的 |
|---|---|---|
| template repo | `.claude/rules/`、`.claude/hooks/`、`.claude/skills/`、`_template/`、根目錄檔案 | 框架自己整包搬家 |
| 單支上傳（claude.ai／Cowork） | 只有那一個 skill 目錄 | 要能像第三方 lib 一樣單獨用的 skill |

**每一支 skill 在自己的 frontmatter 用 `scope:` 說出它走哪一條**，核心不從名字或位置推導：

- `scope: standalone`（沒宣告時的預設）——**幾乎全部。** 判準是一個問題：照這支 skill 自己
  的描述，把它做成通用、不依賴環境，是不是更好用？幾乎每一次答案都是「是」。
  想像的使用者不是你：一個不會寫程式、連工作環境都初始化不了的人，由工程師把 skill 匯進
  他的 Claude Desktop。**在那裡不成立的東西，就不該留在 skill 裡。**
- `scope: framework`——**這一格幾乎是空的，而且應該保持空的。** 只有照描述做成通用就不
  成立的東西才屬於這裡：讀這個 repo 的 `.changeset/`、推這個 repo 的 tag、同步到這個人的
  template repo。
- `scope: company-only`／`scope: maintainer-only`——不出去。

## 一支 skill 怎麼被改

**走同一條脊椎。** 改 skill 就是改行為，所以它跟任何一件開發工作一樣從
`driving-work-to-done` 進來、由 `refinement` 簽下斷言、由 `verify-ac` 判定。

兩件跟迭代有關、但不由閘管的事：

- **摩擦要指名是哪一支。** 一趟工作裡某支 skill 幫到或擋到的時候，在那張單的活文件裡留
  一行 `SKILL-UTILITY` 註解，兩個方向都記。讀它不需要工具，`grep` 就好——**不要為它寫一
  支腳本**。
- **路由的評估集跟著 skill 走。** 例如 `review-pr` 帶著自己的 `.claude/skills/review-pr/evals/evals.json`：一組真的
  會被打出來的話，標好該不該觸發。改 `description` 之前先讀它。

**檢查類腳本的門檻是「預設不要有」。** 每多一道閘、每多一支 selftest，都要先證明它守著一個
不可逆、或會出去到這個 repo 之外的後果，而且那個後果看 diff 的人看不出來。三個條件同時
成立才留。散文斷言散文不是檢查，是重複；檢查自己的檢查一律不做。

## 常駐指令是生成的

`CLAUDE.md`、`AGENTS.md`、`.codex/AGENTS.md`、`.github/copilot-instructions.md` 四份都是
**產出物，不要直接編輯**。來源是 `.claude/instructions/`，組合方式寫在
`.claude/instructions/manifest.yaml`：

```bash
bash .claude/instructions/compile.sh              # 全部重生
bash .claude/instructions/compile.sh --target claude
```

改完沒重生會被釋出尾段的閘擋下來——那一道守的是「之後每個 session 都靜默讀到過期的那一
份」。

## 拿到這份東西之後

**clone 完跑這一行，每一支 skill 需要的工具就齊了**：

```bash
mise trust && mise run init
```

`mise trust` 是 [mise](https://mise.jdx.dev/) 自己要的——一份沒被信任過的設定檔，它會直接
拒絕讀。`mise run init` 之後的每一步都由**各支 skill 自己的宣告**推出來：裝 `mise.toml`
`[tools]` 裡的東西、裝各 package、`uv sync`，最後逐一驗它們真的在。**任何一段沒跑到就是
非 0**，不會裝了一半回報完成。

想知道現在缺什麼：

```bash
mise run doctor
```

**工具不存在時停下來說出修法，不要偷偷安裝**——禁止 `brew install`、`npm -g`、
`pip install`、`curl | sh`，以及任何往 `PATH` 上丟二進位檔的動作。

### 加了新工具的時候

一支 skill 需要什麼，寫在**它自己的 frontmatter**（格式與四種 `install` 寫法見
`.claude/skills/framework-release/scripts/lib/skill_tools.py` 的檔頭）。新的安裝項要先登記
回 `mise.toml` 再重跑一次 `mise run init`——**而你不需要記得這件事**：`init` 遇到一個沒有人
裝的宣告會停下來，並且把要跑的那一條 `mise use` 印給你。

### 這個 repo 沒有 pnpm workspace 檔，所以不要在根目錄跑 `pnpm -r`

`pnpm-workspace.yaml` 在 DP-654 被拿掉了。它住在 workspace 根目錄，而 pnpm 由 cwd 往上找
**最近的**那一份就停——所以根目錄底下並存的其他 repo（沒有自帶 workspace 檔的那些）會找到
它，然後它們的 `pnpm install` 裝的是這個 repo 的成員、對 cwd 什麼都不做，最後 exit 0。

沒有那份檔案之後，pnpm 改用**隱式探索**掃子目錄找 `package.json`。它有兩個性質要知道：

- **跳過隱藏目錄。** 所以 `polaris-toolchain`（在 `.claude/skills/visual-regression/toolchain`）
  用 `pnpm --filter polaris-toolchain` **找不到**，而且找不到的時候回 **rc=0** 加一行
  `No projects matched the filters`。要對它動手一律用 `pnpm --dir <目錄>`——指錯路徑會回
  rc=1。
- **不跳過並存的產品 repo，而且不看 `.gitignore`。** 所以 **不要在這個 repo 的根目錄跑
  `pnpm -r` 或 `pnpm --recursive`**：它會掃到那些 repo，而 `pnpm -r install` 會去動它們的
  `node_modules`，運氣不好連 lockfile 都動。動別人 repo 的設定是紅線。

**這個坑填不掉。** 填掉它的做法就是把 workspace 檔放回去，而那正是上面第一段講的 bug。
做不掉的坑要說出來。

**所以要留的是一條問得出來的命令，不是一句小心。** 症狀是安靜的（`Done in 541ms`、exit 0、
`node_modules` 一個都沒有），而分歧點只有一個：這個目錄往上找到的是哪一份 workspace 檔。
在那個目錄裡跑：

```bash
pnpm root -w
```

- **印出一個路徑** → 它被那個路徑底下的 workspace 檔收進作用域了。它的 `pnpm install` 裝的
  是那份 workspace 的成員，對這個目錄什麼都不做。**下一步是拿掉上游那一份，不是在這個
  目錄放一份自己的**——它如果是別人的 repo，動它的設定是紅線。
- **回 `ERROR  --workspace-root may only be used inside a workspace`** → 上游一份都沒有，
  pnpm 走隱式探索，這個目錄的 `pnpm install` 裝的是它自己。這是現在的狀態
  （2026-08-31 從 `~/work` 一路往上到 `/` 量過）。

框架自己沒有任何一處在用 `-r`，2026-08-31 量的：

```bash
grep -rn 'pnpm -r\|pnpm --recursive\|pnpm recursive' \
  --include='*.sh' --include='*.toml' --include='*.mjs' --include='*.py' --include='*.md' . \
  | grep -v node_modules | grep -v CHANGELOG
```

（無輸出。**要重新確認的時候跑這一條，不要相信這一句。**）

接上 git hook（過不了閘的 commit 從來不存在）：

```bash
bash .claude/skills/framework-release/scripts/install-git-hooks.sh
bash .claude/skills/framework-release/scripts/install-git-hooks.sh --status
```

它有代價，而那個代價寫在 `framework-release` 自己的 `SKILL.md` 裡——安裝之前它會說出來。

## 單住在哪

`issues/` 是**你自己的 git repo**，這個 repo 忽略它。一張單是一個目錄，位置是狀態的投影
——流程搬，人不搬：

```
issues/{命名空間}/backlog/{單}/      立案了，還沒開工
                 in-progress/       兩個閘之間
                 in-review/         送審中
                 done/              做完了，還沒上線
                 released/{日期}/   真的出去了
                 closed/{日期}/     不再執行
                 triage/            推導不出來，在等人歸位
```

命名空間叫什麼不影響任何判定：沒有註冊表、沒有白名單。手動搬一張單，下一次重算會把它搬
回它的狀態說的那一格——那是對的。

## 版號與釋出

版號由 `.changeset/` 決定，那是唯一的宣告源。判定過之後由 `framework-release` 走完剩下
的事：

```bash
bash .claude/skills/framework-release/scripts/spine-release.sh --issue {單}
```

**預設是預覽，不加 `--execute` 不會動任何東西。** 它做哪幾件事、被打斷了怎麼辦、每一步
問哪個系統，全部寫在那支 skill 自己的 `SKILL.md` 裡——這裡不抄第二份。
