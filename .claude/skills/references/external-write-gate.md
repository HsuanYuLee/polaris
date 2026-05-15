# External Write Gate

外部寫入前，skill 應先把最終文字 materialize 成 markdown 或 plain text，再用
`scripts/polaris-external-write-gate.sh` 執行 deterministic preflight。

## Scope

適用 surface：

- JIRA comment / description / summary
- Slack message
- Confluence page body
- GitHub review / inline comment / PR body
- Release prose
- Local artifact handoff summary

不適用：

- 真的呼叫 MCP 或 GitHub CLI。helper 不做外部 side effect。
- Commit message。commit message 使用 commit language gate。
- specs pipeline artifact schema。`refinement.json`、`task.md` 等仍由既有 validators 負責。

## Command

```bash
bash scripts/polaris-external-write-gate.sh \
  --surface jira-comment \
  --body-file /tmp/polaris-jira-comment.md
```

Specs markdown 需要 Starlight authoring check 時：

```bash
bash scripts/polaris-external-write-gate.sh \
  --surface artifact \
  --body-file docs-manager/src/content/docs/specs/design-plans/DP-NNN-topic/refinement.md \
  --starlight
```

## Exit Codes

| Exit | Meaning | Caller action |
|------|---------|---------------|
| 0 | Gate pass | 可執行外部寫入 |
| 1 | Blocking policy fail | 修正文案後重跑，不可外部寫入 |
| 2 | Usage / missing file / unsupported surface | 修 caller flow 或參數 |

## Caller Responsibility

- Caller 負責產生 body file，並在呼叫前決定它是 durable artifact 還是 temporary body file。
- Durable body file 必須放在 owning source container，例如：
  - `{source_container}/jira-comments/YYYYMMDD-{slug}.md`
  - `{source_container}/artifacts/external-writes/YYYYMMDD-{slug}.md`
  - `{source_container}/artifacts/research/YYYY-MM-DD-{slug}.md`
- Temporary body file 可放在 `/tmp/polaris-*` 或 shared runtime cache
  `.polaris/runtime/external-writes/`，但 gate pass / write 完成後必須刪除或移入 owning
  source container。
- `.codex/external-writes/` 與 `.codex/tmp/` 是 forbidden old / scratch residue；producer 不得
  寫入、讀取或把它們當作 fallback。
- Caller 負責在 gate pass 後執行 MCP / CLI 外部寫入。
- Caller 必須在 final summary 或 handoff 中能指出 body file 與 gate command。
- 任何 emergency bypass 必須由 producing skill 明文說明，不可 silent skip。
