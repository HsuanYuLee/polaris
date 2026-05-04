---
title: "Verify AC Disposition Flow"
description: "verify-AC FAIL 後的人工作業分流：implementation drift per-AC Bug、spec issue refinement route、handoff artifact 與互斥 disposition。"
---

# Verify Disposition Contract

這份 reference 負責 FAIL 後的人工分流。

## Gate

FAIL 後在 AC ticket 留 disposition checkbox，並在對話中請使用者選：

1. Implementation drift：code 未達 AC 行為，建立 per-AC Bug，交給 bug-triage。
2. Spec issue：AC 描述錯誤、不完整、或矛盾，回 refinement。
3. Later：保留 FAIL，不路由。

單輪只能選一條 disposition。verify-AC 不自行判斷 root cause。

## Implementation Drift

每條 FAIL AC 建一張 Bug。Bug description 必須包含 `[VERIFICATION_FAIL]` block：

- source AC ticket
- Epic
- analysis branch
- involved repos
- related task keys
- related PRs
- commit range
- failed item observed / expected
- reproduction conditions
- verification metadata
- evidence artifact path

不填 assignee；bug-triage 對 assignee blind。

同時寫 verify-fail handoff artifact，供 bug-triage AC-FAIL path on-demand 讀。Artifact 必須：

- 遵守 `handoff-artifact.md`。
- 若是 specs markdown，遵守 `starlight-authoring-contract.md`。
- 寫入後 scrub and cap。
- 跑 language advisory / gate。
- 跑 Starlight authoring check。

建立 Bug 後，在 AC ticket comment 回寫追蹤 Bug keys，並提示 `bug-triage {BUG_KEY}`。

## Spec Issue

不建 Bug。在 Epic 上加 `verification-spec-issue` label，並寫 `[VERIFICATION_SPEC_ISSUE]`
comment，包含 source AC、observed、expected、spec problem、refinement suggestion。

回 AC ticket comment 說明規格待 refinement 釐清，並提示回 `refinement`。

## Later

保留 FAIL comment 與 evidence，不建立 Bug、不加 spec issue label。Final summary 明確列為
manual pending。
