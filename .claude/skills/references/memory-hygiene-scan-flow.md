---
title: "Memory Hygiene Scan Flow"
description: "memory-hygiene 的 scan/dry-run mode、memory dir resolution、decay-scan command、full classification report 與 apply confirmation gate。"
---

# Memory Hygiene Scan Contract

這份 reference 負責 memory-hygiene 的 scan 與 dry-run modes。

## Memory Dir Resolution

使用 `polaris-project-dir.md` 推導 active workspace memory dir。不得寫死 user-specific
absolute path。

## Scan Mode

Scan 是 advisory、read-only，等同 session-start hook 的 user-triggered 版本。

Run：

```bash
scripts/memory-hygiene-tiering.py decay-scan --memory-dir "{memory_dir}"
```

Report script output，並詢問是否要 dry-run 看完整分類，或 apply 先前已確認的 plan。

## Dry-Run Mode

Dry-run 是 full classification，read-only。

Run：

```bash
scripts/memory-hygiene-tiering.py dry-run --memory-dir "{memory_dir}"
```

Summary must include：

- Hot / Warm / Cold counts
- top Hot demotion candidates
- topic folders that would be created
- pinned entries reminder
- anomalies such as missing frontmatter or unknown topic

## Apply Gate

Dry-run 後才可進 apply。若使用者要求 apply 但本 session 尚未 dry-run，先跑 dry-run 並要求
確認。
