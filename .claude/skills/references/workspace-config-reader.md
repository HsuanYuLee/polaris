# Workspace Config Reader

Skills 和 rules 透過此機制讀取設定值，避免 hardcode 公司/團隊特定的值。

## Authority Boundary

這份 reference 的責任是 **在 company 已 resolve 之後**，讀取 root/company config 取得欄位值。

對多數 reporting / review / planning skill 而言，這份 reference 也只應扮演
`soft_read_consumer` 的 config read layer：它可以提供 Slack channel、Confluence space、
approval threshold、GitHub org、user identity 等 defaults，但不得反向宣告 workflow stage
authority、release authority、或 company routing authority。

它**不是**新的 company routing authority。凡是涉及：

- 解析 active company
- `default_company` fallback
- JIRA ticket / project prefix routing
- partial company name matching
- routing ambiguity / invalid company config fail-stop

都應優先交給：

```bash
bash scripts/resolve-company-context.sh
```

skill / rule / reference 不應再各自手寫第二套 company matching 流程。

## 兩層 Config 架構

```
~/work/workspace-config.yaml          ← Root config（公司路由）
~/work/{company}/workspace-config.yaml ← Company config（完整設定）
```

### Root Config（固定位置）

> `workspace-config.yaml` is gitignored. New users copy from `workspace-config.yaml.example`.

```yaml
# ~/work/workspace-config.yaml
companies:
  - name: my-company
    base_dir: "~/work/my-company"
  - name: company-b
    base_dir: "~/work/company-b"
```

### Company Config（每間公司各一份）

```yaml
# ~/work/{company}/workspace-config.yaml
github:
  org: "acme-org"
jira:
  instance: "acme.atlassian.net"
  ...
```

## 解析流程

```
1. 若尚未 resolve company → 先呼叫 `scripts/resolve-company-context.sh`
2. 取得 resolver 回傳的 `company_name` / `base_dir` / `config_path`
3. Read {base_dir}/workspace-config.yaml → 取得完整公司設定
```

### 範例

```
# 先 resolve company，再讀完整設定
bash scripts/resolve-company-context.sh --ticket ACME-123 --format json
→ company_name=acme
→ base_dir=~/work/acme

Read ~/work/{company}/workspace-config.yaml → jira.instance → "acme.atlassian.net"

# Get GitHub org
Read ~/work/{company}/workspace-config.yaml → github.org → "acme-org"

# Get full project path
base_dir + projects[tags contains "web"].name → "~/work/{company}/my-web-app"

# Get Slack PR channel
Read ~/work/{company}/workspace-config.yaml → slack.channels.pr_review → "C0XXXXXXXXX"
```

## Fallback Chain

```
company config → shared-defaults.md → inline hardcoded 值
```

- **company config 存在**：以 config 為準
- **company config 不存在**：讀 `shared-defaults.md`（向後相容）
- **shared-defaults.md 也找不到**：使用 skill 內的 inline 預設值（最後防線）
- **root config 不存在**：提示使用者執行 `/init` 建立

## Skill 整合方式

在 SKILL.md 的流程步驟開頭加入：

```markdown
### 前置：resolve company + 讀取 workspace config
若 company context 尚未明確，先呼叫 `scripts/resolve-company-context.sh`。
company resolve 後，再依 `references/workspace-config-reader.md` 讀取 config 欄位。
取得本步驟需要的值：`jira.instance`、`github.org`、`slack.channels.pr_review` 等。
```

## 三層繼承（defaults → company → project）

Root config 可包含 `defaults` block，定義框架層預設值。Company config 的欄位如果未設定，向上繼承 root defaults。

```
root: defaults.visual_regression.threshold → 0.02
company: projects[].visual_regression.threshold → (未設定) → 繼承 0.02
company: projects[].visual_regression.threshold → 0.01 → 覆寫為 0.01
```

Skill runtime 負責繼承邏輯：讀到空值就往上層找。

Root config 也包含 `dependencies` block，追蹤框架推薦 lib 的使用者同意狀態。
詳見 `references/dependency-consent.md`。

