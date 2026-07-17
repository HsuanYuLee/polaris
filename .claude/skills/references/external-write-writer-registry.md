# External Write Writer Registry

本 reference 是 Polaris external-write writer 的 canonical registry contract（DP-230 D17）。

External write surface（JIRA comment、Slack message、Confluence page、GitHub PR body / review、
release prose）的 producer 在執行 language preflight 之前，必須先在 registry 登錄 writer
身份。`pre-write-language-policy.sh` 對 `POLARIS_EXTERNAL_WRITE_WRITER` env var 做
deterministic registry lookup：登錄的 writer fall through 到既有 language gate；未登錄的
writer 一律 fail-stop，且 `POLARIS_LANGUAGE_POLICY_BYPASS=1` 不能繞過。

## 1. Why

`workspace-language-policy.md` § 1 列出所有 external write surface 都需要 language gate，
但 producer 端可以靠 `POLARIS_LANGUAGE_POLICY_BYPASS=1` 強制送出英文 prose。這條 escape
hatch 設計上只給 maintainer migration 用，但實務上無法區分「正在 migration 的 known
maintainer producer」與「新加進來、繞過 policy 的 ad-hoc writer」。Registry 把 known
producer 收斂成 enumerable allow-list，未登錄 producer 就 fail-stop，bypass 語意維持單純。

## 2. Source of truth

Registry data 嵌入在 `.claude/hooks/pre-write-language-policy.sh` 的
`POLARIS_EXTERNAL_WRITERS` bash 陣列中，並由 `scripts/selftests/external-write-language-preflight-selftest.sh`
驗證下表的每個 token 都同時出現在 hook 陣列與本文件。Hook 是 runtime authority；本文件是
audit-facing 描述。

每筆 entry 概念上有四個欄位（token = 唯一 key）：

| 欄位 | 說明 |
|------|------|
| `writer_token` | producer 在 `POLARIS_EXTERNAL_WRITE_WRITER` env var 帶入的 token；不得重複 |
| `owning_skill` | 擁有該 writer 的 Polaris skill 或 helper script |
| `surfaces` | 該 writer 可寫的 surface enum（jira-comment、jira-description、jira-summary、slack、confluence、github-review、github-comment、pr-body、release、artifact）|
| `notes` | 一句話描述用途；release reviewer 用來確認 writer scope 是否合理 |

不容許的設定：

- 同一 `writer_token` 出現在多個 producer。
- `surfaces` 為空陣列。

### Baseline registered writers (DP-230 D17)

| writer_token | owning_skill | surfaces | notes |
|--------------|--------------|----------|-------|
| `intake-triage:jira-comment` | intake-triage | jira-comment | intake-triage JIRA intake labels and decision comment |
| `jira-worklog:jira-comment` | jira-worklog | jira-comment | jira-worklog daily / backfill comment |
| `verify-AC:jira-comment` | verify-AC | jira-comment | verify-AC verification report comment on the AC ticket |
| `engineering:jira-comment` | engineering | jira-comment | engineering revision / completion comment |
| `standup:slack` | standup | slack | standup Slack summary before Confluence write |
| `check-pr-approvals:slack` | check-pr-approvals | slack | check-pr-approvals Slack ping |
| `review-inbox:slack` | review-inbox | slack | review-inbox Slack notification |
| `intake-triage:slack` | intake-triage | slack | intake-triage PM summary Slack message |
| `learning:slack` | learning | slack | learning digest Slack message |
| `standup:confluence` | standup | confluence | standup Confluence page write |
| `sasd-review:confluence` | sasd-review | confluence | sasd-review Confluence SA/SD page |
| `sprint-planning:confluence` | sprint-planning | confluence | sprint-planning Confluence release page |
| `engineering:pr-body` | engineering | pr-body, github-comment, github-review | engineering PR body / review reply / completion comment |
| `review-pr:github-review` | review-pr | github-review, github-comment | review-pr review body and inline comments |
| `framework-release:pr-body` | framework-release | pr-body, release | framework-release workspace PR body and GitHub release prose |

## 3. Hook contract

`pre-write-language-policy.sh` 收到 PreToolUse 事件後，依下列順序處理 external-write
context：

1. 解析 `POLARIS_EXTERNAL_WRITE_WRITER` env var。如果沒設，就走原本的 in-scope path /
   producer token / language gate 流程，不額外動作。
2. env var 有值時，從 `scripts/lib/evidence-producers.json` 的 `external_writers` 陣列找出
   token 相符的 entry：
   - 找到：log `BYPASS external-write-writer registered=<token>`，再走既有 language gate。
     換言之，登錄的 writer 仍會被 language gate 檢查；只有 unregistered fail-stop 被跳過。
   - 找不到：stderr 輸出 `POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED: writer=<token>`
     並 exit 2，封鎖外部寫入。
