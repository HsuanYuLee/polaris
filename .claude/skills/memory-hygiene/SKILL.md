---
name: memory-hygiene
description: |
  Manual memory tiering — classify Hot/Warm/Cold, review candidates, and migrate MEMORY.md index + memory files. Use when the session-start advisory fires, MEMORY.md Hot grows past 15 entries, or you want a periodic cleanup. Trigger "memory-hygiene", "整理記憶", "memory 降級", "/memory-hygiene", "decay scan", "tier memory".

  記憶要整理：MEMORY.md 的 Hot 區長太長、session 開場的提醒跳出來、或想定期清一次。
  例如「整理記憶」「memory 降級」「decay scan」。

  不用於：寫一則新記憶（那直接寫）、找一則舊記憶（那直接讀）。
metadata:
  triggers: |
    - "memory-hygiene"
    - "/memory-hygiene"
    - "整理記憶"
    - "memory 降級"
    - "memory 清理"
    - "decay scan"
    - "tier memory"
    - "memory tier"
  version: 1.1.0
  requires:
    - skill: driving-work-to-done
      why: 「哪張單卡住了」這一題本支明文不答，交給它的 spine-loop-state.sh next；沒有它的話那一段是一個指不到任何地方的轉介
---

# Memory Hygiene

`memory-hygiene` 是 manual memory tiering：檢查 Hot / Warm / Cold，產生 demotion
candidate，並在使用者確認後搬移 memory files 與更新 index。

## Contract

這是 memory maintenance skill，不是一般 task planning。Scan / dry-run 只讀；apply 會寫
workspace memory，因此必須先有本 session 的 dry-run 結果與使用者明確確認。

## Mode Routing

| User says | Mode | Reference |
|---|---|---|
| `/memory-hygiene`, `memory-hygiene`, default | scan | `memory-hygiene-scan-flow.md` |
| `dry-run`, `full report`, `看看所有分類` | dry-run | `memory-hygiene-scan-flow.md` |
| `apply`, `搬檔`, `執行`, `migrate` | apply | `memory-hygiene-apply-flow.md` |
| `retire`, `退休`, `清掉做完的`, `過期的 memory` | retire | 見〈退休〉 |

## 退休：記進度的 memory，在它記的工作收斂之後就走

```bash
python3 .claude/skills/memory-hygiene/scripts/memory-hygiene-tiering.py retire \
  --memory-dir {memory_dir}            # 預覽，什麼都不動
python3 .claude/skills/memory-hygiene/scripts/memory-hygiene-tiering.py retire \
  --memory-dir {memory_dir} --execute  # 真的搬
```

**分層不是退休。** Hot → Warm 只是換一個資料夾躺著，索引還是指得到它。退休問的是另一
個問題：這份東西記的工作還活著嗎。`type: project` 記的是「現在做到哪」，那件工作收斂之後
它就不再是任何人的下一步了。

判定的依據是**那張單自己的狀態**（`{單}/.spine/loop-state.json` 的 `status`），不是誰記得
要來清——這一層已經有兩個手動退休到一半就停下來的資料夾。單號從 `snapshot_of` 或檔名取，
**不掃內文**：一份 handoff 會順帶提到十幾張單，拿內文去判會把還在用的錨點記錄，判成某張
早就收斂的單的殘骸。

四件事不退休，而且每一種都會被數出來印在報告上：`type` 不是 `project` 的、`pinned: true`
的（那是人的判斷，機械規則不得蓋過它）、單還在進行的、以及**找不到那張單容器的**。最後
那一種特別重要：把查不到當成做完了，退休掉的就是還在用的東西。

退休 ＝ 搬進 `archive/` 並從索引上拿掉，**不刪檔**。搬的時候會一併把指向它的連結、以及
它自己的相對連結重新算過——換了目錄，相對路徑的起點就換了，兩邊都會變成死指標。

## Reference Loading

| Situation | Load |
|---|---|
| Any run | `polaris-project-dir.md`, `feedback-memory-procedures.md` |
| Scan / dry-run | `memory-hygiene-scan-flow.md` |
| Apply | `memory-hygiene-apply-flow.md` |
| 要寫一份 memory（不是維護它） | `memory-write-contract.md` |

`memory-write-contract.md` 講的是**寫入端**：檔案放哪個資料夾、指標寫進哪一份索引、Hot 的
軟上限、以及 `pinned` / `topic` 兩個分層欄位。它以前住在使用者機器上的常駐指示檔裡，那個
位置沒有任何閘看得見——規矩要跟著執行它的東西走，而消費那兩個欄位的腳本就在這支 skill 的
`scripts/` 底下。

Classification rules live in `.claude/skills/memory-hygiene/scripts/memory-hygiene-tiering.py` and
`_template/rule-examples/feedback-and-memory.md` Memory Tiering.

Plan artifact authority lives in `bash .claude/skills/memory-hygiene/scripts/validate-memory-hygiene-plan.sh`。
`apply` 不應直接吃任意 JSON；必須先通過 plan validator。

## Hard Rules

- Apply requires prior dry-run in the same session.
- Do not hard-code user-specific memory paths; resolve active workspace memory dir.
- Do not auto-move pinned memories.
- 不刪除 Cold memories；archive 是 historical context。
- Routine migrations 不建立 feedback memory。
- If apply finds anomalies, record at most one framework-experience memory.
- Canonical apply chain is `dry-run --json | validate-memory-hygiene-plan.sh | apply`；不要手動改 plan JSON 後直接餵 apply。
- DP-213 起 apply 一定把 Hot 收斂到 ≤ 15（`MEMORY_HOT_CAPACITY` env 可覆寫）：超量者依
  確定性 ranking 自動降 Warm，pinned + graduated_to 永遠不被擠出，migration log 列出
  `overflowed-hot-capacity` 降級檔名。chain 在含 nested_frontmatter 的 plan 也能跑通；
  validator 把 nested_frontmatter 移到 warnings，apply 內部 normalize 是唯一 enforcement
  path，不需要 `POLARIS_MEMORY_HYGIENE_APPLY=1` bypass。

## Completion

Return mode, memory dir, Hot/Warm/Cold counts when available, candidate summary, apply status,
files moved, migration log path, and any anomalies.

