---
title: "Review Inbox Discovery Flow"
description: "review-inbox 的 Label、Slack、Thread discovery、bundled scripts、review_status 判定與 scan freshness 規則。"
---

# Discovery Contract
<!-- PROSE-EXTERNAL-PATHS: contract-design.md — handbook 那個 repo 的設計文件 -->

這份 reference 負責找出需要自己 review 的 PR candidates。

## Defaults

從 `workspace-config.yaml`（含 `defaults` 區塊）取得：

| Value | Use |
|---|---|
| GitHub org | restrict PR URLs and repo scans |
| Slack PR channel | Slack mode scan source and notification target |
| need review label | Label mode |
| approval threshold | approve status summary |

Current GitHub username 必須動態取得，並排除自己的 PR。

## Bundled Scripts

使用 skill bundled scripts 做 deterministic discovery，不手動組 API query：

| Script | Purpose |
|---|---|
| `scan-need-review-prs.sh` | org-wide need review label scan |
| `fetch-prs-by-url.sh` | PR URLs -> PR metadata |
| `check-my-review-status.sh` | attach `review_status` and filter irrelevant PRs |
| `extract-pr-urls.py` | Slack JSON -> PR URLs, PR-thread mapping, root ticket / topic key mapping；也負責 normalize channel dump 與 thread section |
| `scan-my-stale-reviews.sh` | 不靠 Slack 的第二來源：我投過票而 head 已推進的 open PR |
| `scan-unreviewed-prs.sh` | 不等任何人動作的第三來源：指名的 repo 裡我一票都沒投過的 open PR |
| `analyze-channel-dump.py` | 這份 dump 讀完了沒、而且只有這一趟嗎（窗翻到底了嗎、窗內的 thread 讀了嗎、有沒有混進別趟的 thread 區段）|
| `annotate-review-candidates.py` | attach sister PR cluster metadata and model tier hints |
| `slack-webapi.sh` | Slack MCP fallback for read and send |

Script path 以 skill directory 為準。

`check-my-review-status.sh` 的 canonical invocation 是：

```bash
check-my-review-status.sh --my-user <github_username> --org <github_org>
```

Backward-compatible invocation `ORG=<github_org> check-my-review-status.sh <github_username>` 也可用。
Discovery sub-agent 不得把 `--my-user` 當 positional argument，也不得省略 GitHub org；否則所有
review state 會比對錯誤，已 reviewed at head 的 PR 會被誤列為 `needs_first_review`。

## Source Selection

Thread mode 優先：使用者訊息含 Slack URL 且有 review intent。從 URL 解析 channel ID 與
thread timestamp；若 URL 不是 thread link，將 message timestamp 當作 thread root。

Label mode：只有使用者明確提到 `need review` label、`review inbox`、或 label scan 才使用。

Slack mode：其他 batch review intent 的預設來源，從 PR channel 最近訊息提取 PR URLs。
時間範圍依使用者語意推導；未指定時用 7 天。

## Slack Channel Scan

Slack mode 的 channel scan 應委派給 sub-agent，避免 100+ raw Slack messages 進主 context。

### Newest-first 讀法（不傳 oldest）

Channel scan 一律 **newest-first**：先抓最新一頁（`limit 100`），需要更舊訊息時再以
cursor / pagination 往回翻，**讀到第一則超出時間窗的訊息即停**，不無限翻頁。低流量
channel 若整頁都還在時間窗內就讀完整頁即停（見 § Source Selection 的 7 天預設與使用者
語意推導）。

**這一段以前只是散文，而散文沒有被執行。** 2026-09-04 兩輪 discovery 各驗一次：兩輪的
dump 都停在 66 則、最舊 08-31，而 MCP 兩次都明確回了 cursor（`next_ts:1788153051271299`）。
兩輪的 sub-agent 指示都沒寫「看到 cursor 就翻」，而兩輪的答案都是 `POLARIS_DISCOVERY_OK`
——一份只涵蓋窗尾巴的資料，跟一份完整的資料，在原本那四個狀態底下長得一模一樣。

