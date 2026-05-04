---
title: "SASD Review Entry Exploration Flow"
description: "sasd-review 的 workspace config、ticket fetch、project mapping、requirements analysis、design-first confirmation 與 codebase exploration。"
---

# SASD Entry And Exploration Contract

這份 reference 負責 SA/SD 前半段：讀票、定位 project、需求分析、探索。

## Config And Ticket

讀 workspace config，取得 JIRA instance、Confluence space、project mappings。Ticket key 來源：

1. 使用者提供。
2. Current branch。
3. 詢問使用者。

透過 Atlassian MCP 讀 JIRA ticket，取得 summary、description、AC、issue links、attachments
或外部 PRD/design/API/discussion links。

## Project Mapping

依 `project-mapping.md` 從 summary tag、JIRA project key、component、label、config
`projects[].tags` / `keywords` 找 target project。找不到或多個候選時，請使用者確認。

後續 codebase analysis 以 target project path 為 root。

## Requirements Analysis

先回答：

- 要解決什麼問題。
- 預期行為如何改變。
- 受影響使用者或流程。
- 已知 PRD / Design / API / Slack discussion。
- 缺漏或不明確之處。

Ambiguity 必須 surface。不要用假設補齊需求。

## Design-first Confirmation

Medium 或 large scope 要提出 2-3 個 approach，附 trade-offs、風險、推薦方案。即使 ticket
description 已寫方案，也要確認方案仍合理。

使用者確認 approach 前，不產 final SA/SD，也不寫外部系統。

## Codebase Exploration

依 `explore-pattern.md` 探索：

- affected files and modules
- existing architecture
- data flow and service boundaries
- reusable utilities/patterns
- risks and unknowns
- tests or verification entry points

大 scope 可派 Explore sub-agent。Dispatch prompt 使用 main checkout absolute paths 讀
gitignored framework artifacts，遵守 `worktree-dispatch-paths.md`。若需要 runtime probe，
依 `planning-worktree-isolation.md` 使用 dedicated worktree。

收到 exploration summary 後，不重讀全部 source；只在特定區域不足時做 targeted follow-up。
