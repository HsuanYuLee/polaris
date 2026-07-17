# Changeset Convention — Generic L3 Default

當 repo 的 `.changeset/config.json` 已啟用 Changesets，但 repo handbook 沒有提供更具體語意
時，使用本 generic fallback。repo handbook 是 L2 語意 authority；本檔不承載任何特定
framework、package、release lane 或 task ceremony。

## Policy Layers

| 層級 | Authority | 責任 |
|------|-----------|------|
| L1 | `.changeset/config.json` | package graph、base branch、access、changelog plugin 等 machine facts |
| L2 | repo handbook `changeset-convention.md` | repo-specific bump、summary、release 語意 |
| L3 | 本檔 | 無 L2 時的 generic fallback |

`.changeset/config.json` 不存在時，repo 未啟用 Changesets，producer 與 verifier 都 no-op。

## Canonical Shape

```markdown
---
"{package_scope}": patch
---

一句話描述 user-facing 影響
```

- bump 僅可為 `patch`、`minor`、`major`；L3 default 是 `patch`。
- body 必須非空；technical identifiers 可保持原文。
- filename 由 producer 依 active task identity 與 title 穩定推導，不是 task schema 欄位。
- task `Allowed Files` 不列 exact changeset path；changeset 由 repo-native commit policy 管理。

## Producer

```bash
bash scripts/polaris-changeset.sh new --task-md <authoritative-task.md> --repo <repo-root>
```

producer 從 authoritative task 取得 identity/title，從 repo config 解析 package scope，並寫出
canonical changeset。single-package repo 直接推導；multi-package repo 若無法由 config 與 task
改動路徑唯一判定，只允許最小 `deliverables.changeset.package_scope` declaration 作消歧，且
必須 fail loud，不得恢復 exact filename、bump default 或格式 checklist 欄位。

## Enforcement

`scripts/gates/gate-changeset.sh --staged` 是 native pre-commit 與 agent guarded commit 共用的
single verifier。它以 prospective commit tree（HEAD + index）判斷：

- behavioral staged delta 缺 canonical changeset → block；
- changeset 只存在 worktree、未 stage → block；
- canonical changeset 已在 HEAD 或已 stage → pass；
- metadata-only staged delta或未啟用 Changesets → pass。

pre-push、completion 與 PR gate 保留 defense in depth，但不得成為第一次發現 local commit
缺 changeset 的位置。各 runtime 不得各自實作 writer 或分類器。

## Rebase Hygiene

繼承 changeset 的清理由 `scripts/changeset-clean-inherited.sh` 負責，與 producer 分離。
producer 對同一 identity/title 保持 idempotent；rebase 不改 task 意圖時不重寫 body。
