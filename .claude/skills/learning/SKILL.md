---
name: learning
description: |
  "Use when the user wants to learn from external resources (URLs, repos, articles), extract patterns from merged PRs, process a learning queue, configure the daily learning scanner, or backfill review lessons. Trigger: '學習', 'learn', '研究', 'deep dive', '學習 PR', '每日學習', 'daily learning', '設定學習', '批次學習', '掃歷史 PR', or when user shares a URL to analyze."

  要從外部資源學東西：一則 URL、一個 repo、一篇文章，或從已 merge 的 PR 萃取模式。
  例如「學習」「研究」「deep dive」「掃歷史 PR」，或使用者直接丟一個連結要人看。

  不用於：查這個 workspace 自己的既有知識（直接讀就好）。
metadata:
  author: Polaris
  version: 3.1.0
scope: standalone
---

# learning
<!-- PROSE-EXTERNAL-PATHS: learning-archive.md — 跑起來才長出來的去重紀錄，住在 learnings repo -->

`learning` 把外部資料、文章 queue、PR review lessons、daily scanner setup
轉成可落地的 workspace knowledge。`SKILL.md` 只保留 mode routing、邊界與
必讀 reference；mode 細節延後載入。

## Mandatory Contracts

- 任何 sub-agent dispatch 前，先說出它要回傳什麼（Completion Envelope），並要求它把
  完整分析寫進一個檔案（`/tmp/polaris-agent-{timestamp}.md`），主 session 只收摘要。
  envelope 的形狀由派工的那一份 flow 自己定義——PR / Batch 在
  `learning-pr-batch-flow.md`，queue 在 `learning-queue-flow.md`。
- 任何 Slack / JIRA / GitHub / Confluence 或其他 external write 前，遵守
  `scripts/validate-language-policy.sh` 或 external write gate。
- 任何 specs Markdown 產出或匯入，遵守 `starlight-authoring-contract.md`。
- Learning 可以 seed / import research evidence，但不得自動 invoke `refinement`，
  也不得替任何已凍結的斷言改寫成功的定義。
- 寫入 handbook、backlog、learnings、README acknowledgement、RemoteTrigger 或
  specs artifact 後，最後必跑 Post-Task Reflection。

## Mode Detection

依使用者輸入選 mode；只讀該 mode 的 reference。

| Signal | Mode | Reference |
|---|---|---|
| PR number、PR URL、`PR` + `學習/learn`、某人的 PR、時間範圍 + PR | PR mode | `learning-pr-batch-flow.md` |
| `掃 review`、`batch learn`、`批次學習`、`掃歷史 PR`、`補齊 review lessons` | Batch mode | `learning-pr-batch-flow.md` |
| 外部 URL、GitHub repo、文章、local research file、使用者貼的研究題材 | External mode | `learning-external-flow.md` |
| `每日學習`、`今天有什麼可以學的`、`有新文章嗎`、`讀文章`、`daily learning`、`queue`、bare `學習` without URL/PR context | Queue mode | `learning-queue-flow.md` |
| `設定學習`、`learning setup`、`更新學習主題`、`scanner 設定`、`learning scanner` | Setup mode | `learning-setup-flow.md` |
| 模糊輸入 | Ask one concise clarification | N/A |

首次使用但 daily scanner 尚未設定時，提示使用者可用 `設定學習` 或
`learning setup` 啟用每日文章推薦。

## External Mode Contract

讀 `learning-external-flow.md`。外部學習必須先判斷 target：

- `framework`：Polaris / 框架 / AI agent pattern / skill / rule / mechanism。
- `project:{name}`：使用者指定產品 repo 或目前工作脈絡可明確推導。
- ambiguous：詢問「這個學習要用在 Polaris 框架，還是特定產品 repo？」

GitHub repo 若包含 `.claude/skills/`、`SKILL.md` 或 `skills/`，探索前先跑
`.claude/skills/learning/scripts/skill-sanitizer.py` pre-scan；HIGH/CRITICAL 風險需讓使用者確認是否繼續。

External mode 的 execute 階段只有在使用者確認後進行，落點三選一或混選：

- Route A：把研究結果交給 `refinement`，由人決定要不要立案。
- Route B：寫入 backlog。
- Route C：只寫 `polaris-learnings`。

Quick path 不可走 Route A；需 Standard / Deep 才能 seed。

### Route A：research 怎麼落地

研究產出的是**證據與判斷**，不是成功的定義。兩者的分界就是 Route A 的全部規則：

- **source 已存在**：把 research 寫進該 source 的活區（`issues/{source}/index.md` 活區段落），
  或放在旁邊的檔案並在活區指過去。**不要碰凍結塊**——那是已經簽過的成功定義，改它要回 `refinement`。
- **source 不存在**：不要自己建。研究到一個值得立案的題目時，把題目與依據講出來，
  由人在 `refinement` 決定要不要簽。learning 產出的是 `refinement` 的輸入，不是它的替代品。

Why：research 是「我讀到了什麼」，斷言是「怎樣算成功」。讓研究直接寫成功的定義，
等於讓收集證據的人自己決定及格線。

## Queue Mode Contract

讀 `learning-queue-flow.md`。Queue mode 從 Slack daily learning queue 讀最新
message，先給 condensed summary，再由使用者決定要 detailed recommendation、
全部歸檔或略過。已處理文章一律更新 `learning-archive.md` 去重紀錄。

## Setup Mode Contract

讀 `learning-setup-flow.md`。Setup mode 設定、更新、測試或停用 daily learning
scanner。先從 workspace config 偵測 Slack channel、tech stack、repos、
custom topics、schedule；只詢問缺失或模糊的值。RemoteTrigger prompt 必須包含完整
search queries、repo tagging rules、Slack channel ID、`learning-archive.md`
dedup，以及 Slack 發送前的 language gate。Setup 過程不得 commit 或 push。

## PR Mode Contract

讀 `learning-pr-batch-flow.md`。PR mode 只處理已 merged 且有 review comments
的 PR；open PR 需先提示風險。每次最多 10 個 PR。萃取、dedup、寫入 handbook
時使用 `review-lesson-extraction.md`。

## Batch Mode Contract

讀 `learning-pr-batch-flow.md`。Batch mode 掃 merged PR history，先用 handbook
既有 `Source:` 做 Layer 1 dedup，再對剩餘 PR 篩選 qualifying review comments。
每 repo 預設 3 個月、最多 30 個 PR；sub-agent 平行上限 5。

## Post-Task Reflection (required)

> Non-optional. Execute before reporting task completion after any write.


<!-- PROSE-EXTERNAL-PATHS: docs-manager/ — 動手對象：那是 specs 站台自己的 repo，這支 skill 往它寫東西、讀它的結構，不是我們抄一份放著的知識 -->
