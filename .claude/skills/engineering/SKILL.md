---
name: engineering
description: |
  已經有凍結的 assertion、要開始或繼續施工時的站。兩個關卡之間的 loop：探索、實作、換量測、推進輪次。這裡沒有關卡。

  某張單的 assertion 已經凍結，接下來要動手做的時候，或剛從 refinement 交出來。

  也用於：跨 session 接手一張做到一半的單——讀凍結塊與可以改的那部分就能接上。

  不用於：還沒有 assertion 的工作、要判這次算不算達成（走 verify-ac）、
  決定下一站是哪一站（走 driving-work-to-done）。
metadata:
  version: 3.0.0
  requires:
    - skill: driving-work-to-done
      why: 輪次與停點由它保管；換站與停哪一種也只有它回答
scope: universal
---

# engineering — 兩個關卡之間

這裡沒有關卡。派工怎麼切、實作怎麼做、試幾次、走哪條路，都在這裡，沒有人在等你交表格。
正因為頭尾兩個關卡在，中間才可以很隨便。

## 接手

讀 `{issue}/index.md` 就夠了——凍結塊是成功的定義，可以改的那部分是其餘一切。不需要去翻別的
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

**跑可能不會自己結束的腳本時，命令自己帶逾時。** 輪詢、梯子、等外部系統的命令，不靠工具的
預設上限結束；被移到背景之後沒有人等得到它。

**每一趟量測都是一個新的 process。** 探針不要依賴同一趟以外留下的產物：判定那一站會拿同一條
命令單獨重跑，那時候上一趟的檔案不在。需要共用產物的，每一次都自己建。**改動前後的兩趟對照
跑在同一組設定上**：會把自己的路徑印進輸出的工具，換了工作目錄就多出跟這一版無關的差異，紅得
像實作壞了。

**自己剛寫的檢查第一次就綠是可疑訊號**，通常代表規則太窄。落地之前先餵它一份已知壞掉的
輸入，確認它真的會紅。

## 在這裡發現問題，先自己解

| 發現的問題 | 怎麼辦 |
|---|---|
| 量測方法不對 | 原地改，帶紅過證據換命令，繼續 |
| 切分不對 | 重切，繼續 |
| assertion 不對 | 不是這一站能解的——回 `driving-work-to-done` 讀該停哪一種 |

施工計劃那一類不存在：這條流程不分「明確施工」與「嘗試實作」。看得懂就做，看不懂就先探。

## 派工給 Codex

找不到 Codex 執行檔，或它回用量上限（例：2026-11-11 17:43 派出的那一趟回
`turn.failed`「You've hit your usage limit… try again at 8:33 PM」），那一步就由這條線
自己做，說出是哪一種，不停下來等。

**哪些步驟走 Codex。** 唯讀的步驟，或只做到改好檔、測試綠的步驟：改 code、補測試、跑測試、
寫腳本、用 curl 量測、整理單上的表、寫報告檔。留在 Claude 線的是：瀏覽器操作、SIT 手點、
push、PR、對外送出、JIRA 與 Slack，以及下面〈已量到的限制〉列的那幾件。這條分界對每一條線
都成立，產品線與框架線一樣。指揮官用 `command-post.py` 的 `--order`、`--say`、`--review`
產指令時，stderr 會多印一行提示指到這一節。

**派的人就是審的人。** 外包的那條線自己寫 prompt、自己派、自己審回傳，commit 也由它做。
不交給指揮官或別的 session 代跑。

**prompt 檔**由那條線寫，位置是 `<單>/.spine/codex/prompt-<步驟名>.md`，必須寫出：

- repo 的絕對路徑，以及 branch 或 worktree；
- 要改什麼、怎麼算做完、跑哪些測試；
- 不 commit、不 add、不 stash、不 push；搬檔用 `mv`，不用 `git mv`。
  commit 由外包的那條線在沙箱外做；
- 開頭先讀 repo 的 `CLAUDE.md`、指名的 skill，以及 `.claude/rules` 三份。
  Codex 載不到 `.claude/rules`，所以 prompt 要逐份指名；
- 結尾的回傳格式：核對、改了哪些檔、測試結果、沒做到的。

**派工命令**，一字不差，由外包的那條線自己用 Bash `run_in_background` 跑：

