# Session-Switch Advisory

> 薄轉述契約（DP-291 D7）：`session-switch-eval` hook 在 UserPromptSubmit 算出
> `decision=SWITCH` 並注入單行 `[SESSION-SWITCH]` marker 時，agent 必須對使用者**轉述一句**。
> 偵測與決策本身純機械（hook 算 OR-of-limits）；轉述是 LLM 行為，本檔只規範這條轉述紀律，
> 不重做門檻計算（門檻見 `workspace-config.yaml` → `defaults.session_switch`）。

## Core Rule — 收到 SWITCH marker 必轉述一句

當該輪 context 出現 `session-switch-eval` 注入的 marker：

```
[SESSION-SWITCH] decision=SWITCH; triggered: <axis> <n>/<limit> = <pct>%[; ...]
```

agent 必須在回覆中對使用者**主動轉述一句**，內容至少包含：

- **觸發軸**（`tool_calls` / `turns` / `elapsed_minutes` / `minutes_since_checkpoint`）；
- 該軸的**原始 n/limit** 與**百分比**（marker 已算好，直接引用，不自行重算）。

範例轉述：「本 session 已達 session-switch 門檻（tool_calls 52/40 = 130%），建議存
checkpoint 後切新 session 接續。」轉述後仍可繼續當前工作；本契約只要求**告知**，不強制立即切。

`decision=CONTINUE`（marker 為空或標 CONTINUE）時**不需轉述**——`surface=on_switch` 預設讓
CONTINUE 靜音以避免每輪噪音（D6）。

## Honest Boundary（機械 vs LLM）

- **純機械**：壓力訊號蒐集（`session-pressure-tick` PostToolUse 計數）、四軸 OR-of-limits
  判定、marker 文字產生，全部由 hook 決定，可被 selftest 重現。
- **LLM 行為**：把 marker 轉述成一句給使用者，是本契約規範的 agent 行為。誠實標註此邊界，
  避免把「轉述」誤宣稱成 framework 的 deterministic 保證。

## Negative Contract（DP-291 D8 / AC-NEG2）

兩個 hook（`session-switch-eval`、`session-pressure-tick`）**永遠不得**：

- 自動切 session、自動開新 session，或代替使用者執行任何 session 狀態以外的 mutation；
- 寫入 `.polaris/runtime/session-pressure/` 之外的任何路徑（tick 只寫該 state，eval 唯讀）；
- 進行網路請求 / build / 安裝；
- 把 env / secrets dump 到 stdout；
- 以 `exit 2` 阻擋 prompt——hook 一律 `exit 0` fail-open，門檻 / config / state 任一缺失或
  毀損都退回內建預設並靜默放行。

此 negative contract 由 `scripts/selftests/session-switch-codex-parity-selftest.sh` 與
`scripts/selftests/session-switch-eval-selftest.sh` /
`scripts/selftests/session-pressure-tick-selftest.sh` 機械斷言。

## Cross-Runtime Parity（DP-291 D9）

session-switch 機制的跨 runtime 等價以四條 lane 標註，登記在
`.claude/rules/mechanism-registry.md` 的 Runtime Annotation Registry（兩列：
`session-switch-eval`、`session-pressure-tick`）：

- **claude-code-native** — 第一條實作 lane。Claude Code 的 UserPromptSubmit / PostToolUse
  native hook 直接執行本機制；marker 經 stdout 注入該輪 context。
- **codex-native-candidate** — Codex 已具備 UserPromptSubmit / PostToolUse hook，因此**不可**
  再標成「無 per-turn auto-injection」。其 native lane 為 candidate：必須先以 runtime selftest
  證明 hook payload、session/thread key、stdout-to-context / block 語義成立，才視為 native 等價。
- **codex-wrapper-guaranteed** — 若 native candidate 任一點不成立，Codex app-server / SDK
  wrapper lane 可在 turn / start 前**deterministic 地 prepend** 同一行 `[SESSION-SWITCH]`
  marker，達成完整等價。這條 lane 是 guaranteed fallback（marker 為單行、deterministic，
  wrapper 可直接前置）。
- **copilot-fallback** — Copilot 等其餘 runtime 以最小 fallback 對齊：至少能在回合前注入同一
  marker 文字，使轉述契約跨 runtime 一致。

Codex native probe 與 wrapper probe 的 runtime 證據由
`scripts/selftests/session-switch-codex-parity-selftest.sh` 覆蓋（AC7）。

## Cross-Reference

- 門檻 configuration surface：`workspace-config.yaml` → `defaults.session_switch`（D5）。
- Runtime annotation 兩列：`.claude/rules/mechanism-registry.md` § Runtime Annotation Registry。
- 既有 session 管理偏好：`.claude/rules/handbook/working-habits.md` § Session 管理
  （「切 session 直接說，不問」）——本機制提供 deterministic 訊號，轉述後是否切由使用者決定。