## Config 欄位索引

| 需求 | Config 路徑 | Fallback 來源 |
|------|------------|--------------|
| 公司列表 | `root: companies[]` | 無（必須存在） |
| 公司根目錄 | `root: companies[].base_dir` | 無（必須存在） |
| GitHub org | `company: github.org` | shared-defaults.md |
| JIRA instance | `company: jira.instance` | 各 skill hardcoded |
| JIRA project keys | `company: jira.projects[].key` | 各 skill hardcoded |
| JIRA 需求來源欄位 | `company: jira.custom_fields.requirement_source` | jira-status-flow.md |
| Confluence space | `company: confluence.space` | 各 skill hardcoded |
| Confluence SA/SD folder | `company: confluence.folders.sasd` | sasd-confluence.md |
| Slack PR channel | `company: slack.channels.pr_review` | shared-defaults.md |
| Slack AI notifications | `company: slack.channels.ai_notifications` | memory |
| Kibana host | `company: kibana.host` | kibana-logs skill |
| 專案對應（by tag） | `company: projects[tags]` | project-mapping.md |
| 專案對應（by keyword） | `company: projects[keywords]` | CLAUDE.md mapping 表 |
| Approval threshold | `company: scrum.approval_threshold` | shared-defaults.md |
| Need review label | `company: scrum.need_review_label` | shared-defaults.md |
| Ansible repo | `company: infra.ansible_repo` | env-var-workflow.md |
| VR 預設 fixture 工具 | `root: defaults.visual_regression.fixtures_tool` | `"mockoon"` |
| VR 預設瀏覽器 | `root: defaults.visual_regression.browsers` | `["chromium"]` |
| VR 預設 threshold | `root: defaults.visual_regression.threshold` | `0.02` |
| VR 預設整頁截圖 | `root: defaults.visual_regression.full_page` | `true` |
| VR 預設 timeouts | `root: defaults.visual_regression.timeouts.*` | 見 visual-regression-config.md |
| E2E 預設 runner | `root: defaults.e2e.runner` | `"playwright"` |
| 依賴同意狀態 | `root: dependencies.{lib}.status` | `"pending"` |
| 依賴支撐功能 | `root: dependencies.{lib}.features` | dependency-consent.md |
| 專案 Dev 環境 | `company: projects[].dev_environment.*` | /init Step 9a |
| 專案依賴安裝指令 | `company: projects[].dev_environment.install_command` | `scripts/env/install-project-deps.sh` detector |
| 專案 Dev 啟動指令 | `company: projects[].dev_environment.start_command` | — |
| 專案 Test 指令 | `company: projects[].dev_environment.test_command` | breakdown 產 task.md `## Test Command` 的來源 |
| 專案 Dev base URL | `company: projects[].dev_environment.base_url` | — |
| 專案 PR title 規則 | `company: projects[].delivery.pr_title.developer` | `"[{TICKET}] {summary}"` |
| 專案 PR review label 規則 | `company: projects[].delivery.pr_review_label.policy` + `.labels[]` | `company: scrum.need_review_label`（optional 相容） |
| VR domain 設定 | `company: visual_regression.domains[]` | visual-regression-config.md |
| VR domain server | `company: visual_regression.domains[].server.*` | visual-regression-config.md |
| VR domain pages | `company: visual_regression.domains[].pages[]` | visual-regression-config.md |
| Git base branch | `company: git.base_branch` | `"develop"` |
| Git branch pattern (Epic) | `company: git.branch_patterns.epic` | `"feat/{TICKET}-{slug}"` |
| Git branch pattern (Task) | `company: git.branch_patterns.task` | `"task/{TICKET}-{slug}"` |
| 估點量表 | `company: estimation.scale` | `[1, 2, 3, 5, 8, 13]` |
| 估點 velocity | `company: estimation.velocity_per_day` | `2.5` |
| 估點標準詳細定義 | `company: estimation.scale_reference` | estimation-scale.md |
