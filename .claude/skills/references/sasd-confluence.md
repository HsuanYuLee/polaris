# SA/SD Confluence 存放位置

> **Config 優先**：Confluence 設定從公司 config 讀取（`confluence.instance`、`confluence.space`、`confluence.folders.sasd`）。參考 `references/workspace-config-reader.md`。
> 以下為 fallback 值。

SA/SD 文件統一存放在 Confluence 指定 space 的 SA/SD folder。

- **Folder URL**: 由 `confluence.instance` + `confluence.space` + `confluence.folders.sasd` config 決定
- **結構**: SA/SD folder → 西元年份子頁面 → 在該年份下新增個別 SA/SD 頁面
- **範例**: `SA/SD` → `2026` → `[PROJ-1234] 功能名稱 SA/SD`

建立新 SA/SD 頁面時：
1. 確認當年度子頁面是否存在，若無則先建立
2. 在年份頁面下建立新頁面，標題格式：`[TICKET-KEY] 功能名稱 SA/SD`
3. 重估後更新原頁面，不另開新頁
