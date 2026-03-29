# 自動 Feedback 機制

每次完成一個完整任務（發 PR、fix review、估點、review PR 等）後，靜默回顧本次對話：

1. **使用者糾正了做法** → 存 feedback memory，記錄規則 + Why + How to apply
2. **同一條 feedback memory 被引用 ≥ 3 次** → 觸發 Rule 畢業流程（見下方）
3. **被 hook block 或權限拒絕** → 即時記錄指令和建議 pattern，任務結束前統一列出並修正（通用 → `~/.claude/settings.json`，project-specific → `settings.local.json`）
4. **指令失敗後自行修正成功**（路徑猜錯、參數錯誤、API 格式不對等） → 記錄「錯誤指令 → 正確指令」的修正對，存 feedback memory
5. **卡關超過 2 輪未解決** → 記錄根因和最終解法到 feedback memory
6. **使用者確認了非顯而易見的做法**（「對」「就是這樣」接受了不尋常的選擇） → 存正向 feedback memory

靜默執行，只在發現值得記錄的 feedback 時通知使用者確認後再寫入。第 3、4 項不需使用者確認即可記錄。

## Feedback Memory Frontmatter 規範

所有 feedback memory 必須包含 trigger tracking 欄位：

```yaml
---
name: 規則的可讀標題
description: 一行描述（用於判斷是否相關）
type: feedback
trigger_count: 1          # 被引用/應用的次數（新建時 = 1）
last_triggered: 2026-03-29  # 最後一次被引用的日期
---
```

### Trigger Count 更新規則

在對話中**依據某筆 feedback memory 做出決策或引導行為**時，視為一次「引用」：

1. 讀取 feedback memory 後，遞增 `trigger_count`，更新 `last_triggered` 為當天日期
2. 同一次對話中多次引用同一筆 feedback，只算 1 次
3. 純粹衛生檢查（掃描 frontmatter）不算引用

## Feedback → Rule 畢業（Auto-Evolution）

當 `trigger_count >= 3` 時，觸發畢業流程：

### Step 1：判斷目標 Rule 檔案

根據 feedback 內容語意，找到 `.claude/rules/` 中最適合的檔案：

| Feedback 主題 | 目標檔案 |
|--------------|---------|
| Sub-agent 委派行為 | `rules/{company}/sub-agent-delegation.md` |
| PR / Review 流程 | `rules/{company}/pr-and-review.md` |
| JIRA 慣例 | `rules/{company}/jira-conventions.md` |
| Skill 使用方式 | `rules/{company}/skill-routing.md` |
| 其他 | 依語意判斷，或建議新建 rule 檔案 |

### Step 2：草擬 Rule 文字

將 feedback 內容轉成 rule 格式：
- 去掉 `Why:` / `How to apply:` 結構，改成 rule 檔案的行文風格（直述句 + bullet）
- 保留核心規則和理由，融入目標章節的上下文
- 不加「來自 feedback」註記

### Step 3：呈現給使用者確認

```
📋 Feedback 畢業建議

「{feedback name}」已被引用 {N} 次，建議升級為 rule：

目標：{rules/company/xxx.md} § {章節}
新增內容：
  {草擬的 rule 文字}

確認後我會：
1. 寫入目標 rule 檔案
2. 刪除對應的 feedback memory
3. 更新 MEMORY.md index
```

### Step 4：使用者確認後執行

1. 將草擬文字併入目標 rule 檔案的對應位置
2. 刪除 feedback memory 檔案
3. 從 MEMORY.md 移除該筆 index
4. 在回覆末尾簡要列出異動

### 手動觸發

使用者說「整理 feedback」「feedback 畢業」→ 掃描所有 feedback memory：
- `trigger_count >= 3` → 進入畢業流程
- `trigger_count == 0` 且 `last_triggered` 超過 30 天 → 建議刪除（可能已過時）
- 其他 → 不動

## 即時收集被拒絕的指令

執行過程中遇到權限拒絕時，立即記錄該指令和對應的 pattern 建議。任務結束前統一列出所有被拒絕/手動允許的指令，建議新增 pattern 並在使用者確認後寫入（通用 → `~/.claude/settings.json`，project-specific → `settings.local.json`）。

## Memory 衛生檢查（隨對話漸進執行）

**觸發時機：**
- 對話中讀取了某筆 memory → 只檢查被讀取的那幾筆
- 完成任務做靜默回顧時 → 順便掃描本次引用過的 memory
- 使用者說「整理 memory」「清理 memory」→ 完整掃描所有 memory

**檢查項目：**
1. **冗餘** — memory 內容已存在於 CLAUDE.md 或 `.claude/rules/` → 刪除
2. **過時** — description 標註「已被取代」或「已過時」→ 直接刪除
3. **夾帶待辦** — 內含「待修正」「TODO」→ 檢查是否已完成
4. **重疊** — 兩筆 memory 內容高度相似 → 合併為一筆
5. **Frontmatter 品質** — 缺少 `trigger_count` / `last_triggered` → 補上（`trigger_count: 1`，`last_triggered` 用檔案修改日）
