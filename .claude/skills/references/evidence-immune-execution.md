---
title: "Evidence-Immune Execution Contract"
description: "蒐集驗證證據的命令必須走對 command-rewrite proxy 免疫的執行路徑：evidence-bearing pattern 清單、必走 immune 路徑契約、run-verify-command.sh 子行程免疫之記載，以及 user-owned proxy-config exclusion 建議。"
---

## 為什麼需要 immune 路徑

部分命令的 **stdout 與 exit code 本身就是驗證證據**：negative-assertion grep、產 patch 的
diff、比對用的 patch apply、checksum 比對。透明的 command-rewrite proxy（token 節省工具，
例：rtk；同類如 Headroom、LeanCTX）會攔截最外層的 Bash tool-call 字串並改寫成「等價」形式。
對一般開發操作這是好事，但一旦改寫到 evidence-bearing 命令，證據就失真：

- negative grep `! <grep> <forbidden-pattern>` 被改寫成在 error 時 exit 非 0 的 grep 變體，
  外層 `!` 把 error-exit 反轉成 exit 0 → **假性 PASS**（forbidden pattern 檢查反而通過）。
- diff proxy 對兩個實際內容不同的檔案回報「Files are identical」→ **假性 identical**。
- 存檔的 patch 變成 proxy-summarized 格式、非合法 unified diff → `git apply` 失敗。

因此這類命令必須走 **immune 路徑**：證據來自真 binary 的真實輸出，而不是 proxy 的
token-optimized 摘要。本契約對 proxy **agnostic**：核心防護不綁特定 proxy，proxy-specific
的細節只是可擴充的 allowlist。

## Evidence-bearing pattern 明確清單

下列 pattern 一律視為 evidence-bearing；用它們蒐集 DP 驗證證據時 **必走 immune 路徑**。漏列
即留破口，故此清單是 enumeration source of truth，新增 pattern 時同步更新本表與
`scripts/lint-evidence-command-direct-call.sh` 的偵測集。

| Pattern | 形狀 | 失真風險 |
|---------|------|----------|
| `! rg <pattern>` | negative-assertion grep | error-exit 被外層 `!` 反轉成 exit 0 假性 PASS |
| `rg --pcre2 <pattern>` / `rg -P <pattern>` | PCRE2 grep | 被改寫成不支援 PCRE2 的 grep，error 非 0 |
| `git apply <patch>` | patch 套用（比對證據） | proxy-summarized patch 非合法 unified diff，apply 失敗 |
| 產 patch 的 `git diff` | 產出 unified diff 供後續比對 / 套用 | 輸出被摘要，產不出合法 patch |
| `git diff --no-index <a> <b>` | 兩檔比對 | 不同檔被報為 identical（假性 identical） |
| `cksum` / `sha1sum` / `sha256sum` / `shasum` 兩檔比對 | checksum 比對 | 摘要輸出掩蓋實際差異 |

非 evidence 的一般開發操作（純 `rg foo`、不帶 `--no-index` 的 `git diff`）**不在**此清單，
維持經 proxy 改寫的省 token 行為，不必走 immune 路徑。

## 必走 immune 路徑契約

蒐集驗證證據時，evidence-bearing 命令一律走下列任一 immune 路徑，**禁止**以直接 Bash
tool call 跑（直接 tool call 會被 PreToolUse proxy 改寫成假證據）：

1. **腳本子行程（首選）**：經 `scripts/run-evidence-command.sh` 執行。helper 把 binary 解析成
   真實絕對路徑後，在 **自身子行程** 內 exec。PreToolUse proxy 只看得到最外層
   `bash scripts/run-evidence-command.sh ...` 這個 tool call，看不到腳本內部的子行程，因此對
   proxy 改寫免疫（機制免疫，已證）。

   ```bash
   # negative grep 走 immune 路徑（取真 ripgrep 的 exit code）
   bash scripts/run-evidence-command.sh rg --pcre2 'forbidden-pattern' target.txt
   # 兩檔比對走 immune 路徑（不被報 identical）
   bash scripts/run-evidence-command.sh git diff --no-index file-a.txt file-b.txt
   ```

2. **絕對 binary 路徑 / `command` 規避 function wrapper**：直接以 trusted system bin 的絕對
   路徑呼叫真 binary（例：`/opt/homebrew/bin/rg`）。proxy 可能在互動 shell 以 function
   wrapper 形式覆寫 `rg` / `git`，或在 PATH 前段注入 shim dir；絕對路徑與 `command` 不依賴
   PATH 解析，繞過 wrapper 與 shim。

`scripts/run-evidence-command.sh` 的免疫採三層防護（DP-356 Decisions D4）：

