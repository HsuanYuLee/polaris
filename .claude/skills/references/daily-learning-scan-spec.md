# Daily Learning Scan — 規格文件

本文件是 daily-learning-scan scheduled agent 的 single source of truth。
更新雲端 prompt（claude.ai/code/scheduled）時以此為準。

## 排程

- **頻率**：每天 22:00 UTC+8
- **執行方式**：Claude Code Scheduled Agent（cloud）
- **輸出**：寫入 `skills/references/learning-queue.md`，commit & push

## 每日目標量：7-10 篇

| 類別 | 篇數 | 必選 | 說明 |
|------|------|------|------|
| **AI/Agent** | 2-3 | ✅ | Claude Code、MCP、multi-agent、skill patterns、AI-assisted dev、prompt engineering、AI coding workflow |
| **Active Repos 技術棧** | 4-5 | | Nuxt/Vue/TS/Vitest/Turborepo 等，標記相關 repo |
| **Architecture / DX** | 1-2 | | 跨 repo 通用：monorepo、CI/CD、ESLint、效能、設計模式 |

> AI/Agent 是必選類別 — 每日至少 2 篇。這是 workspace 持續提升的關鍵。

## 掃描類別與關鍵字

### AI/Agent（必選）
- Claude Code features, updates, tips
- MCP server patterns, tool design
- Multi-agent orchestration, agent frameworks
- AI-assisted development workflow
- Skill / prompt engineering patterns
- AI code review, AI testing
- LLM application patterns（RAG, function calling, structured output）

### Testing
- Vitest mock patterns, browser mode, coverage optimization
- Vue Test Utils, component testing
- E2E testing（Playwright）
- Testing architecture patterns

### Performance
- Core Web Vitals（TTFB, LCP, CLS, INP）
- Nuxt SSR/ISR/SWR optimization
- Bundle size optimization
- Image optimization, lazy loading

### Framework
- Nuxt 3/4 features, migration
- Vue 3 composable patterns
- TypeScript type safety patterns
- Server components, hybrid rendering

### DX Toolchain
- Turborepo, pnpm workspaces
- ESLint flat config, linting
- CI/CD optimization
- Developer experience improvements

### Architecture
- 大型 Vue/Nuxt 專案組織
- Design System versioning
- Monorepo 策略
- API design patterns

## Active Repos

Scanner 優先掃這些 repo 相關的技術主題，並在每篇文章標記 `Relevant Repos`：

| Repo | 技術棧 | 關注重點 |
|------|--------|---------|
| `your-org-app-a` | Nuxt 3/4, Vue 3, TypeScript, Vitest, Turborepo | SSR 效能、SEO、CWV、商品頁優化 |
| `your-org-app-b` | PHP (Laravel), Vue 2→3 migration | API 設計、前後端整合 |
| `your-org-mobile` | Vue 3, mobile-first | Mobile 效能、RWD |
| `your-org-docker` | Docker, nginx | 開發環境、部署 |
| `your-design-system` | Vue 3, component library | 元件設計、token system |
| `your-org-skills` | Claude Code skills, AI workflow | AI agent 設計模式 |

其他 repo（`your-org-email`、`your-org-static`）有相關文章時標記，但不主動搜尋。

## Relevant Repos 標記規則

每篇文章必須標記 `Relevant Repos`，依文章內容判斷：

| 文章主題 | 標記 |
|---------|------|
| Nuxt SSR / ISR / route rules | `your-org-app-a` |
| Vue 3 composable / component patterns | `your-org-app-a`, `your-org-mobile`, `your-design-system` |
| Vitest / testing patterns | `your-org-app-a`, `your-org-mobile` |
| TypeScript 通用（type safety, new features） | `all` |
| Turborepo / monorepo | `your-org-app-a` |
| Docker / nginx / dev environment | `your-org-docker` |
| AI agent / Claude Code / MCP / skill design | `your-org-skills` |
| Design system / component library | `your-design-system` |
| PHP / Laravel | `your-org-app-b` |
| 跨 repo 通用（ESLint, CI/CD, architecture） | `all` |

## Output 格式

每篇文章寫入 `learning-queue.md` 的格式：

```markdown
### {Article Title}
- **URL**: {url}
- **Category**: {category}
- **Tags**: {tag1}, {tag2}, ...
- **Relevant Repos**: {repo1}, {repo2} 或 all
- **Summary**: {一段話摘要，說明文章內容和為什麼值得讀}
- **Added**: {YYYY-MM-DD}
```

## 品質篩選標準

- **發佈時間**：優先 3 個月內，最多 6 個月
- **深度**：有具體 code examples 或 config 範例，不是純概念介紹
- **實用性**：可直接應用到我們的專案，或提供明確的 migration path
- **去重**：比對 `learning-queue.md` 和 `learning-archive.md` 的 URL，不重複加入

## Commit 格式

```
chore: daily learning queue update YYYY-MM-DD
```

## Scheduled Agent 維護規則

Scan prompt 透過 RemoteTrigger API 管理（不是本地 cron）。調整 scan 邏輯時：

1. **修改本文件**（`daily-learning-scan-spec.md`）— 這是 single source of truth
2. **停用舊 trigger**：`RemoteTrigger update` → `{"enabled": false}`
3. **建立新 trigger**：`RemoteTrigger create` — prompt 引用本文件（`Read skills/references/daily-learning-scan-spec.md`），不在 prompt 裡重複寫規則
4. 確認新 trigger 的 `next_run_at` 正確

> 不要用 `RemoteTrigger update` 改 prompt — 建新的比較乾淨，舊的留著當歷史紀錄。

**目前 trigger**：`daily-learning-scan-v2`（`trig_018Dy1eTy2tBBYxjY52SUXCA`），cron `57 13 * * *`（每天 21:57 UTC+8）
