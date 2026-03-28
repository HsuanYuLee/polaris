# 場景 Playbook

## 評估 Epic → 實作（Estimation-Implementation Loop）

**階段 A：Estimation Agent**
1. 讀取 JIRA Epic → 檢查資訊完整性（path、Figma、AC、API doc）
2. 確認專案（mapping）
3. 拆解子任務，每張附帶估點 + Happy Flow 驗證場景
4. 以表格呈現 → **與使用者討論調整，直到確認最終版本**
5. 確認後，以 sub-agent 平行批次建立 JIRA 子單
6. 詢問是否產出 SA/SD → 若是，產出並推上 Confluence

**階段 B：Implementation Agent**
7. 讀取子單 + SA/SD（從 JIRA/Confluence）+ codebase
8. 規劃實作方式，判斷是否有**技術難題**：
   - 預估的實作方式行不通（API 不存在、元件不支援所需 props）
   - 影響範圍比子單描述的大很多（改 A 連帶影響 B、C）
   - 需要跨專案改動（需先改 DS 才能在 B2C 用）
   - ⚠️ 不算技術難題：單純多寫幾行 code、需查 API 文件確認參數
9. **無難題** → 進入開發
10. **有難題** → 帶回具體問題，交由 Estimation Agent 重估

**重估 Guardrail：**
- 重估後更新 JIRA 子單 + Confluence SA/SD（原頁面更新，不另開新頁）
- 估點變動 > 原本 30% 時，pause 讓使用者確認
- **最多 2 輪重估**，超過則 escalate 給使用者手動處理
- JIRA / Confluence 作為 agent 間的共享記憶體，不依賴 agent context

## 依賴分支（Base on 未合併 Branch）

當 JIRA 單依賴另一張尚未 merge 的單時：

1. **偵測依賴**：建 branch 前檢查 JIRA comments，尋找依賴標記（`base on`、`depends on`、`依賴`、`需等 XX merge`）
2. **找到依賴 branch**：用 `gh pr list --search "<依賴單 JIRA key>"` 找到對應 PR 和 branch
3. **從依賴 branch 開出新 branch**：`create-branch.sh <TICKET> <DESC> <依賴-branch>`
4. **發 PR 時 base 設為依賴 branch**（不是 develop）→ diff 只顯示本單改動
5. **依賴單 merge 後**：rebase develop → PR base 改回 develop
6. **依賴單 PR 被退回/大改時**：rebase 依賴 branch 最新版，解 conflict

⚠️ 建 branch 前務必向使用者確認依賴關係和 base branch，不要自動決定

## 開發功能

1. 讀取 JIRA 單 → 確認專案（mapping）→ cd 到該專案目錄
2. Estimation Agent 拆單估點 → 建 JIRA 子單 → SA/SD（選擇性）
3. Implementation Agent 可行性驗證（有難題則回 Estimation Agent 重估，最多 2 輪）
4. 自動進入開發：從 develop 開母單 branch（`{任務類型}/{EPIC-KEY}-{description}`），產出子單依賴圖
5. **每張子單必須從母單 branch 開出獨立 branch**（`task/{SUB-TICKET-KEY}-{description}`）→ 開發 → 品質檢查 → Pre-PR review loop → **對母單 branch 發 PR**
   - ⚠️ **禁止**直接在母單 branch 上 commit 子單的改動
   - 有依賴關係的子單可以在同一個 branch 開發，但**必須分成不同 commit**
   - 子單 PR 的 base branch 是母單 branch，不是 develop
6. 所有子單 merge 後，母單 branch → develop 的 PR 由 RD 手動發出。母單 PR 使用專用模板（`pr-convention` Step 4a）

## 修正 Bug

> **一鍵觸發**：`幫我修正 PROJ-123` / `修 bug PROJ-123` / `fix bug PROJ-123`

1. 讀取 JIRA 單 → 確認專案（mapping）→ cd 到該專案目錄
2. 分析根因 → 產出 Root Cause + Solution + 估點（初版）→ RD 確認後留 JIRA comment
3. 轉 IN DEVELOPMENT + 建立分支
4. 實作（發現情況不同時，新增 JIRA comment 標註修正版，估點變動 > 30% pause 確認）
5. 品質檢查 → Pre-PR review loop → 發 PR

⚠️ **「幫我修正」+ JIRA URL/ticket key → fix-bug**；**「幫我修正」+ PR URL → fix-pr-review**

## 重構優化

1. RD 自行開單 → 與 QA 同步影響範圍
2. 之後同「開發功能」Step 2-6

## 審查 PR

1. 確認 repo（從 PR URL 或使用者指定）
2. 讀取 diff + 該專案的 `.claude/rules/` 規範
3. 檢查：型別安全、邊界處理、測試覆蓋、程式碼風格
4. 在 PR 上留下結構化 review（blocking / suggestion / good）

## 打磨工作流

1. 留在 `work/` 目錄，不切換專案
2. 討論改善點 → 更新 `docs/rd-workflow.md` 或 `CLAUDE.md`
3. 穩定後由使用者通知同步回 Confluence