**現在有東西在問了**：`extract-pr-urls.py --emit-normalized` 會把 payload 的 cursor 寫成
一行 `Pagination cursor: <值>`（沒有下一頁時寫 `(none)`），probe 讀它。所以
**每一頁都要走 `--emit-normalized` 產生 dump 再接起來**——直接把 MCP 的回應存成檔案的話
那一行不會存在，probe 回 `POLARIS_DISCOVERY_NO_PAGINATION_MARKER`。

**不要傳 `oldest`**（不論是 MCP 參數還是 `slack-webapi.sh read-channel --oldest`）來限縮
channel scan 的起點。

> **Pitfall：oldest → stale**
> 傳 `oldest` 會把讀取錨定在一個**過去的時間點**，於是只回傳「`oldest` 之後、但仍可能是
> 數天前」的舊訊息，最新的 PR 訊息反而落在回傳視窗之外。下游 `review-inbox-discovery-probe.sh`
> 對這批舊訊息做 staleness 判定時，最新 message TS 已超過 `--stale-seconds` 閾值，於是
> probe 回 `exit 2` + `POLARIS_DISCOVERY_STALE`，整條 discovery 被誤判成「資料過舊」而 fail
> loud。Newest-first 從最新訊息往回讀，最新 message TS 就是真正的最新時間，主來源實際有效
> 時不會再觸發 `POLARIS_DISCOVERY_STALE`。

### MCP output format 一律 detailed（不可用 concise）

Sub-agent 先試 Slack MCP，並且**一律指定 `detailed` output format**；timeout、auth error、
unavailable 時改用 `slack-webapi.sh` fallback。Fallback `read-channel` 同樣 newest-first：
不傳 `--oldest`，由 script 取最新訊息往回翻。

`detailed` 是**唯一合法**的 channel scan 格式，理由是 `extract-pr-urls.py` 的 channel mode
parser 只認 detailed dump 才有的兩種 marker：

- 每則訊息開頭的 `=== Message from {Name} (UXXXX) at {time} ===` header。
- 訊息 body 內的 `Message TS: {epoch_float}` 行（parser 一律從這行取 `thread_ts`）。

`concise` format 不輸出這兩種 marker，會讓 parser 找不到 message header 而**靜默回傳 0 URL**
（stderr 只印一行 WARN）。對主來源仍有訊息的 channel 來說，concise → 0 URL 的結果與
「channel 真的空」無法區分，正是這條 discovery flow 過去靜默退化成空 inbox 的根因。因此
sub-agent **不得**指定 `concise`，fallback `slack-webapi.sh` 也必須輸出含上述 header / TS 行
的 detailed dump。

### MCP detailed 輸出格式：單行 escaped-JSON → 確定性 normalize

Slack MCP 的 `detailed` channel scan 輸出在某些 runtime 下不是「人眼可讀的多行 dump」，
而是**單行 escaped-JSON**——整批訊息被序列化成一行 JSON 字串，真換行被 escape 成字面
`\n`、`=== Message from ===` header 與 `Message TS:` 行也都藏在 escaped 字串裡。直接餵這種
單行 escaped-JSON 給 `extract-pr-urls.py` channel parser，parser 找不到實體的 message
header marker，會與 concise → 0 URL 相同症狀：誤判成空 channel。

正確處理是**確定性 normalize**，不是叫 sub-agent 手動 `json.loads` 再貼回：

1. 偵測輸入是否為單行 escaped-JSON（單行、可被 `json.loads` 還原成含 `\n`、message
   marker 的字串）。
2. 是 → decode 成 canonical 真換行 detailed dump（含 `=== Message from {Name} (UXXXX) at
   {time} ===` header 與 `Message TS: {epoch_float}` 行），讓 `extract-pr-urls.py` 與
   `review-inbox-discovery-probe.sh` 兩個 consumer 看到**同一份**真換行格式，避免兩端 parse
   假設 drift。
3. 否（已是真換行 detailed dump，例如 `slack-webapi.sh` fallback 產出）→ passthrough，
   **不** 再 decode、不破壞既有格式。
