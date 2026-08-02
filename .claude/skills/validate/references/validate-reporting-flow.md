---
title: "Validate Reporting Flow"
description: "validate 的 combined report format、PASS/WARN/FAIL summary、proposed fixes、skipped checks 與 user confirmation boundary。"
---

# Validate Reporting Contract

這份 reference 負責 validate report。

## Report Shape

Report sections:

- mode
- date
- isolation results when run
- mechanism results when run
- summary counts
- failed checks
- warnings
- skipped checks
- proposed fixes

## Status Semantics

| Status | Meaning |
|---|---|
| PASS | check succeeded |
| WARN | issue surfaced but not blocking |
| FAIL | health violation or validator failure |
| SKIPPED | not applicable or already covered by another mode |

## Fix Boundary

每個 FAIL 都提出具體 fix，包含 file/script reference；套用前先詢問使用者。

每個 WARN 都標示 impact 與 owner；除非 validator 定義 WARN blocking，否則不阻擋。

## Combined Summary

Show total checks, PASS/WARN/FAIL/SKIPPED counts, and next recommended action.
