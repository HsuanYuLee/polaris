---
title: "Checkpoint Carry Forward Flow"
description: "checkpoint save mode 的 cross-session carry-forward deterministic validator、exit code handling、pending item disposition 與 retry 規則。"
---

# Checkpoint Carry-Forward Contract

這份 reference 負責 checkpoint save 前的 carry-forward validator。

## Purpose

新 checkpoint 不能默默遺失上一個同 topic checkpoint 的 pending items。每個舊 pending item
都必須被標記為：

- done
- carry-forward
- dropped

## Preconditions

新的 project-memory checkpoint 必須已寫到 disk；validator 比對檔案，不比對對話草稿。

需要：

- `new_checkpoint_path`
- `memory_dir`

## Command

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-carry-forward.sh" \
  --new-checkpoint "{new_checkpoint_path}" \
  --memory-dir "{memory_dir}"
```

## Exit Code Handling

| Exit | Meaning | Handling |
|---|---|---|
| 0 | PASS | continue save flow |
| 1 | recoverable failure | fix invocation/path and retry, max 3 rounds |
| 2 | hard stop | show missing items and ask user disposition |

Exit 2 時，依使用者 disposition 更新新的 checkpoint file，然後重跑直到 pass。

Never delete missing-item evidence just to silence the gate.