```bash
<codex 執行檔> exec -C <workspace 根或 worktree 根> -s workspace-write --add-dir <單樹根> -c approval_policy=never --json -o <單>/.spine/codex/<時間>-<步驟名>.md "$(cat <prompt 檔>)" < /dev/null > <同名>.jsonl 2> <同名>.err
```

- `<codex 執行檔>` 填找得到的那一個：`codex` 在 `PATH` 上就用它。macOS 的 ChatGPT.app 內帶
  一份，例如 `Contents/Resources/codex-cli/bin/codex`（2026-11-11 量到；2026-11-06 那一版在
  `Contents/Resources/codex`）。不另外裝（`CLAUDE.md`〈工具不存在時〉）；兩處都找不到，
  就是第一句說的「找不到」。
- `-C` 指 workspace 根或 worktree 根，那裡有 `.agents/skills` 與 `AGENTS.md`；不指 issues 樹。
- 單樹根由派的人填，不寫任何一台機器的路徑。

**完成**要同時成立三件事：process exit 0、jsonl 裡有 `turn.completed`、`-o` 回傳檔非空。
缺一件就是還沒做完，把 `.err` 尾端貼進單。jsonl 裡是 `turn.failed` 而訊息是用量上限，
那一步照第一句自己做。

沒做完的那一趟，工作樹可能留著改到一半的檔。先跑 `git -C <worktree> diff --stat`，看過內容
再決定：照同一份 prompt 重派，或用 `git checkout -- <檔>` 還原指名的檔，不還原整棵樹。
重派時換一個新的 `<時間>`，不要蓋掉上一趟的 `-o`、`.jsonl`、`.err`，那三個檔是上一趟的證據。

**回傳怎麼審。** 外包的那條線自己讀整份回傳檔，逐條對單上的 AC，每句事實看它標的是量到、
讀到還是推的。通過才派一次 Claude 驗證（push-verifier 或 `verify-ac`）；沒通過就改 prompt
重派。回報時標「Codex 做、我審過」。Codex 的回傳是這條線的交付物，收回報的人照讀交付物的
規矩讀它，不另外再審一次 Codex。

### 已量到的限制

- `.codex/hooks.json` 的 `^Bash$` matcher 登記兩支：`block-git-hook-bypass` 擋
  `git commit --no-verify` 這類繞過 git hook 的 commit、push 命令；`gate-ship-point` 只在
  非 draft `gh pr create`、`gh pr ready`、`gh pr merge`、tag 與 release 出貨點檢查單是否判過。
  `send_message` 與 `schedule_message` 的 matcher 只登記 `gate-ship-point`，只擋符合 skill
  宣告的部署請求樣式、而所屬單還沒判過的那一種；其他對外訊息不擋（規矩：hook 只補防線，
  邊界仍是 prompt 與這一節）。
- 沙箱有網路（`gh pr view` 與 github.com 都通），所以沙箱擋不了 `gh pr create`。push、PR 與
  對外送出留在 Claude 線是規矩，不是沙箱做不到；hook 只擋其中幾種，所以不把這些步驟寫進 prompt。
- 非 TTY 那一趟判成掛住的標記是 jsonl 0 bytes，而且沒有 `-o` 回傳檔。`.err` 裡的
  「Reading additional input from stdin...」成功的那一趟也會印，不能拿來判斷有沒有掛住；
  派工命令仍要帶 `< /dev/null`（設定解不開：非 TTY 一律帶）。
- 2026-11-06 量到加上 `-c sandbox_workspace_write.network_access=true` 後，`<內網 Kibana 主機>`
  解析得到，`curl -I` 回 302；`<SIT API 主機>` 解析得到，`curl -I` 回 200（代價：所有對外連線
  全開，不只開這幾台主機）。見 `<DP-1007 單>/.spine/codex/20261106-1630-probe-network-access.md`
  與 `<DP-1007 單>/.spine/codex/20261106-1633-probe-sit-api-host.md`。
- 2026-11-06 量到沙箱連不到本機 PostgreSQL：PHPUnit 回 `SQLSTATE[08006] ... Operation not
  permitted`；要資料庫的 oracle 由 Claude 線跑（未證實：要在使用者的 `~/.codex/config.toml`
  寫 permission profile，由使用者決定）。見 `<那張產品單>/.spine/codex/20261106-1434-verify-sh.md`。
