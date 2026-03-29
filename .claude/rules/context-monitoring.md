# Context Window 自我監察

## 核心原則

長對話會觸發 context compression（系統自動截斷早期訊息）。Commander 必須主動管理 context 使用，避免資訊丟失或重複工作。

## 監察規則

### 1. 委派大量探索，保持主 context 乾淨

- 需要讀超過 3 個檔案或 grep 多個 pattern 時 → 派 sub-agent（Explore）
- 需要分析大量 diff（> 500 行）時 → 派 sub-agent
- **禁止**在主 session 連續發出 > 5 個 Read/Grep tool call 而不產出結論

### 2. 里程碑收尾

完成一個獨立階段（如拆單完成、PR 發出、review 結束）後：
- 用簡短摘要記錄關鍵決策和產出（artifact URLs、branch name、ticket keys）
- 不再需要的中間資料（大段 diff、API response、file listing）不要重複引用
- 如果後續步驟需要前面的資訊，在摘要中保留關鍵數值而非原始資料

### 3. 避免重複讀檔

- 同一檔案在同一對話中不要讀超過 2 次（除非檔案被修改過）
- 讀過的關鍵資訊（config 值、函式簽名、API 路徑）記在回覆中，後續直接引用
- 如果需要反覆查閱某檔案結構，考慮一次讀完後記下重點

### 4. Compression 感知

當系統提示 context 被壓縮時：
- 回顧當前任務的 todo list，確認進度沒有丟失
- 重新確認 key artifacts（branch name、PR URL、ticket key）仍然可用
- 如有疑慮，用 memory 或 todo 補齊丟失的狀態

### 5. 大任務分段

預估任務會產生大量 tool call（> 30 次）時：
- 在開始前建立 todo list 拆分階段
- 每完成一個 todo 都記錄產出，確保即使 compression 發生也不影響後續步驟
- 批次操作（如建立多張 JIRA 子單）委派給 sub-agent 一次完成
