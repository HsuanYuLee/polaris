# L2 Script Conventions

L2 = skill-embedded deterministic check。SKILL.md 明寫 `bash scripts/check-X.sh`（或等效呼叫）+ 依 exit code 決定流程動作。這份 reference 規定 L2 script 的寫作模板與 skill 端的呼叫模板，讓不同 LLM（Claude Code / Cursor / Codex / Copilot / Gemini）行為一致。

> 來源：DP-030 D2/D3/D4（`specs/design-plans/DP-030-llm-to-script-migration/plan.md`）。Phase 1 POC 已落地 `cross-session-carry-forward`（L2 主） + `no-cd-in-bash`（legacy L1）為首批下放；legacy Claude Code L1 wrappers later retired.

## Why L2（vs L1 hook）

- **L1 hook** 是 Claude Code tool-use event 才觸發，其他 LLM 沒對等 hook → 選擇性失效
- **L2 embedded** 在 SKILL.md 內呼叫 script，由 LLM 依 skill flow 執行 → 跨 LLM 行為一致
- 同一支 script 可被 L1 hook 和 L2 skill 共用（邏輯同，呼叫端不同）

## Exit Code 語意（硬性規定）

每支 L2 script 必須使用以下 exit code 語意之一；script 作者依 canary 性質決定。

| Exit | 名稱 | 意義 | Skill 應該怎麼做 |
|------|------|------|-----------------|
| `0` | PASS | 檢查通過 | 繼續下一步 |
| `1` | RECOVERABLE_FAIL | 可由 LLM 自癒的失敗（命令錯、資料缺、格式偏離） | 讀 stderr、修 input/實作、重跑（遵守 retry budget） |
| `2` | HARD_STOP | 自癒會偽造 enforcement 意圖的失敗 | **立刻 STOP**，不給 retry，回報 user 做人工處置 |

Script 必須把失敗原因寫到 **stderr**（不是 stdout），讓呼叫端可以單獨攔截；stdout 保留給結構化輸出（JSON / diff 結果）。

### 何時用 `exit 1`

可自癒的偏離 — 修實作、改 command、補資料就能過。例：
- `no-independent-cmd-chaining`：LLM 拆成多個 Bash call 即可重試
- `feedback-trigger-count-update`：bump frontmatter 後重跑
- `version-bump-reminder`：更新 VERSION + CHANGELOG 後通過

### 何時用 `exit 2`

自癒的唯一路徑是「偽造 enforcement 意圖」— 給 LLM retry 反而鼓勵作弊。例：
- `cross-session-carry-forward`：若讓 LLM retry，誘因是「硬把前輪 pending 塞進 next steps」而非真的回顧處置。正確路徑是停下來讓 user 看 diff 決定 done/carry-forward/dropped
- `design-plan-checklist-done`：若允許 retry，LLM 可能會改 checklist 文字假裝都完成

## Retry Budget

Skill 呼叫端必須實作 retry budget，避免 exit 1 進入死循環：

```
Budget = 3 輪
第 1 輪 fail → 讀 stderr、修實作、重跑（輪次 1→2）
第 2 輪 fail → 讀 stderr、修實作、重跑（輪次 2→3）
第 3 輪 fail → 讀 stderr、修實作、重跑（輪次 3→4）
第 4 輪仍 fail → STOP + 回報 user 原因與三次嘗試摘要
```

`exit 2` 不吃 retry budget — 立刻 STOP。

## Script 寫作模板

```bash
#!/usr/bin/env bash
# scripts/check-{canary-id}.sh
#
# Purpose: {一句話描述這支 script 檢查什麼}
# Canary: {mechanism-registry.md 對應 canary ID，或 reusable/manual check ID}
# Exit codes:
#   0 — PASS
#   1 — RECOVERABLE_FAIL（可由 LLM 自癒）
#   2 — HARD_STOP（自癒會偽造 enforcement，立刻停）
#
# Usage:
#   check-{canary}.sh [--flag1 value] [--flag2 value] <args>
#
# Invoked by:
#   - .claude/skills/{skill-name}/SKILL.md Step {n}（L2 primary）
#   - .claude/hooks/{canary}.sh（L1 fallback / hook-only）

set -u  # 不要 set -e — 失敗路徑要自己控，避免 silent exit

# --- Arg parsing ---
# 優先長選項（--todo-file）而非位置參數，script 呼叫端明確易讀

# --- Input validation ---
# 必要資料缺 → exit 2（HARD_STOP）or exit 1 視情況
# 例：checkpoint 檔不存在 → exit 1（可由 LLM 生檔後重跑）
#     上一輪 checkpoint 找不到且不應該找不到 → exit 2（HARD_STOP）

# --- Core check ---
# 檢查邏輯；失敗時寫 stderr 說明具體哪邊偏離
# 成功 → echo 結構化結果（optional）到 stdout → exit 0

# --- Default exit ---
exit 0
```

