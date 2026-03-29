# Skill Routing 決策樹

收到使用者請求時，依序比對以下表格決定觸發哪個 skill。

| 輸入特徵 | 觸發 Skill | 備註 |
|---------|-----------|------|
| 「init / initialize / setup workspace / 初始化 / 設定 workspace / 填 config」 | `/init` | 互動式 workspace-config.yaml 生成精靈，clone Xuanji 後第一步 |
| JIRA ticket key（一個或多個）+「做 / 我要做 / work on / 接這張 / take / 估點 / estimate / 幫我估」 | `/work-on` | 智慧路由：自動判斷估點/拆單/建 branch/開發。估點已整合，不需單獨呼叫 |
| Slack 連結含 PR URL → 要求 review | `/review-pr` | 含 re-review：先查上輪 comments |
| GitHub PR URL + 「fix review / 修正 review」 | `/fix-pr-review` | 修自己 PR 上的 review comments |
| JIRA ticket key + 「修正 / fix / 修 bug」 | `/fix-bug` | 端到端 bug 修正流程 |
| JIRA Epic key + 「拆單 / breakdown」 | `/epic-breakdown` | Epic 拆解子單（手動指定步驟） |
| JIRA ticket key + 「開始開發 / start」 | `/start-dev` | 只轉 IN DEVELOPMENT（手動指定步驟） |
| 「發 PR / create PR / open PR」 | `/pr-convention` | 依 YourOrg PR 規範 |
| 「確認 PR 狀態 / PR approve 狀況」 | `/check-pr-approvals` | rebase + 檢查 approve 數量 + reviewer 明細 |
| 「review 所有 PR / 掃 need review / review inbox」 | `/review-inbox` | 批次 review 別人的 PR，發 Slack |
| 「SA/SD / 實作評估」 | `/sasd-review` | 產出技術設計文件 |
| 「standup / 站立會議 / YDY / 寫 standup」 | `/standup` | 收集 git/JIRA/Calendar 產出 YDY/TDT/BOS |
| 「sprint planning / 排 sprint / 下個 sprint」 | `/sprint-planning` | 拉 JIRA tickets、算 capacity、排優先順序 |
| 「TDD / test driven / 先寫測試 / 紅綠燈」 | `/tdd` | Red-Green-Refactor 循環，可被 work-on/fix-bug invoke |
| 「驗證 / verify / 確認改好了 / 驗收」 | `/verify-completion` | 品質檢查通過後的行為驗證，PR 前最後一關 |
| 「refinement / brainstorm / 討論需求 / 方案討論」 | `/refinement` | 結構化需求討論，產出 Decision Record 後再估點/拆單 |
| 「scope challenge / 挑戰需求 / 需求質疑」 | `/scope-challenge` | 估點前挑戰 scope 合理性（advisory） |
| 「auto improve / 自動改善 / 掃 code / 程式碼健檢」 | `/auto-improve` | 掃描 repo 品質問題，開 PR 供 review |
| 「整理 review lessons / graduate lessons / review lessons 畢業」 | `/review-lessons-graduation` | 整併 review-lessons 到主 rules（自動 invoke 或手動） |
| 外部 URL / 文章 / repo +「學習 / learn / 研究一下 / 借鑑 / 看看這個」 | `/learning` | 外部學習模式 |
| PR + 「學習 / learn / 研究 review」或「最近的 PR / merge 的 PR」 | `/learning` | PR 學習模式 |
| 「每日學習 / 今天有什麼可以學的 / 看看今天的推薦 / daily learning」 | `/learning` | Queue 模式 |

## 常見誤判

- 「估 PROJ-123」/ 「幫我估 PROJ-123」→ `/work-on`（估點已整合進 work-on，**不要**觸發 `/jira-estimation`）
- 「做 PROJ-123」→ `/work-on`（work-on 會自動判斷是否需要估點）
- 「做 PROJ-123 PROJ-123 PROJ-123」→ `/work-on`（批次模式：Phase 1 平行分析 → 確認 → Phase 2 平行實作）
- 「修 PROJ-123 PROJ-123 PROJ-123」→ `/work-on`（多張 bug 也走批次模式，不是逐張呼叫 fix-bug）
- 「幫我修正」+ JIRA key → `/fix-bug`（不是 `/fix-pr-review`）
- 「幫我修正」+ PR URL → `/fix-pr-review`（不是 `/fix-bug`）
- 「review 所有 PR」/ 「幫我看所有要 review 的」→ `/review-inbox`（不是 `/review-pr`，後者是單一 PR）
- 自己的 PR 不要 self-review — review 只用在別人的 PR

## Skill Chain 慣例

Skill 之間可以用自然語言 invoke 下一個 skill。常見 chain：
- **實作鏈**：`refinement` → `epic-breakdown` / `jira-estimation` → `work-on` → `tdd`（選用）→ `dev-quality-check` → `verify-completion` → `git-pr-workflow`
- **Bug 修正鏈**：`fix-bug` → `tdd`（選用）→ `dev-quality-check` → `verify-completion` → PR
- **Scrum 鏈**：`refinement` → `epic-breakdown` → `sprint-planning`

每個 skill 可獨立執行，chain 不是強制的，但建議在複雜任務中遵循。
