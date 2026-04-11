# 自適應 Codebase 探索模式

當 skill 需要掃描 codebase 理解現狀時，使用此模式。目的：避免大量原始碼塞滿主 agent 的 context window，同時根據實際範圍自動決定探索深度。

## 使用方式

主 agent 啟動 **1 個 Explore subagent**（`model: "sonnet"`），帶入完整的任務描述和專案路徑。Explore subagent 自行判斷範圍大小，決定直接探索或分裂成多個 sub-Explore。

> **Model 選擇**：Explore subagent 用 **Sonnet** — 搜尋 + 摘要不需要最強推理，Sonnet 的程式碼理解能力足以產出高品質摘要。分裂出的 sub-sub-Explore 也用 Sonnet。

## Handbook-First 探索協議

Explorer subagent 在做任何 codebase 掃描之前，必須先檢查 repo handbook：

### 流程

```
1. 檢查 {project_path}/.claude/rules/handbook/ 是否存在
   ├─ 存在 → 讀 index.md + 與任務相關的子文件
   │         用 handbook 作為起始心智模型
   │         只探索 handbook 沒覆蓋的 gap
   └─ 不存在 → 進入正常自適應探索流程
```

### Handbook 怎麼減少探索

| Handbook 已覆蓋 | Explorer 動作 |
|----------------|--------------|
| Tech stack、directory structure | 跳過基礎結構掃描，直接定位任務相關目錄 |
| Data flow、API integration | 跳過「追資料怎麼流」的 grep chain，直接讀相關檔案 |
| Component conventions | 不需要掃 10 個元件推導 pattern，直接套用 |
| Cross-repo dependencies | 知道資料源頭在哪個 repo，不在本 repo 裡瞎找 |

### Handbook 沒覆蓋的才探索

Handbook 是起點，不是真理。Explorer 應：
- **信任但驗證**：handbook 描述的架構可直接採用，但關鍵假設（「這個 API 回傳 X 格式」）要讀 code 確認
- **補足 gap**：任務涉及的區域如果 handbook 沒提到，正常探索
- **標記過時**：探索中發現 handbook 描述與實際不符，在回傳的 Handbook Observations 中標記

### 主 agent 的 prompt 模板

```
你是自適應 codebase 探索 agent。依照以下指引探索專案，回傳結構化摘要。

## 專案路徑
{project_path}

## 任務描述
{task_description — 需求摘要 / bug 描述 / 問題分析}

## 探索目標
{goal — 例如「找出與需求相關的所有檔案和影響範圍」「找出 bug 的可疑程式碼」}

## Handbook-First

探索前先檢查 {project_path}/.claude/rules/handbook/：
- 存在 → 讀 index.md + 與任務相關的子文件，作為起始 context。只探索 handbook 沒覆蓋的 gap
- 不存在 → 跳過，進入自適應探索

## 自適應規則

先用 Glob 快速掃描專案結構（頂層目錄 + 關鍵子目錄），評估與任務相關的檔案數量和分布：

### 小範圍（相關檔案 ≤ 10 個，集中在 1-2 個目錄）
直接探索，不需分裂。依序讀取相關檔案，產出摘要。

### 大範圍（相關檔案 > 10 個，或分散在 3+ 個目錄）
啟動 2-3 個平行 sub-Explore subagent，依**專案實際結構**切分範圍。

常見切分策略（依實際情況選擇最適合的）：

| 策略 | 適用情境 | 切分方式 |
|------|---------|---------|
| **按層切** | 全端功能（有 UI + 邏輯 + API） | UI 層 / 邏輯層 / API+型別+測試 |
| **按功能切** | 多個獨立功能模組 | 功能 A / 功能 B / 共用模組 |
| **按專案切** | 跨專案改動（B2C + DS） | 專案 A / 專案 B |

每個 sub-Explore 的 prompt：
```
你是 codebase 探索 agent。在以下範圍搜尋與任務相關的程式碼，回傳結論摘要。

## 專案路徑
{project_path}

## 任務描述
{task_description}

## 你負責的範圍
{該 sub-Explore 的具體範圍和目錄}

## 回傳格式
{使用下方的標準回傳格式}

只做 research（Read、Grep、Glob），不要編輯任何檔案。
```

### 判斷完成後，回傳結構化摘要

## 標準回傳格式

無論是直接探索或彙整 sub-Explore 結果，最終回傳格式統一：

```markdown
## 探索摘要

