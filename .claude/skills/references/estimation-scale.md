# Web Team 估點度量衡

參考：Confluence（由 workspace-config.yaml 的 `confluence.instance` 和 `confluence.space` 決定）

## 估點標準

**允許值僅限 `{1, 2, 3, 5, 8, 13}`**（修改費式數列）。不可使用小數（如 2.5, 3.5）或表外整數（如 4, 6, 7）。

| Point | 說明 | 範例 |
|-------|------|------|
| **1** | 簡單的改文案作業、改 lokalise、改 DCS 等 | — |
| **2** | 簡單的 component | PROJ-100 |
| **3** | 整合性 UI component、基本列表型 UI component、API 串接、埋點 | PROJ-101, PROJ-102 |
| **5** | 複雜的純 UI component（高互動性 UI）、整合 component 和 API 資料 (ajax api)、預期會需要有溝通成本的 API 串接（BFF，沒 API 文件，需要溝通） | PROJ-200, PROJ-201 |
| **8** | spike、POC、邏輯複雜的整合 | PROJ-300, PROJ-301 |
| **13** | spike、POC、需要一整個 sprint 時間的 task | — |

## 估點考量因素

1. **開發複雜度** — UI 複雜度、邏輯複雜度、API 串接數量
2. **影響範圍** — 改動涉及多少個檔案 / 模組
3. **溝通成本** — 是否需要和後端、PM、設計師確認
4. **不確定性** — 是否有技術調研 (spike/POC) 的需求
5. **測試範圍** — 需要測試的場景多寡

## Timeline 計算

Total days = 總點數 / 每日可消化點數（通常 2-3 點/天）
