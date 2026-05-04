---
title: "Docs Sync Verification Flow"
description: "docs-sync 的 bilingual language validation、docs lint、internal links、Starlight check 與 completion report。"
---

# Docs Verification Contract

這份 reference 定義 docs-sync 完成前的 verification。

## Language Modes

Docs-sync 使用 docs-specific language policy，不可把 English source docs 當 zh-TW artifact
檢查。

Use：

| File type | Mode |
|---|---|
| `README.md`, English workflow/checklist docs | `bilingual-source` |
| `README.zh-TW.md`, zh-TW workflow/checklist, quick start, chinese triggers | `bilingual-translation` |

這是 `workspace-language-policy.md` 中登記的 docs-specific exception。不要改成 artifact mode。

## Deterministic Checks

完成更新後：

1. Re-run README/docs lint。
2. Verify skill counts and trigger table consistency。
3. Check bilingual pair section alignment for modified pairs。
4. Check internal links touched by this sync。
5. 若本次產生或修改 Starlight docs/specs，對 explicit paths 執行 Starlight authoring check。

## Translation Consistency

對每個 modified pair 檢查：

- source section exists in translation。
- skill names match。
- code blocks and commands unchanged。
- Mermaid node IDs and labels align。
- links point to equivalent targets。

不要因為全檔舊內容已有 drift 就重寫全檔；只回報 unrelated drift。

## Completion Report

Final output 包含：

- docs lint result。
- changed files and what changed。
- translation pairs synced。
- files checked but unchanged。
- skipped dimensions with reason。
- verification commands and pass/fail status。
- remaining manual follow-up if any。

若 docs already in sync，回報 lint clean 與 no docs-impacting diff。
