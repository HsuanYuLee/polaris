# TDD 智慧判斷

決定每個要改動的檔案是否適合 TDD 的共用判斷邏輯。

## 0. 前置：Repo Coverage Gate 偵測（硬性凌駕）

進入判斷表前，先偵測當前 repo 是否有 Codecov patch gate：

1. `codecov.yml` / `.codecov.yml` 含 `type: patch`
2. `.github/workflows/*.yml` 提到 `codecov/patch`

**若 repo 有 patch gate → 規則凌駕以下判斷表**：所有 source 改動（非「無法寫測試」類）一律走 TDD，**不以「改動小」、「加一行 option」、「只改字串」為由豁免**。

理由：repo 的 patch gate 是 CI 硬門檻，即使 code 改動只有一兩行，CI 仍會檢查 patch line 是否被 test 覆蓋。engineering 本地判定「不需測試」→ push → CI fail 是已知失效模式（TASK-3847 事件）。

若 repo **無** patch gate，才走下方判斷表。

## 判斷規則

對每個要改動的檔案，先嘗試寫測試：

| 類別 | 範例 | 處理方式 |
|------|------|---------|
| **可寫測試** | composable、util、store、API handler | 走 TDD 循環（Red-Green-Refactor） |
| **無法寫測試** | config、純 template、純 style、型別定義 | 記錄原因，直接實作 |

「無法寫測試」的檔案即使在有 patch gate 的 repo 也不強制 TDD — codecov.yml 的 `ignore:` 段通常已排除這些（config.ts、d.ts 等）。但若 ignore 段沒排除某種檔案，以 codecov 設定為準，必須補測試。

## 回報格式

完成後回報：

```
TDD 覆蓋 X 個檔案，Y 個檔案跳過（原因：...）
Coverage gate: [detected / absent]
```

例 1：`TDD 覆蓋 3 個檔案，2 個檔案跳過（原因：config 檔、型別定義）。Coverage gate: detected (codecov.yml patch target 60%)`

例 2：`TDD 覆蓋 1 個檔案，0 個跳過。Coverage gate: detected — 改動雖小但 repo 有 patch gate 強制補測試`

## 使用方式

此判斷邏輯配合 `unit-test` skill 的 Red-Green-Refactor 循環使用。Skill 讀取 `unit-test` SKILL.md + 專案 CLAUDE.md 以確保程式碼符合專案規範。

呼叫端（engineering、bug-triage 等）在進入開發階段時套用此判斷，無需重複描述規則。

TDD 完成後、push 前必須依 `engineer-delivery-flow.md § Step 2 Local CI Mirror` 跑 `ci-local.sh` 並寫 evidence（若 repo 有 `ci-local.sh`；patch gate / lint / typecheck 等 workflow checks 由 `ci-local-generate.sh` 從 repo CI config 推導內含）。
