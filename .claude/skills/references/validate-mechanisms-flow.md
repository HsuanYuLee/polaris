---
title: "Validate Mechanisms Flow"
description: "validate mechanisms mode 的 static canary smoke tests、routing/skill contract drift、hook/settings checks、model tier drift、L2 embedding integrity 與 exit handling。"
---

# Validate Mechanisms Contract

這份 reference 負責 mechanism static smoke tests。

## Static Checks

Run applicable checks:

- scope headers, unless isolation already ran
- settings bash patterns that encourage unsafe directory changes
- skill routing completeness
- memory company isolation, unless isolation already ran
- sub-agent role standards
- feedback memory frontmatter
- mechanism source file freshness
- ghost references to deleted skills
- hardcoded path patterns in generic skills
- hooks in project local settings
- L2 embedding integrity via `scripts/validate-l2-embedding.sh`
- cross-LLM skill mirror mode via `scripts/check-skills-mirror-mode.sh`
- model tier policy drift via `scripts/validate-model-tier-policy.sh`
- skill contract drift via `scripts/validate-skill-contracts.sh`

## Exit Handling

| Exit | Status |
|---|---|
| 0 | PASS |
| 1 | FAIL unless tool documents WARN-only semantics |
| 2 | FAIL / registry meta error |

Deterministic validators 的 per-entry errors 要完整呈現，不要折疊成 generic fail。

## Scope Boundary

Static validate cannot prove live conversation behavior such as skill-first invoke,
delegation timing, or post-task reflection quality. Those remain post-task audit mechanisms.