4. 真正的空輸入 / fetch 失敗 → 不被 normalize 掩蓋，仍由 probe 回
   `POLARIS_DISCOVERY_SOURCE_UNAVAILABLE`（normalize 只負責格式轉換，不負責偽裝 source
   有效）。

這個 normalize 由 `extract-pr-urls.py` 的前處理（共用單一 decoder）承擔，是 Gap 3 的
deterministic enforcement（`contract-design.md` Heuristic 1 — Deterministic-First）；本節
只記錄格式與步驟，dispatch sub-agent 不需也不應手動 decode escaped-JSON。

### Sub-agent pipeline

1. 讀 channel messages（detailed format，newest-first；不傳 oldest）。
2. **把 dump normalize 成真換行的 detailed 格式，寫成一個檔。** 這一步是獨立的，因為
   下游有兩個 consumer（parser 與 probe），而它們必須看到**同一份**文字：

   ```bash
   python3 .claude/skills/review-inbox/scripts/extract-pr-urls.py --org <org> \
     --emit-normalized < <MCP 回應的檔> > <normalized_dump_file>
   ```

   **`--emit-normalized` 不吃參數**，它把結果寫到 stdout，所以那個檔名要用 `>` 導向，
   不能接在旗標後面（接了會拿到 `error: unrecognized arguments`）。下面 § Channel scan 也要讀
   thread（不只 top-level）用的 `--emit-normalized-thread` **吃一個 TS**——兩個旗標長得像，只有後者
   收參數。

   這個 runtime 的 MCP detailed 回的是單行 escaped-JSON——真換行被 escape 成字面的 `\n`，
   header 藏在字串裡（見上方 § MCP detailed 輸出格式）。
3. **跑 fail-closed discovery probe**（見下方 § Discovery Fail-Closed Probe）：把**上一步
   產出的 normalized dump**與 parser 產出的 candidate URL list 餵給
   `review-inbox-discovery-probe.sh`，probe `exit 0` 後才往下走；`exit 2` 時**早報並 fail
   loud**，不得靜默 fallback 到 label scan。

   餵還沒 normalize 的那一份會拿到 `POLARIS_DISCOVERY_NOT_NORMALIZED`，訊息裡帶著上面那條
   命令。那不是錯誤處理，是這一步被跳過時的說法——2026-08-09 之前它回的是
   `POLARIS_DISCOVERY_SOURCE_UNAVAILABLE`，於是每一次 Slack mode 都把一份完整的資料讀成
   「上游拿不到」。
4. 用 `fetch-prs-by-url.sh` 取得 metadata 並排除自己的 PR。
5. 用 `check-my-review-status.sh` 判定 review status。
6. 用 `annotate-review-candidates.py --mapping <mapping.json>` 補 `cluster_role`,
   `cluster_key`, `cluster_lead_url`, `model_tier`。
7. Completion Envelope 回傳 annotated candidates JSON、mapping JSON、PR count、raw URL count，
   並附上 probe 的 marker line（`POLARIS_DISCOVERY_OK` / `POLARIS_DISCOVERY_LEGITIMATE_EMPTY`）。

主 session 不讀 raw Slack JSON，只讀 filtered artifacts。

## Discovery Fail-Closed Probe

Channel scan 在產出 candidates **之前**必須先過 `review-inbox-discovery-probe.sh`
（`.claude/skills/review-inbox/scripts/review-inbox-discovery-probe.sh`）。這支 probe 是 prose-vs-gate 准入標準的 A 類
worked example：把一條原本只靠 prose「主來源不可用時應早報、不要靜默 fallback」的 invariant
落成 fail-closed gate（見 `polaris-config/polaris-framework/handbook/contract-design.md`
§ prose-vs-gate 行為原則准入標準）。

### Invocation

```bash
bash .claude/skills/review-inbox/scripts/review-inbox-discovery-probe.sh \
  --raw-dump <normalized_channel_dump_file> \
  --candidates <parsed_pr_urls_file> \
  --window-seconds <這一趟回溯多久，秒> \
  --now-epoch <這一趟開始的那一刻，epoch 秒> \
  --stale-seconds <threshold> \
  --mode channel|thread \
  --source-available 0|1
```

