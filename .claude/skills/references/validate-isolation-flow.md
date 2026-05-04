---
title: "Validate Isolation Flow"
description: "validate isolation mode 的 multi-company scope headers、cross-company conflicts、memory company tags、MEMORY.md index、user data leak scan 與 report rows。"
---

# Validate Isolation Contract

這份 reference 負責 isolation health checks。

## Checks

1. Scope headers：company-specific rule files must declare matching scope.
2. Cross-company conflicts：scan for contradictory rules and cross-company references.
3. Memory company tags：company-specific memories need `company:` frontmatter.
4. `MEMORY.md` index：company-scoped entries need visible company marker.
5. User data leak：run `scripts/scan-user-data-leak.sh` for hardcoded user-specific data in
   shared rules.

## Result Classification

| Finding | Status |
|---|---|
| Missing required scope header | FAIL |
| Cross-company contradiction | FAIL |
| Company-specific memory without tag | WARN or FAIL by severity |
| User-specific data in shared rules | FAIL |
| Index marker missing but memory has company tag | WARN |

## Output

Report per company:

- scope header count
- missing files
- conflicting references
- memory tag findings
- user-data-leak findings

Do not apply fixes automatically.
