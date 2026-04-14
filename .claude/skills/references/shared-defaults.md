# 跨 Skill 共用設定

多個 skill 共用的設定值集中在此管理，避免散落各處不一致。

> **Config 必須**：所有設定值從公司 config 讀取（參考 `references/workspace-config-reader.md`）。
> Config 不存在時 skill 應提示使用者執行 `/init` 建立，不使用硬編碼 fallback。

## 設定值對照表

| 用途 | Config 路徑 | 引用 skill |
|------|------------|-----------|
| PR Slack channel | `slack.channels.pr_review` | review-inbox, check-pr-approvals, review-pr |
| AI notifications channel | `slack.channels.ai_notifications` | check-pr-approvals, fix-pr-review |
| Worklog report channel | `slack.channels.worklog_report` | worklog-report |
| Approval threshold | `scrum.approval_threshold` | check-pr-approvals, review-inbox |
| GitHub org | `github.org` | 全部 |
| Need review label | `scrum.need_review_label` | check-pr-approvals, review-inbox |
| Bot exclusion list | `scrum.excluded_bots` | check-pr-approvals, fix-pr-review |
| JIRA instance | `jira.instance` | 全部 JIRA 相關 skill |
| Confluence space | `confluence.space` | standup, sprint-planning, sasd-review |
| Dev host | `infra.dev_host` | quality-check-flow, engineer-delivery-flow |
| Dev port | `infra.dev_port` | quality-check-flow, engineer-delivery-flow |
| Kibana hosts | `kibana.host`, `kibana.sit_host`, `kibana.stage_host` | kibana-logs |
| Kibana index pattern | `kibana.index_pattern` | kibana-logs |

## 動態值（非常數）

以下值不應寫死，每次執行時動態取得：

| 值 | 取得方式 | 說明 |
|----|----------|------|
| GitHub username | `gh api user --jq '.login'` | 當前使用者的 GitHub 帳號，用於排除自己的 PR、搜尋自己的 PR 等 |

各 skill workflow 開頭應執行：

```bash
MY_USER=$(gh api user --jq '.login')
```

再將 `$MY_USER` 傳入 scripts 的 `--author` / `--exclude-author` 參數。