### 具體範例（截自 Phase 1 POC）

```bash
# scripts/check-carry-forward.sh —— exit 2 hard-stop 示範
if [[ ! -f "$new_checkpoint" ]]; then
  echo "HARD_STOP: new checkpoint file missing — cannot diff pending items" >&2
  exit 2
fi

missing=$(diff_pending_items "$prev" "$new")
if [[ -n "$missing" ]]; then
  echo "HARD_STOP: next-session memory dropped previous pending items:" >&2
  echo "$missing" >&2
  echo "Resolve by marking each item (a) done / (b) carry-forward / (c) dropped" >&2
  exit 2
fi

exit 0
```

## Skill 呼叫模板

在 SKILL.md 寫入對應 step 時，使用以下 shape 讓不同 LLM 都能照執行：

```markdown
### Step N — L2 Deterministic Check: {canary-id}

執行 `scripts/check-{canary-id}.sh` 檢查 {檢查目的}。

```bash
bash /Users/hsuanyu.lee/work/scripts/check-{canary-id}.sh \
  --flag1 "value1" \
  --flag2 "value2"
```

根據 exit code：
- **exit 0** — 繼續 Step N+1
- **exit 1** — 讀 stderr 自癒（修 input / 實作 / 資料）後重跑。Retry budget **3 輪**；第 4 輪仍 fail → STOP + 回報 user
- **exit 2** — **立刻 STOP**，不 retry。stderr 的訊息直接給 user，由 user 決定處置（通常是語意上需要人工判斷的情境）
```

### 呼叫端 bash 模板（可貼進 SKILL.md，讓不同 LLM 都能直接執行）

```bash
retry=0
max_retry=3
while true; do
  bash /abs/path/to/scripts/check-X.sh [args] 2>/tmp/l2-stderr.$$
  rc=$?
  case $rc in
    0) break ;;
    2)
      cat /tmp/l2-stderr.$$ >&2
      echo "[L2] HARD_STOP — 不 retry，回報使用者" >&2
      exit 2
      ;;
    *)
      cat /tmp/l2-stderr.$$ >&2
      retry=$((retry+1))
      if (( retry >= max_retry )); then
        echo "[L2] Retry budget exhausted ($retry/$max_retry) — STOP" >&2
        exit 1
      fi
      # LLM 在這裡依 stderr 修實作/輸入後重跑
      ;;
  esac
done
rm -f /tmp/l2-stderr.$$
```

## L1 Hook Fallback 模式

為避免 skill bypass（user 不走 skill 直接動手），L2 對應的 canary 建議同步設 L1 hook 當 fallback：

- L1 hook 監聽對應 tool event（Edit / Write / Bash with 特定 pattern）
- 呼叫**同一支** `scripts/check-X.sh`，讀 exit code 決定是否 exit 2 阻擋
- 維護成本：一個 script、兩個呼叫端

無 L2 對應的 reusable script（例：`no-cd-in-bash`）不需 L2 整合；若沒有 active hook，它只是 manual/Copilot compatibility check，不依附 skill flow。

## Registry 同步規定

每個 canary 下放完成後（不論 L1 only / L2 only / L1+L2）：

1. 從 `rules/mechanism-registry.md` **移除該 canary** 的 behavioral 條目（原表格那行）
2. 把它加到 § **Deterministic Quality Hooks** 區塊，記錄 Enforcement + Script 欄位
3. 若該 canary 出現在 **§ Priority Audit Order**，移除或改列 deterministic 註記
4. 在 plan.md Implementation Checklist 勾掉對應 POC 項

DP-030 D5 規則：**直切、no shadow mode**。下放 PR 同時完成「加 script/hook/embed」+「移除 behavioral canary」，一個 commit 到位，不保留 double-enforcement。

## 常見陷阱

- **Stdout vs stderr 混用** — script 把失敗訊息寫到 stdout 會讓結構化輸出污染；一律寫 stderr
- **exit 1 vs exit 2 搞混** — 作者寫 script 時先問：「retry 能不能靠改實作/改輸入過？能 → exit 1；不能（只能靠偽造數據）→ exit 2」
- **L2 呼叫端忘記實作 retry budget** — 沒 budget 會死循環；套用上方 bash 模板
- **Meta-linter 漏追蹤** — 每加一個 L2 embed 要同步更新 `skills/references/l2-embedding-registry.md`（Phase 2 task BS#8），否則 `scripts/validate-l2-embedding.sh` 無法驗證 SKILL.md 有沒有該 embed

## References

- DP-030 plan: `specs/design-plans/DP-030-llm-to-script-migration/plan.md`
- DP-027 multi-LLM rule sharing（L2 跨 LLM 必要性）: `specs/design-plans/DP-027-multi-llm-rule-sharing/`
- Source of truth: `.claude/rules/mechanism-registry.md`
- 呼叫端範例: `.claude/skills/checkpoint/SKILL.md`（DP-030 Phase 1 POC 落地）
