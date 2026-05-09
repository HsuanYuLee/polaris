# Multi-Company Isolation Strategy

## How Rules Load

Claude Code 會把 `.claude/rules/` 之下的 **所有** `.md` 檔遞迴載入到每次對話中。
它沒有原生的 scope 隔離機制；因此就算現在在處理 `bigcorp` 的 ticket，放在
`.claude/rules/acme/` 的檔案也一樣會被載入。

Polaris works around this with **convention-based isolation**.

## Directory Convention

```
.claude/rules/
├── *.md                    # L1 — Universal rules (apply to ALL companies)
├── {company-a}/            # L2 — Company A rules
└── {company-b}/            # L2 — Company B rules

_template/rule-examples/    # Reference templates (NOT under rules/ — never auto-loaded)
```

## Defensive Rule Writing

Since all rules load globally, every company-specific rule file **must** include a scope header:

```markdown
# Rule Title

> **Scope: {company-name}** — applies only when working on {company-name} tickets or projects.

(rule content)
```

Strategist 會依這個 header 判斷該規則是否適用於目前 context。沒有 scope header 的規則，
會被視為 universal rule。

## Rule Examples (Reference Templates)

Rule examples 放在 `_template/rule-examples/`，刻意 **不在** `.claude/rules/` 底下，因此不會自動
載入對話。它們只用來示範 L2 company rules 的結構與內容模式。

- 當 `/init` 建立新公司時，會把對應模板複製到 `.claude/rules/{company}/`，並填入公司專屬值與 scope header
- To browse examples manually, read files in `_template/rule-examples/`

## Context Cost

Every rule file consumes context window tokens. With multiple companies:

- Keep rule files concise — one concern per file
- 盡量把相關規則合併在同一個檔案，而不是拆成過多小檔
- If a company has > 10 rule files, consider consolidating

## Routing Disambiguation

當 JIRA ticket key 有歧義（可能屬於多間公司）時：

1. Prefer `bash scripts/resolve-company-context.sh --ticket PROJ-123 --format json` as the shared routing authority
2. If the resolver returns `status=ok`, apply that company's L2 rules
3. 若 resolver 回傳 `project_prefix_ambiguous`，代表自動 routing 無法辨識公司；開始工作前必須先用 `/use-company` 明確設定 context
4. 若 resolver 回傳 `project_prefix_no_match`，則回退到 `/use-company`，或直接詢問使用者要用哪個 company context
5. When no ticket exists, prefer `bash scripts/resolve-company-context.sh --format json` for `default_company` / single-company fallback
6. 不得在 rules 或 skills 內再手工實作第二套 YAML matching flow；shared resolver 的輸出才是權威

## Diagnostic Tool

可執行 `/validate-isolation` 掃描 isolation 違規：缺 scope header、memory 未標記、跨公司衝突等。
建議在新增公司後或 version release 前執行一次。

## Known Limitations

- **No conditional loading**: all rule files load regardless of active company context. Defensive headers mitigate but don't eliminate wasted context tokens
- **Cross-contamination risk**：若某條規則漏掉 scope header，Strategist 可能把它錯用到其他公司。
  scope header convention 是主要的防線
