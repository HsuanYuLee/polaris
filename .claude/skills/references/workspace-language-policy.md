# Workspace Language Policy

本 reference 是 workspace language policy 的 skill 共用入口。會產出 downstream-facing
文字的 skill 必須引用本檔，避免各 skill 自行複製不同版本的 gate 規則。

## 1. 適用輸出

凡是會交給人讀、交給下游 skill 讀、或寫到外部系統的自然語言文字，都需要先經過
language gate。

## 1.1 Authoring default

Workspace `language` 是預設 authoring language，不只是送出前的 validation language。
Skill、runtime adapter、外部寫入 producer 在產生 user-facing / downstream-facing prose 時，
必須直接用解析出的 workspace language 起稿；不可把英文第一稿當成正常流程，最後才在送出前
翻譯成 workspace language。

Language gate 是 fail-stop validation，不是翻譯器。若 gate 發現英文自然語言違反 zh-TW
policy，正確處理是回到 producer/template/prompt 修正原始產出語言，再重跑 gate。

例外仍依本檔 § 5：source code、identifier、CLI、log/error 原文、PR template heading、
bilingual source docs 等可以保留原文；skill 自己新增的說明 prose 仍要依 workspace language
撰寫。

| Surface | 範例 | Gate |
|---------|------|------|
| Local artifacts | `refinement.md`、`plan.md`、`task.md`、`V*.md`、escalation sidecar、handoff package、verification report | `--blocking --mode artifact` |
| GitHub PR | title、body、comments、review body、inline replies | wrapper/hook 可攔截時用 wrapper/hook；skill 送出前仍要先 gate 最終文字 |
| JIRA | issue summary、description、comment、RCA、decision audit trail、驗收結果 | MCP call 前寫暫存 markdown 並 gate |
| Slack | review ping、standup、intake summary、daily learning digest | `slack_send_message` 前寫暫存 markdown 並 gate |
| Confluence | SA/SD page、sprint page、release page、report | create/update 前寫暫存 markdown 並 gate |
| Git commit | commit subject/body 的自然語言部分 | 使用 commit language gate；規則見 § 4 |
| Release prose | changelog prose、GitHub release body、changeset description | producer 或 wrapper 送出前 gate |

## 2. 標準 temp artifact 流程

外部寫入前，先把最終文字落成暫存 markdown，再執行共用 validator：

```bash
bash scripts/validate-language-policy.sh \
  --blocking \
  --mode artifact \
  <tmp-output.md>
```

若該輸出仍在 rollout 期，skill 可以明文宣告 `--advisory`，但使用 skill 自己撰寫的主敘述仍
必須依 policy 語言。advisory 只用於必要引用、HTTP transcript、error message、GitHub
suggestion block 等 false positive 風險尚未收斂的 surface。

## 3. 語言來源

預設語言解析順序：

1. 呼叫端明確提供的 `--language`。
2. 從目前 workspace 往上尋找第一個含非空 `language:` 的 `workspace-config.yaml`。
3. 若完全找不到，validator 應回報 `language_unset`，skill 不可宣稱已 enforce。

局部 surface 有更明確語言規則時，先依局部規則決定 `--language` 或 `--mode`：

| 情境 | 規則 |
|------|------|
| PR body | prose 依 root workspace language；repo template headings 可保留原文 |
| Review body / inline comment | 依 PR description 或 thread 的主要語言；無法判定時 fallback workspace language |
| Commit message | 依 PR author 主要語言；無法判定時 fallback PR description，再 fallback workspace language |
| Bilingual docs | English source 用 `--mode bilingual-source`；zh-TW translation 用 `--mode bilingual-translation` |
| 原文引用 | 保留原文；skill 自己的說明仍依 policy 語言 |

## 4. Commit message policy

Commit message 不是完全排除，也不是一律跟 workspace language。

- 既有 PR branch：subject/body 的自然語言部分跟隨 PR author 主要語言。
- PR author 語言無法判定：fallback PR description 主要語言。
- 尚未開 PR 的 first-cut commit：fallback root workspace language。
- Conventional commit type/scope、ticket key、branch name、package name、file path、API name、
  CLI flag、env var 等 structural tokens 不納入自然語言判定。
- Bot/generated commit 只有在 producer 明文宣告 mode-specific exception 時可例外；LLM 不可臨場跳過。

## 5. 例外與排除

下列內容不要求翻譯成 workspace language：

- Source code、identifier、import path、JSON/YAML key、CLI flag、env var。
- URL、branch name、ticket key、version tag、package name、API name。
- Repo PR template headings 或保留格式用的固定標籤。
- Reviewer、customer、PM、系統錯誤訊息、HTTP response、log transcript 的原文引用。
- Bilingual mode 的 English source。

例外必須寫在輸出或 skill 規則中，說明來源與保留理由。不可用「這次看起來合理」作為跳過 gate 的理由。

## 6. Skill 接入點

| Skill | 必要接入 |
|-------|----------|
| `refinement` | `refinement.md` / DP `plan.md` 對下游公開前 blocking gate |
| `breakdown` | 每張 `task.md` / `V*.md` schema pass 後 blocking gate |
| `engineering` | PR metadata、handoff、sidecar、completion summary、commit message gate |
| `verify-AC` | JIRA 驗收 comment、verification report、AC fail handoff artifact |
| `review-pr` | review body 與 inline comments，依 PR/thread 語言決定 gate language |
| `docs-sync` | bilingual source/translation mode，不可用 zh-TW-only artifact mode 檢查 English source |

## 7. 完成證明

凡是 skill 會寫外部 surface，最終 handoff 或 summary 應能指出：

- 產出的暫存 artifact 或 canonical artifact 路徑。
- 使用的 validator command。
- Gate 結果：blocking pass、advisory with follow-up，或 fail-stop。

若 gate fail，先修輸出語言並重跑；不可把 fail 的內容送到 GitHub、JIRA、Slack、Confluence
或下游 skill。

## 8. External write rollout status

T5 第一版已接入下列 producer-level gate：

- JIRA comment：`bug-rca`、`bug-triage`、`intake-triage`、`jira-worklog`。
- Slack message：`standup` 的 Confluence 前本地 artifact、`check-pr-approvals`、`review-inbox`、`intake-triage`、`learning`。
- Confluence page：`standup`、`sasd-review`、`sprint-planning`。

剩餘風險：MCP runtime 本身仍沒有全域 preflight interception；在 MCP hook 存在前，責任落在 skill producer 必須先產生 temp artifact 並執行本檔定義的 gate。