3. Unregistered writer 不受 `POLARIS_LANGUAGE_POLICY_BYPASS=1` 影響。Bypass env var 只
   針對既有 in-scope path 的 language gate，不能用來繞 registry check。
4. `POLARIS_PRODUCER` token bypass 與 external writer registry 是兩條獨立路徑：
   `POLARIS_PRODUCER` 控管 evidence marker 寫入；`POLARIS_EXTERNAL_WRITE_WRITER` 控管
   external surface 寫入。同時設置兩個 env var 時，hook 先處理 external-write 檢查，再
   evaluate `POLARIS_PRODUCER` 路徑。

## 4. Producer 接入

要寫 external surface 的 producer，需要：

1. 在 `scripts/lib/evidence-producers.json` 的 `external_writers` 陣列登錄 entry。
2. 呼叫 `scripts/polaris-external-write-gate.sh` 之前，於環境設定
   `POLARIS_EXTERNAL_WRITE_WRITER=<token>`。Token 命名建議用 `{skill}:{surface}` 形式，
   例如 `intake-triage:jira-comment`、`standup:slack`、`engineering:pr-body`。
3. Gate 通過後執行真實 external write（MCP / gh CLI / Slack webhook）。
4. Skill 在 final summary 提及 writer token 與 gate 結果。

GitHub review 額外使用 `scripts/submit-pr-review.sh`；wrapper 固定
`review-pr:github-review` 與 `github.pull_request_review.submit`，並在真正 API write 前把
canonical structured payload 交給 external-write gate。未知 token、舊 tool identity 或
ad-hoc payload shape 一律 fail-closed。

## 5. 例外與限制

- Registry 不負責檢查 body content；body content 的 language policy 仍由
  `scripts/validate-language-policy.sh` 執行。
- Registry 不限制 surface 數量；同一 writer 可同時宣告多個 surfaces。`scope` validation
  由各 surface 對應的 gate 負責，registry 只看 writer identity。
- Maintainer migration 加入新 writer 時，必須先 PR registry entry，再 PR 對應 producer
  程式碼。不允許 producer 程式碼先上線、隨後補登錄（registry 是上游 gate）。
- 撤掉 writer 時，先把對應 producer 改成不再呼叫 external write，再從 registry 移除
  entry；保留 entry 比留下 dangling token 安全。

## 6. Verification

`scripts/selftests/external-write-language-preflight-selftest.sh` 覆蓋：

- 已登錄 writer 寫 zh-TW body → exit 0。
- 已登錄 writer 寫英文 body → exit 2（被 language gate 擋下，stderr 含
  `BLOCKED by pre-write-language-policy`）。
- 未登錄 writer → exit 2，stderr 含 `POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED`。
- 未登錄 writer + `POLARIS_LANGUAGE_POLICY_BYPASS=1` → 仍 exit 2，bypass 不生效。
- registry entry duplicate token → registry self-check fail-stop。
- 行數上限：本 reference ≤ 300 行。

選擇 AC13 對應 fixture 時，selftest 直接呼叫 hook 並透過 stdin 傳遞 Write payload；不需要
mock MCP / gh / Slack。Registry consumer 不執行外部寫入。

## 7. Migration path

DP-230 R8 之前：external surface producer 只走 `polaris-external-write-gate.sh`，沒有
identity registry。AC13 上線後：

- 新 producer 必須先在 registry 登錄 token，才允許跑 gate。
- 既有 producer（`standup`、`intake-triage`、`learning` 等）依
  `workspace-language-policy.md` § 8 列出的 surface 一次補上 registry entry。
- Hook 上線時若 producer 還沒設 `POLARIS_EXTERNAL_WRITE_WRITER`，hook 走 legacy path，
  不會誤擋；只有當 producer 顯式宣告 `POLARIS_EXTERNAL_WRITE_WRITER` 但 token 未登錄時，
  hook fail-stop。這設計允許漸進切換，但完成 migration 後 producer 必須一律宣告 token。

## 8. Open follow-ups

- 把 registry validation 接到 PR-time check（與
  `scripts/validate-spec-source-parity.sh` 同類 governance gate）。本 task 範圍以 hook +
  selftest 為主；PR gate 將在後續 task 處理。
- 若 surface 出現新類型（例如 GitHub Discussions），需先在
  `workspace-language-policy.md` 與 `external-write-gate.md` 補 surface enum，再來這裡
  擴張 registry。