- **(a) 子行程免疫**（proxy-agnostic）：命令在 helper 的子行程內執行，proxy 改寫不到。
- **(c) 絕對 binary 解析**（proxy-agnostic）：binary 對固定的 trusted system bin 目錄集解析成
  絕對路徑，**不**信任 caller 繼承的 PATH 排序，故 PATH 前段的 shim 無法搶先；解析集可由
  `POLARIS_EVIDENCE_TRUSTED_BIN_DIRS`（colon-separated，prepend）覆寫，供 selftest fixture 用。
- **(b) kill-switch env allowlist**（proxy-specific，defense-in-depth，可擴充）：exec 前 export
  已知 proxy 的 kill-switch env。rtk 的 `RTK_DISABLED=1` 為首筆；新增 proxy 只需在
  `PROXY_KILL_SWITCH_ENV` append 一筆，不動機制骨架。

(a)(c) 為 proxy-agnostic 骨架，(b) 為 proxy-specific allowlist——proxy 改版或更換 proxy 不會
讓骨架失效。

## run-verify-command.sh 既有子行程免疫

`scripts/run-verify-command.sh` 以 `bash -c "$verify_command"` 在 **腳本內以子行程** 執行
task.md 的 Verify Command。PreToolUse proxy 只改寫最外層
`bash scripts/run-verify-command.sh ...` tool call，看不到腳本內部的 `bash -c` 子行程，
因此 **透過 run-verify 跑的 Verify Command 對 proxy 改寫免疫**（與本契約 immune 路徑 (1)
同機制）。run-verify 既有行為不需修改：formal Verify Command 已走 immune 子行程。

真正的破口在 **Verify Command 之外的臨時蒐證**——為了臨時確認某件事直接跑 `rg` / `git diff` /
`git apply`、不走腳本——這時才會被改寫成假證據。本契約把 immune 路徑要求擴及這類蒐證
（diff / patch / negative grep / checksum），避免破口只在 formal Verify Command 之外復發。

## 可 gate 半邊與殘餘（A/B 分類）

依 `contract-design.md` § prose-vs-gate-admission 的 A/B 分類：

- **A 類可 gate 半邊**：以直接 Bash tool call 跑 evidence-bearing 命令、且該 callsite 留在
  檔案中（task.md Verify Command block、evidence-gathering script、fixture）時，可被
  `scripts/lint-evidence-command-direct-call.sh` 機械偵測。lint 指向 evidence-gathering
  target 時對枚舉 pattern fail-closed（exit 2 + `POLARIS_EVIDENCE_DIRECT_CALL: <file>:<line>`），
  且不誤標一般 dev grep / diff、不誤標已走 immune 路徑者。lint 是 fixture-proven、指向
  evidence target 用，**刻意不**作為 whole-repo `--self-check` release gate——既有 framework
  script 以 `rg` / `git` / checksum 做自身 control flow（非 DP 驗證證據），blanket 掃會誤標。
- **B 類殘餘**：sub-agent 為臨時蒐證直接打一次 tool call、無持久 callsite 的情況，沒有
  deterministic 觀察點可攔。由 `.claude/rules/mechanism-registry.md` 的
  `evidence-bearing-command-direct-call` canary 在 post-task reflection 事後偵測，發現時寫
  feedback memory，不假裝有 commit-time gate。

## User-owned proxy-config exclusion 建議（非框架交付 AC）

> 本節是 **建議**，由使用者在自己的 proxy config 落地，**不是框架交付物**，框架也不測試。

command-rewrite proxy（如 rtk）屬使用者全域 config，不在 Polaris framework ownership。框架的
immune 機制（子行程 + 絕對 binary）已對 proxy agnostic，不依賴 proxy 端做任何事。作為
defense-in-depth，建議使用者在自己的 proxy config 對上述 evidence-bearing pattern 加
exclusion，讓這些命令即使以直接 tool call 跑也不被改寫：

- 偏好用 proxy 的 **kill-switch env**（rtk 為 `RTK_DISABLED=1`）作 session / invocation-scoped
  bypass；這是最可靠的途徑，immune helper 已自動利用。
- 部分 proxy 的 `exclude_commands` config 有已知 bug（rtk Issue #1335，對 rewrite / hook
  output 無效），**不建議單押**該機制。
- exclusion 落地與否屬使用者決定；框架的免疫不因使用者未落地而失效。

## 交叉引用

- immune 執行 helper：`scripts/run-evidence-command.sh`（DP-356 T1）。
- 直接-tool-call lint：`scripts/lint-evidence-command-direct-call.sh`（DP-356 T2）。
- canary 登錄：`.claude/rules/mechanism-registry.md` § Mechanism Canary Entries
  （`evidence-bearing-command-direct-call`）。
- A/B 分類準則：`.claude/rules/handbook/framework/contract-design.md`
  § prose-vs-gate-admission（DP-299）。