- `--raw-dump`：**上一步產出的 normalized detailed dump**（`=== Message from ===` /
  `Message TS:` 各自佔一行），**必填**。旗標名字留著沒改是因為它已經被別處引用；它要的
  是 normalize 過的那一份，不是 MCP 直接吐出來的那一份。
- `--candidates`：`extract-pr-urls.py` 產出的 PR URL list（一行一個，可為空），**必填**。
- `--stale-seconds`：staleness 閾值，預設 `86400`（24h）。低流量 channel 應由 caller 放寬，
  不要硬編；threshold 是 per-source 參數（見下方 § Staleness Threshold）。
- `--source-available`：fetch 成功 / token 已設為 `1`（預設）；fetch 非零退出或 token 未設
  傳 `0`。
- `--window-seconds`：這一趟宣告的回溯時間窗，**channel 模式必填**。它由 § Source
  Selection 的語意推導而來（未指定時 7 天 = `604800`）。probe 不替你挑一個——挑了的話
  「窗有多長」就有兩個答案，而其中一個沒有人看得到。
- `--now-epoch`：窗的**起點**，**channel 模式必填**。一趟 run 開始時定一次
  （`date +%s`），寫下來，之後**每一次 probe 都交同一個值**。理由跟上一條是同一個：窗有
  多長與窗從哪裡開始是同一個參數的兩半，probe 兩半都不替你挑。
  **每次各自重算會怎樣**：窗的起點跟著時鐘往前爬，於是同一份 dump 的判定會隨著現在幾點
  翻面——一段合法的 thread 回覆在十幾分鐘後被判成不屬於這一趟（假紅，而它印的修法是去刪掉
  那幾段），而一份沒翻完窗的 dump 在十幾分鐘後過關（假綠）。兩個方向都在真的 run 上出現過
  （DP-714）。
- `--mode`：`channel`（預設）或 `thread`。`thread` 模式跳過涵蓋範圍的三條判定，窗在那裡
  不參與任何事，所以那個模式不必交 `--now-epoch`。

### 四態與 fail-loud 契約

| Probe 結果 | Exit | Marker | discovery 動作 |
|---|---|---|---|
| source-unavailable | 2 | `POLARIS_DISCOVERY_SOURCE_UNAVAILABLE` | **fail loud 早報**；不靜默 fallback 到 label scan |
| format-mismatch | 2 | `POLARIS_DISCOVERY_FORMAT_MISMATCH` | **fail loud 早報**（多半是 concise/detailed parser 不一致）；不靜默 fallback |
| stale | 2 | `POLARIS_DISCOVERY_STALE` | **fail loud 早報**（資料過舊）；不靜默 fallback |
| 沒有分頁標記 | 2 | `POLARIS_DISCOVERY_NO_PAGINATION_MARKER` | dump 不是走 `--emit-normalized` 產生的，「讀完了沒」問不到；重做那一步 |
| 沒翻完窗 | 2 | `POLARIS_DISCOVERY_UNPAGED` | 帶訊息裡那個 cursor 再讀一頁接上去 |
| thread 沒讀 | 2 | `POLARIS_DISCOVERY_UNREAD_THREADS` | 逐條指名，照訊息裡那條命令把回覆接上去 |
| 混進別趟的 thread | 2 | `POLARIS_DISCOVERY_NOT_ONLY_THIS_RUN` | 逐條指名；把不屬於這一趟的那幾段從 dump 裡拿掉 |
| 算不出涵蓋範圍 | 2 | `POLARIS_DISCOVERY_DUMP_UNMEASURABLE` | dump 裡沒有可校準的訊息抬頭；先確認格式 |
| legitimate-empty | 0 | `POLARIS_DISCOVERY_LEGITIMATE_EMPTY` | 合法空 inbox，正常結束，回報 0 candidates |
| non-empty | 0 | `POLARIS_DISCOVERY_OK` | 帶 candidates 往下走 pipeline |

