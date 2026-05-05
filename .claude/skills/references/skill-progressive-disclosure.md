---
title: "Skill Progressive Disclosure Reference"
description: "Skill slimming 的 progressive disclosure 與 resource ownership placement policy。"
---

# Skill Progressive Disclosure Policy

此 reference 定義 Polaris skill slimming 的 placement rule。目標不是把 `SKILL.md`
壓到越短越好，而是讓 agent 啟動時只先讀必要的 orchestration contract，細節在需要時
再載入 reference 或 script。

## 判斷基準

`scripts/skill-progressive-disclosure-audit.sh` 的輸出是 advisory baseline：

| Severity | Word count | 建議處理 |
|----------|------------|----------|
| P0 | `> 1000` | 優先拆出 reference / script，避免單次 skill 啟動載入過多內容 |
| P1 | `750-1000` | 檢查是否有可下沉的 mode、範例、長流程或 script block |
| P2 | `500-749` | 保持觀察；只有出現明顯重複或 mode 膨脹時處理 |
| INFO | `< 500` | 通常不處理，除非內容位置明顯錯誤 |

Scanner signals 的意義：

- `multi-mode`：同一 skill 內有多個入口或流程，適合把 mode-specific 細節拆成 reference。
- `long-section`：單一 section 過長，適合切成 reference 或 script。
- `script-candidate`：大段命令、查詢或格式化邏輯，優先移成 deterministic script。

## Placement Rules

先判斷內容是否應離開 `SKILL.md`，再判斷下沉後的 owner。

| 內容類型 | 放置位置 | 判斷方式 |
|----------|----------|----------|
| Routing、authority boundary、mandatory gate、fail-stop 條件 | `SKILL.md` | agent 一進 skill 就必須知道，不能延後讀取 |
| Single-consumer procedure、範例、schema、decision table | `.claude/skills/<skill>/references/*` | 只有一個 skill 會讀，或內容是該 skill 的 mode-specific flow |
| Multi-consumer framework contract、共用 schema、跨 skill decision table | `.claude/skills/references/*` | 兩個以上 skill 會讀，且語意不是單一 skill 私有流程 |
| Single-consumer deterministic helper | `.claude/skills/<skill>/scripts/*` | 只服務單一 skill，且不需要被 hook / release gate / 其他 skill 呼叫 |
| Multi-consumer deterministic helper、hook、validator、release helper | `scripts/*` | 需要可重跑、可測試，且會被多個 skill、hook 或 gate 呼叫 |
| 歷史決策、一次性討論、取捨脈絡 | DP / memory | 不應每次 skill 執行都進入 prompt |
| Company / project 專屬知識 | `{company}/polaris-config/**` | 不放進 shared skill；避免跨公司污染 |

## Resource Ownership Rules

用下列規則決定 private bundled resource 與 shared layer 的邊界：

| Signal | Action |
|--------|--------|
| Reference/script 只有一個 active consumer | 預設 rehome 到 owning skill folder，使用 skill-private resource |
| Reference/script 有兩個以上 active consumers | 預設留在 shared reference 或 shared script layer |
| Textual consumer count 是 1，但內容是 framework-wide contract | 留 shared，並在 audit 中標 `needs_manual_review` |
| Root `scripts/*` 被 hook、release gate、CI local、docs health 呼叫 | 即使只有一個 skill 也留 root script |
| Skill folder 內 script 被其他 skill 呼叫 | 標 owner mismatch，優先改成 shared script 或切出公共 helper |

Naming guidance：

- skill-private references 放在 `.claude/skills/<skill>/references/*`，由該 skill 的
  `SKILL.md` 直接說明何時讀取。
- skill-private scripts 放在 `.claude/skills/<skill>/scripts/*`，由該 skill 或該 skill
  的 private reference 呼叫。
- shared reference 必須維持 `.claude/skills/references/INDEX.md` entry，方便跨 skill
  discovery。
- shared script 應維持 root `scripts/*`，並有自測或 validator coverage。

不要為了「未來可能共用」提前抽象。先讓 single-consumer resource 跟 owner 放在一起；
等第二個真實 consumer 出現，再提升到 shared layer。

## Slimming Granularity

每次實作只處理一個 skill 的一個 mode 或一個 section。不要在同一個 task 同時重寫多個
skill，因為 reviewer 需要能清楚比對「原本行為」與「搬移後行為」是否等價。

建議流程：

1. 先跑 scanner，記錄 baseline。
2. 選一個 P0/P1 skill 的單一 mode 或長 section。
3. 將細節移到 reference 或 script，`SKILL.md` 只留下何時讀取與 fail-stop contract。
4. 跑該 skill 既有 deterministic gates；若沒有 gate，至少跑 language / contract / selftest。
5. 產出 before/after 摘要，說明行為沒有改變，只有 disclosure boundary 改變。

## Inline Context Exception

下列內容即使很長，也可以留在 `SKILL.md`：

- 不讀就可能做錯權限邊界的 mandatory rule。
- 入口解析需要立即使用的 decision table。
- 不可被延後載入的 safety rule，例如 forbidden shortcut、scope boundary、delivery authority。

若保留 inline，應在 slimming closeout 說明原因；不要只因為搬移麻煩就保留。

## Validation Expectations

Slimming task 至少要證明：

- `scripts/skill-progressive-disclosure-audit.sh` 可跑，並能產出 baseline 或 before/after。
- 新增或修改的 reference 通過 `validate-language-policy.sh`。
- 沒有把公司或專案專屬資訊寫入 shared skill/reference。
- 沒有修改 unrelated `SKILL.md` body。
- 若新增 script，必須有 selftest，並保持 read-only 或明確宣告寫入面。
