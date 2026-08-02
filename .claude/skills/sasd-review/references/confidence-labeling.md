# Confidence Labeling

AI 研究產出的信心標示機制。LLM 做研究但不做結論 — 產出附信心等級，人決定是否採納。

## 信心等級

| Level | 條件 | 顯示 | 下游處理 |
|-------|------|------|---------|
| **HIGH** | 官方 docs URL（`.dev`, `developers.*`, 官方 GitHub），內容日期 < 2 年 | `[HIGH]` | 可直接採用作為決策依據 |
| **MEDIUM** | WebFetch 成功但頁面可能不完整（SPA）、或非官方但高信譽來源（MDN, Stack Overflow 高票答案） | `[MEDIUM]` | 列出供參考，需人工判斷是否採納 |
| **LOW** | 搜尋摘要、未 fetch 原文驗證、或來源日期 > 2 年 | `[LOW]` | 僅列出，明確標示「未驗證」 |
| **NOT_RESEARCHED** | 知道該查但沒查到 / 沒查 / 超出 AI 能力 | `[NOT_RESEARCHED]` | 明確標示缺口，由人決定是否自行研究 |

## 判定規則

```
有 URL + fetch 成功？
  ├─ Yes → 是官方 docs？
  │         ├─ Yes → 日期 < 2 年？ → HIGH / LOW
  │         └─ No  → 高信譽來源？  → MEDIUM / LOW
  └─ No  → 有搜尋摘要？
            ├─ Yes → LOW
            └─ No  → NOT_RESEARCHED
```

### 官方 docs 判定

以下 pattern 視為官方：
- `*.dev` 開發者文件（web.dev, developer.android.com）
- `developers.*`（developers.google.com）
- GitHub org 下的官方 repo（vuejs/core, nuxt/nuxt）
- npm package 的 README（與 package name 相同的 repo）
- RFC 文件（IETF, W3C, TC39）

### 高信譽來源

- MDN Web Docs
- Stack Overflow 答案（score ≥ 10）
- 知名技術 blog（CSS-Tricks, Smashing Magazine, web.dev blog）
- Conference talks with published slides/video

## 使用方式

### 在 refinement artifact 中

```json
{
  "research": [
    {
      "topic": "Intersection Observer for lazy loading",
      "findings": "瀏覽器原生支援，MDN 推薦取代 scroll event listener",
      "confidence": "HIGH",
      "sources": [
        { "url": "https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API", "type": "official_docs" }
      ]
    }
  ]
}
```

### 在 JIRA comment 中

```
### Solution Research

| # | 做法 | 信心 | 來源 |
|---|------|------|------|
| 1 | Intersection Observer lazy loading | [HIGH] | [MDN](https://...) |
| 2 | Virtual scroll for long lists | [MEDIUM] | CSS-Tricks 文章（2024） |
| 3 | Server-side pagination | [NOT_RESEARCHED] | 需確認 API 是否支援 |
```

## 適用 Skill

| Skill | 使用場景 |
|-------|---------|
| **refinement** (Tier 3) | Solution Research 步驟的研究產出 |
| **breakdown** (scope-challenge mode) | 挑戰需求時引用的業界做法 |
| **learning** (external mode) | 外部資源消化的信心標示 |
| **sasd-review** | 技術方案選擇的依據標示 |

## 設計原則

1. **AI 不做結論** — 標信心、列來源，但不說「應該用方案 A」
2. **人的判斷優先** — HIGH 表示「來源可靠」，不表示「答案正確」
3. **明確標示缺口** — NOT_RESEARCHED 比「我覺得可以」有價值
4. **來源可追溯** — 每個 finding 附 URL，讓人可以自己驗證
