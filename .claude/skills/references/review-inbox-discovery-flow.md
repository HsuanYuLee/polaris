---
title: "Review Inbox Discovery Flow"
description: "review-inbox 的 Label、Slack、Thread discovery、bundled scripts、review_status 判定與 scan freshness 規則。"
---

# Discovery Contract

這份 reference 負責找出需要自己 review 的 PR candidates。

## Defaults

從 workspace config 與 `shared-defaults.md` 取得：

| Value | Use |
|---|---|
| GitHub org | restrict PR URLs and repo scans |
| Slack PR channel | Slack mode scan source and notification target |
| need review label | Label mode |
| approval threshold | approve status summary |
| batch size | maximum PRs reviewed this run |
| concurrency | parallel review count only when a constrained code-reviewer adapter exists |
| confirm | list-only confirmation behavior |

Current GitHub username 必須動態取得，並排除自己的 PR。

## Bundled Scripts

使用 skill bundled scripts 做 deterministic discovery，不手動組 API query：

| Script | Purpose |
|---|---|
| `scan-need-review-prs.sh` | org-wide need review label scan |
| `fetch-prs-by-url.sh` | PR URLs -> PR metadata |
| `check-my-review-status.sh` | attach `review_status` and filter irrelevant PRs |
| `extract-pr-urls.py` | Slack JSON -> PR URLs, PR-thread mapping, root ticket / topic key mapping |
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
2. 把 channel dump 餵給 `extract-pr-urls.py` 產出 PR URLs 與 mapping——若輸入是單行
   escaped-JSON，由其共用 decoder 先確定性 normalize 成真換行 detailed dump（見上方
   § MCP detailed 輸出格式）。
3. **跑 fail-closed discovery probe**（見下方 § Discovery Fail-Closed Probe）：把 raw detailed
   channel dump 與 parser 產出的 candidate URL list 餵給 `review-inbox-discovery-probe.sh`，
   probe `exit 0` 後才往下走；probe `exit 2`（source-unavailable / format-mismatch / stale）
   時**早報並 fail loud**，不得靜默 fallback 到 label scan。
4. 用 `fetch-prs-by-url.sh` 取得 metadata 並排除自己的 PR。
5. 用 `check-my-review-status.sh` 判定 review status。
6. 用 `annotate-review-candidates.py --mapping <mapping.json>` 補 `cluster_role`,
   `cluster_key`, `cluster_lead_url`, `model_tier`。
7. Completion Envelope 回傳 annotated candidates JSON、mapping JSON、PR count、raw URL count，
   並附上 probe 的 marker line（`POLARIS_DISCOVERY_OK` / `POLARIS_DISCOVERY_LEGITIMATE_EMPTY`）。

主 session 不讀 raw Slack JSON，只讀 filtered artifacts。

## Discovery Fail-Closed Probe

Channel scan 在產出 candidates **之前**必須先過 `review-inbox-discovery-probe.sh`
（`scripts/review-inbox-discovery-probe.sh`）。這支 probe 是 prose-vs-gate 准入標準的 A 類
worked example：把一條原本只靠 prose「主來源不可用時應早報、不要靜默 fallback」的 invariant
落成 fail-closed gate（見 `.claude/rules/handbook/framework/contract-design.md`
§ prose-vs-gate 行為原則准入標準）。

### Invocation

```bash
bash scripts/review-inbox-discovery-probe.sh \
  --raw-dump <raw_detailed_channel_dump_file> \
  --candidates <parsed_pr_urls_file> \
  --stale-seconds <threshold> \
  --source-available 0|1
```

- `--raw-dump`：sub-agent 取得的 raw detailed channel text（含 `=== Message from ===` /
  `Message TS:`），**必填**。
- `--candidates`：`extract-pr-urls.py` 產出的 PR URL list（一行一個，可為空），**必填**。
- `--stale-seconds`：staleness 閾值，預設 `86400`（24h）。低流量 channel 應由 caller 放寬，
  不要硬編；threshold 是 per-source 參數（見下方 § Staleness Threshold）。
- `--source-available`：fetch 成功 / token 已設為 `1`（預設）；fetch 非零退出或 token 未設
  傳 `0`。

### 四態與 fail-loud 契約

| Probe 結果 | Exit | Marker | discovery 動作 |
|---|---|---|---|
| source-unavailable | 2 | `POLARIS_DISCOVERY_SOURCE_UNAVAILABLE` | **fail loud 早報**；不靜默 fallback 到 label scan |
| format-mismatch | 2 | `POLARIS_DISCOVERY_FORMAT_MISMATCH` | **fail loud 早報**（多半是 concise/detailed parser 不一致）；不靜默 fallback |
| stale | 2 | `POLARIS_DISCOVERY_STALE` | **fail loud 早報**（資料過舊）；不靜默 fallback |
| legitimate-empty | 0 | `POLARIS_DISCOVERY_LEGITIMATE_EMPTY` | 合法空 inbox，正常結束，回報 0 candidates |
| non-empty | 0 | `POLARIS_DISCOVERY_OK` | 帶 candidates 往下走 pipeline |

三個 `exit 2` 態（前三列）一律 **fail loud**：probe 一回非零就停下，把 marker 與 human note
回報給使用者，**禁止**把 degraded 狀態當成「沒有待 review PR」靜默改走 label scan 或宣告空
inbox。只有 `exit 0`（後兩列）才允許繼續：legitimate-empty 表示主來源 fetch 成功、格式正確、
資料新鮮、且真的 0 待 review PR，與 degraded-empty 明確區分（probe 的判定順序先排除
source-unavailable / format-mismatch，再判 stale，最後才回 legitimate-empty）。

### Staleness Threshold

`--stale-seconds` 預設 24h（`86400`）。低流量 channel 若硬套預設可能把正常但久未更新的
channel 誤判為 stale，因此這是 per-source 參數：caller 依 channel 流量放寬，不要在 probe 內
硬猜。需要覆寫時由 discovery sub-agent 在 invocation 帶入較大的 `--stale-seconds`。

## Thread Scan

Thread mode 只讀單一討論串，訊息量通常小，可在主 session 直接執行同一條 pipeline。
所有 URL 都映射到指定 `thread_ts`。

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
| `needs_re_review` | REQUEST_CHANGES 後作者已回覆 comments |

`valid_approve` 與 `waiting_for_author` 必須被過濾。Stale approval 判定見
`stale-approval-detection.md`。

`prior_review_no_new_push` 屬於 `waiting_for_author` 的 detail 分類：只要 reviewer 最新一次
review 是 `COMMENTED` / `CHANGES_REQUESTED` / `APPROVED` 任一狀態，且該 review 之後沒有新
commit，就不進 actionable candidate list。例外情境只能用明確 rerun / include-skipped 方式處理，
不得讓 discovery 預設重複 review 同一個 head SHA。

## Scan Freshness

Scan 是 point-in-time snapshot。每次 show list 或開始 review 前，檢查 scan result mtime。
若距離現在超過 60 秒，必須重跑 discovery；不可沿用舊 candidates JSON。
