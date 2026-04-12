# TDD 智慧判斷

決定每個要改動的檔案是否適合 TDD 的共用判斷邏輯。

## 判斷規則

對每個要改動的檔案，先嘗試寫測試：

| 類別 | 範例 | 處理方式 |
|------|------|---------|
| **可寫測試** | composable、util、store、API handler | 走 TDD 循環（Red-Green-Refactor） |
| **無法寫測試** | config、純 template、純 style、型別定義 | 記錄原因，直接實作 |

## 回報格式

完成後回報：

```
TDD 覆蓋 X 個檔案，Y 個檔案跳過（原因：...）
```

例：`TDD 覆蓋 3 個檔案，2 個檔案跳過（原因：config 檔、型別定義）`

## 使用方式

此判斷邏輯配合 `unit-test` skill 的 Red-Green-Refactor 循環使用。Skill 讀取 `unit-test` SKILL.md + 專案 CLAUDE.md 以確保程式碼符合專案規範。

呼叫端（work-on、bug-triage 等）在進入開發階段時套用此判斷，無需重複描述規則。
