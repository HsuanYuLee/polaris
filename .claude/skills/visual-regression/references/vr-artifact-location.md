# VR 產出物住哪

一次 VR 跑完會留下三種東西：baseline 截圖、mockoon fixtures、比對報告。**它們屬於某一張
單**，所以跟著那張單走。

## 預設：單自己的目錄

```
issues/{命名空間}/{單號}/
├── index.md                  # 活文件——比對結果、判讀、下一步都寫這裡
└── tests/
    ├── vr/baseline/          # baseline 截圖（單存續期）
    │   ├── homepage-zh-tw-1280.png
    │   └── ...
    └── mockoon/              # mockoon 環境 JSON（錄製或 bootstrap 而來）
        ├── dev.exampleco.com.json
        └── api-*.json
```

**報告寫進那張單的 `{issue}/index.md`，不另開檔案。** 一張單的過程紀錄住在它的活文件裡，這是
`.claude/rules/document-flow.md` 的規矩；截圖與 fixtures 是二進位與設定，才需要自己的路徑。

## 外部使用：建一個帶單號的目錄

這支 skill 會被帶到沒有 `issues/` 的地方（別的 repo、claude.ai、Cowork）。那裡沒有單的
目錄可以放，所以**在當下的工作目錄建一個以單號命名的目錄**，底下的形狀跟上面一樣：

```
{單號}/
└── tests/
    ├── vr/baseline/
    └── mockoon/
```

單號從哪來：JIRA ticket key、git branch（`feat/{單號}-*`）、或命令列參數。三個都取不到時
**停下來問**，不要拿時間戳或 `default` 湊一個——一批沒有單號的截圖，三天後沒有人知道它
在驗什麼。

## 換位置由流程做，不由這支 skill 做

一張單換不換位置，由 `issues/{命名空間}/{單號}/.spine/loop-state.json` 的 `status` 決定，
沒有第二個開關。`spine-loop-state.sh record` 寫完輪次就呼叫 `place-issues-by-state.sh`，
把每一張單重算到它的狀態說的那一格。

```bash
bash .claude/skills/driving-work-to-done/scripts/place-issues-by-state.sh --issues issues --check
```

`--check` 是用來讓「位置與狀態對不上」被看見，不是用來讓人選一邊。手動 `git mv` 一張單，
下一次 `record` 會把它搬回它該在的地方——這是對的。想讓一張單離開待辦清單，讓它收斂，
不要搬它。

## Bootstrap：從上一張單接過來

新的一張單第一次跑 VR 時，`tests/vr/baseline/` 與 `tests/mockoon/` 是空的。可以從上一張
單複製當起點：

```bash
cp -r issues/{命名空間}/{上一張單}/tests/mockoon/ issues/{命名空間}/{這張單}/tests/mockoon/
cp -r issues/{命名空間}/{上一張單}/tests/vr/baseline/ issues/{命名空間}/{這張單}/tests/vr/baseline/
```

- **mockoon**：這張單要打的 API 通常跟上一張大致相同，複製後再錄製差異覆蓋。
- **VR baseline**：上一張單的 baseline 就是這張單的 "before" 快照。

**Bootstrap 不自動做。** skill 在 Step 0 檢查兩個目錄空不空，空就提示，由人決定要不要接。
自動複製會讓一個「其實不該當基準」的快照無聲地變成基準。

## 跨單共用的 mockoon 設定

proxy routing、示範環境這類跨單共用的設定檔不隨單走，存在公司層：

```
{company_base_dir}/mockoon-config/
├── proxy-config.yaml     # API routing overrides
└── demo.json             # 示範環境（optional）
```

啟動時把單的 fixtures 目錄指給工具：

```bash
.claude/skills/visual-regression/scripts/polaris-toolchain.sh run fixtures.mockoon.start -- \
  issues/{命名空間}/{單號}/tests/mockoon
```

`workspace-config.yaml` 的 `fixtures` block 只留工具層設定（ports、ready_signal），
不含路徑也不含單號。

## 舊產出物在哪

2026-08 之前的 VR 證據留在 `docs-manager/src/content/docs/specs/` 底下，沒有跟著搬——
搬證據要重寫一整批相對路徑，而證據的價值在於它當時就長在那裡。要找一張舊單的來龍去脈去
`issues/`，要找它當時貼的圖才去 specs。詳見 `.claude/rules/document-flow.md`。

## 與其他 reference 的關係

| Reference | 關係 |
|---|---|
| `visual-regression-config.md` | VR 設定（工具層），與這裡的 per-單 baseline 分開 |
| `api-contract-guard.md` | mockoon fixture 的 schema drift 偵測 |