### 相關檔案清單
| 檔案路徑 | 職責（1-2 句） | 與任務的關係 |
|----------|---------------|-------------|
| ... | ... | 直接修改 / 間接影響 / 參考 |

### 現有實作模式
- 資料流：...
- 命名慣例：...
- 元件/模組結構：...

### 關鍵程式碼片段
（僅與任務直接相關的 10-20 行，不要整個檔案）

### 影響範圍
- 直接影響：...
- 間接影響（改 A 連帶影響 B）：...

### Handbook Observations
- **Used**: handbook 哪些 section 幫助跳過了探索（或「無 handbook」）
- **Gaps**: 任務涉及但 handbook 沒覆蓋的知識（空 = handbook 已足夠）
- **Stale**: 發現 handbook 描述與實際不符之處（空 = 無過時）

### 探索方式
- [ ] 直接探索（小範圍）
- [ ] 分裂探索：N 個 sub-Explore（列出各自範圍）
```

只做 research（Read、Grep、Glob），不要編輯任何檔案。
```

## 主 agent 收到結果後

1. **不要再額外讀取原始碼** — subagent 的摘要已包含足夠資訊
2. **資訊不足時**：針對特定面向追加 1 個 Explore subagent 補充，不要重新全面掃描
3. **處理 Handbook Observations**（見下方 § Handbook 回寫）
4. **直接使用摘要**進入 skill 的下一步驟

## Handbook 回寫（Explorer → Handbook Ingest）

Explorer 回傳的 `Handbook Observations` 是 handbook 自動成長的主要管道。Strategist 收到後依以下規則處理：

### 處理 Gaps

Explorer 報告的 Gaps = handbook 缺少但對任務有幫助的知識。

| 條件 | 動作 |
|------|------|
| Gap 是 **repo 架構/慣例**（data flow, module structure, naming） | 寫入 repo handbook 對應 section 或新建子文件 |
| Gap 是 **跨 repo 知識**（API dependency, team convention） | 寫入 company handbook（`rules/{company}/handbook/`） |
| Gap 是 **一次性資訊**（只跟這個任務有關，不會再用到） | 不寫入，skip |

**寫入格式**：在 handbook section 末尾追加，標記來源：

```markdown
<!-- ingest: explorer, {date}, confidence: generated -->
{新增的知識}
```

`confidence: generated` 表示這是 AI 探索推導的，尚未被 user 驗證。下次有人讀到並確認後，可移除 comment 或改為 `validated`。

### 處理 Stale

Explorer 報告的 Stale = handbook 描述與實際程式碼不符。

| 條件 | 動作 |
|------|------|
| 差異明確（版本號錯、檔案路徑改了、dependency 換了） | 直接修正 handbook，不需確認 |
| 差異涉及架構判斷（「這個 pattern 是不是已經廢棄？」） | 標記 `<!-- stale-hint: {description}, {date} -->`，不自動修改。下次 user 糾正或 lazy lint 時處理 |

### Conflict Resolution（優先級）

當多個來源對同一 handbook section 有不同說法：

```
User correction > PR review lesson > Explorer 回寫
```

具體規則：
1. **User correction 永遠覆蓋** — 不問，直接更新
2. **PR review lesson vs Explorer** — lesson 來自 code review 實踐（validated），Explorer 來自靜態分析（generated）。Lesson 優先
3. **Explorer vs Explorer**（不同 session 的探索結果矛盾） — 保留較新的，標記衝突讓 user 在下次相關任務時決定

### 不寫入的情況

- Explorer 回報「無 handbook」+ 有 Gaps → **不要在探索後順便生成 handbook**。Handbook 生成有自己的 protocol（`repo-handbook.md` Step 1-3），需要 user Q&A
- Gaps 全是任務特定的一次性資訊 → skip
- 當前 task 已在趕時間（user 明確催促） → 記到 todo 稍後補

## 各 skill 的探索目標範例

| Skill | 探索目標 |
|-------|---------|
| sasd-review | 找出與需求相關的所有檔案，分析異動範圍和實作模式 |
| jira-estimation | 找出與需求相關的檔案，評估改動複雜度和影響範圍 |
| refinement Phase 0 | 分析指定模組的引用關係、測試覆蓋、程式碼品質 |
| refinement Phase 1 | 找出與 Epic 需求相關的現有實作，產出 scope 和 edge cases 建議 |
| epic-breakdown | 找出與 Epic 相關的現有程式碼結構，識別可複用模組和依賴順序 |
| systematic-debugging | 從 bug 症狀追蹤相關程式碼，找出可疑的根因位置 |
