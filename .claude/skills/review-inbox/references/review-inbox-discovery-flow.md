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
| `analyze-channel-dump.py` | 這份 dump 讀完了沒（窗翻到底了嗎、窗內的 thread 讀了嗎）|
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
   python3 .claude/skills/review-inbox/scripts/extract-pr-urls.py \
     --emit-normalized <normalized_dump_file> ...
   ```

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
- `--mode`：`channel`（預設）或 `thread`。`thread` 模式跳過涵蓋範圍的兩條判定。

### 四態與 fail-loud 契約

| Probe 結果 | Exit | Marker | discovery 動作 |
|---|---|---|---|
| source-unavailable | 2 | `POLARIS_DISCOVERY_SOURCE_UNAVAILABLE` | **fail loud 早報**；不靜默 fallback 到 label scan |
| format-mismatch | 2 | `POLARIS_DISCOVERY_FORMAT_MISMATCH` | **fail loud 早報**（多半是 concise/detailed parser 不一致）；不靜默 fallback |
| stale | 2 | `POLARIS_DISCOVERY_STALE` | **fail loud 早報**（資料過舊）；不靜默 fallback |
| 沒有分頁標記 | 2 | `POLARIS_DISCOVERY_NO_PAGINATION_MARKER` | dump 不是走 `--emit-normalized` 產生的，「讀完了沒」問不到；重做那一步 |
| 沒翻完窗 | 2 | `POLARIS_DISCOVERY_UNPAGED` | 帶訊息裡那個 cursor 再讀一頁接上去 |
| thread 沒讀 | 2 | `POLARIS_DISCOVERY_UNREAD_THREADS` | 逐條指名，照訊息裡那條命令把回覆接上去 |
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
# 對每一條這樣的 thread：
python3 .claude/skills/review-inbox/scripts/extract-pr-urls.py --org <org> \
  --emit-normalized-thread <那則訊息的 Message TS> < <slack_read_thread 的回應> \
  >> <normalized_dump_file>
```

它會把 thread 的 `From:` / `Time:` / `Message TS:` 三行翻成 channel 的
`=== Message from … ===` 抬頭（兩種格式不一樣，不翻的話 parser 一則都認不得），並在最前面
放一行 `=== Thread replies for TS <parent> ===`。那一行有兩個作用：parser 把這一段裡的
URL 全部掛到 `<parent>` 上（回覆自己的 ts 不是它所屬的 thread），probe 拿它當「這條讀過了」
的證據。

**哪幾條要讀不用自己數**——probe 會逐條指名（`POLARIS_DISCOVERY_UNREAD_THREADS`）。

## GitHub 條件掃描（第二來源，與 Slack 取聯集）

Slack 那條路徑的前提是「有人說話」。這一條沒有這個前提：

```bash
bash .claude/skills/review-inbox/scripts/scan-my-stale-reviews.sh \
  --my-user <github_username> --org <github_org> \
  [--merge-with <Slack 那條路徑產出的 candidates JSON>]
```

它問 GitHub：我投過票、還 open 的 PR 裡，哪幾顆的 head 已經不是我最後一票綁的那顆
commit。輸出格式與 `fetch-prs-by-url.sh` 相同，可以直接接 `check-my-review-status.sh`。
`--merge-with` 把兩條來源以 url 去重後取聯集——**聯集在腳本裡做**，不是散文裡的一行 jq。

問不到上游時它離場 2 並印 `POLARIS_STALE_REVIEW_SCAN_UNAVAILABLE`，不回空陣列：
`gh search` 對打錯的 owner 會回 `[]` 而且離場 0，那跟「問到了而且沒有」分不開。

## Thread Scan

Thread mode 只讀單一討論串，訊息量通常小，可在主 session 直接執行同一條 pipeline。
所有 URL 都映射到指定 `thread_ts`。Probe 用 `--mode thread` 跑：那裡沒有「翻完頻道」
這回事，涵蓋範圍的兩條判定跳過。

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

Scan 是 point-in-time snapshot。每次 show list 或開始 review 前，檢查 scan result mtime。
若距離現在超過 60 秒，必須重跑 discovery；不可沿用舊 candidates JSON。
