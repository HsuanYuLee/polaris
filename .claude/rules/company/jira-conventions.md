# JIRA 慣例

- **JIRA 單缺資訊時不要猜測**：主動列出缺少的項目（path、Figma、AC、API doc），請使用者補充
- **JIRA 子單建立後附可點擊連結**：用 `createJiraIssue` 建完子單後，回應中必須附完整 JIRA URL（`https://{jira.instance}/browse/XX-NNN`），不能只給單號
- **PM 提供的範例不等於實作方式**：JIRA 上 PM 給的 HTML/code snippet 是參考方向，不是實作 spec。建子單或寫 Dev Scope 時，先讀 codebase 對應元件再決定做法
- **母單只有外部連結時先取得內容再建子單**：JIRA 母單描述只有無法存取的外部連結（ChatGPT、Google Docs 等）時，不可自行推測需求。主動告知使用者「描述不足，需要補充」
- **拆單估點必須附帶 Happy Flow 驗證場景**：每張子單描述使用者視角的操作步驟與預期結果，為未來 Playwright e2e 測試鋪路
- **確認拆單後以 Sub-agent 平行建立子單**：批次建立 JIRA 子單、填入估點、更新母單，不逐張等待確認
