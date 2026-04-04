---
name: systematic-debugging
description: >
  Structured debugging workflow for local code issues: root cause investigation before
  fixes. Use when: (1) user encounters a local bug, test failure, or unexpected behavior
  in the codebase, (2) user says "debug", "找 bug", "為什麼壞了", "why is this failing",
  "investigate", "查問題", "這個怎麼回事", (3) a test or build is failing and the cause
  is unclear, (4) user says "root cause", "根因", "排查".
  This skill focuses on local code analysis — reading source code, tracing logic, and
  forming hypotheses. Do NOT use this for querying production logs or Kibana (use
  kibana-logs instead). If debugging requires checking production logs, invoke
  kibana-logs as a complementary step.
metadata:
  author: Polaris
  version: 1.1.0
---

# Systematic Debugging

找到根因再修，不要猜測式修正。

## 核心原則

隨機修正浪費時間、製造新 bug。快速補丁掩蓋底層問題。

**沒有根因調查就修正 = 失敗。**

## 四階段流程

### Phase 1: 根因調查

依序執行，每步記錄發現：

1. **仔細閱讀錯誤訊息** — 完整看 stack trace，不要只看第一行
2. **穩定重現** — 確認可以一致重現問題（跑測試、重現步驟）
3. **檢查近期變更** — `git log --oneline -10`、`git diff develop...HEAD` 看最近改了什麼
4. **收集證據（跨模組時用自適應 Explore）** — 判斷問題是否可能跨越多個模組（如 component + composable + API + store）。若是，使用 `references/explore-pattern.md` 的自適應探索模式：

   **探索目標**：從 bug 症狀追蹤相關程式碼，找出可疑的根因位置。

   啟動 1 個 Explore subagent，帶入錯誤訊息、stack trace、重現步驟和專案路徑。Subagent 會自行判斷範圍大小 — 單一模組直接探索，跨多模組自動分裂成 sub-Explore 平行追蹤各層。

   **收到探索摘要後**，主 agent 彙整各層的可疑點和假設，交叉比對找出最可能的根因。

   > 若問題明顯侷限在單一檔案或模組（如只是一個 typo），直接用 grep/glob 快速掃描即可，不需啟動 subagent。

5. **追蹤資料流** — 從錯誤點往回追，找出資料在哪一步開始不對

### Phase 2: 模式分析

1. **找到正常運作的案例** — 類似功能是怎麼正確實作的？
2. **比對差異** — 壞掉的 vs 正常的，差在哪裡？
3. **檢查依賴** — 是否有版本不一致、缺少的依賴、環境差異？

### Phase 3: 假設與驗證

1. **形成單一假設** — 一次只測一個假設，不要同時改多個東西
2. **最小化測試** — 用最小的改動驗證假設
3. **驗證後再繼續** — 假設正確才進入修正，不正確就回到 Phase 1

### Phase 4: 修正

1. **先寫失敗測試** — 能重現 bug 的測試案例
2. **實作單一修正** — 最小化改動，只修根因
3. **驗證修正** — 新測試通過 + 既有測試不破壞
4. **修不動就質疑架構** — 如果 3 次修正都沒效，問題可能不在你以為的地方

## Checkpoint 機制（必須遵守）

**每 3-4 步探索後，暫停並輸出 checkpoint：**

```
## Debug Checkpoint N

### 已確認的事實
- ...

### 已排除的方向
- ...

### 當前假設（前 2 個）
1. ...
2. ...

### 下一步
- ...
```

Checkpoint 的目的：
- **防止 context 耗盡沒結論** — 在每個 checkpoint 確保有進展
- **保留進度** — 如果 session 中斷，checkpoint 讓新 session 能接續
- **防止隧道視野** — 強制重新評估方向，避免在錯誤路徑上越鑽越深

## 停損規則

| 情境 | 行動 |
|------|------|
| 3 次修正失敗 | 停下來，質疑架構假設，考慮問題是否在更上層 |
| 5 個 checkpoint 仍無進展 | 總結所有發現，列出需要人工判斷的問題，交給 RD 決策 |
| 發現問題跨越自己的知識範圍 | 明確說「我不確定」，列出已知和未知，建議找對的人 |

## Red Flags — 停下來重新思考

- 「先改改看」— 沒有假設的修正是浪費時間
- 「應該是這個」— 應該 ≠ 確定，需要證據
- 「我修了一個地方但另一個壞了」— 沒找到根因的徵兆
- 「讓我再試一次一樣的東西」— 重複同樣的事不會得到不同結果

## Do / Don't

- Do: 先讀完整個 error message 和 stack trace
- Do: 每 3-4 步輸出 checkpoint
- Do: 一次只測一個假設
- Do: 修正前先寫重現 bug 的測試
- Don't: 沒有根因就開始改 code
- Don't: 同時改多個地方然後看哪個有效
- Don't: 在同一個方向上無限深入（超過 5 個 checkpoint 要停損）
- Don't: 說「應該修好了」但沒跑驗證


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
