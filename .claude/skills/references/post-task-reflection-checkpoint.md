# Post-Task Reflection Checkpoint

所有 write skill 的最後必要步驟。這一步把 `rules/feedback-and-memory.md`
的 post-task reflection 變成流程內建動作，不依賴 AI 自律。

## Why This Exists

連續兩次 PROJ-483 session 產生 12+ 個 mechanism violation，但沒有寫入任何
feedback。根因是 Strategist 一直處於「還在修」狀態，task-completion trigger
沒有觸發。把 reflection 嵌入成具名 skill step 後，流程上就不能跳過。

## Who Executes

- **Main session (Strategist)**：skill 完成後一定執行此步驟。
- **Sub-agent**：不執行此步驟；sub-agent 回傳結果給 Strategist，由 Strategist
  統一 reflection。

## Checklist (execute silently, ~30 seconds)

### 1. Behavioral Feedback Scan

| Signal | Action |
|--------|--------|
| User corrected a behavior during this task | Save/merge feedback memory (rule + Why + How to apply) |
| A command failed and was self-corrected | Save feedback memory (wrong → correct pair) |
| Stuck > 2 rounds before resolution | Save feedback memory (root cause + solution) |
| User confirmed a non-obvious approach | Save positive feedback / framework-experience memory |
| Hook blocked or permission denied | Record command + suggest pattern fix |

`framework-experience` 判斷依 `.claude/rules/feedback-and-memory.md` 的 trigger criteria。若本次 skill 透過 workaround / bypass 才能完成既有 gate，且使用者要求追蹤流程摩擦點，需把該摩擦點列入後續 DP 或 backlog，不可只在 final summary 口頭提到。

### 2. Gate Failure Ledger Consumption

若本輪任務有 task id，先讀取：

```text
.polaris/evidence/gate-failures/{task_id}.jsonl
```

每筆 `classification: pending` entry 都必須在結束前有 disposition，不可只靠 agent
口頭說明「已修正」。可接受值：

- `fixed`：已修改流程、程式或命令，並重新通過對應 gate。
- `accepted-workaround`：本輪為了不中斷交付採用 workaround，且已把摩擦點列入 backlog / DP。
- `escalated`：需要使用者或 framework owner 決策，已留下阻塞原因與下一步。

reflection 輸出或 checkpoint 必須包含 strict required 欄位：

```json
{
  "self_correct_disposition": [
    {
      "gate_id": "gate id",
      "disposition": "fixed | accepted-workaround | escalated",
      "evidence": "verify command, PR, backlog item, or DP path",
      "note": "short factual note"
    }
  ]
}
```

若 ledger 非空但無法完成 disposition，任務不可宣稱完成；改為回報仍待處理的
gate failure 與下一個 deterministic action。

### 3. Technical Learning Check

若發現非顯而易見的技術洞察，執行 `polaris-learnings.sh add`（每個 task 最多
2 筆）。類型規範見 `cross-session-learnings.md`。

### 3a. Auto-pass Friction Log Consumption (DP-214)

若本輪任務由 `/auto-pass` 觸發，且 ledger 有 `friction_log[]` 條目（繞道、手動補位、
deterministic gap），reflection 必須消費這些訊號，不可只在報告口頭交代：

1. 讀取 ledger 的 `friction_log[]`（schema 見 `auto-pass-ledger.md`）。
2. 對應 report 的 `friction_log_summary`（由 `validate-auto-pass-report.sh` 驗算）。
3. `friction_log` 非空時，必須在 report 內提出 `follow_up_dp_seed` 或既有
   `follow_ups[]` 條目，並指向待開的 DP / backlog item；不可只標 `terminal_status=complete`
   就結束。已存在的 follow-up DP 可重用，但 reflection summary 必須點名 friction
   kind 與下一步 owner。
4. `friction_kind=language_drift_repair` 或 `validator_contract_conflict` 屬於高優先
   訊號，下一輪 refinement / sprint planning 必須優先排入。

不要把 friction_log 當成可選的吐槽欄位；它是 deterministic signal source。

### 4. Mechanism Audit (top 5)

依 `rules/mechanism-registry.md` 的前 5 個 priority canaries 掃描本輪對話：

1. `no-workaround-accumulation` / `design-implementation-reconciliation`
2. `skill-first-invoke` / `no-manual-skill-steps`
3. `fix-through-not-revert` / `query-original-impl`
4. `delegate-exploration` / `delegate-implementation`
5. `post-task-feedback-reflection`

若發現 violation，寫入 feedback memory，並帶上 mechanism ID。

### 5. Rule Promotion Check

若有 feedback memory 已確認正確，且代表清楚可重複的模式，提出 direct rule
write；流程見 `skills/references/feedback-memory-procedures.md` § Feedback →
Direct Rule Write。

### 6. Checkpoint Todo-Diff (when splitting session)

若下一步要切到不同 skill 或 topic（見 `rules/context-monitoring.md` § 5a-bis），
在通知使用者前先執行 checkpoint verification：

1. **寫入 checkpoint memory**（type: project），包含所有 pending items。
2. **執行 `scripts/checkpoint-todo-diff.sh`**，傳入目前 todo items 與 checkpoint file path：
   ```bash
   scripts/checkpoint-todo-diff.sh --todo-items "item1|item2|item3" --checkpoint-file /path/to/memory/file.md
   ```
3. **若 script exit non-zero**（有 missing items），先修正 checkpoint。每個 todo
   item 都必須在 checkpoint 中標為 done、carry-forward 或 dropped（含原因）。
4. **只有 diff pass 後**，才用 session split message 與 trigger phrase 通知使用者。

這是 **hard gate**：diff pass 前不能送出 session split notification。花 10 秒重查，
比下一個 session 才發現 deliverable 遺漏便宜得多。

## SKILL.md Integration

把以下段落加到任何 write skill 的**最後一步**：

```markdown
## Step N: Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
```

依 skill 目錄深度調整相對路徑。