前面幾個 `exit 2` 態一律 **fail loud**：probe 一回非零就停下，把 marker 與 human note
回報給使用者，**禁止**把 degraded 狀態當成「沒有待 review PR」靜默改走 label scan 或宣告空
inbox。只有 `exit 0`（後兩列）才允許繼續：legitimate-empty 表示主來源 fetch 成功、格式正確、
資料新鮮、且真的 0 待 review PR，與 degraded-empty 明確區分（probe 的判定順序先排除
source-unavailable / format-mismatch，再判 stale，最後才回 legitimate-empty）。

### Staleness Threshold

`--stale-seconds` 預設 24h（`86400`）。低流量 channel 若硬套預設可能把正常但久未更新的
channel 誤判為 stale，因此這是 per-source 參數：caller 依 channel 流量放寬，不要在 probe 內
硬猜。需要覆寫時由 discovery sub-agent 在 invocation 帶入較大的 `--stale-seconds`。

### Channel scan 也要讀 thread（不只 top-level）

**這個團隊的「我改好了，再看一次」幾乎都寫在 thread 回覆裡。** 2026-09-04 量到的：
`pull/10694` 自 09-01 起在 #b2c-web-pr 的每一則提及（09-02、09-03、09-04 各數則），
permalink 全帶 `thread_ts=1787297348.327969`——那是一條 08-17 開的公告 thread。
`slack_read_channel` 一頁 79 則、回溯到 08-28，`pull/10694` 命中 0 次；`pull/2979`、
`12709`、`10698` 也都是 0。不是沒翻頁，是**這些訊息在 top-level 根本不存在**。

所以 channel scan 的第二步是：dump 裡每一則帶著
`Thread: N replies (latest: …)` 而**最新回覆落在時間窗內**的訊息，都要把它的回覆讀進來。
判準用 `latest`，不看 top-level 自己的時間——長壽 thread 是這個團隊的常態，那條公告
thread 的根落在窗外 14 天。

```bash
# 一批一條命令，TS 明列在迴圈裡：
for ts in <這一批的 TS…>; do
  python3 .claude/skills/review-inbox/scripts/extract-pr-urls.py --org <org> \
    --emit-normalized-thread "$ts" < threads/"$ts".json >> <normalized_dump_file>
done
```

**一批的 `slack_read_thread` 在同一個回合裡一起發出去，不要一條一條輪流。** 這一段的成本
幾乎全是往返：2026-09-16 實測一趟 discovery 59 分 30 秒，其中 **52 分鐘（88%）**花在逐條讀
43 條 thread——每條 72 秒，而 Slack 的回應本身不用那麼久。probe 本來就一次把該讀的全部指名
了，所以它分得了批。

**批要多大不寫在這裡。** `analyze-channel-dump.py` 的 `THREAD_READ_BATCH_SIZE` 說了算，而
probe 把切好的批直接印出來——一份抄在散文裡的數字會跟那一邊漂開，而漂掉的那一刻沒有人在看。


它會把 thread 的 `From:` / `Time:` / `Message TS:` 三行翻成 channel 的
`=== Message from … ===` 抬頭（兩種格式不一樣，不翻的話 parser 一則都認不得），並在最前面
放一行 `=== Thread replies for TS <parent> ===`。那一行有兩個作用：parser 把這一段裡的
URL 全部掛到 `<parent>` 上（回覆自己的 ts 不是它所屬的 thread），probe 拿它當「這條讀過了」
的證據。

**哪幾條要讀、分成幾批，都不用自己數**——probe 會把該讀的逐條指名，然後切好批印出來（`POLARIS_DISCOVERY_UNREAD_THREADS`）。**切批不改「哪幾條該讀」**：少讀幾條換到的時間，買的是一份不完整的 dump，而它跟完整的那一份長得一樣。

