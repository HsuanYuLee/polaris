---
title: "Bug Triage Root Cause Flow"
description: "bug-triage fast/full path root cause analysis、Explorer prompt boundary、impact/proposed fix schema 與 evidence artifact。"
---

# Root Cause Analysis Contract

這份 reference 負責一般 Bug 的根因分析。

## Full Path

需要 codebase investigation 時，派 Explorer sub-agent。Prompt 包含：

- ticket summary
- description
- AC or repro steps
- project directory or remote-read context
- handbook path
- expected output schema

Explorer 任務：

1. 讀 handbook。
2. 找 ticket 描述對應的功能、頁面、元件、API。
3. 找出哪個檔案、哪段邏輯造成 bug。
4. 評估同一段邏輯的其他使用者與連動風險。
5. 提出修正方向，不寫 code。
6. 回報 handbook gaps or stale observations。

若需要啟動 dev server、重現 bug、或跑 runtime verification，依 `planning-worktree-isolation.md`
使用 dedicated worktree，不污染 main checkout。

## Output Schema

Root Cause：

- file path
- one-line problem
- why it happens

Impact：

- affected features/pages
- related risk

Proposed Fix：

- fix direction
- estimated file count / scope

Handbook Observations：

- gaps
- stale entries

## Evidence Artifact

Full path Explorer Detail 寫入 `handoff-artifact.md` schema，包含 concise summary 與 raw
evidence。Raw evidence 可包含 grep results、suspect code lines、error trace、commit hash、
handbook excerpt。寫入後必跑 scrub and cap。

Fast path 沒有 Explorer artifact，但仍要保留同樣的 Root Cause / Impact / Proposed Fix
structure。

## Fast Path

Fast path 只能基於 ticket info 與最多少量 file reads inline analysis。仍需：

- project mapping
- root cause statement
- impact statement
- proposed fix scope
- RD confirmation hard stop

若 inline analysis 超出小範圍，立即升 full path。
