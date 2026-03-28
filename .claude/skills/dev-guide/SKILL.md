---
name: dev-guide
description: >
  Project-aware development guide: project structure, naming conventions, coding patterns,
  and implementation workflow. Auto-detects the current project from the working directory.
  This is a reference skill — primarily invoked by other skills (work-on, fix-bug)
  during implementation, or when the user explicitly asks about project conventions.
  Use when: (1) user asks about project structure, naming conventions, or coding patterns,
  (2) user asks "how should I structure this", "where should I put this file",
  "這個檔案放哪", "怎麼寫比較好", "專案結構", "命名規範",
  (3) creating new files and need to know where to put them,
  (4) writing components, composables, stores, or APIs and need convention guidance.
  Do NOT trigger directly for "implement" or "start coding" — those go to work-on
  which will reference this guide internally when needed.
metadata:
  author: ""
  version: 1.0.0
---

# dev-guide

專案開發指南。實作功能時，依循當前專案的規範。

> **重要**：本 skill 為跨專案共用版本。如果當前專案目錄有專屬的 `dev-guide` skill（在 `{project}/.claude/skills/`），會自動使用專案版本。

## 0. Project Detection & Context Loading

1. **偵測當前專案**：根據工作目錄比對 `workspace-config.yaml` 的 `projects[]` 清單（`projects[].path`）
2. **讀取 CLAUDE.md**：取得專案概覽、技術棧、重要約定
3. **讀取 `.claude/rules/`**：如果存在，載入所有規則檔案作為開發規範

```
判斷流程：
  讀取 {config: projects[]} 中各項的 path 和 tags
  比對 pwd → 找到對應專案 → 載入該專案的 CLAUDE.md 和 .claude/rules/
  若 pwd 不在任何已知專案下 → 提示使用者確認專案，或依 package.json 推測技術棧
```

若 workspace-config.yaml 尚未設定，fallback 到讀取 pwd 下的 `CLAUDE.md` 和 `package.json` 推測。

## 1. Read Project Context

**必須先執行以下步驟，才能提供開發指引：**

1. 讀取專案根目錄的 `CLAUDE.md`（所有專案都已建立）
2. 檢查是否有 `.claude/rules/` 目錄，若有則讀取所有規則
3. 檢查 `package.json` 確認技術棧細節（測試框架、lint 設定等）

## 2. General Coding Patterns

以下為跨專案通用的開發原則（各專案的 CLAUDE.md 和 rules 有更細的規範）：

### 2.1 TypeScript
- 一律使用 TypeScript
- 避免 `any`，優先使用明確型別
- 物件結構用 `interface`，聯合/條件型別用 `type`

### 2.2 命名慣例
- **Vue 組件檔案**：PascalCase（`ProductCard.vue`）
- **一般檔案**：camelCase 或 kebab-case（依專案慣例）
- **變數**：camelCase
- **常數**：UPPER_SNAKE_CASE
- **布林變數**：`is`/`has`/`can` 前綴
- **事件處理**：`handle` 前綴

### 2.3 Vue 組件
- 使用 Composition API + `<script setup lang="ts">`（Vue 3 專案）
- Vue 2.7 專案也應優先使用 `<script setup>`（如專案支援）
- SFC 順序：script → template → style

### 2.4 測試
- 測試檔案放在 source 旁邊
- 命名格式：`*.test.ts` 或 `*.spec.ts`（依專案慣例）
- 每個 public function 至少一個 happy path 測試

## 3. Project-Specific Guidance

**根據偵測到的專案，提供以下專屬指引。**

> 專案清單來自 `{config: projects[]}`。每個專案的技術棧細節在該專案的 `CLAUDE.md` 中定義。
> 以下僅列出通用技術棧識別模式，具體細節以專案 CLAUDE.md 為準。

### Vue 2.7 + Webpack 專案（PHP + CI 框架後端）

| 面向 | 說明 |
|------|------|
| 框架 | Vue 2.7 + Vuex 3 + Vue Router 3 |
| 建置 | Webpack 5 |
| 測試 | Jest 29 + @vue/test-utils |
| 樣式 | SCSS + Stylelint |
| 套件管理 | pnpm |
| Lint | ESLint + Prettier（lint-staged + husky） |

識別特徵：`package.json` 含 `vue@2.x`、`webpack`

### Design System / 元件庫

| 面向 | 說明 |
|------|------|
| 框架 | Vue 2.7 / Vue 3（vue-demi 雙版本支援） |
| 建置 | Vite + Rollup |
| 測試 | Jest 29 + @vue/test-utils |
| 文件 | VuePress + Storybook |
| Monorepo | pnpm workspace |

識別特徵：`package.json` 含 `rollup`、`vue-demi`

### Email 模板專案

| 面向 | 說明 |
|------|------|
| 框架 | MJML + Handlebars |
| 建置 | Gulp 4 |
| 測試 | 無 |
| 樣式 | Style Dictionary |

識別特徵：`package.json` 含 `mjml`、`gulp`

## 4. Implementation Workflow

```
1. 理解需求        → 讀 JIRA ticket / SA/SD
2. 確認專案        → 根據 ticket 的 path 或 mapping 確認專案
3. 讀取規範        → CLAUDE.md + .claude/rules/（如有）
4. 建立分支        → git-pr-workflow 或 jira-branch-checkout
5. 確認檔案位置    → 參考 CLAUDE.md 的目錄結構說明
6. 實作            → 依循專案規範
7. 環境變數檢查    → 若新增 env var，依 .claude/rules/env-var-workflow.md 流程處理
8. 品質檢查        → dev-quality-check skill
9. Commit & PR     → git-pr-workflow
```

## 5. Pre-commit Checklist

- [ ] 新檔案放在正確的目錄
- [ ] TypeScript 型別完整，無 `any`
- [ ] 新的 public function 有對應測試
- [ ] 現有測試仍然通過
- [ ] 無 `console.log` / debugger 遺留
- [ ] 程式碼通過 ESLint 檢查
- [ ] 程式碼符合 `.claude/rules/` 規範（如有）
- [ ] 新增環境變數時：`.env` + `.env.template` + `turbo.json` 皆已同步更新
