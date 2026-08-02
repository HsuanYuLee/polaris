# Dependency Consent Mechanism

Polaris 推薦特定外部工具來支撐框架功能（如 visual regression、E2E testing）。這些工具不會被自動安裝 — 安裝決定權在使用者手上。

## 設計原則

- **框架推薦，使用者決定** — Polaris 有預設推薦的 lib，但不強制
- **記住使用者的選擇** — 同意或拒絕都記錄，不重複詢問
- **使用者可隨時調整** — 說「裝 playwright」或「不要 mockoon」即可
- **公司可覆寫工具選擇** — 框架推薦 Mockoon，公司可以選 Prism

## Config 位置

```yaml
# root: ~/work/workspace-config.yaml（框架層）
dependencies:
  playwright:
    status: consented          # consented | declined | pending
    decided_at: 2026-04-05
    features: ["visual-regression", "e2e"]
  mockoon-cli:
    status: declined
    decided_at: 2026-04-05
    features: ["visual-regression"]
```

### 欄位說明

| 欄位 | 型別 | 說明 |
|------|------|------|
| `status` | enum | `pending`（未詢問）、`consented`（同意安裝）、`declined`（拒絕安裝） |
| `decided_at` | date | 最後一次決定的日期（ISO 格式） |
| `features` | string[] | 這個 lib 支撐哪些框架功能 |

## 生命週期

### Phase 1: /init 階段

初始化新公司時，掃描該公司啟用的功能（如 `visual_regression.enabled: true`），列出所需的 lib：

```
此公司啟用了 visual regression，需要以下工具：

  1. playwright — 瀏覽器截圖引擎（提供 SSR 頁面截圖比對）
  2. mockoon-cli — API fixture server（提供穩定測資確保截圖一致）

框架推薦 Mockoon CLI 作為 fixture server（提供穩定 API 測資）。
你也可以用其他工具，只要能起 HTTP server 回應固定資料即可。

要安裝嗎？(全部安裝 / 逐一確認 / 跳過)
```

- **全部安裝** → 所有 lib status 設為 `consented`，執行安裝
- **逐一確認** → 逐一詢問每個 lib
- **跳過** → 所有 lib status 設為 `declined`，警告缺失的功能

警告格式：
```
⚠ 以下功能因缺少依賴將無法使用：
  - visual regression（需要 playwright + mockoon-cli）

之後隨時可以說「裝 playwright」來啟用。
```

### Phase 2: Runtime 碰到缺失

Skill 執行時檢查 `dependencies.{lib}.status`：

| Status | 行為 |
|--------|------|
| `consented` | 確認 lib 已安裝（`which` / `npx --version`）。沒裝就自動裝 |
| `declined` | **靜默 skip** 該功能，不詢問。在 skill output 末尾附註：「visual regression 已跳過（playwright 未安裝）」 |
| `pending` 或不存在 | **首次提示**（見下方） |

首次提示：
```
Visual regression 需要 playwright 來執行截圖比對。

框架推薦：playwright（免費、支援 SSR 全頁截圖）
你也可以選擇其他瀏覽器自動化工具，只要支援截圖比對即可。

(安裝推薦的 / 我要用其他的 / 不安裝)
```

- **安裝推薦的** → `status: consented`，安裝，繼續執行
- **我要用其他的** → 詢問工具名稱，記錄到公司層 config 的對應欄位，`status: consented`
- **不安裝** → `status: declined`，警告缺失功能，記錄日期

### Phase 3: 使用者調整

使用者隨時可以說：

| 指令 | 效果 |
|------|------|
| 「裝 playwright」 | `status` 改為 `consented`，執行安裝 |
| 「不要 mockoon」 | `status` 改為 `declined`，更新 `decided_at` |
| 「我要用 prism 取代 mockoon」 | `mockoon-cli.status` 改為 `declined`，公司 config 覆寫 fixture tool |
| 「重設依賴選擇」 | 所有 status 改為 `pending`，下次碰到重新詢問 |

## Skill 端整合方式

在 SKILL.md 需要外部 lib 的步驟前加入：

```markdown
### 前置：檢查依賴
讀取 root workspace-config.yaml → dependencies.{lib}.status。
依照 dependency-consent 機制（參考 `references/dependency-consent.md`）處理。
```

## 框架推薦清單

| 功能 | 推薦 lib | 角色說明 | 替代選項 |
|------|---------|---------|---------|
| visual-regression | `playwright` | 瀏覽器截圖引擎，支援 SSR 全頁截圖 | — （目前無同級替代） |
| visual-regression | `mockoon-cli` | API fixture server，提供穩定測資 | Prism、json-server、WireMock |
| e2e | `playwright` | 瀏覽器自動化引擎 | Cypress |

此表隨框架功能擴充而增長。新增功能需要新 lib 時，更新此表並在下次 `/init` 時提示。
