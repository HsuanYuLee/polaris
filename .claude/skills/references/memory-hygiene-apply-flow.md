---
title: "Memory Hygiene Apply Flow"
description: "memory-hygiene apply mode 的 safety checks、dry-run plan reuse、migration command、post-apply report、fresh-session verification 與 anomaly memory rule。"
---

# Memory Hygiene Apply Contract

這份 reference 負責 memory-hygiene apply mode。

## Safety Checks

Apply 前確認：

- 本 session 已看過 dry-run。
- 使用者明確同意 apply。
- memory dir path 已由 `polaris-project-dir.md` 推導。
- pinned memories 不會被自動搬移。

若 memory dir 有未預期 local edits，先提示使用者；不要覆寫或刪除。

## Preferred Command

Prefer dry-run JSON piped to apply，確保 apply 使用同一組 file set：

```bash
scripts/memory-hygiene-tiering.py dry-run --memory-dir "{memory_dir}" --json \
  | scripts/memory-hygiene-tiering.py apply --memory-dir "{memory_dir}"
```

若 apply mode 不支援該輸入，停止並回報 script limitation；不要手動搬檔補洞。

## Post-Apply Report

回報：

- hot to warm count
- warm to cold count
- new topic folders
- `MEMORY.md` size before/after
- `.migration-log.md` path
- anomalies

## Verification

建議 fresh session 讀 `/memory` 或等效 memory load，確認 `MEMORY.md` 可正常載入且 Hot count
合理。

## Anomaly Memory

只有 apply 發現 non-obvious behavior 時，才寫一筆 `framework-experience` memory，例如：

- orphan files
- missing frontmatter pattern
- topic inference miss
- script limitation

Routine migration 不寫 feedback memory。