**接回 dump 的時候明列這一趟的那幾個 TS，不要用 `threads/*.json` 這種 glob。** session 的
scratchpad 跨天重用，那個目錄裡躺著上一輪的 payload；glob 一次接回來的是兩趟的東西。
2026-09-14 量到的：正確的 dump 100 顆候選，接上 47 個舊 payload 之後 108 顆，多出來的 8 顆
全是舊窗的 PR。**多出來的候選會被真的派去 review**，而「多看了幾顆」沒有人會抱怨，所以
這個誤差方向本來永遠不會有人來報。

現在 probe 會問這一題（`POLARIS_DISCOVERY_NOT_ONLY_THIS_RUN`）：**判準是那一段的 parent**
——它要是這份 dump 裡一則帶著 `Thread:` 行、而且最新回覆落在窗內的訊息，也就是上一段說的
那個唯一來源。判準不看那一段裡面回覆的時間：讀一條 thread 本來就會帶回它全部的回覆，而
長壽 thread 是這個團隊的常態。真的要讀一條 top-level 不在這一頁的 thread，就把 channel
那一頁先翻到涵蓋它。

**parent 只從 channel 那一頁的 top-level 找，區段裡那一份不算。** `slack_read_thread` 的第
一則就是 parent 自己，所以每一段裡面都有一份它——而那一份沒有 `Thread:` 那一行。拿它來回答
「這一段的 parent 長什麼樣」，每一段都會被判成外來：2026-09-14 一趟 52 段全紅，而那 52 段
每一段都是對的（DP-712）。同一個理由，「這一頁翻到哪」也只問這一頁的 top-level——區段裡一
則舊回覆就足以讓那個判定安靜下來。

## GitHub 條件掃描（第二來源，與 Slack 取聯集）

Slack 那條路徑的前提是「有人說話」。這一條沒有這個前提：

```bash
bash .claude/skills/review-inbox/scripts/scan-my-stale-reviews.sh \
  --my-user <github_username> --org <github_org> \
  [--merge-with <Slack 那條路徑產出的 candidates JSON>]
```

它問 GitHub：我投過票、還 open 的 PR 裡，哪幾顆的 head 已經不是我最後一票綁的那顆
commit。**它自己會把找到的那幾顆交給 `check-my-review-status.sh` 補上 `review_status` 與
`review_detail` 再輸出**，所以輸出跟 Slack 那條路徑的 candidates 同形，不要再接一次。
補不到的時候它印 `POLARIS_STALE_REVIEW_STATUS_UNAVAILABLE` 並說出有幾顆沒有狀態——那幾顆
下游接不住，不是安靜地少一個欄位。

`--merge-with` 把兩條來源取聯集——**聯集在腳本裡做**，不是散文裡的一行 jq。同一個 `url`
在兩邊都有時合併的是**欄位**，不是挑一整列留下：挑一列的寫法保留的是輸入順序的第一列，
而這條路徑固定把自己掃出來的那一列放在前面，於是欄位比較多的另一列每次都輸。每一個鍵取
兩邊非空的值排序後的第一個，所以結果由值本身決定，不由誰先進陣列決定。

問不到上游時它離場 2 並印 `POLARIS_STALE_REVIEW_SCAN_UNAVAILABLE`，不回空陣列：
`gh search` 對打錯的 owner 會回 `[]` 而且離場 0，那跟「問到了而且沒有」分不開。

## GitHub 首次 review 掃描（第三來源，與前兩條取聯集）

前兩條都錨在**有人針對我做了動作**：Slack 那條要有人把 PR 貼進頻道，`scan-my-stale-reviews.sh`
的定義域是「我投過票、而 head 已經推進」。兩個定義域的交集是空的，聯集也不涵蓋**一顆我還
沒碰過的 PR**——那一類結構上進不了任何一條。

```bash
bash .claude/skills/review-inbox/scripts/scan-unreviewed-prs.sh \
  --my-user <github_username> --org <github_org> \
  --repo <name> [--repo <name>]... \
  [--updated-within-seconds <秒，預設 604800>] \
  [--merge-with <前兩條產出的 candidates JSON>]
```

