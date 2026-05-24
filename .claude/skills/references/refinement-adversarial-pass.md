---
title: "Refinement Adversarial Pass"
description: "Author-side loophole pattern bank for refinement handoff hardening."
---

# Pattern Bank

在 handoff 前逐條 AC 自問以下攻擊面；若答案不清楚，就補 AC verification detail 或在
Adversarial Pass section 寫明 no attack surface 的理由。

1. Validator 有 schema 但 writer 沒有產生對應欄位。
2. Selftest 只測 happy path，沒有 broken fixture。
3. `--help` 文件暴露的 flag 與 AC detail 不一致。
4. 新 production script 沒有對應 selftest。
5. Reference delete / rename 沒有 referrer scan。
6. Release surface 改 `.claude/**` 或 `scripts/**`，但沒檢查 VERSION / CHANGELOG / manifest。
7. Modules table 與 `refinement.json` modules action drift。
8. Risks / edge cases 只更新其中一份 artifact。
9. AC ID 用非 canonical shape，導致 extractor 漏抓。
10. Machine contract 仍依賴 free-form `breakdown_hints[]`。
11. Derived view 允許手改，導致 JSON 與 Markdown drift。
