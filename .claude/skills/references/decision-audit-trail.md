# Decision Audit Trail — 決策記錄規範

在決策型 skill（估點、拆單、技術選型、scope challenge）執行完畢、使用者確認後，將推理過程以 JIRA comment 的形式記錄下來，供事後追溯。

## 什麼時候要寫 Decision Record

| 場景 | 觸發 Skill | 紀錄時機 |
|------|-----------|---------|
| 估點結果（Story/Task/Bug） | `jira-estimation` | 使用者確認估點後，寫入 JIRA comment，再更新 story points |
| Epic 拆單策略 | `epic-breakdown` | 使用者確認拆單表格後，在母單寫入 Decision Record，再批次建子單 |
| Scope Challenge 建議 | `scope-challenge` | 使用者選擇方案後，在 JIRA comment 留下最終決策脈絡 |
| SA/SD 技術選型 | `sasd-review` | 每個重要技術決策寫在 SA/SD 文件對應章節 |

## 什麼時候不需要寫 Decision Record

以下屬於明確、無爭議的操作，不需要 Decision Record：

- JIRA 狀態轉換（如 IN DEVELOPMENT → CODE REVIEW）
- Git branch 建立（命名遵循現有規範）
- 複製貼上子單 summary / description 等模板操作
- story points 寫入（值本身即是決策，Decision Record 中已含理由）
- PR 建立、label 設定等機械性操作

判斷原則：**若未來有人問「當時為什麼這樣做？」，且這問題值得被回答，就需要寫 Decision Record。**

## JIRA Comment 格式模板

```
📋 Decision Record

- **Input**: <讀了哪些 code / 文件 / API（具體路徑或名稱）>
- **Considered**: <考量的方案，至少 2 個>
- **Reasoning**: <為什麼選這個方案，說明關鍵 trade-off>
- **Decision**: <最終結論（估點數字、拆單方式、採用技術）>
```

### 範例 — 估點 Decision Record

```
📋 Decision Record

- **Input**: 讀了 `components/product/ProductCard.vue`、`composables/useCart.ts`，確認目前加購流程
- **Considered**: 方案 A：修改現有 `useCart` composable（影響範圍：3 個頁面共用）；方案 B：建立 `useCartV2` 限定此頁面使用
- **Reasoning**: 方案 A 影響面太大，需要回歸測試其他頁面；此功能為 A/B test，範圍明確，方案 B 風險較低
- **Decision**: 估 5 點，採方案 B（新 composable），待 A/B test 結束後再合併
```

### 範例 — Scope Challenge Decision Record

```
📋 Decision Record

- **Input**: Ticket description、`components/search/` 現有實作
- **Considered**: 方案 A：原 spec（全新搜尋引擎，HIGH）；方案 B：擴充現有設定（MEDIUM）；方案 C：先 hardcode top 10，後再接 API（LOW）
- **Reasoning**: 方案 B 可複用現有設定，測試覆蓋成本低；PM 確認本期 deadline 優先，方案 A 排下一期
- **Decision**: 採方案 B，估 3 點，後續擴充需求另開單
```

## 實作注意事項

1. **長度控制**：Decision Record 簡潔為主，`Input` 列具體名稱（不要貼整段程式碼），`Considered` 列 2-3 個選項即可
2. **寫入時機**：在更新 story points 或建子單之前先寫 Decision Record，確保決策脈絡先被記錄
3. **語言**：中文或英文均可，與 ticket 使用語言一致
4. **JIRA 工具呼叫**：使用 `mcp__claude_ai_Atlassian__addCommentToJiraIssue`，body 直接貼模板內容
