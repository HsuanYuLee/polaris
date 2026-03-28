# 自動 Feedback 機制

每次完成一個完整任務（發 PR、fix review、估點、review PR 等）後，靜默回顧本次對話：

1. **使用者糾正了做法** → 存 feedback memory，記錄規則 + Why + How to apply
2. **同一條 feedback memory 已被觸發 ≥ 2 次** → 建議升級到 CLAUDE.md 規則（通知使用者確認）
3. **被 hook block 或權限拒絕** → 即時記錄指令和建議 pattern，任務結束前統一列出並修正（通用 → `~/.claude/settings.json`，project-specific → `settings.local.json`）
4. **指令失敗後自行修正成功**（路徑猜錯、參數錯誤、API 格式不對等） → 記錄「錯誤指令 → 正確指令」的修正對，存 feedback memory
5. **卡關超過 2 輪未解決** → 記錄根因和最終解法到 feedback memory
6. **使用者確認了非顯而易見的做法**（「對」「就是這樣」接受了不尋常的選擇） → 存正向 feedback memory

靜默執行，只在發現值得記錄的 feedback 時通知使用者確認後再寫入。第 3、4 項不需使用者確認即可記錄。

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
5. **Frontmatter 品質** — `name` 用檔名而非可讀標題、缺少 `type` 欄位 → 順手修正

靜默執行，刪除/修正後在回覆末尾簡要列出異動。
