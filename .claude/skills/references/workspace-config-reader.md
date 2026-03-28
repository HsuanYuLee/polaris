# Workspace Config Reader

Skills 和 rules 透過此機制讀取設定值，避免 hardcode 公司/團隊特定的值。

## 兩層 Config 架構

```
~/work/workspace-config.yaml          ← Root config（公司路由）
~/work/{company}/workspace-config.yaml ← Company config（完整設定）
```

### Root Config（固定位置）

```yaml
# ~/work/workspace-config.yaml
companies:
  - name: your-company
    base_dir: "~/work/company"
  - name: company-b
    base_dir: "~/work/company-b"
```

### Company Config（每間公司各一份）

```yaml
# ~/work/company/workspace-config.yaml
github:
  org: "your-org"
jira:
  instance: "your-domain.atlassian.net"
  ...
```

## 解析流程

```
1. Read ~/work/workspace-config.yaml → 取得 companies 列表
2. 解析目標公司：
   - 只有一間 → 直接用
   - 多間 → 依以下優先順序比對：
     a. 當前工作目錄是否在某 base_dir 下
     b. JIRA ticket key 是否匹配某公司的 jira.projects[].key
     c. 都 match 不到 → 問使用者
3. Read {base_dir}/workspace-config.yaml → 取得完整公司設定
```

### 範例

```
# 只有一間公司 → 直接取得完整設定
Read ~/work/workspace-config.yaml → companies[0].base_dir → "~/work/company"
Read ~/work/company/workspace-config.yaml → jira.instance → "your-domain.atlassian.net"

# 取得 GitHub org
Read ~/work/company/workspace-config.yaml → github.org → "your-org"

# 取得專案完整路徑
base_dir + projects[tags contains "b2c"].name → "~/work/company/your-app"

# 取得 Slack PR channel
Read ~/work/company/workspace-config.yaml → slack.channels.pr_review → "YOUR_CHANNEL_ID"
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
### 前置：讀取 workspace config
讀取 workspace config（參考 `references/workspace-config-reader.md`）。
取得本步驟需要的值：`jira.instance`、`github.org`、`slack.channels.pr_review` 等。
```

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