- prompt 裡要寫：資源被占就停下來回報。2026-11-06 讀到那一趟 3001 被 push-verifier 的 dev server
  占著，Codex 照 prompt 停下來回報；資源空了就重派同一份 prompt（設定解不開：兩個 listener
  不能同時獨占同一個 address 與 port）。見 `<另一張產品單>/.spine/codex/20261106-1422-dev-oracles.md`。
- 2026-11-06 在沙箱裡跑 `pnpm exec nuxt dev --port 3001`，第一次啟動就 exit 1，錯誤是
  `EMFILE: too many open files, watch`；本機 dev server 的量測留在 Claude 線（未查 Codex 有沒有
  可以調 open-file 上限的設定）。見 `<另一張產品單>/.spine/codex/20261106-1650-dev-oracles.md`。
- 2026-11-06 量到 Codex 裡起不了第二個 Codex：app-server 初始化被拒。標本 eval 這類「派一次
  Codex」的步驟由外包的那條線在沙箱外跑（設定解不開：`approval_policy=never` 下沒有逐次 escalation）。
- **Codex 不跑站別腳本與單樹重算。** refinement 搬單、engineering 開輪次與
  `place-issues-by-state.sh` 都由外包的那條線在沙箱外跑。2026-11-06 一趟 Codex 跑 refinement
  觸發重算，因為沒有 JIRA 憑證，重算搬了 55 張單；Codex 只做站裡的活：改檔、測試、量測、寫表。
- `~/.codex/AGENTS.md` 由使用者自己管理，不交給 Codex 或任何一條線改。
- **commit 由外包的那條線在沙箱外做。** 只用路徑限定的 `git add <檔>`，不用 `git commit -a`；
  2026-11-06 一次 `-a` 把 Codex 改的另一張單的檔掃進別的 commit。workspace-write 沙箱在主
  checkout、worktree 的 gitdir 與 issues 寫 `.git` 時都回 `index.lock: Operation not permitted`；
  官方文件寫 workspace-write 下 `.git` 與 gitdir 唯讀，`writable_roots` 與 `--add-dir` 都解不開。
  見 [codex-core README]。
- Codex 的 workspace-write 沙箱不准寫主 checkout 的 `.git`，fetch 與 `worktree add` 都會被拒，
  所以 fetch 與開 worktree 由外包的那條線在派工前做好，prompt 裡寫 worktree 路徑。
- 盲跑 runner 需要 `sandbox-exec`，Codex 沙箱裡起不來；盲跑與 preflight 留在 Claude 線。
- 2026-11-06 量到 `npx tsx` 跑同一支 prebuild 腳本回 `listen EPERM`，`node --import tsx` 跑同一支
  腳本 exit 0。要在沙箱裡 build 得改 repo 的 build 入口，而框架對 repo 的支援一律外掛、不往
  repo 寫，所以 build 留在 Claude 線。

[codex-core README]: https://github.com/openai/codex/blob/main/codex-rs/core/README.md

## 輪次

一輪沒產出 code 也是一輪。「試過 A，撞到 X，結論走 B，code 全丟」是正常結果——這一輪的產出
是知識，寫進可以改的那部分就是交付。不要為了讓這一輪看起來有東西，把失敗的探索包裝成交付。

```bash
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh record \
  --state {issue}/.spine/loop-state.json \
  --outcome converged|unconverged|zero_delta --note '<一句話>'
```

連續沒收斂到上限時流程升人類，不繼續自轉。上限是活區可調的參數，不是驗收條件。

## 三件要浮出來的事

方法自由，但有三件事 oracle 照不到，即使做了會變綠也要寫進可以改的那部分並講清楚為什麼，等人回話：

- **新增依賴**：把一個新套件拉進來。
- **重造既有組件**：手寫一個 repo 裡已經有的東西。
- **擴大 security surface**：多開一個對外介面、多讀一份憑證、多信任一個輸入。

共同點是後果落在綠燈之外——測試會過，代價在別的地方。

還有一件不是這一站能處理的：

- **需求留白的值**：門檻、數字、預設這類需求沒給、要由需求方拍板的值。這些值不是這一站能填的，
  施工填下去就是在改成功的定義。

撞到的時候停 `assertion_wrong`，回 `refinement`，跟上面〈在這裡發現問題，先自己解〉表裡
「assertion 不對」那一列走同一條路。要推一個建議值，那是 `refinement` 簽 assertion 時的事：照
`refinement`〈交給 PM 與使用者的開發計畫〉把建議值列進待確認，這裡不抄第二份。