它問 GitHub：指名的那幾個 repo 裡，哪幾顆 open、非 draft、不是我開的 PR 我一票都還沒投。
輸出與另外兩條同形（`review_status` 由 `check-my-review-status.sh` 補，不要再接一次），
`--merge-with` 的聯集跟那一條走同一份實作（`lib/merge-candidates.sh`）。

### 為什麼「有人指名要我」不是這條腿的判準

`review-requested:<me>` 漏掉的是同一類：**review request 常常指到 team 而不是個人。**
2026-09-16 的實例——某個 repo 上一顆 PR 的 review request 指的是兩個 team，於是
那一組 38 顆裡沒有它；它也沒有任何 label，所以 Label mode 一樣看不到。三條既有路徑同時
為零，而那顆 PR 在等人看。

### `--repo` 沒有預設，一個都不給就拒絕執行

**這支不掃整個 org。** org-wide 的搜尋會被單頁上限截斷，而上游仍然回離場碼 0——那跟
「問到了而且就這幾顆」分不開。同一天實測：一次 org-wide 查詢在其中一個 repo 上只回
9 顆，單問那個 repo 是 35 顆。**誤差方向是「比較少」，所以沒有人會來報。**

要問哪幾個 repo 是呼叫者的知識，讀公司自己的 `workspace-config.yaml` 的
`github.review_repos`。那份清單由人列，**不從 `reviewed-by` 的歷史動態推**：那樣推有冷啟動
問題——一個剛加入的 repo 不會出現在歷史裡，於是它的 PR 永遠掃不到，而那正是這條腿要修的
形狀。

### 窗由呼叫者傳

`--updated-within-seconds` 預設 7 天，跟 § Source Selection 的頻道掃描預設窗一致。**沒有窗
的話長尾會淹掉清單**：2026-09-16 對三個 repo 實測共 40 顆，只有 15 顆是七天內更新過的，其餘
最舊的一顆是兩年前開的。要不設窗傳 `0`。

### 走 repo 自己的 pulls 清單，不走搜尋端點

搜尋端點一句話就問得到「我沒投過票的 open PR」，但它的次級限流極緊：2026-09-16 實測，三個
repo 連著問在第三個撞 403，中間隔 3 秒再問還是撞。**而撞到的代價是整批候選消失**——這一支
照設計離場 2，那是對的行為，但收件匣那一天就是空的。

`repos/{owner}/{repo}/pulls` 走另一個額度桶（每小時 5000 次），代價是「我投過票沒」要逐顆
問。三個 repo、七天窗實測是十幾次呼叫、27 秒，離那個上限很遠。換桶還順帶解掉搜尋索引的延遲
——同一趟裡剛開幾分鐘的 PR，搜尋端點還看不到，清單端點已經有了。

### 被擋住不等於沒有

離場碼 2 ＋ `POLARIS_UNREVIEWED_SCAN_UNAVAILABLE`，三種情況都算問不到：清單端點離場非 0
（**限流回的 403 是這一種**）、回應形狀不對、**某一顆的票數問不到**。最後那一種特別要說：
問不到不得當成「我沒投過」——那個方向會把一顆已經看過的 PR 再送一次，而它跟真的沒看過長得
一樣。**一顆都不回，不回空陣列**：問不到與沒有的下一步相反。

## Thread Scan

Thread mode 只讀單一討論串，訊息量通常小，可在主 session 直接執行同一條 pipeline。
所有 URL 都映射到指定 `thread_ts`。Probe 用 `--mode thread` 跑：那裡沒有「翻完頻道」
這回事，涵蓋範圍的三條判定跳過。

## Sister PR Cluster And Model Tier Annotation

Discovery 結束後，所有來源都必須執行 `annotate-review-candidates.py`。Annotation rules：

- Cluster key = `(thread_ts, root_ticket_key || root_topic_key || ticket_key)`。
  `extract-pr-urls.py` 從 Slack root message 的第一個 PR URL 前方擷取 umbrella ticket，
  例如 `DEMO-493`；若 root 沒有 umbrella ticket，但前綴有 topic signal
  （例如 `JsBridgeUtils platform case insensitive` 或 `favicon.ico`），mapping 寫入
  deterministic `root_topic_key`，避免同 thread topic-only cross-repo PR 被不同 per-PR
  ticket 拆散；最後才 fallback 到 PR title / URL / repo 的 `APP-NNN` 或通用
  `PROJECT-NNN`。
