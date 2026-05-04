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

| 內容類型 | 放置位置 | 判斷方式 |
|----------|----------|----------|
| Routing、authority boundary、mandatory gate、fail-stop 條件 | `SKILL.md` | agent 一進 skill 就必須知道，不能延後讀取 |
| Mode-specific procedure、範例、schema、decision table | `.claude/skills/references/*.md` | 只有特定分支需要，且可被多個 skill 重用 |
| 可 deterministic 化的掃描、驗證、格式化、查詢 | `scripts/*` | 需要可重跑、可測試、可被 hook 或 gate 呼叫 |
| 歷史決策、一次性討論、取捨脈絡 | DP / memory | 不應每次 skill 執行都進入 prompt |
| Company / project 專屬知識 | `{company}/polaris-config/**` | 不放進 shared skill；避免跨公司污染 |

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