2026-10-21 的標本：需求原文只寫「先用建議門檻」，施工時填成一個百分位與一個天數。計畫沒回寫，也沒標
RD 提案，上到測試環境才被使用者問到。使用者原話：「你還沒確認門檻就做了嗎！」這一節隨後一度寫成
「施工填完、回寫待確認就繼續」，跟本站「凍結塊不要動」相反。使用者原話：
「我們 /driving-work-to-done 不是有定義 /engineering 不能改定義，要退回重新 /refinement 嗎」

## 交出去

可以改的那部分寫到讓下一個人（可能是明天的你）能接手：現在在哪、試過什麼、為什麼走這條、下一步是
什麼。**凍結塊不要動**——需要動它時，回 `refinement`，而且改完要 commit：凍結 ＝ commit，
`verify` 會拿 fence 內文跟 git 歷史比，改了沒 commit 就是紅的，重簽也救不了。

這一輪做完，回 `driving-work-to-done` 讀下一步——換站與停點都由那裡回答，這一站不自己決定
往哪走。

### 開 PR 或往 PR 推改動之前，先跑 `check-your-own-work`

**這一輪會開 PR、或往一顆已經開著的 PR 推新的改動時，開之前在改動落下去的那棵樹上跑一次
`check-your-own-work`，把它列出的每一項處置完。** 怎麼指名那棵樹、為什麼要指名，在
`swe-knowledge`〈開 PR〉。

**紀錄寫進單上可以改的那部分，一段，行首是 `check-your-own-work 九問`，後面帶跑在哪個
head 上**，例如 `check-your-own-work 九問，head a96b2f94 → 013ef5c3`，接著逐問寫抓到什麼、
怎麼處置。行首這幾個字是給交付紀錄找的：`verify-ac` 寫交付紀錄時指向這一段，找不到就寫
「沒跑」。

**這種輪次，那段紀錄存在才記成收斂。** 沒有它就是還沒做完，不是做完了而少一份文件。

這一句放在這裡，是因為開 PR 的是這一站。2026-10-14 量到：同一個 epic 的九張子單只有兩張
跑過這一步，而那時候它只寫在 `swe-knowledge` 裡，這一站一個字都沒提。

### 送審之前，把自己寫下的話跟自己寫下的行為對一遍

這是 `check-your-own-work` 的第一問：這一輪寫下的每一句描述性的話，在 diff 裡都要找得到對應的
改動。在描述裡承認了一個邊界情況（「這裡可能是空的」），就要接著回答「那誰會收到這個空的」，
那是第九問。開 PR 之前跑那支 skill 時兩問都會問到，這裡不另寫一份。

### 一條裁決落地的那一輪，單上引用它的段落一起改

**收到一條裁決，同一輪 grep 這張單（與它的母單）上所有引用同一件事的段落，改到一致。**
commit 訊息列出改了哪幾段。裁決常常只落在一處，而單上依賴它的段落還寫著舊的說法；下一個
接手的人照那幾段做，做出來的是被推翻的那一版。使用者 2026-10-27 原話：「每張單的前因後果
應該都是清楚的，到底掉在哪」。那天一條裁決落在指揮官的紀錄裡，epic 上依賴它的三段沒有同一輪
改，新的線把其中一段照抄進對外的稿。

### 送審之前，先讓證據跟得上 head

`verify-ac` 的交付紀錄會逐條檢查：fence 宣告的每個 assertion ID 都要有 `verdict: PASS` 的證據，
而且**證據綁的 head 要等於要交付的那個 head**。證據證的是一棵樹綠了，不是一條分支綠了；
量完之後又推了三個 commit，那些證據就跟要出去的東西無關了。

所以順序是：**先追上 `origin/main` → code 全部 commit 完 → 才跑量測 → 才送審**。反過來做，
verify-ac 會把你打回來重量一次。

**第一步最常被跳過，而它的代價跟其他幾步一樣大。** 在一棵落後 `origin/main` 的樹上量完，
證據綁的是那棵舊樹；之後 rebase 上去，head 就換了，那批證據不再是要交付的那個 head 的
——**即使 rebase 前後的內容逐位元相同也一樣**，交付紀錄比的是 head，不是內容。被打回來時
要重跑的是整趟量測，不是一條命令。

**不要反過來去動那道檢查。** 給它加一個「rebase 產生的 commit 免驗」的例外，等於讓每一份
證據都可能釘在別的樹上——而那件事沒有任何輸出看得出來。