- 同一 cluster 內按 `(repo, PR number)` 排序，第一筆是 `cluster_lead`，其餘是
  `cluster_sibling`。
- `cluster_lead` 使用 `standard_coding`，完整 review 並留下 lead summary。
- `cluster_sibling` 使用 `small_fast` model class hint 跑 sibling-diff mode；若行為差異或
  confidence 不足，輸出 `needs_standard_review` 讓主流程升級。
- 非 cluster PR 依 PR size/path 判斷 model tier：單檔且 additions+deletions <= 50，或全為
  asset/config/changeset-only 檔案時用 `small_fast`；其他用 `standard_coding`。

## Review Status

Candidates 只保留：

| Status | Meaning |
|---|---|
| `needs_first_review` | reviewer 尚未 review |
| `needs_re_approve` | approve 後作者有新 commit，approval stale |
| `needs_re_review` | 我上次 review 之後 head 已經推進（不論上次投的是哪一種票、也不論作者有沒有回留言）|

`valid_approve` 與 `waiting_for_author` 必須被過濾。Stale approval 判定見
`stale-approval-detection.md`。

**`needs_re_review` 不再問作者有沒有回留言（DP-681）。** 以前「CHANGES_REQUESTED 之後
有新 push 但作者沒回話」被判成 `waiting_for_author` 而濾掉，於是一顆作者早就修好的 PR
永遠回不到收件匣——2026-09-04 一次量到五顆。使用者拍板：作者推了就是要人看。

`prior_review_no_new_push` 屬於 `waiting_for_author` 的 detail 分類：只要 reviewer 最新一次
review 是 `COMMENTED` / `CHANGES_REQUESTED` / `APPROVED` 任一狀態，且該 review 之後沒有新
commit，就不進 actionable candidate list。例外情境只能用明確 rerun / include-skipped 方式處理，
不得讓 discovery 預設重複 review 同一個 head SHA。

## Scan Freshness

Scan 是 point-in-time snapshot。不可沿用舊 candidates JSON：**派工之前，對候選清單再核
一次**，而 60 秒的門檻對那次重核計時。

**門檻錨在重核，不錨在 discovery 產出。** discovery 自己可以跑得比門檻久——逐條讀完一個
頻道的 thread 可以要二十幾分鐘，跑完的那一刻清單就已經過期，照字面「重跑 discovery」永遠
追不上。所以真正讓清單新鮮的是派工前那一次核對：

1. 把最新一頁**整頁**重抽 PR URL，跟清單比，新出現的補進去（照一般路徑查狀態）。
2. 重跑第二來源（〈GitHub 條件掃描〉那一支），新出現的一樣補進去。
3. 重跑第三來源（〈GitHub 首次 review 掃描〉那一支），同樣補進去。**這一條不能省**：
   重核之間新開的 PR 只有這條腿看得到——它不必等任何人把它貼出來，也不必等我先投過票。
4. 從這一刻起 60 秒內開始派工；超過就再核一次。

**只讀 ts 比上一輪新的訊息，不算重跑，也不算重核。** Slack 編輯一則訊息不會更新它的
ts，所以一則被編輯過、內容換成另一顆 PR 的訊息，照時間過濾會被判成舊的而略過。
2026-09-10 的實例：有人在頻道裡把一則訊息裡的 PR 劃掉、補上新開的那一顆，那則訊息的時間
仍是早上那一刻；只讀新訊息的那一次重驗漏掉它，是整頁重抽 URL 才抓到。整頁重抽讀的是訊息
**現在**的文字，所以編輯過的內容自然在裡面，不需要另外看編輯標記。

**重核不重讀 thread。** discovery 跑完之後才出現在某一條 thread 裡的回覆，這次重核看不到；
那一類要等下一次 discovery。
