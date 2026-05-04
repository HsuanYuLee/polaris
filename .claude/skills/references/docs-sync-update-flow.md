---
title: "Docs Sync Update Flow"
description: "docs-sync 的 English source docs 更新順序、zh-TW translation sync、pillar mapping 與 editorial constraints。"
---

# Docs Update Contract

這份 reference 定義實際文件更新順序。

## English Source First

English docs 是 source of truth。先更新 English source，再同步 zh-TW translation pair。

Update order：

1. `docs/chinese-triggers.md`：skill trigger catalog，雖是 zh-TW standalone，但由 skill
   frontmatter 直接導出。
2. `README.md`：Three Pillars skill lists 與 high-level user-facing narrative。
3. `docs/workflow-guide.md`：development lifecycle、workflow diagrams、orchestration prose。
4. `docs/pm-setup-checklist.md`：只有 PM handoff 或 setup responsibility 改變時更新。
5. `docs/quick-start-zh.md`：primary workflow examples 或 quick-start path 改變時更新。

不要重寫未變更 sections。

## Trigger Docs

`docs/chinese-triggers.md` 維持既有 table format：

- 功能
- 中文觸發詞
- 英文觸發詞
- 說明

新增 skill 時放到正確 category，並保留 pillar tag。移除 skill 時同步刪除 stale row。

## README And Workflow Guide

README 只更新 high-level skill list 或 narrative。不要把 SKILL.md internal steps 寫進 README。

Workflow guide 只更新 user-visible flow。若要改 Mermaid diagrams：

- add/remove nodes consistently across affected diagrams。
- assign existing style class。
- update connectivity prose below diagrams。
- keep labels stable unless skill renamed。

## zh-TW Translation Sync

每個 English file 修改後，只翻譯 changed section：

| Source | Translation |
|---|---|
| `README.md` | `README.zh-TW.md` |
| `docs/workflow-guide.md` | `docs/workflow-guide.zh-TW.md` |
| `docs/pm-setup-checklist.md` | `docs/pm-setup-checklist.zh-TW.md` |

Translation rules：

- 使用台灣繁體中文。
- Skill names、commands、paths、code blocks 保持原樣。
- Mermaid labels 保持 English。
- 不重翻 unchanged sections。

## Pillar Mapping

| Skill Type | Pillar | Category |
|---|---|---|
| dev workflow, branch, code, PR | 輔助開發 | 開發流程 or 程式碼審查 |
| learning and quality | 自我學習 | 品質保障 |
| standup, sprint, worklog | 日常紀錄 | 專案管理 |
| tools, config, init | none | 工具與設定 |

## Editorial Constraints

遵守 `docs-editorial-guideline.md`：

- 結論先行。
- Show, do not over-explain.
- Public docs 描述「使用者能做什麼」，不要複製 internal implementation。
- Keep bilingual docs structurally aligned。
